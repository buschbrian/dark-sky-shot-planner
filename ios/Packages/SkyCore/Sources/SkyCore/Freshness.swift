public import Foundation

/// Swift port of `app/src/freshness.ts` (ADR-0006). The windows come from
/// `config/app-config.json` → `freshness_days`, never from Swift.
public enum Freshness: String, Sendable, Hashable, Codable, CaseIterable {
    case fresh, aging, stale, unavailable

    /// Same text as the web app's `FRESHNESS_LABEL`.
    public var label: String {
        switch self {
        case .fresh: "fresh"
        case .aging: "aging"
        case .stale: "stale — verify before trusting"
        case .unavailable: "unavailable"
        }
    }

    var rank: Int {
        switch self {
        case .fresh: 0
        case .aging: 1
        case .stale: 2
        case .unavailable: 3
        }
    }

    /// The least trustworthy of several; `fresh` for none.
    public static func worst(_ all: some Sequence<Freshness>) -> Freshness {
        all.max { $0.rank < $1.rank } ?? .fresh
    }
}

/// One layer's windows (`LayerFreshnessConfig` in the web app).
public struct FreshnessWindow: Sendable, Hashable, Codable {
    public let layerId: String
    public let freshMaxDays: Double
    public let agingMaxDays: Double
    public let staleMaxDays: Double

    enum CodingKeys: String, CodingKey {
        case layerId = "layer_id"
        case freshMaxDays = "fresh_max_days"
        case agingMaxDays = "aging_max_days"
        case staleMaxDays = "stale_max_days"
    }

    /// `freshnessOf`: whole days elapsed since UTC midnight of `publicationDate`.
    /// Accepts what `new Date(`${d}T00:00:00Z`)` accepts for dates (YYYY, YYYY-MM,
    /// YYYY-MM-DD, day overflow rolling into the next month); anything else is unavailable.
    public func freshness(publicationDate: String?, today: Date) -> Freshness {
        guard let publicationDate, let midnight = Self.utcMidnight(publicationDate) else { return .unavailable }
        return freshness(since: midnight, now: today)
    }

    /// The same rule for an instant such as a Worker `fetched_utc` or `model_run_utc`.
    public func freshness(since instant: Date?, now: Date) -> Freshness {
        guard let instant else { return .unavailable }
        let ageDays = (now.timeIntervalSince(instant) * 1000 / 86_400_000).rounded(.down)
        if ageDays <= freshMaxDays { return .fresh }
        if ageDays <= agingMaxDays { return .aging }
        return .stale
    }

    static func utcMidnight(_ s: String) -> Date? {
        guard let m = s.wholeMatch(of: /(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?/),
              let year = Int(m.1) else { return nil }
        let month = m.2.flatMap { Int($0) } ?? 1
        let day = m.3.flatMap { Int($0) } ?? 1
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let days = daysFromCivil(year: year, month: month, day: 1) + (day - 1)
        return Date(timeIntervalSince1970: Double(days) * 86_400)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/// `freshness_days` from `config/app-config.json`.
public struct FreshnessConfig: Sendable, Hashable, Decodable {
    /// The layer whose windows apply to live conditions (Worker fields).
    public static let conditionsLayer = "weather_forecast"

    public let layers: [String: FreshnessWindow]

    enum CodingKeys: String, CodingKey {
        case layers = "freshness_days"
    }

    public func window(_ layerId: String) throws -> FreshnessWindow {
        guard let w = layers[layerId] else { throw CocoaError(.coderValueNotFound) }
        return w
    }

    public func conditionsWindow() throws -> FreshnessWindow {
        try window(Self.conditionsLayer)
    }

    public static func decode(_ data: Data) throws -> FreshnessConfig {
        try JSONDecoder().decode(FreshnessConfig.self, from: data)
    }

    public static func bundled() throws -> FreshnessConfig {
        try decode(SharedResources.data("app-config.json"))
    }
}
