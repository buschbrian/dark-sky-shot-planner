public import Foundation

/// A meteor shower radiant as the Sky view needs it. The Sky view does not
/// know any showers itself: the sky-events code (ADR-0008, the curated
/// `config/sky-events.json`) supplies them through `SkyRadiantProviding`.
public struct SkyRadiant: Sendable, Hashable, Identifiable {
    /// Stable id, e.g. the IMO code ("PER").
    public let id: String
    public let name: String
    /// Radiant J2000 RA and Dec at `peak` (or mid-activity), degrees.
    public let raDeg: Double
    public let decDeg: Double
    public let activeFrom: Date
    public let activeUntil: Date
    public let peak: Date?
    /// Zenithal hourly rate at the peak; nil when the source gives none.
    public let zhr: Double?
    /// IMO population index r; 2.5 when unknown.
    public let populationIndex: Double?
    /// Daily radiant drift (IMO calendar), degrees per day, applied from `peak`.
    public let driftRADegPerDay: Double
    public let driftDecDegPerDay: Double
    /// Where the numbers came from (ADR-0008), and whether a person checked them.
    public let sourceURL: URL?
    public let verified: Bool

    public init(
        id: String, name: String, raDeg: Double, decDeg: Double, activeFrom: Date, activeUntil: Date,
        peak: Date? = nil, zhr: Double? = nil, populationIndex: Double? = nil,
        driftRADegPerDay: Double = 0, driftDecDegPerDay: Double = 0, sourceURL: URL? = nil, verified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.raDeg = raDeg
        self.decDeg = decDeg
        self.activeFrom = activeFrom
        self.activeUntil = activeUntil
        self.peak = peak
        self.zhr = zhr
        self.populationIndex = populationIndex
        self.driftRADegPerDay = driftRADegPerDay
        self.driftDecDegPerDay = driftDecDegPerDay
        self.sourceURL = sourceURL
        self.verified = verified
    }

    public func isActive(at date: Date) -> Bool { date >= activeFrom && date <= activeUntil }

    /// Radiant J2000 RA/Dec at `date`, drifting linearly from the peak.
    public func equatorial(at date: Date) -> (raDeg: Double, decDeg: Double) {
        guard let peak else { return (raDeg, decDeg) }
        let days = date.timeIntervalSince(peak) / 86400
        return (Geodesy.normalizedAzimuth(raDeg + driftRADegPerDay * days), max(-90, min(90, decDeg + driftDecDegPerDay * days)))
    }
}

/// Feeds radiants to the Sky view. The events code conforms a type (for
/// example one backed by `config/sky-events.json`) and sets it on the Sky
/// screen's environment; the Sky view asks for what is active at its time.
public protocol SkyRadiantProviding: Sendable {
    func radiants(activeAt date: Date) -> [SkyRadiant]
}

/// A fixed list, for tests, previews and simple adapters.
public struct StaticRadiants: SkyRadiantProviding {
    public let all: [SkyRadiant]
    public init(_ all: [SkyRadiant]) { self.all = all }
    public func radiants(activeAt date: Date) -> [SkyRadiant] { all.filter { $0.isActive(at: date) } }
}

public enum MeteorRadiants {
    /// Apparent (refracted) radiant position.
    public static func position(of radiant: SkyRadiant, at date: Date, observer: Observer) -> HorizontalPosition {
        HorizontalPosition(reference: referenceVector(of: radiant, at: date, observer: observer))
    }

    public static func referenceVector(of radiant: SkyRadiant, at date: Date, observer: Observer) -> SIMD3<Double> {
        let eq = radiant.equatorial(at: date)
        return SkyRotation.refracted(
            SkyRotation.eqjToReference(at: date, observer: observer) * SkyRotation.vector(raDeg: eq.raDeg, decDeg: eq.decDeg))
    }

    /// Expected meteors an hour for one observer, the IMO definition of ZHR
    /// run backwards (imo.net, "ZHR"): HR = ZHR · sin(h) / r^(6.5 − LM).
    /// Zero with the radiant down; nil when the shower has no ZHR.
    public static func hourlyRate(radiant: SkyRadiant, radiantAltitudeDeg h: Double, limitingMagnitude lm: Double = 6.5) -> Double? {
        guard let zhr = radiant.zhr else { return nil }
        guard h > 0 else { return 0 }
        let r = radiant.populationIndex ?? 2.5
        return zhr * sin(h * .pi / 180) / pow(r, 6.5 - min(lm, 6.5))
    }

    /// Short great-circle arcs pointing away from the radiant, the way its
    /// meteors travel: `count` directions, each from `from` to `to` degrees
    /// out, as reference-frame vectors. The first direction is straight up
    /// from the radiant (toward the zenith) when that is defined.
    public static func directionHints(
        radiant r: SIMD3<Double>, count: Int = 8, from: Double = 12, to: Double = 30, samples: Int = 6
    ) -> [[SIMD3<Double>]] {
        let radiant = r / (r * r).sum().squareRoot()
        // A tangent basis at the radiant: toward the zenith, and across.
        var up = SIMD3<Double>(0, 0, 1) - radiant * radiant.z
        if (up * up).sum() < 1e-10 { up = SIMD3(1, 0, 0) - radiant * radiant.x }
        up /= (up * up).sum().squareRoot()
        let across = SIMD3(radiant.y * up.z - radiant.z * up.y, radiant.z * up.x - radiant.x * up.z, radiant.x * up.y - radiant.y * up.x)
        return (0..<count).map { k in
            let theta = 2 * Double.pi * Double(k) / Double(count)
            let tangent = up * cos(theta) + across * sin(theta)
            return (0..<samples).map { s in
                let d = (from + (to - from) * Double(s) / Double(max(samples - 1, 1))) * .pi / 180
                return radiant * cos(d) + tangent * sin(d)
            }
        }
    }
}
