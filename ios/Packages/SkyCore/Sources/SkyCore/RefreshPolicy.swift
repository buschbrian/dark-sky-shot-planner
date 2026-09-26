public import Foundation

/// A model's latest run as Open-Meteo's `/data/{id}/static/meta.json` reports it.
public struct ModelRunInfo: Sendable, Hashable {
    public let run: Date
    /// When that run's data became available to the API.
    public let available: Date?
    /// How often the model runs (HRRR 3600 s, the global models 6 h or 12 h).
    public let updateInterval: TimeInterval?

    public init(run: Date, available: Date?, updateInterval: TimeInterval?) {
        self.run = run
        self.available = available
        self.updateInterval = updateInterval
    }

    public static func parse(_ meta: Data?) -> ModelRunInfo? {
        guard let meta,
              let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              obj["error"] as? Bool != true,
              let run = (obj["last_run_initialisation_time"] as? NSNumber)?.doubleValue
        else { return nil }
        return ModelRunInfo(
            run: Date(timeIntervalSince1970: run),
            available: (obj["last_run_availability_time"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            updateInterval: (obj["update_interval_seconds"] as? NSNumber)?.doubleValue)
    }
}

/// When to fetch conditions again: when a model the snapshot uses has published
/// a newer run, not on a blind timer. The one time-based rule is `maxAge`,
/// because AirNow observations change hourly and carry no run time.
public enum RefreshPolicy {
    public static let maxAge: TimeInterval = 3600
    public static let minCheckInterval: TimeInterval = 120
    public static let maxCheckInterval: TimeInterval = 1800
    /// Slack after a run's expected availability before checking for it.
    static let availabilitySlack: TimeInterval = 120

    /// `meta.json` id for each series model id the Worker returns.
    public static let metaIDs: [String: String] = Dictionary(
        uniqueKeysWithValues: OpenMeteoDirect.models.map { ($0.id, $0.meta) } + [("cams_global", "cams_global")])

    public enum Reason: Sendable, Hashable {
        case noSnapshot
        /// The snapshot is the direct fallback: try the Worker again.
        case fallback
        case newerRun(model: String)
        case tooOld
    }

    /// The newest run each model contributed to the snapshot (usable series only).
    public static func runs(in response: ConditionsResponse) -> [String: Date] {
        var out: [String: Date] = [:]
        for field in response.fields.values {
            for s in field.series where s.status == .ok {
                guard let run = s.modelRunUTC else { continue }
                out[s.model] = max(out[s.model] ?? run, run)
            }
        }
        return out
    }

    /// nil means the snapshot is as fresh as the upstreams can make it.
    /// `latest` is keyed by `meta.json` id. With no Worker configured the
    /// direct fallback is the best there is, so only newer runs and age count.
    public static func reason(
        snapshot: ConditionsSnapshot?, latest: [String: ModelRunInfo], now: Date, workerConfigured: Bool = true
    ) -> Reason? {
        guard let snapshot else { return .noSnapshot }
        if workerConfigured && snapshot.response.isDirectFallback { return .fallback }
        for (model, run) in runs(in: snapshot.response).sorted(by: { $0.key < $1.key }) {
            if let meta = metaIDs[model], let info = latest[meta], info.run > run { return .newerRun(model: model) }
        }
        if now.timeIntervalSince(snapshot.confirmedUTC) >= maxAge { return .tooOld }
        return nil
    }

    /// Next time to look at `meta.json` again: just after the soonest expected
    /// run, clamped to 2–30 min so a late run or a quiet model is still noticed.
    public static func nextCheck(latest: [String: ModelRunInfo], now: Date) -> Date {
        let expected = latest.values.compactMap { info -> Date? in
            guard let available = info.available, let interval = info.updateInterval, interval > 0 else { return nil }
            return available.addingTimeInterval(interval + availabilitySlack)
        }
        let soonest = expected.filter { $0 > now }.min() ?? now.addingTimeInterval(maxCheckInterval)
        let wait = min(max(soonest.timeIntervalSince(now), minCheckInterval), maxCheckInterval)
        return now.addingTimeInterval(wait)
    }
}
