public import Foundation

/// Mirrors of `worker/src/types.ts` and the shapes built in `worker/src/routes.ts`.
/// `shared/golden/{conditions,space-weather}-response.json` are the contract.
public enum WorkerStatus: String, Sendable, Hashable, Codable {
    case ok, unavailable

    /// A status this client doesn't know is treated as unavailable, never ok.
    public init(from decoder: any Decoder) throws {
        self = WorkerStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unavailable
    }
}

public struct WorkerPoint: Sendable, Hashable, Codable {
    public let t: Date
    /// Null upstream stays nil: missing, never 0.
    public let v: Double?

    public init(t: Date, v: Double?) {
        self.t = t
        self.v = v
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(v, forKey: .v)
    }
}

public struct WorkerSeries: Sendable, Hashable, Codable {
    public let model: String
    public let upstreamModel: String?
    public let modelRunUTC: Date?
    public let fetchedUTC: Date?
    public let status: WorkerStatus
    public let reason: String?
    public let lastGoodUTC: Date?
    public let values: [WorkerPoint]

    enum CodingKeys: String, CodingKey {
        case model
        case upstreamModel = "upstream_model"
        case modelRunUTC = "model_run_utc"
        case fetchedUTC = "fetched_utc"
        case status, reason
        case lastGoodUTC = "last_good_utc"
        case values
    }

    /// The time the data describes the sky as of: the older of the model run and
    /// the fetch (or the last good fetch), so an age never flatters the data.
    public var asOfUTC: Date? {
        [modelRunUTC, fetchedUTC ?? lastGoodUTC].compactMap(\.self).min()
    }
}

/// An AirNow row as `worker/src/sources/airnow.ts` reports it.
public struct AirNowObservation: Sendable, Hashable, Codable {
    public let parameter: String
    public let aqi: Double
    public let category: String
    public let categoryNumber: Int
    public let reportingArea: String?
    public let siteName: String?
    public let reportingAgency: String?
    public let observedLocal: String
    public let localTimeZone: String?
    public let observedUTC: Date?

    enum CodingKeys: String, CodingKey {
        case parameter, aqi, category
        case categoryNumber = "category_number"
        case reportingArea = "reporting_area"
        case siteName = "site_name"
        case reportingAgency = "reporting_agency"
        case observedLocal = "observed_local"
        case localTimeZone = "local_time_zone"
        case observedUTC = "observed_utc"
    }
}

/// `Field`, plus the per-source extras the Worker adds.
public struct WorkerField: Sendable, Hashable, Codable {
    public let unit: String
    public let source: String
    public let status: WorkerStatus
    public let fetchedUTC: Date?
    public let series: [WorkerSeries]
    public let reason: String?
    public let lastGoodUTC: Date?
    public let observations: [AirNowObservation]?
    public let preliminary: Bool?
    public let attribution: String?
    public let description: String?
    public let valueKind: String?
    public let calibrated: Bool?
    public let calibration: String?
    public let resolutionNote: String?
    public let terms: String?
    public let optional: Bool?

    enum CodingKeys: String, CodingKey {
        case unit, source, status
        case fetchedUTC = "fetched_utc"
        case series, reason
        case lastGoodUTC = "last_good_utc"
        case observations, preliminary, attribution, description
        case valueKind = "value_kind"
        case calibrated, calibration
        case resolutionNote = "resolution_note"
        case terms, optional
    }
}

public struct WorkerCell: Sendable, Hashable, Codable {
    public let lat: Double
    public let lon: Double
    public let roundingDeg: Double

    enum CodingKeys: String, CodingKey {
        case lat, lon
        case roundingDeg = "rounding_deg"
    }
}

/// `GET /v1/conditions`.
public struct ConditionsResponse: Sendable, Hashable, Codable {
    public struct Window: Sendable, Hashable, Codable {
        public let startUTC: Date
        public let endUTC: Date

        enum CodingKeys: String, CodingKey {
            case startUTC = "start_utc"
            case endUTC = "end_utc"
        }
    }

    public let cell: WorkerCell
    public let window: Window
    public let generatedUTC: Date
    public let fields: [String: WorkerField]
    public let attribution: [String]

    enum CodingKeys: String, CodingKey {
        case cell, window
        case generatedUTC = "generated_utc"
        case fields, attribution
    }

    public static func decode(_ data: Data) throws -> ConditionsResponse {
        try WorkerJSON.decoder().decode(ConditionsResponse.self, from: data)
    }
}

/// `GET /v1/space-weather`.
public struct SpaceWeatherResponse: Sendable, Hashable, Codable {
    public struct KpPoint: Sendable, Hashable, Codable {
        public let t: Date
        public let v: Double
        /// "observed", "estimated" or "predicted" on forecast rows.
        public let kind: String?
        public let noaaScale: String?

        enum CodingKeys: String, CodingKey {
            case t, v, kind
            case noaaScale = "noaa_scale"
        }
    }

    public struct KpBlock: Sendable, Hashable, Codable {
        public let source: String
        public let unit: String
        public let status: WorkerStatus
        public let reason: String?
        public let fetchedUTC: Date?
        public let lastGoodUTC: Date?
        public let values: [KpPoint]

        enum CodingKeys: String, CodingKey {
            case source, unit, status, reason
            case fetchedUTC = "fetched_utc"
            case lastGoodUTC = "last_good_utc"
            case values
        }
    }

    public struct NearCell: Sendable, Hashable, Codable {
        public let lat: Double
        public let lon: Double
        public let probabilityPct: Double
        public let method: String

        enum CodingKeys: String, CodingKey {
            case lat, lon
            case probabilityPct = "probability_pct"
            case method
        }
    }

    public struct Aurora: Sendable, Hashable, Codable {
        public let source: String
        public let status: WorkerStatus
        public let fetchedUTC: Date?
        public let reason: String?
        public let lastGoodUTC: Date?
        public let observationTimeUTC: Date?
        public let forecastTimeUTC: Date?
        public let nearCell: NearCell?

        enum CodingKeys: String, CodingKey {
            case source, status
            case fetchedUTC = "fetched_utc"
            case reason
            case lastGoodUTC = "last_good_utc"
            case observationTimeUTC = "observation_time_utc"
            case forecastTimeUTC = "forecast_time_utc"
            case nearCell = "near_cell"
        }
    }

    public let generatedUTC: Date
    public let cache: String
    public let kpObserved: KpBlock
    public let kpForecast: KpBlock
    public let aurora: Aurora

    enum CodingKeys: String, CodingKey {
        case generatedUTC = "generated_utc"
        case cache
        case kpObserved = "kp_observed"
        case kpForecast = "kp_forecast"
        case aurora
    }

    public static func decode(_ data: Data) throws -> SpaceWeatherResponse {
        try WorkerJSON.decoder().decode(SpaceWeatherResponse.self, from: data)
    }
}

/// ISO 8601 UTC, as the Worker's `iso()` writes it; fractional seconds are accepted.
public enum WorkerJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO 8601 time: \(s)")
            }
            return date
        }
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(Date.ISO8601FormatStyle()))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func parse(_ s: String) -> Date? {
        (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: Date.ISO8601FormatStyle()))
    }
}
