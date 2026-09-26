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

/// One layer's windows (`LayerFreshnessConfig` in the web app), counted in
/// whole days (`freshness_days`) or whole hours (`freshness_hours`).
public struct FreshnessWindow: Sendable, Hashable, Codable {
    public enum Unit: String, Sendable, Hashable, Codable {
        case days, hours

        public var seconds: TimeInterval { self == .days ? 86_400 : 3_600 }
    }

    public let layerId: String
    public let unit: Unit
    public let freshMax: Double
    public let agingMax: Double
    public let staleMax: Double

    public init(layerId: String, unit: Unit, freshMax: Double, agingMax: Double, staleMax: Double) {
        self.layerId = layerId
        self.unit = unit
        self.freshMax = freshMax
        self.agingMax = agingMax
        self.staleMax = staleMax
    }

    public init(layerId: String, freshMaxDays: Double, agingMaxDays: Double, staleMaxDays: Double) {
        self.init(layerId: layerId, unit: .days, freshMax: freshMaxDays, agingMax: agingMaxDays, staleMax: staleMaxDays)
    }

    private enum CodingKeys: String, CodingKey {
        case layerId = "layer_id"
        case freshMaxDays = "fresh_max_days", agingMaxDays = "aging_max_days", staleMaxDays = "stale_max_days"
        case freshMaxHours = "fresh_max_hours", agingMaxHours = "aging_max_hours", staleMaxHours = "stale_max_hours"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let layerId = try c.decode(String.self, forKey: .layerId)
        if c.contains(.freshMaxHours) {
            self.init(
                layerId: layerId, unit: .hours,
                freshMax: try c.decode(Double.self, forKey: .freshMaxHours),
                agingMax: try c.decode(Double.self, forKey: .agingMaxHours),
                staleMax: try c.decode(Double.self, forKey: .staleMaxHours))
        } else {
            self.init(
                layerId: layerId, unit: .days,
                freshMax: try c.decode(Double.self, forKey: .freshMaxDays),
                agingMax: try c.decode(Double.self, forKey: .agingMaxDays),
                staleMax: try c.decode(Double.self, forKey: .staleMaxDays))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layerId, forKey: .layerId)
        let keys: (CodingKeys, CodingKeys, CodingKeys) = unit == .hours
            ? (.freshMaxHours, .agingMaxHours, .staleMaxHours)
            : (.freshMaxDays, .agingMaxDays, .staleMaxDays)
        try c.encode(freshMax, forKey: keys.0)
        try c.encode(agingMax, forKey: keys.1)
        try c.encode(staleMax, forKey: keys.2)
    }

    /// `freshnessOf`: whole days elapsed since UTC midnight of `publicationDate`.
    /// Accepts what `new Date(`${d}T00:00:00Z`)` accepts for dates (YYYY, YYYY-MM,
    /// YYYY-MM-DD, day overflow rolling into the next month); anything else is unavailable.
    public func freshness(publicationDate: String?, today: Date) -> Freshness {
        guard let publicationDate, let midnight = Self.utcMidnight(publicationDate) else { return .unavailable }
        return freshness(since: midnight, now: today)
    }

    /// The same rule for an instant such as a Worker `fetched_utc` or
    /// `model_run_utc`: whole units elapsed, floored.
    public func freshness(since instant: Date?, now: Date) -> Freshness {
        guard let instant else { return .unavailable }
        let age = (now.timeIntervalSince(instant) / unit.seconds).rounded(.down)
        if age <= freshMax { return .fresh }
        if age <= agingMax { return .aging }
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

/// `freshness_days` (published map layers) and `freshness_hours` (live
/// conditions) from `config/app-config.json`.
public struct FreshnessConfig: Sendable, Hashable, Decodable {
    /// The `freshness_hours` layer that applies to any Worker field no other
    /// hourly layer lists.
    public static let conditionsLayer = "weather_forecast"

    public let layers: [String: FreshnessWindow]
    public let hourlyLayers: [String: FreshnessWindow]
    /// Worker field name → the hourly layer that ages it.
    public let hourlyLayerForField: [String: String]

    private enum CodingKeys: String, CodingKey {
        case layers = "freshness_days"
        case hourlyLayers = "freshness_hours"
    }

    private struct FieldList: Decodable { let fields: [String]? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layers = try c.decode([String: FreshnessWindow].self, forKey: .layers)
        hourlyLayers = try c.decodeIfPresent([String: FreshnessWindow].self, forKey: .hourlyLayers) ?? [:]
        let lists = try c.decodeIfPresent([String: FieldList].self, forKey: .hourlyLayers) ?? [:]
        var byField: [String: String] = [:]
        for (layer, list) in lists {
            for field in list.fields ?? [] {
                guard byField.updateValue(layer, forKey: field) == nil else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .hourlyLayers, in: c, debugDescription: "\(field) is listed by two hourly layers")
                }
            }
        }
        hourlyLayerForField = byField
    }

    public func window(_ layerId: String) throws -> FreshnessWindow {
        guard let w = layers[layerId] ?? hourlyLayers[layerId] else { throw CocoaError(.coderValueNotFound) }
        return w
    }

    public func conditionsWindow() throws -> FreshnessWindow {
        guard let w = hourlyLayers[Self.conditionsLayer] else { throw CocoaError(.coderValueNotFound) }
        return w
    }

    public func conditionsFreshness() throws -> ConditionsFreshness {
        ConditionsFreshness(
            default: try conditionsWindow(),
            byField: try hourlyLayerForField.mapValues { try window($0) })
    }

    public static func decode(_ data: Data) throws -> FreshnessConfig {
        try JSONDecoder().decode(FreshnessConfig.self, from: data)
    }

    public static func bundled() throws -> FreshnessConfig {
        try decode(SharedResources.data("app-config.json"))
    }
}

/// Which hourly window ages each Worker field: sources update on different
/// schedules (hourly HRRR, twice-daily CAMS, daily RAP-Smoke).
public struct ConditionsFreshness: Sendable, Hashable {
    public let `default`: FreshnessWindow
    public let byField: [String: FreshnessWindow]

    public init(default: FreshnessWindow, byField: [String: FreshnessWindow] = [:]) {
        self.default = `default`
        self.byField = byField
    }

    public func window(forField field: String?) -> FreshnessWindow {
        field.flatMap { byField[$0] } ?? `default`
    }
}
