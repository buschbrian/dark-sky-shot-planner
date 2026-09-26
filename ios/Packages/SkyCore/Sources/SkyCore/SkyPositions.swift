public import Foundation
import CAstronomy

public enum SkyObject: String, Sendable, Hashable, Codable, CaseIterable {
    case sun, moon, mercury, venus, mars, jupiter, saturn, galacticCenter

    public static let planets: [SkyObject] = [.mercury, .venus, .mars, .jupiter, .saturn]

    var body: astro_body_t? {
        switch self {
        case .sun: BODY_SUN
        case .moon: BODY_MOON
        case .mercury: BODY_MERCURY
        case .venus: BODY_VENUS
        case .mars: BODY_MARS
        case .jupiter: BODY_JUPITER
        case .saturn: BODY_SATURN
        case .galacticCenter: nil
        }
    }
}

public struct SkySample: Sendable, Hashable, Codable {
    public let date: Date
    public let position: HorizontalPosition
}

/// A point on the galactic plane (b = 0) placed on the observer's sky.
public struct GalacticBandPoint: Sendable, Hashable, Codable {
    public let galacticLongitudeDeg: Double
    public let position: HorizontalPosition
}

public enum SkyPositions {
    /// Topocentric position of `object`. Sun, Moon and planets use the
    /// equator of date with aberration (as the web planner's moon-up test
    /// does). The GC is precessed from J2000 to the date, so with `.none`
    /// refraction it equals `gcAltitude`/`gcAzimuth` exactly.
    public static func position(
        of object: SkyObject, at date: Date, observer: Observer, refraction: Refraction
    ) throws(AstronomyError) -> HorizontalPosition {
        guard let body = object.body else {
            return Planner.gcPosition(observer, at: date, refraction: refraction)
        }
        return try bodyPosition(body, at: date, observer: observer, refraction: refraction)
    }

    /// Samples from `start` to `end` inclusive, every `step` seconds.
    public static func series(
        of object: SkyObject, from start: Date, to end: Date, step: TimeInterval,
        observer: Observer, refraction: Refraction
    ) throws(AstronomyError) -> [SkySample] {
        precondition(step > 0, "step must be positive")
        var out: [SkySample] = []
        var t = start
        while t <= end {
            out.append(SkySample(date: t, position: try position(of: object, at: t, observer: observer, refraction: refraction)))
            t = t.addingTimeInterval(step)
        }
        return out
    }

    /// The Milky Way's mid-plane (galactic latitude 0) sampled every
    /// `stepDeg` of galactic longitude from 0 up to (not including) 360.
    /// Uses astronomy-engine's GAL→EQJ→HOR rotations, so precession and
    /// nutation are applied, as for the GC.
    public static func milkyWayBand(
        at date: Date, observer: Observer, stepDeg: Double = 5, refraction: Refraction
    ) throws(AstronomyError) -> [GalacticBandPoint] {
        precondition(stepDeg > 0 && stepDeg <= 360, "stepDeg must be in (0, 360]")
        var time = AstroTime.from(date)
        let galToEqj = Astronomy_Rotation_GAL_EQJ()
        let eqjToHor = Astronomy_Rotation_EQJ_HOR(&time, observer.c)
        try check(galToEqj.status, "Rotation_GAL_EQJ")
        try check(eqjToHor.status, "Rotation_EQJ_HOR")
        let rotation = Astronomy_CombineRotation(galToEqj, eqjToHor)
        try check(rotation.status, "CombineRotation")

        var points: [GalacticBandPoint] = []
        var l = 0.0
        while l < 360 {
            let sphere = astro_spherical_t(status: ASTRO_SUCCESS, lat: 0, lon: l, dist: 1)
            let gal = Astronomy_VectorFromSphere(sphere, time)
            try check(gal.status, "VectorFromSphere")
            let hor = Astronomy_RotateVector(rotation, gal)
            try check(hor.status, "RotateVector")
            let h = Astronomy_HorizonFromVector(hor, refraction.c)
            try check(h.status, "HorizonFromVector")
            points.append(GalacticBandPoint(
                galacticLongitudeDeg: l,
                position: HorizontalPosition(altitudeDeg: h.lat, azimuthDeg: h.lon)))
            l += stepDeg
        }
        return points
    }

    static func bodyPosition(
        _ body: astro_body_t, at date: Date, observer: Observer, refraction: Refraction
    ) throws(AstronomyError) -> HorizontalPosition {
        var time = AstroTime.from(date)
        let eq = Astronomy_Equator(body, &time, observer.c, EQUATOR_OF_DATE, ABERRATION)
        try check(eq.status, "Equator")
        let hor = Astronomy_Horizon(&time, observer.c, eq.ra, eq.dec, refraction.c)
        return HorizontalPosition(altitudeDeg: hor.altitude, azimuthDeg: hor.azimuth)
    }

    static func fixedPosition(
        raHours: Double, decDeg: Double, at date: Date, observer: Observer, refraction: Refraction
    ) -> HorizontalPosition {
        var time = AstroTime.from(date)
        let hor = Astronomy_Horizon(&time, observer.c, raHours, decDeg, refraction.c)
        return HorizontalPosition(altitudeDeg: hor.altitude, azimuthDeg: hor.azimuth)
    }
}
