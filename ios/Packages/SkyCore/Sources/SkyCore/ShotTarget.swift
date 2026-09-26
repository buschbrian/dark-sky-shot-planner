import Foundation
import CAstronomy

/// What one shot points at (M11). Positions follow the planner's conventions:
/// the GC and the Milky Way band are geometric (ADR-0002 amendment), the Moon
/// is its refracted top limb (the rise/set rule), planets and fixed targets
/// are refracted apparent positions, which is what the camera sees.
public enum ShotTarget: Sendable, Hashable, Codable {
    /// Sgr A*, as `Planner.gcPosition`.
    case galacticCore
    /// A stretch of the galactic plane (b = 0) from `fromL` to `toL` degrees of
    /// galactic longitude, increasing and wrapping through 0. It "clears" when
    /// every point of the stretch stands above the skyline.
    case milkyWayArch(MilkyWaySegment)
    case moon
    /// One of `SkyObject.planets`.
    case planet(SkyObject)
    /// A bright star, deep-sky object or constellation center (J2000 RA/Dec),
    /// precessed to the date before any horizon math.
    case fixed(FixedTarget)

    public static let presets: [ShotTarget] =
        [.galacticCore, .milkyWayArch(.coreToCygnus), .milkyWayArch(.cygnusToCassiopeia), .moon]
        + SkyObject.planets.map(ShotTarget.planet)
        + FixedTarget.catalog.map(ShotTarget.fixed)

    public var name: String {
        switch self {
        case .galacticCore: "Galactic Core"
        case .milkyWayArch(let s): "Milky Way arch (\(s.name))"
        case .moon: "Moon"
        case .planet(let p): p.rawValue.prefix(1).uppercased() + p.rawValue.dropFirst()
        case .fixed(let f): f.name
        }
    }

    /// The short subject of a sentence: "Core clears the ridge 23:40".
    public var shortName: String {
        switch self {
        case .galacticCore: "Core"
        case .milkyWayArch: "Arch"
        default: name
        }
    }

    /// The Moon is the one target that needs no moon-free darkness.
    public var needsMoonFree: Bool { self != .moon }

    /// Stable id for persistence and pickers.
    public var id: String {
        switch self {
        case .galacticCore: "gc"
        case .milkyWayArch(let s): "arch:\(s.fromL):\(s.toL)"
        case .moon: "moon"
        case .planet(let p): "planet:\(p.rawValue)"
        case .fixed(let f): "fixed:\(f.name):\(f.raHours):\(f.decDeg)"
        }
    }
}

public struct MilkyWaySegment: Sendable, Hashable, Codable {
    public let name: String
    public let fromL: Double
    public let toL: Double

    public init(name: String, fromL: Double, toL: Double) {
        self.name = name
        self.fromL = fromL
        self.toL = toL
    }

    /// Sagittarius (l = 0, the core) up to Cygnus (l = 80): the summer arch
    /// seen from the Mountain West.
    public static let coreToCygnus = MilkyWaySegment(name: "core to Cygnus", fromL: 0, toL: 80)
    /// Cygnus to Cassiopeia (l = 80–120), overhead on autumn evenings.
    public static let cygnusToCassiopeia = MilkyWaySegment(name: "Cygnus to Cassiopeia", fromL: 80, toL: 120)

    /// Galactic longitudes sampled every `stepDeg`, both ends included.
    public func longitudes(stepDeg: Double = 5) -> [Double] {
        let span = ((toL - fromL).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let n = max(1, Int((span / stepDeg).rounded(.up)))
        return (0...n).map { i in
            ((fromL + span * Double(i) / Double(n)).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
        }
    }

    /// Middle of the stretch, the point the track reports for orientation.
    public var midL: Double {
        let span = ((toL - fromL).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return (fromL + span / 2).truncatingRemainder(dividingBy: 360)
    }
}

public struct FixedTarget: Sendable, Hashable, Codable {
    public let name: String
    public let raHours: Double
    public let decDeg: Double

    public init(name: String, raHours: Double, decDeg: Double) {
        self.name = name
        self.raHours = raHours
        self.decDeg = decDeg
    }

    /// J2000 positions (SIMBAD, rounded to 1″); proper motion is ignored
    /// (under 1′ over decades for all of these).
    public static let catalog: [FixedTarget] = [
        FixedTarget(name: "Andromeda Galaxy (M31)", raHours: 0.712306, decDeg: 41.269167),
        FixedTarget(name: "Pleiades (M45)", raHours: 3.790833, decDeg: 24.116667),
        FixedTarget(name: "Orion Nebula (M42)", raHours: 5.588139, decDeg: -5.391111),
        FixedTarget(name: "Betelgeuse", raHours: 5.919528, decDeg: 7.406944),
        FixedTarget(name: "Sirius", raHours: 6.752472, decDeg: -16.716111),
        FixedTarget(name: "Arcturus", raHours: 14.261028, decDeg: 19.182500),
        FixedTarget(name: "Antares", raHours: 16.490111, decDeg: -26.431944),
        FixedTarget(name: "Vega", raHours: 18.615639, decDeg: 38.783611),
        FixedTarget(name: "Altair", raHours: 19.846389, decDeg: 8.868333),
        FixedTarget(name: "Deneb", raHours: 20.690528, decDeg: 45.280278),
        FixedTarget(name: "Polaris", raHours: 2.530306, decDeg: 89.264167),
    ]
}

extension ShotTarget {
    /// Where the target stands, and the altitude that counts for clearance:
    /// the band's lowest point above its skyline, anyone else's own altitude.
    struct Placement {
        /// Reported in the track: the target itself, or the band's midpoint.
        let position: HorizontalPosition
        /// Degrees above the effective horizon (`threshold(az)`); > 0 is clear.
        let clearanceDeg: Double
    }

    func placement(
        _ observer: Observer, at date: Date, threshold: (Double) -> Double
    ) throws(AstronomyError) -> Placement {
        switch self {
        case .galacticCore:
            let p = Planner.gcPosition(observer, at: date)
            return Placement(position: p, clearanceDeg: p.altitudeDeg - threshold(p.azimuthDeg))
        case .moon:
            let p = try Self.moonTopLimb(observer, at: date)
            return Placement(position: p, clearanceDeg: p.altitudeDeg - threshold(p.azimuthDeg))
        case .planet(let object):
            let p = try SkyPositions.position(of: object, at: date, observer: observer, refraction: .normal)
            return Placement(position: p, clearanceDeg: p.altitudeDeg - threshold(p.azimuthDeg))
        case .fixed(let f):
            let eqd = Self.equatorOfDate(raHours: f.raHours, decDeg: f.decDeg, at: date)
            let p = SkyPositions.fixedPosition(
                raHours: eqd.raHours, decDeg: eqd.decDeg, at: date, observer: observer, refraction: .normal)
            return Placement(position: p, clearanceDeg: p.altitudeDeg - threshold(p.azimuthDeg))
        case .milkyWayArch(let segment):
            let points = try Self.galacticPoints(segment.longitudes() + [segment.midL], observer: observer, at: date)
            let clearance = points.dropLast().map { $0.altitudeDeg - threshold($0.azimuthDeg) }.min()!
            return Placement(position: points.last!, clearanceDeg: clearance)
        }
    }

    /// The Moon's top limb with standard refraction at its altitude, as
    /// `Planner.moonClearanceDeg` measures it against a skyline.
    static func moonTopLimb(_ observer: Observer, at date: Date) throws(AstronomyError) -> HorizontalPosition {
        var time = AstroTime.from(date)
        let eq = Astronomy_Equator(BODY_MOON, &time, observer.c, EQUATOR_OF_DATE, ABERRATION)
        try check(eq.status, "Equator(moon)")
        let hor = Astronomy_Horizon(&time, observer.c, eq.ra, eq.dec, REFRACTION_NORMAL)
        let topLimb = hor.altitude + RAD2DEG * (MOON_EQUATORIAL_RADIUS_KM / KM_PER_AU / eq.dist)
        return HorizontalPosition(altitudeDeg: topLimb, azimuthDeg: hor.azimuth)
    }

    /// J2000 RA/Dec on the true equator of date, as `Planner.gcEquatorOfDate`.
    static func equatorOfDate(raHours: Double, decDeg: Double, at date: Date) -> (raHours: Double, decDeg: Double) {
        var time = AstroTime.from(date)
        let rotation = Astronomy_Rotation_EQJ_EQD(&time)
        let eqj = Astronomy_VectorFromSphere(
            astro_spherical_t(status: ASTRO_SUCCESS, lat: decDeg, lon: raHours * 15, dist: 1), time)
        let eqd = Astronomy_EquatorFromVector(Astronomy_RotateVector(rotation, eqj))
        precondition(eqd.status == ASTRO_SUCCESS, "precession failed: \(eqd.status)")
        return (eqd.ra, eqd.dec)
    }

    /// Geometric alt/az of galactic-plane points, like `SkyPositions.milkyWayBand`.
    static func galacticPoints(
        _ longitudes: [Double], observer: Observer, at date: Date
    ) throws(AstronomyError) -> [HorizontalPosition] {
        var time = AstroTime.from(date)
        let galToEqj = Astronomy_Rotation_GAL_EQJ()
        let eqjToHor = Astronomy_Rotation_EQJ_HOR(&time, observer.c)
        try check(galToEqj.status, "Rotation_GAL_EQJ")
        try check(eqjToHor.status, "Rotation_EQJ_HOR")
        let rotation = Astronomy_CombineRotation(galToEqj, eqjToHor)
        try check(rotation.status, "CombineRotation")
        var out: [HorizontalPosition] = []
        for l in longitudes {
            let gal = Astronomy_VectorFromSphere(astro_spherical_t(status: ASTRO_SUCCESS, lat: 0, lon: l, dist: 1), time)
            let h = Astronomy_HorizonFromVector(Astronomy_RotateVector(rotation, gal), REFRACTION_NONE)
            try check(h.status, "HorizonFromVector")
            out.append(HorizontalPosition(altitudeDeg: h.lat, azimuthDeg: h.lon))
        }
        return out
    }
}
