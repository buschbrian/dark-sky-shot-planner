public import Foundation

public enum Rating: Int, Sendable, Hashable, Comparable, Codable {
    case poor, marginal, good

    public static func < (a: Rating, b: Rating) -> Bool { a.rawValue < b.rawValue }
}

/// `config/conditions-thresholds.json`: the only place verdict thresholds live.
/// `opportunities` is not decoded here; aurora reaches the verdict as a flag.
public struct ConditionsThresholds: Sendable, Hashable, Decodable {
    public static let supportedRule = "worst_gating_factor"
    public static let supportedWindow = "moon_free_darkness"

    public enum Better: String, Sendable, Hashable, Codable {
        case lower, higher
    }

    public struct Factor: Sendable, Hashable, Decodable {
        public let label: String
        public let unit: String
        public let better: Better
        public let good: Double?
        public let marginal: Double?
        public let gatesVerdict: Bool
        public let note: String?

        enum CodingKeys: String, CodingKey {
            case label, unit, better, good, marginal
            case gatesVerdict = "gates_verdict"
            case note
        }

        /// Whether both edges are set; a factor with a `null` edge is shown, never rated.
        public var isRatable: Bool { good != nil && marginal != nil }

        /// Edges are inclusive: at `good` is good, at `marginal` is marginal.
        public func rate(_ value: Double) -> Rating? {
            guard let good, let marginal, value.isFinite else { return nil }
            switch better {
            case .lower: return value <= good ? .good : value <= marginal ? .marginal : .poor
            case .higher: return value >= good ? .good : value >= marginal ? .marginal : .poor
            }
        }

        /// 0 at the good edge, 1 at the marginal edge, above 1 poor. Orders readings
        /// that share a rating, so "worst" means furthest past the thresholds.
        public func severity(_ value: Double) -> Double? {
            guard let good, let marginal, value.isFinite else { return nil }
            let past = better == .lower ? value - good : good - value
            let span = abs(marginal - good)
            return span > 0 ? past / span : past
        }

        /// The less favourable of two raw values in this factor's direction.
        func worse(_ a: Double, _ b: Double) -> Double {
            better == .lower ? max(a, b) : min(a, b)
        }
    }

    public enum ConfigError: Error, Sendable, Hashable {
        case unsupportedRule(String)
        case unsupportedWindow(String)
    }

    public let version: Int
    public let status: String?
    public let verdictRule: String
    public let window: String
    public let factors: [String: Factor]

    enum CodingKeys: String, CodingKey {
        case version, status
        case verdictRule = "verdict_rule"
        case window, factors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        verdictRule = try c.decode(String.self, forKey: .verdictRule)
        window = try c.decode(String.self, forKey: .window)
        factors = try c.decode([String: Factor].self, forKey: .factors)
        guard verdictRule == Self.supportedRule else { throw ConfigError.unsupportedRule(verdictRule) }
        guard window == Self.supportedWindow else { throw ConfigError.unsupportedWindow(window) }
    }

    public static func decode(_ data: Data) throws -> ConditionsThresholds {
        try JSONDecoder().decode(ConditionsThresholds.self, from: data)
    }

    public static func bundled() throws -> ConditionsThresholds {
        try decode(SharedResources.data("conditions-thresholds.json"))
    }
}
