import SkyCore
import SwiftUI

/// Words, symbols and provenance for sky events. Colours always come from
/// the palette at the call site, so field mode stays pure red.
enum SkyEventsFormat {
    static func symbol(_ item: SkyEventItem) -> String {
        switch item.detail {
        case .moonPhase(let p): p.angle == 0 ? "moonphase.new.moon" : "moonphase.full.moon"
        case .supermoon: "moon.circle.fill"
        case .apparition: "circle.circle"
        case .pairing: "moonphase.waxing.crescent"
        case .lunarEclipse: "circle.lefthalf.filled"
        case .solarEclipse: "sun.max.trianglebadge.exclamationmark"
        case .zodiacal: "sun.haze"
        case .coreSeason: "moon.stars.fill"
        case .season: "sunrise"
        case .shower: "sparkle"
        case .place: "person.3"
        }
    }

    static func category(_ c: SkyEventItem.Category) -> String {
        switch c {
        case .moon: "Moon"
        case .planet: "Planet"
        case .conjunction: "Pairing"
        case .eclipse: "Eclipse"
        case .meteorShower: "Meteor shower"
        case .milkyWay: "Milky Way"
        case .zodiacal: "Zodiacal light"
        case .season: "Season"
        case .place: "Event"
        }
    }

    /// "Tonight", "Tomorrow", or "Sat Oct 3".
    static func nightLabel(_ night: NightDate, tonight: NightDate) -> String {
        if night == tonight { return "Tonight" }
        if night == tonight.adding(days: 1) { return "Tomorrow night" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: night.year, month: night.month, day: night.day, hour: 12))!
        return noon.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day())
    }

    static func clock(_ d: Date, _ tz: TimeZone) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    }

    static func day(_ d: Date, _ tz: TimeZone) -> String {
        d.formatted(Date.FormatStyle(timeZone: tz).month(.abbreviated).day())
    }

    /// The best viewing line: a window, a time, or words when a clock time would mislead.
    static func best(_ h: SkyEventHighlight, _ tz: TimeZone) -> String? {
        if let w = h.bestWindow {
            let span = "\(clock(w.start, tz))–\(clock(w.end, tz))"
            if let t = h.bestTime, t >= w.start, t <= w.end, h.item.category != .eclipse {
                return "Best \(span), highest \(clock(t, tz))"
            }
            if let t = h.bestTime, h.item.category == .eclipse { return "\(span), peak \(clock(t, tz))" }
            return "Best \(span)"
        }
        if let when = h.bestWhen { return when }
        if let t = h.bestTime { return "Best at \(clock(t, tz))" }
        return nil
    }

    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    /// What the Moon does to it, or nil when the Moon is the subject.
    static func moon(_ m: SkyEventHighlight.Moon, _ tz: TimeZone) -> String? {
        switch m {
        case .notApplicable: nil
        case .notCounted: "Moon not counted here; the night report has the moon-free part"
        case .clear(let f): f > 0.005 ? "Moon down (\(percent(f)) lit)" : "No moon in the way"
        case .partial(let f, let usable):
            "\(percent(f)) moon for part of it; moon-free "
                + usable.map { "\(clock($0.start, tz))–\(clock($0.end, tz))" }.joined(separator: ", ")
        case .spoils(let f): "\(percent(f)) moon up throughout: washes out faint meteors"
        }
    }

    static func moonIsBad(_ m: SkyEventHighlight.Moon) -> Bool {
        if case .spoils = m { return true }
        return false
    }

    /// "Computed on this phone" or "Curated · verified 2026-09-24 · imo.net".
    static func provenance(_ p: SkyEventItem.Provenance) -> String {
        switch p {
        case .computed: "Computed on this phone"
        case .curated(let url, let on):
            "Curated · " + (on.map { "verified \($0)" } ?? "unverified") + " · " + host(url)
        }
    }

    static func host(_ url: String) -> String {
        guard let u = URL(string: url), var h = u.host() else { return url }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        // The archive's own host says nothing; name the archived site.
        if h == "web.archive.org", let inner = url.range(of: "https://", options: .backwards) {
            return host(String(url[inner.lowerBound...])) + " (archived)"
        }
        return h
    }
}
