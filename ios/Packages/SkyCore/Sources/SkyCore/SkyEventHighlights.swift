public import Foundation

/// "In the sky tonight / this week": the agenda (`SkyEventsAgenda`) narrowed
/// to a run of nights at one place, each event reduced to what the app shows
/// at a glance: which night, a one-line why-it-matters, the best viewing time
/// and what the Moon does to it. iOS-only presentation logic over the golden-
/// tested agenda; nothing here changes a number the web app prints.
public struct SkyEventHighlight: Sendable, Hashable, Identifiable {
    public enum Moon: Sendable, Hashable {
        /// The Moon is the subject (phases, pairings, eclipses) or irrelevant (daytime, festivals).
        case notApplicable
        /// Down (or under 15% lit) for the whole best window.
        case clear(illumination: Double)
        /// Up for part of the best window.
        case partial(illumination: Double, usable: [TimeWindow])
        /// Up throughout.
        case spoils(illumination: Double)
        /// Deliberately not judged (the core season: the night report does that).
        case notCounted
    }

    public let item: SkyEventItem
    /// The night (local evening date) the event is best on.
    public let night: NightDate
    /// A single instant worth being out for, when there is one.
    public let bestTime: Date?
    /// The span worth being out for, when there is one.
    public let bestWindow: TimeWindow?
    /// "All night", "After sunset", … when a clock time would be false precision.
    public let bestWhen: String?
    public let whyItMatters: String
    public let moon: Moon
    /// Higher first. Eclipses and strong shower peaks outrank a quarter moon.
    public let significance: Int
    /// Short badge text for a Week row ("Orionids peak").
    public let badge: String

    public var id: String { item.id + "|" + night.iso }
}

public enum SkyEventHighlights {
    /// Below this significance an item stays in the full list only.
    public static let sectionThreshold = 30

    /// Highlights for the `nights` nights starting at `first`, most significant
    /// first, then by time. Items whose night falls outside the run are dropped;
    /// a shower still running but peaking elsewhere is kept at low significance.
    public static func highlights(
        _ result: SkyEventsResult, first: NightDate, nights: Int, timeZone: TimeZone, site: Observer
    ) -> [SkyEventHighlight] {
        let last = first.adding(days: nights - 1)
        let runStart = first.evening(in: timeZone).addingTimeInterval(-9 * 3600)
        let runEnd = last.evening(in: timeZone).addingTimeInterval(15 * 3600)
        var out: [SkyEventHighlight] = []
        for item in result.items {
            if let h = highlight(item, first: first, last: last, runStart: runStart, runEnd: runEnd, tz: timeZone, site: site) {
                out.append(h)
            }
        }
        return out.stableSorted {
            $0.significance != $1.significance ? $0.significance > $1.significance : $0.night < $1.night
        }
    }

    /// Highlights on one night, for a Week-row badge, most significant first.
    public static func badges(_ highlights: [SkyEventHighlight], on night: NightDate) -> [SkyEventHighlight] {
        highlights.filter { $0.night == night && $0.significance >= sectionThreshold }
    }

    static func highlight(
        _ item: SkyEventItem, first: NightDate, last: NightDate, runStart: Date, runEnd: Date,
        tz: TimeZone, site: Observer
    ) -> SkyEventHighlight? {
        func inRun(_ n: NightDate) -> Bool { n >= first && n <= last }
        func nightOf(_ d: Date) -> NightDate { NightDate.containing(d, in: tz) }
        func make(
            night: NightDate, time: Date? = nil, window: TimeWindow? = nil, when: String? = nil,
            why: String, moon: SkyEventHighlight.Moon, significance: Int, badge: String
        ) -> SkyEventHighlight {
            SkyEventHighlight(
                item: item, night: night, bestTime: time, bestWindow: window, bestWhen: when,
                whyItMatters: why, moon: moon, significance: significance, badge: badge)
        }

        switch item.detail {
        case .shower(let event, let a):
            let peakNight = nightOf(a.peakNight.eveningUtc)
            let zhr = event.zhr ?? 0
            let why = event.zhr.map {
                "ZHR ~\(JSFormat.number($0)): the ideal dark-sky hourly rate at peak; expect fewer."
            } ?? "A meteor shower with no published rate."
            if !a.observableHere {
                guard inRun(peakNight) else { return nil }
                return make(
                    night: peakNight, why: "Radiant never clears 10° in darkness here.", moon: .notApplicable,
                    significance: 5, badge: "\(item.title): not from here")
            }
            // The better night wins when it is in the run; the peak otherwise.
            var chosen: (MeteorShowers.Night, Bool)?
            if let b = a.betterNight, inRun(nightOf(b.eveningUtc)) { chosen = (b, false) }
            else if inRun(peakNight) { chosen = (a.peakNight, true) }
            if let (night, isPeak) = chosen {
                let significance = (zhr >= 50 ? 90 : zhr >= 10 ? 70 : 40) + (isPeak ? 0 : -5)
                return make(
                    night: nightOf(night.eveningUtc), time: night.maxAltitudeAt,
                    window: longest(night.usableWindows) ?? night.radiantWindow,
                    why: why, moon: showerMoon(night), significance: significance,
                    badge: isPeak ? "\(item.title) peak" : "\(item.title): best night")
            }
            // Running during the run but peaking elsewhere (the Taurids, all autumn).
            let span = event.activeSpan
            guard span.end >= runStart && span.start <= runEnd else { return nil }
            return make(
                night: max(first, min(last, nightOf(max(span.start, runStart)))),
                why: why + " Active now; the peak is another night.", moon: .notApplicable,
                significance: 10, badge: "\(item.title) active")

        case .pairing(let p):
            let n = nightOf(p.at)
            guard inRun(n) else { return nil }
            let occults = p.occultation?.behindDiscFromHere == true
            return make(
                night: n, time: p.at,
                why: occults ? "The Moon passes in front of \(p.body.displayName) as seen from here."
                    : "A close Moon–\(p.body.displayName) pairing, \(JSFormat.fixed(p.separationDeg, 1))° apart from here.",
                moon: .notApplicable, significance: occults ? 80 : (p.observableHere ? 45 : 15),
                badge: occults ? "\(p.body.displayName) occultation" : "Moon–\(p.body.displayName)")

        case .lunarEclipse(let e):
            let n = nightOf(e.peak)
            guard inRun(n) else { return nil }
            let visible = max(e.moonAltitudeAtBeginDeg, e.moonAltitudeAtPeakDeg, e.moonAltitudeAtEndDeg) >= 0
            let window = e.totalBegin.flatMap { b in e.totalEnd.map { TimeWindow(start: b, end: $0) } }
                ?? e.partialBegin.flatMap { b in e.partialEnd.map { TimeWindow(start: b, end: $0) } }
            return make(
                night: n, time: e.peak, window: window,
                why: e.kind == .total ? "The Moon turns red in Earth's shadow; the sky darkens around it."
                    : e.kind == .partial ? "Part of the Moon passes through Earth's shadow."
                    : "The Moon dims slightly in Earth's outer shadow.",
                moon: .notApplicable,
                significance: visible ? (e.kind == .penumbral ? 35 : 95) : 20,
                badge: "\(e.kind.capitalised) lunar eclipse")

        case .solarEclipse(let e):
            let n = nightOf(e.peak)
            guard inRun(n) else { return nil }
            return make(
                night: n, time: e.peak, window: TimeWindow(start: e.begin, end: e.end),
                why: "Solar filter required: never look at the Sun, or aim a camera at it, unprotected.",
                moon: .notApplicable, significance: 100, badge: "\(e.kind.capitalised) solar eclipse")

        case .apparition(let e):
            let n = nightOf(e.at)
            guard inRun(n) else { return nil }
            if e.kind == .opposition {
                return make(
                    night: n, when: "All night",
                    why: "\(e.body.displayName) is at its closest and brightest, up from dusk to dawn.",
                    moon: moonNote(site, at: midnight(n, tz)), significance: 60,
                    badge: "\(e.body.displayName) at opposition")
            }
            let evening = e.visibility == .evening
            return make(
                night: n, when: evening ? "After sunset, low in the west" : "Before sunrise, low in the east",
                why: "\(e.body.displayName) at its widest from the Sun: the easiest time to see it.",
                moon: .notApplicable, significance: 40,
                badge: "\(e.body.displayName) at elongation")

        case .supermoon(let m):
            let n = nightOf(m.at)
            guard inRun(n) else { return nil }
            return make(
                night: n, when: "At moonrise",
                why: "The biggest, brightest full moon: moonlit landscapes, no Milky Way.",
                moon: .notApplicable, significance: 50, badge: "Supermoon")

        case .moonPhase(let p):
            let n = nightOf(p.at)
            guard inRun(n), p.angle == 0 || p.angle == 180 else { return nil }
            return make(
                night: n, when: p.angle == 0 ? "All night" : nil,
                why: p.angle == 0 ? "The darkest night of the month." : "No moon-free darkness tonight.",
                moon: .notApplicable, significance: p.angle == 0 ? 30 : 20, badge: p.name)

        case .zodiacal(let r):
            let from = nightOf(r.start), to = nightOf(r.end)
            guard to >= first && from <= last else { return nil }
            let morning = r.season == .autumnMorning
            return make(
                night: max(from, first),
                when: morning ? "An hour before dawn, looking east" : "An hour after dusk, looking west",
                why: "A faint cone of sunlight scattered by interplanetary dust.",
                moon: .clear(illumination: 0), significance: 25, badge: "Zodiacal light")

        case .coreSeason(let r):
            let opensNight = nightOf(r.first.eveningUtc), endsNight = nightOf(r.last.eveningUtc)
            if r.opens && inRun(opensNight) {
                return make(
                    night: opensNight, time: r.first.maxAltitudeAt,
                    why: "The first nights this year the Galactic Center clears the threshold in darkness.",
                    moon: .notCounted, significance: 55, badge: "Core season opens")
            }
            if r.closes && inRun(endsNight) {
                return make(
                    night: endsNight, time: r.last.maxAltitudeAt,
                    why: "The last nights this year the Galactic Center clears the threshold in darkness.",
                    moon: .notCounted, significance: 55, badge: "Core season ends")
            }
            return nil

        case .season(let s):
            let n = nightOf(s.at)
            guard inRun(n) else { return nil }
            return make(
                night: n, why: "Night length changes fastest around this date.",
                moon: .notApplicable, significance: 10, badge: s.name)

        case .place(let e, let km):
            let span = e.activeSpan
            guard span.end >= runStart && span.start <= runEnd else { return nil }
            // Curated days are calendar dates (anchored 12:00 UTC), not instants.
            let n = max(first, calendarNight(e.activeFrom))
            let near = (km ?? .max) <= 400
            return make(
                night: min(n, last), when: e.activeFrom == e.activeTo ? nil : "Through \(dayMonth(e.activeTo))",
                why: km.map { "\(e.location?.place ?? e.name), \($0) km away." } ?? e.name,
                moon: .notApplicable, significance: near ? 35 : 5, badge: e.name)
        }
    }

    static func showerMoon(_ n: MeteorShowers.Night) -> SkyEventHighlight.Moon {
        if n.usableMinutes == 0 { return .spoils(illumination: n.moonIllumFraction) }
        if SkyEventsAgenda.isFullyMoonless(n) { return .clear(illumination: n.moonIllumFraction) }
        return .partial(illumination: n.moonIllumFraction, usable: n.usableWindows.map { TimeWindow(start: $0.start, end: $0.end) })
    }

    static func longest(_ windows: [MoonFreeWindow]) -> TimeWindow? {
        windows.max { $0.minutes < $1.minutes }.map { TimeWindow(start: $0.start, end: $0.end) }
    }

    /// Moon above the horizon and 15% lit or more spoils a faint target.
    static func moonNote(_ site: Observer, at when: Date) -> SkyEventHighlight.Moon {
        let illum = SkyEvents.moonIllumination(at: when)
        let up = SkyEvents.altitudeDeg(site, .moon, at: when) > 0
        return up && illum >= SkyEvents.zodiacalMaxMoonIllum ? .spoils(illumination: illum) : .clear(illumination: illum)
    }

    static func midnight(_ n: NightDate, _ tz: TimeZone) -> Date { n.evening(in: tz).addingTimeInterval(3 * 3600) }

    static func calendarNight(_ d: Date) -> NightDate {
        let c = JSTime.utcCalendar.dateComponents([.year, .month, .day], from: d)
        return NightDate(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// The curated calendar day, printed in UTC so no zone shifts it.
    static func dayMonth(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
    }
}

/// A curated meteor shower as the Sky view's radiant overlay needs it. Field
/// for field it matches the `SkyRadiant` initialiser the sky-realism work
/// defines; no drift or population index is invented (the curated file has
/// neither), so those stay at their defaults.
public struct ShowerRadiantRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// J2000, degrees.
    public let raDeg: Double
    public let decDeg: Double
    /// Whole calendar days of activity, last day included.
    public let activeFrom: Date
    public let activeUntil: Date
    public let peak: Date?
    public let zhr: Double?
    public let sourceURL: URL?
    /// A person checked the row against its source (`verified_on` is set).
    public let verified: Bool

    /// Every curated shower, active or not; filter by date at the call site.
    public static func all(_ curated: CuratedLoadResult = CuratedEvents.bundled) -> [ShowerRadiantRow] {
        curated.events.compactMap { e in
            guard e.kind == .meteorShower, let r = e.radiant else { return nil }
            let span = e.activeSpan
            return ShowerRadiantRow(
                id: e.id, name: e.name, raDeg: r.raHours * 15, decDeg: r.decDeg,
                activeFrom: span.start, activeUntil: span.end, peak: e.peakUtc, zhr: e.zhr,
                sourceURL: URL(string: e.sourceURL), verified: e.verifiedOn != nil)
        }
    }

    public func isActive(at date: Date) -> Bool { date >= activeFrom && date <= activeUntil }
}
