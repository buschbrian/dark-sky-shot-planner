import Foundation
import Testing
@testable import SkyCore

/// Unit checks that mirror `app/tests/skyevents.test.ts` and `showers.test.ts`
/// where the golden file cannot reach (malformed rows, formatting edge cases).
@Suite("Curated sky-events file")
struct CuratedEventsTests {
    let good: [String: Any] = [
        "id": "x", "name": "X", "kind": "meteor_shower",
        "active_from": "2026-01-01", "active_to": "2026-01-10", "peak_utc": "2026-01-05T00:00:00Z",
        "radiant_ra_hours": 1, "radiant_dec_deg": 2,
        "source_url": "https://example.org/x", "verified_on": "2026-01-01",
    ]

    func parse(_ rows: [[String: Any]]) -> CuratedLoadResult {
        CuratedEvents.parse(object: ["events": rows])
    }

    func with(_ changes: [String: Any]) -> [String: Any] {
        good.merging(changes) { _, new in new }
    }

    @Test("the bundled file parses with no problems, every row sourced")
    func bundled() {
        let r = CuratedEvents.bundled
        #expect(r.problems.isEmpty)
        #expect(!r.events.isEmpty)
        for e in r.events { #expect(e.sourceURL.hasPrefix("https://")) }
        for e in r.events where e.kind == .meteorShower {
            #expect(e.radiant != nil && e.peakUtc != nil)
        }
    }

    @Test("unverified rows stay unverified and say why in their notes")
    func unverified() {
        let ids = CuratedEvents.bundled.events.filter { $0.verifiedOn == nil }.map(\.id)
        #expect(ids.contains("leonids-2026") && ids.contains("geminids-2026"))
        for e in CuratedEvents.bundled.events where e.verifiedOn == nil {
            #expect(e.notes.lowercased().contains("approximate"))
        }
    }

    @Test("rows are anchored at 12:00 UTC so the calendar day survives west of UTC")
    func middayAnchors() {
        for e in CuratedEvents.bundled.events {
            #expect(JSTime.utcCalendar.component(.hour, from: e.activeFrom) == 12)
            #expect(e.activeTo >= e.activeFrom)
        }
    }

    @Test func dropsShowerWithoutRadiant() {
        let r = parse([with(["radiant_ra_hours": NSNull(), "radiant_dec_deg": NSNull()])])
        #expect(r.events.isEmpty)
        #expect(r.problems.first?.contains("needs a radiant") == true)
    }

    @Test func dropsRowWithoutSource() {
        let r = parse([with(["source_url": ""])])
        #expect(r.events.isEmpty)
        #expect(r.problems.first?.contains("source_url") == true)
    }

    @Test func dropsDuplicateKeepsFirst() {
        let r = parse([good, with(["name": "Y"])])
        #expect(r.events.map(\.name) == ["X"])
        #expect(r.problems.first?.contains("duplicate id") == true)
    }

    @Test func dropsUnknownKind() {
        #expect(parse([with(["kind": "eclipse"])]).problems.first?.contains("unknown kind \"eclipse\"") == true)
    }

    @Test func rejectsReversedRange() {
        #expect(parse([with(["active_to": "2025-12-01"])]).problems.first?.contains("active_from/active_to") == true)
    }

    @Test func rejectsBadPeak() {
        #expect(parse([with(["peak_utc": "soon"])]).problems.first?.contains("peak_utc") == true)
    }

    @Test func survivesNoEventsArray() {
        #expect(CuratedEvents.parse(object: [String: Any]()).problems.count == 1)
        #expect(CuratedEvents.parse(object: nil).problems.count == 1)
    }

    @Test func blankVerifiedOnIsUnverified() {
        let r = parse([with(["verified_on": NSNull()])])
        #expect(r.problems.isEmpty)
        #expect(r.events.first?.verifiedOn == nil)
    }

    @Test("a JSON boolean is not a number")
    func booleanIsNotANumber() {
        #expect(parse([with(["radiant_ra_hours": true])]).problems.first?.contains("needs a radiant") == true)
    }

    @Test("the active span covers the whole last day")
    func activeSpan() throws {
        let draconids = try #require(CuratedEvents.bundled.events.first { $0.id == "draconids-2026" })
        #expect(draconids.activeSpan.start == (try ISO.date("2026-10-06T00:00:00Z")))
        #expect(draconids.activeSpan.end == (try ISO.date("2026-10-11T00:00:00Z")))
    }

    @Test("distance Millcreek to Great Basin, and zero for the same point")
    func distance() {
        let km = CuratedEvents.distanceKm(40.687, -111.824, 39.006, -114.22)
        #expect(km > 250 && km < 300)
        #expect(CuratedEvents.distanceKm(40, -111, 40, -111) == 0)
    }
}

@Suite("Meteor showers at the observer")
struct MeteorShowerTests {
    let millcreek = try! Observer(latitude: 40.687, longitude: -111.824, heightMeters: 1400)
    let orionids = MeteorShowers.Radiant(raHours: 6.3, decDeg: 16)

    @Test("a morning peak belongs to the night that began the evening before")
    func eveningKeying() throws {
        let evening = MeteorShowers.evening(for: try ISO.date("2026-10-23T06:54:00Z"), longitude: millcreek.longitude)
        let lmt = evening.addingTimeInterval(millcreek.longitude / 15 * 3600)
        #expect(lmt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).hasPrefix("2026-10-22T21"))
        let dusk = MeteorShowers.evening(for: try ISO.date("2026-10-23T02:00:00Z"), longitude: millcreek.longitude)
        let smallHours = MeteorShowers.evening(for: try ISO.date("2026-10-23T09:00:00Z"), longitude: millcreek.longitude)
        #expect(dusk == smallHours)
    }

    @Test("transit altitude is 90 − |latitude − declination|")
    func transitAltitude() throws {
        var best = -90.0
        let day = try ISO.date("2026-10-23T00:00:00Z")
        for m in stride(from: 0, to: 24 * 60, by: 5) {
            best = max(best, MeteorShowers.radiantAltitudeDeg(millcreek, orionids, at: day.addingTimeInterval(Double(m) * 60)))
        }
        #expect(abs(best - (90 - abs(millcreek.latitude - orionids.decDeg))) < 0.6)
    }

    @Test("a northern radiant is unobservable from 40°S")
    func southern() throws {
        let a = try MeteorShowers.assess(
            try Observer(latitude: -40, longitude: -71), .init(raHours: 17.5, decDeg: 54),
            peak: try ISO.date("2026-10-09T01:00:00Z"),
            activeFrom: try ISO.date("2026-10-06T00:00:00Z"), activeTo: try ISO.date("2026-10-11T00:00:00Z"))
        #expect(!a.observableHere)
        #expect(a.peakNight.usableMinutes == 0)
    }
}

@Suite("JavaScript number rendering")
struct JSFormatTests {
    @Test func number() {
        #expect(JSFormat.number(60) == "60")
        #expect(JSFormat.number(65.3) == "65.3")
        #expect(JSFormat.number(-0.0) == "0")
        #expect(JSFormat.number(0.171) == "0.171")
    }

    @Test("toFixed rounds the exact binary value, exact ties away from zero")
    func fixed() {
        #expect(JSFormat.fixed(2.25, 1) == "2.3")   // exact tie
        #expect(JSFormat.fixed(0.35, 1) == "0.3")   // 0.34999… in binary
        #expect(JSFormat.fixed(1.005, 2) == "1.00") // 1.00499… in binary
        #expect(JSFormat.fixed(9.96, 1) == "10.0")
        #expect(JSFormat.fixed(0.171, 3) == "0.171")
        #expect(JSFormat.fixed(-0.04, 1) == "-0.0")
        #expect(JSFormat.fixed(0, 2) == "0.00")
    }
}

@Suite("Sky events tonight and this week")
struct SkyEventHighlightTests {
    let millcreek = try! Observer(latitude: 40.687, longitude: -111.824)
    let denver = TimeZone(identifier: "America/Denver")!

    func week(from first: String, nights: Int = 7) throws -> [SkyEventHighlight] {
        let night = try #require(NightDate(iso: first))
        let result = try SkyEventsAgenda.build(
            millcreek, centre: night.evening(in: denver), formatters: .local(denver), gcMinAltitudeDeg: 12)
        return SkyEventHighlights.highlights(result, first: night, nights: nights, timeZone: denver, site: millcreek)
    }

    @Test("a total lunar eclipse tops its week, on the night it starts")
    func eclipseFirst() throws {
        let h = try week(from: "2026-02-28")
        let top = try #require(h.first)
        #expect(top.item.title == "Total lunar eclipse")
        #expect(top.night.iso == "2026-03-02")
        #expect(top.bestWindow != nil)
        #expect(SkyEventHighlights.badges(h, on: top.night).first?.badge == "Total lunar eclipse")
    }

    @Test("the Moon–Jupiter occultation is placed on the evening before the morning it happens")
    func occultation() throws {
        let h = try week(from: "2026-10-03")
        let occ = try #require(h.first { $0.badge == "Jupiter occultation" })
        #expect(occ.night.iso == "2026-10-05")
        #expect(occ.bestTime != nil)
        let saturn = try #require(h.first { $0.badge == "Saturn at opposition" })
        #expect(saturn.night.iso == "2026-10-03")
        #expect(saturn.bestWhen == "All night")
    }

    @Test("a moonlit shower peak points to the better night inside the run, with the Moon judged")
    func betterNight() throws {
        let h = try week(from: "2026-10-16")
        let orionids = try #require(h.first { $0.item.title == "Orionids" })
        #expect(orionids.night.iso == "2026-10-17")
        #expect(orionids.badge == "Orionids: best night")
        if case .clear = orionids.moon {} else if case .partial = orionids.moon {} else {
            Issue.record("expected a usable moon note, got \(orionids.moon)")
        }
        #expect(orionids.bestWindow != nil)
    }

    @Test("a shower running but peaking elsewhere stays out of the section and the badges")
    func runningShower() throws {
        let h = try week(from: "2026-10-03")
        let taurids = try #require(h.first { $0.item.title == "Southern Taurids" })
        #expect(taurids.significance < SkyEventHighlights.sectionThreshold)
        for n in 0..<7 {
            let night = NightDate(iso: "2026-10-03")!.adding(days: n)
            #expect(!SkyEventHighlights.badges(h, on: night).contains { $0.item.title == "Southern Taurids" })
        }
    }

    @Test("every highlight falls inside the run and keeps its provenance")
    func insideRun() throws {
        let first = NightDate(iso: "2026-09-06")!
        for h in try week(from: first.iso) {
            #expect(h.night >= first && h.night <= first.adding(days: 6), "\(h.item.title) on \(h.night)")
            if h.item.category == .meteorShower || h.item.category == .place {
                if case .computed = h.item.provenance { Issue.record("\(h.item.title) lost its curated provenance") }
            }
        }
    }

    @Test("radiant rows for the Sky view come from the curated file, unaltered")
    func radiantRows() throws {
        let rows = ShowerRadiantRow.all()
        #expect(rows.count == CuratedEvents.bundled.events.filter { $0.kind == .meteorShower }.count)
        let orionids = try #require(rows.first { $0.id == "orionids-2026" })
        #expect(abs(orionids.raDeg - 6.33 * 15) < 1e-9 && orionids.decDeg == 16)
        #expect(orionids.verified)
        #expect(orionids.isActive(at: try ISO.date("2026-10-21T18:28:00Z")))
        #expect(!(rows.first { $0.id == "leonids-2026" }!.verified))
    }
}
