import Foundation
import SkyCore

/// One voice for how the app talks about data. Five words, used the same way
/// on every screen (ADR-0006, ios/AGENTS.md invariants 3 and 4):
///
/// - **unavailable**: there is no value. Never shown as 0 or as good.
/// - **stale**: a value older than its freshness window. Shown, with its age.
/// - **last good copy**: the latest fetch failed, so the previous value is
///   shown with its age.
/// - **estimated**: worked out without the preferred input (a flat horizon,
///   this phone's time zone).
/// - **not set up**: an optional service the build has no address for. Not
///   an error.
///
/// Data ages read "3 h old"; events (a check, a fetch) read "3 h ago".
enum Voice {
    static let unavailable = "unavailable"
    static let stale = "stale"
    static let lastGood = "last good copy"
    static let estimated = "estimated"
    static let notSetUp = "not set up"
    static let onDevice = "computed on this phone"
    /// What the Worker is called on screen.
    static let service = "live conditions service"

    /// "just now", "12 min old", "3 h old", "2 d old".
    static func age(_ seconds: TimeInterval) -> String {
        let text = span(seconds)
        return text == "just now" ? text : "\(text) old"
    }

    /// "just now", "12 min ago", "3 h ago", "2 d ago".
    static func ago(_ seconds: TimeInterval) -> String {
        let text = span(seconds)
        return text == "just now" ? text : "\(text) ago"
    }

    static func age(of date: Date, now: Date = .now) -> String { age(now.timeIntervalSince(date)) }
    static func ago(_ date: Date, now: Date = .now) -> String { ago(now.timeIntervalSince(date)) }

    /// Whole minutes under an hour, whole hours under two days, then days.
    private static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 2 * 86_400 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86_400)) d"
    }

    /// A model run in UTC, forecasters' style: "18Z", or "Fri 18Z" past a day.
    static func run(_ run: Date, now: Date = .now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let hour = String(format: "%02dZ", cal.component(.hour, from: run))
        guard now.timeIntervalSince(run) > 86_400 else { return hour }
        let day = run.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
        return "\(day) \(hour)"
    }

    /// Source names as shown in provenance. The direct fallback is named for
    /// what it is; why it was used is said once, in the conditions status line.
    static func source(_ raw: String) -> String {
        raw == OpenMeteoDirect.source ? "Open-Meteo direct" : raw
    }

    /// SkyCore's reasons, reworded for the screen. The Worker "didn't answer"
    /// only when one is configured; otherwise it is not set up.
    static func reason(_ raw: String, workerConfigured: Bool) -> String {
        switch raw {
        case OpenMeteoDirect.otherFieldsReason:
            return workerConfigured
                ? "the \(service) didn't answer; only clouds come from Open-Meteo directly"
                : "needs the \(service), which is \(notSetUp) in this build"
        case OpenMeteoDirect.lastGoodReason:
            return lastGood
        case "not in the Worker response":
            return "not in the conditions response"
        default:
            return raw
        }
    }
}

extension Freshness {
    /// The ADR-0006 word, short: "fresh", "aging", "stale", "unavailable".
    var word: String {
        switch self {
        case .fresh: "fresh"
        case .aging: "aging"
        case .stale: Voice.stale
        case .unavailable: Voice.unavailable
        }
    }

    /// Shape as well as color, so field mode (brightness only) still tells them apart.
    var symbol: String {
        switch self {
        case .fresh: "circle.fill"
        case .aging: "circle.lefthalf.filled"
        case .stale: "exclamationmark.triangle.fill"
        case .unavailable: "circle.dashed"
        }
    }
}

/// Where Tonight's conditions came from, in the one voice.
enum ConditionsSourceStatus: Equatable {
    case checking
    case none(reason: String)
    case lastGood(fetched: Date, refreshing: Bool)
    case service(fetched: Date)
    /// A 304 from the service: the same run, re-checked; never "offline" (review B-4).
    case confirmed(fetched: Date, checked: Date)
    case direct(serviceConfigured: Bool)

    func text(now: Date, timeZone: TimeZone = .current) -> String {
        switch self {
        case .checking:
            "Checking conditions…"
        case .none(let reason):
            reason
        case .lastGood(let fetched, let refreshing):
            refreshing
                ? "Last good copy, fetched \(Voice.ago(fetched, now: now)). Checking for a newer one…"
                : "Offline: last good copy, fetched \(Voice.ago(fetched, now: now))."
        case .service(let fetched):
            "Live conditions service, fetched \(fetched.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))."
        case .confirmed(let fetched, let checked):
            "Live conditions service, checked \(Voice.ago(checked, now: now)) and unchanged since \(fetched.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))."
        case .direct(let configured):
            configured
                ? "The live conditions service didn't answer, so clouds come from Open-Meteo directly. Smoke, haze and wind show their last good copy or read unavailable."
                : "Clouds from Open-Meteo directly: the live conditions service is not set up in this build. Smoke, haze and wind read unavailable."
        }
    }

    var tone: StatusTone {
        switch self {
        case .checking, .service, .confirmed: .neutral
        case .direct(let configured): configured ? .caution : .neutral
        case .lastGood: .caution
        case .none: .caution
        }
    }

    var symbol: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .service, .confirmed: "antenna.radiowaves.left.and.right"
        case .direct: "cloud"
        case .lastGood: "clock.arrow.circlepath"
        case .none: "wifi.slash"
        }
    }
}

enum StatusTone {
    case neutral, caution
}
