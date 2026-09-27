public import Foundation

/// M11: the client side of the Worker's freshness contract (PLAN.md §Worker
/// "Refresh times", "Revalidation", "Near term"). Pure, so it tests offline.
extension ConditionsSnapshot {
    /// The last time this body was known current: received, or confirmed by a 304.
    public var confirmedUTC: Date { max(fetchedUTC, checkedUTC ?? fetchedUTC) }

    /// The same body after a 304: `fetchedUTC` and every age inside stay as
    /// they were; only the check time moves.
    public func confirmed(at date: Date, etag: String? = nil) -> ConditionsSnapshot {
        ConditionsSnapshot(
            response: response, fetchedUTC: fetchedUTC, etag: etag ?? self.etag,
            checkedUTC: max(date, checkedUTC ?? date))
    }

    /// Fields that carry HRRR's native 15-minute series (`series_15min`).
    public static let nearTermFields = ["temperature", "dew_point", "wind_speed", "wind_gust", "visibility"]

    /// The 15-minute series for `field` from `model`, as the Worker sent it
    /// (possibly unavailable); nil when there is none.
    public func nearTerm(_ field: String, model: String = "hrrr") -> WorkerSeries? {
        response.fields[field]?.series15Min?.first { $0.model == model }
    }

    /// Every field's usable 15-minute series, keyed by field.
    public var nearTermSeries: [String: WorkerSeries] {
        var out: [String: WorkerSeries] = [:]
        for name in Self.nearTermFields {
            if let s = nearTerm(name), s.status == .ok, !s.values.isEmpty { out[name] = s }
        }
        return out
    }

    /// For charts: the same points the verdict reads (`ForecastCadence`),
    /// 15-minute where the native series is complete, hourly elsewhere.
    /// Empty when the model has no usable hourly series.
    public func finestPoints(_ field: String, model: String = "hrrr") -> [WorkerPoint] {
        guard let hourly = response.fields[field]?.series.first(where: { $0.model == model }), hourly.status == .ok
        else { return [] }
        return ForecastCadence.select(hourly: hourly, fine: nearTerm(field, model: model)).points
    }
}

/// When to ask the Worker again.
public enum ConditionsSchedule {
    /// Never sooner than this after now (the Worker's own minimum `max-age`).
    public static let minimumWait: TimeInterval = 60
    /// Never later than this after the last confirmation: the Worker's
    /// `max-age` cap, which also bounds AirNow's hourly observations.
    public static let maximumWait: TimeInterval = 1800
    /// After a failed attempt, or while showing the direct fallback with a Worker configured.
    public static let retryWait: TimeInterval = 120

    /// `max(nextUpdateExpectedUTC, now + 60 s)`, capped at 30 min after the
    /// last confirmation. No estimate means the cap. The direct fallback
    /// (Worker configured but silent) retries the Worker after `retryWait`.
    public static func nextFetch(after snapshot: ConditionsSnapshot?, now: Date, workerConfigured: Bool = true) -> Date {
        guard let snapshot else { return now.addingTimeInterval(retryWait) }
        if workerConfigured && snapshot.response.isDirectFallback { return now.addingTimeInterval(retryWait) }
        let cap = snapshot.confirmedUTC.addingTimeInterval(maximumWait)
        let expected = snapshot.response.nextUpdateExpectedUTC.map { min($0, cap) } ?? cap
        return max(expected, now.addingTimeInterval(minimumWait))
    }
}

/// The HTTP `Date` header (RFC 9110 IMF-fixdate).
public enum HTTPDate {
    public static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.date(from: value.trimmingCharacters(in: .whitespaces))
    }
}
