import Foundation
import SkyCore

/// Where the conditions on screen came from. Every case is a normal state of
/// the app, not an error: the words are for the views to set calmly.
nonisolated enum ConditionsStatus: Sendable, Hashable {
    /// The Worker answered: a new body, or a 304 confirming the saved one.
    case liveWorker(confirmedAt: Date, revalidated: Bool)
    /// A Worker is configured but didn't answer in time, so clouds came
    /// straight from Open-Meteo; the other factors show their last good copy.
    case workerSilentDirect(fetchedAt: Date)
    /// Nothing could be reached: the newest saved copy for this place and night.
    case offlineCache(fetchedAt: Date)
    /// No Worker is configured, by choice: clouds come straight from Open-Meteo.
    case notSetUp(fetchedAt: Date)
    /// Nothing could be reached and nothing is saved.
    case nothing

    /// Status for a snapshot the caller already holds. `cached` means it came
    /// from disk rather than from this refresh.
    static func of(_ snapshot: ConditionsSnapshot?, cached: Bool, workerConfigured: Bool) -> ConditionsStatus {
        guard let snapshot else { return .nothing }
        if cached { return .offlineCache(fetchedAt: snapshot.fetchedUTC) }
        if snapshot.response.isDirectFallback {
            return workerConfigured ? .workerSilentDirect(fetchedAt: snapshot.fetchedUTC) : .notSetUp(fetchedAt: snapshot.fetchedUTC)
        }
        return .liveWorker(confirmedAt: snapshot.confirmedUTC, revalidated: snapshot.checkedUTC != nil)
    }

    var isLive: Bool {
        switch self {
        case .liveWorker, .workerSilentDirect, .notSetUp: true
        case .offlineCache, .nothing: false
        }
    }

    /// A default line; views may word it their own way.
    func summary(now: Date) -> String {
        switch self {
        case .liveWorker(let at, let revalidated):
            return revalidated
                ? "Live conditions, checked \(Self.ago(at, now)) and unchanged"
                : "Live conditions, fetched \(Self.ago(at, now))"
        case .workerSilentDirect(let at):
            return "The conditions service didn't answer, so clouds came straight from Open-Meteo \(Self.ago(at, now)); other factors show their last good copy"
        case .offlineCache(let at):
            return "No connection: showing the copy saved \(Self.ago(at, now))"
        case .notSetUp(let at):
            return "Clouds straight from Open-Meteo, \(Self.ago(at, now)); smoke, haze and wind need the conditions service, which isn't set up"
        case .nothing:
            return "No connection, and nothing saved for this place and night yet"
        }
    }

    static func ago(_ date: Date, _ now: Date) -> String {
        let s = now.timeIntervalSince(date)
        return s < 60 ? "just now" : "\(ShotText.age(s).replacingOccurrences(of: " old", with: "")) ago"
    }
}

/// One refresh: what to show, where it came from, and when to ask again.
nonisolated struct ConditionsFetch: Sendable {
    let snapshot: ConditionsSnapshot?
    let status: ConditionsStatus
    /// `ConditionsSchedule.nextFetch`: for the Tonight loop, Week and the Spots background refresh.
    let nextRefresh: Date
    /// The Worker's HTTP status (200, 304) and wall time, when it answered.
    var workerHTTPStatus: Int? = nil
    var workerDuration: Duration? = nil
}
