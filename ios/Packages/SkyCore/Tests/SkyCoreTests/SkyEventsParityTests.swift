import Foundation
import Testing
@testable import SkyCore

/// `shared/golden/sky-events.json` is the web/iOS contract for sky events
/// (written by `app/tests/sky-events-golden.test.ts`). Tolerances come from
/// the file and are never loosened here; counts, titles, categories,
/// provenance and verdict text must match exactly.
struct SkyEventsGolden: Decodable {
    struct Tolerance: Decodable, Sendable {
        let time_s: Double
        let angle_deg: Double
        let illum_fraction: Double
        let minutes: Int
    }
    struct Span: Decodable, Sendable { let start: String; let end: String; let minutes: Int? }
    struct Phase: Decodable, Sendable { let at: String; let angle: Int }
    struct Apparition: Decodable, Sendable {
        let at: String; let body: String; let kind: String
        let elongation_deg: Double?; let visibility: String?
    }
    struct Occultation: Decodable, Sendable {
        let min_separation_deg: Double; let min_separation_at: String; let moon_radius_deg: Double
        let moon_altitude_deg: Double; let sun_altitude_deg: Double; let behind_disc_from_here: Bool
        let disappears_at: String?; let reappears_at: String?; let reappear_moon_altitude_deg: Double?
    }
    struct Pairing: Decodable, Sendable {
        let body: String; let at: String; let separation_deg: Double; let observable_here: Bool
        let moon_altitude_deg: Double; let body_altitude_deg: Double; let moon_illum_fraction: Double
        let geocentric_min_deg: Double; let geocentric_min_at: String; let possible_occultation: Bool
        let occultation: Occultation?
    }
    struct Zodiacal: Decodable, Sendable { let season: String; let start: String; let end: String; let nights: Int }
    struct Season: Decodable, Sendable { let at: String; let name: String }
    struct Night: Decodable, Sendable {
        let evening_utc: String; let darkness: Span?; let max_altitude_deg: Double?; let max_altitude_at: String?
        let radiant_observable: Bool; let radiant_window: Span?; let moon_illum_fraction: Double
        let usable_windows: [Span]; let usable_minutes: Int
    }
    struct Shower: Decodable, Sendable {
        let id: String; let observable_here: Bool; let peak_night: Night; let better_night: Night?
    }
    struct Provenance: Decodable, Sendable { let kind: String; let sourceUrl: String?; let verifiedOn: String? }
    struct Item: Decodable, Sendable {
        let at: String; let until: String?; let category: String; let title: String
        let verdict: String; let provenance: Provenance
    }
    struct Expected: Decodable, Sendable {
        let window: Span
        let moon_phases: [Phase]
        let apparitions: [Apparition]
        let pairings: [Pairing]
        let zodiacal: [Zodiacal]
        let seasons: [Season]
        let showers: [Shower]
        let items: [Item]
        let problems: [String]
    }
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let latitude: Double
        let longitude: Double
        let elevation_m: Double
        let centre_utc: String
        let utc_offset_hours: Double
        let expected: Expected
        var testDescription: String { id }

        func site() throws -> Observer {
            try Observer(latitude: latitude, longitude: longitude, heightMeters: elevation_m)
        }
    }

    let astronomy_engine: String
    let window_days: Double
    let tolerance: Tolerance
    let cases: [Case]

    static func load() throws -> SkyEventsGolden {
        try JSONDecoder().decode(SkyEventsGolden.self, from: Repo.data("shared/golden/sky-events.json"))
    }

    /// Loaded once for the parameterised tests (a failure shows up in `fileLoads`).
    static let shared: SkyEventsGolden? = try? load()
}

/// Comparison helpers bound to the file's tolerances.
struct Near {
    let tol: SkyEventsGolden.Tolerance

    func time(_ actual: Date?, _ expected: String?, _ what: String) throws {
        guard let expected else {
            #expect(actual == nil, "\(what): expected none, got \(String(describing: actual))")
            return
        }
        let e = try ISO.date(expected)
        guard let actual else {
            Issue.record("\(what): expected \(expected), got none")
            return
        }
        #expect(abs(actual.timeIntervalSince(e)) <= tol.time_s, "\(what): \(actual) vs \(expected)")
    }

    func angle(_ actual: Double?, _ expected: Double?, _ what: String) {
        guard let expected else {
            #expect(actual == nil || actual == -.infinity, "\(what): expected none, got \(String(describing: actual))")
            return
        }
        guard let actual else { Issue.record("\(what): expected \(expected), got none"); return }
        #expect(abs(actual - expected) <= tol.angle_deg, "\(what): \(actual) vs \(expected)")
    }

    func illum(_ actual: Double, _ expected: Double, _ what: String) {
        #expect(abs(actual - expected) <= tol.illum_fraction, "\(what): \(actual) vs \(expected)")
    }

    func minutes(_ actual: Int, _ expected: Int, _ what: String) {
        #expect(abs(actual - expected) <= tol.minutes, "\(what): \(actual) vs \(expected)")
    }

    func span(_ actual: TimeWindow?, _ expected: SkyEventsGolden.Span?, _ what: String) throws {
        #expect((actual == nil) == (expected == nil), "\(what): presence differs")
        guard let actual, let expected else { return }
        try time(actual.start, expected.start, "\(what).start")
        try time(actual.end, expected.end, "\(what).end")
    }

    func night(_ n: MeteorShowers.Night, _ e: SkyEventsGolden.Night, _ what: String) throws {
        try time(n.eveningUtc, e.evening_utc, "\(what).evening")
        try span(n.darkness, e.darkness, "\(what).darkness")
        angle(n.maxAltitudeDeg.isFinite ? n.maxAltitudeDeg : nil, e.max_altitude_deg, "\(what).maxAltitude")
        try time(n.maxAltitudeAt, e.max_altitude_at, "\(what).maxAltitudeAt")
        #expect(n.radiantObservable == e.radiant_observable, "\(what).radiantObservable")
        try span(n.radiantWindow, e.radiant_window, "\(what).radiantWindow")
        illum(n.moonIllumFraction, e.moon_illum_fraction, "\(what).moonIllum")
        #expect(n.usableWindows.count == e.usable_windows.count, "\(what).usableWindows count")
        for (a, b) in zip(n.usableWindows, e.usable_windows) {
            try time(a.start, b.start, "\(what).usable.start")
            try time(a.end, b.end, "\(what).usable.end")
            minutes(a.minutes, b.minutes ?? -1, "\(what).usable.minutes")
        }
        minutes(n.usableMinutes, e.usable_minutes, "\(what).usableMinutes")
    }
}

@Suite("Golden sky-events parity with the web agenda")
struct SkyEventsParityTests {
    static var cases: [SkyEventsGolden.Case] { SkyEventsGolden.shared?.cases ?? [] }

    @Test("the golden file loads, has its 7 cases, and was written by the vendored astronomy-engine")
    func fileLoads() throws {
        let file = try SkyEventsGolden.load()
        #expect(file.cases.count == 7)
        #expect(file.window_days == SkyEvents.defaultWindowDays)
        #expect(file.astronomy_engine == (try VendoredAstronomy.version()))
    }

    @Test("computed events match", arguments: cases)
    func computed(_ c: SkyEventsGolden.Case) throws {
        let near = Near(tol: try SkyEventsGolden.load().tolerance)
        let site = try c.site()
        let window = SkyEvents.window(around: try ISO.date(c.centre_utc))
        try near.span(window, c.expected.window, "window")

        let phases = SkyEvents.moonPhases(window)
        #expect(phases.map(\.angle) == c.expected.moon_phases.map(\.angle))
        for (a, e) in zip(phases, c.expected.moon_phases) { try near.time(a.at, e.at, "phase \(e.angle)") }

        let apparitions = SkyEvents.planetOppositions(window) + SkyEvents.greatestElongations(window)
        #expect(apparitions.map(\.body.displayName) == c.expected.apparitions.map(\.body))
        for (a, e) in zip(apparitions, c.expected.apparitions) {
            try near.time(a.at, e.at, "\(e.body) \(e.kind)")
            #expect(a.kind.rawValue == e.kind)
            #expect(a.visibility?.rawValue == e.visibility)
            near.angle(a.elongationDeg, e.elongation_deg, "\(e.body) elongation")
        }

        let zodiacal = SkyEvents.zodiacalLightRanges(site, window)
        #expect(zodiacal.map(\.season.rawValue) == c.expected.zodiacal.map(\.season))
        for (a, e) in zip(zodiacal, c.expected.zodiacal) {
            try near.time(a.start, e.start, "zodiacal start")
            try near.time(a.end, e.end, "zodiacal end")
            #expect(a.nights == e.nights)
        }

        let seasons = SkyEvents.seasonMarkers(window)
        #expect(seasons.map(\.name) == c.expected.seasons.map(\.name))
        for (a, e) in zip(seasons, c.expected.seasons) { try near.time(a.at, e.at, e.name) }
    }

    @Test("moon–planet pairings and occultations match", arguments: cases)
    func pairings(_ c: SkyEventsGolden.Case) throws {
        let near = Near(tol: try SkyEventsGolden.load().tolerance)
        let window = SkyEvents.window(around: try ISO.date(c.centre_utc))
        let pairings = SkyEvents.moonPlanetPairings(try c.site(), window)
        #expect(pairings.map(\.body.displayName) == c.expected.pairings.map(\.body))
        for (a, e) in zip(pairings, c.expected.pairings) {
            let what = "Moon–\(e.body) \(e.at)"
            try near.time(a.at, e.at, what)
            near.angle(a.separationDeg, e.separation_deg, "\(what) separation")
            #expect(a.observableHere == e.observable_here, "\(what) observable")
            near.angle(a.moonAltitudeDeg, e.moon_altitude_deg, "\(what) moon altitude")
            near.angle(a.bodyAltitudeDeg, e.body_altitude_deg, "\(what) body altitude")
            near.illum(a.moonIllumFraction, e.moon_illum_fraction, "\(what) illum")
            near.angle(a.geocentricMinDeg, e.geocentric_min_deg, "\(what) geocentric min")
            try near.time(a.geocentricMinAt, e.geocentric_min_at, "\(what) geocentric min at")
            #expect(a.possibleOccultation == e.possible_occultation, "\(what) possible occultation")
            #expect((a.occultation == nil) == (e.occultation == nil), "\(what) occultation presence")
            if let o = a.occultation, let x = e.occultation {
                near.angle(o.minSeparationDeg, x.min_separation_deg, "\(what) occ min")
                try near.time(o.minSeparationAt, x.min_separation_at, "\(what) occ min at")
                near.angle(o.moonRadiusDeg, x.moon_radius_deg, "\(what) moon radius")
                near.angle(o.moonAltitudeDeg, x.moon_altitude_deg, "\(what) occ moon alt")
                near.angle(o.sunAltitudeDeg, x.sun_altitude_deg, "\(what) occ sun alt")
                #expect(o.behindDiscFromHere == x.behind_disc_from_here, "\(what) behind disc")
                try near.time(o.disappearsAt, x.disappears_at, "\(what) disappears")
                try near.time(o.reappearsAt, x.reappears_at, "\(what) reappears")
                near.angle(o.reappearMoonAltitudeDeg, x.reappear_moon_altitude_deg, "\(what) reappear alt")
            }
        }
    }

    @Test("meteor showers are judged at the observer as on the web", arguments: cases)
    func showers(_ c: SkyEventsGolden.Case) throws {
        let near = Near(tol: try SkyEventsGolden.load().tolerance)
        let site = try c.site()
        let window = SkyEvents.window(around: try ISO.date(c.centre_utc))
        let showers = CuratedEvents.inWindow(CuratedEvents.bundled.events, window).filter { $0.kind == .meteorShower }
        #expect(showers.map(\.id) == c.expected.showers.map(\.id))
        for (e, x) in zip(showers, c.expected.showers) {
            let span = e.activeSpan
            let a = try MeteorShowers.assess(site, e.radiant!, peak: e.anchor, activeFrom: span.start, activeTo: span.end)
            #expect(a.observableHere == x.observable_here, "\(e.id) observable")
            try near.night(a.peakNight, x.peak_night, "\(e.id) peak")
            #expect((a.betterNight == nil) == (x.better_night == nil), "\(e.id) better night presence")
            if let b = a.betterNight, let xb = x.better_night { try near.night(b, xb, "\(e.id) better") }
        }
    }

    @Test("the agenda's lines, order, provenance and wording match", arguments: cases)
    func agenda(_ c: SkyEventsGolden.Case) throws {
        let near = Near(tol: try SkyEventsGolden.load().tolerance)
        let result = try SkyEventsAgenda.build(
            try c.site(), centre: try ISO.date(c.centre_utc),
            formatters: .fixedOffset(hours: c.utc_offset_hours))
        #expect(result.problems == c.expected.problems)
        #expect(result.items.map(\.title) == c.expected.items.map(\.title))
        #expect(result.items.map(\.category.rawValue) == c.expected.items.map(\.category))
        for (a, e) in zip(result.items, c.expected.items) {
            try near.time(a.at, e.at, "\(e.title) at")
            try near.time(a.until, e.until, "\(e.title) until")
            #expect(a.verdict == e.verdict, "\(e.title)")
            switch a.provenance {
            case .computed:
                #expect(e.provenance.kind == "computed", "\(e.title) provenance")
            case .curated(let url, let on):
                #expect(e.provenance.kind == "curated" && e.provenance.sourceUrl == url && e.provenance.verifiedOn == on,
                        "\(e.title) provenance")
            }
        }
    }
}
