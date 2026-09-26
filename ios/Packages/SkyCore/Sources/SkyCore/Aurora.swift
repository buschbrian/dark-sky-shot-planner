public import Foundation

/// One planetary Kp value for the 3-hour interval starting at `start`.
public struct KpReading: Sendable, Hashable {
    public enum Kind: Int, Sendable, Hashable, Comparable {
        case predicted, estimated, observed

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// Worker `/v1/space-weather` values: `kp_observed` rows carry no kind;
        /// `kp_forecast` rows carry SWPC's `observed` column.
        init(worker kind: String?) {
            switch kind {
            case nil, "observed": self = .observed
            case "estimated": self = .estimated
            default: self = .predicted
            }
        }
    }

    public let start: Date
    public let kp: Double
    public let kind: Kind

    public init(start: Date, kp: Double, kind: Kind) {
        self.start = start
        self.kp = kp
        self.kind = kind
    }

    /// Kp is defined over 3-hour UT intervals.
    static let interval: TimeInterval = 3 * 3600

    var window: TimeWindow { TimeWindow(start: start, end: start.addingTimeInterval(Self.interval)) }
}

public enum AuroraOutlook: Sendable, Hashable {
    public enum Basis: Sendable, Hashable {
        /// The latest observed Kp, applied to the next dark window.
        case observedNow
        /// An observed or estimated interval inside the dark window.
        case observedInWindow
        /// A predicted interval inside the dark window.
        case forecastInWindow
    }

    public enum UnavailableReason: Sendable, Hashable {
        case noKpData
        /// The Kp rows do not reach across the whole dark window (SWPC forecasts ~3 days).
        case kpDoesNotCoverNight
        case noAstronomicalDarkness
    }

    case possible(kp: Double, visibleKp: Double, basis: Basis)
    /// Kp covers the whole dark window and stays below the visible Kp.
    case notExpected(maxKp: Double, visibleKp: Double)
    case unavailable(UnavailableReason)
    /// The spot is equatorward of every row of the visible-Kp table.
    case outOfRange(geomagneticLatDeg: Double)

    public var isPossible: Bool {
        if case .possible = self { true } else { false }
    }
}

/// `opportunities.kp_index` in `config/conditions-thresholds.json`: the NOAA
/// G-scale latitudes, applied in geomagnetic (centred dipole) latitude.
public struct AuroraRule: Sendable, Hashable, Decodable {
    public struct Pole: Sendable, Hashable, Decodable {
        public let latDeg: Double
        public let lonDeg: Double

        enum CodingKeys: String, CodingKey {
            case latDeg = "lat_deg"
            case lonDeg = "lon_deg"
        }
    }

    public struct VisibleKp: Sendable, Hashable, Decodable {
        public let noaaScale: String
        public let kpMin: Double
        public let geomagneticLatMinDeg: Double

        enum CodingKeys: String, CodingKey {
            case noaaScale = "noaa_scale"
            case kpMin = "kp_min"
            case geomagneticLatMinDeg = "geomagnetic_lat_min_deg"
        }
    }

    public let geomagneticNorthPole: Pole
    public let visibleKp: [VisibleKp]

    enum CodingKeys: String, CodingKey {
        case geomagneticNorthPole = "geomagnetic_north_pole"
        case visibleKp = "visible_kp"
    }

    private struct File: Decodable {
        struct Opportunities: Decodable {
            let kpIndex: AuroraRule
            enum CodingKeys: String, CodingKey { case kpIndex = "kp_index" }
        }
        let opportunities: Opportunities
    }

    /// Decodes a whole `conditions-thresholds.json`.
    public static func decode(thresholdsJSON data: Data) throws -> AuroraRule {
        try JSONDecoder().decode(File.self, from: data).opportunities.kpIndex
    }

    public static func bundled() throws -> AuroraRule {
        try decode(thresholdsJSON: SharedResources.data("conditions-thresholds.json"))
    }

    /// Centred-dipole geomagnetic latitude (degrees, negative in the south).
    public func geomagneticLatitude(_ observer: Observer) -> Double {
        let r = Double.pi / 180
        let lat = observer.latitude * r
        let poleLat = geomagneticNorthPole.latDeg * r
        let dLon = (observer.longitude - geomagneticNorthPole.lonDeg) * r
        let s = sin(lat) * sin(poleLat) + cos(lat) * cos(poleLat) * cos(dLon)
        return asin(max(-1, min(1, s))) / r
    }

    /// The lowest Kp at which aurora is flagged here; nil when no row reaches this far from the pole.
    public func visibleKpThreshold(_ observer: Observer) -> Double? {
        let mlat = abs(geomagneticLatitude(observer))
        return visibleKp.filter { mlat >= $0.geomagneticLatMinDeg }.map(\.kpMin).min()
    }

    /// - Parameters:
    ///   - darkness: the night's astronomical darkness window.
    ///   - isNextDarkWindow: this is the first night whose darkness has not ended at `now`,
    ///     so the Kp observed now applies to it.
    public func outlook(
        _ observer: Observer,
        darkness: TimeWindow?,
        readings: [KpReading],
        now: Date,
        isNextDarkWindow: Bool
    ) -> AuroraOutlook {
        guard let visible = visibleKpThreshold(observer) else {
            return .outOfRange(geomagneticLatDeg: geomagneticLatitude(observer))
        }
        guard !readings.isEmpty else { return .unavailable(.noKpData) }
        guard let darkness else { return .unavailable(.noAstronomicalDarkness) }

        // Per interval, what was observed outranks what was estimated or predicted.
        var best: [Date: KpReading] = [:]
        for r in readings where r.kp.isFinite {
            if let held = best[r.start], held.kind >= r.kind { continue }
            best[r.start] = r
        }
        let byStart = best.values.sorted { $0.start < $1.start }

        if isNextDarkWindow,
           let latest = byStart.last(where: { $0.kind == .observed && $0.start <= now }),
           now < latest.window.end.addingTimeInterval(KpReading.interval),
           latest.kp >= visible {
            return .possible(kp: latest.kp, visibleKp: visible, basis: .observedNow)
        }

        let inWindow = byStart.filter { $0.window.start < darkness.end && $0.window.end > darkness.start }
        if let peak = inWindow.max(by: { $0.kp < $1.kp }), peak.kp >= visible {
            return .possible(kp: peak.kp, visibleKp: visible, basis: peak.kind == .predicted ? .forecastInWindow : .observedInWindow)
        }

        var cursor = darkness.start
        for r in inWindow where r.window.start <= cursor {
            cursor = max(cursor, r.window.end)
        }
        guard cursor >= darkness.end, let peak = inWindow.max(by: { $0.kp < $1.kp }) else {
            return .unavailable(.kpDoesNotCoverNight)
        }
        return .notExpected(maxKp: peak.kp, visibleKp: visible)
    }
}
