public import Foundation
import CAstronomy

// Apparent star places for the Sky view. The catalogue's J2000 positions get
// proper motion to the date and annual aberration once per night (both move
// a star by well under an arcsecond in a night); each frame then needs one
// rotation from the J2000 equator to the observer's horizon, which
// astronomy-engine builds with precession, nutation and sidereal time, and
// standard refraction per star. astronomy-engine's HOR frame is (north,
// west, zenith), exactly Core Motion's `.xTrueNorthZVertical` reference frame
// (SkyFrames.swift, frame 3), so its output feeds `DeviceAttitude` directly.

extension RotationMatrix {
    /// astronomy-engine's `rot[i][j]` maps input component i to output
    /// component j (`Astronomy_RotateVector`), so its matrix is the transpose.
    init(_ r: astro_rotation_t) {
        let m = r.rot
        self.init(
            m11: m.0.0, m12: m.1.0, m13: m.2.0,
            m21: m.0.1, m22: m.1.1, m23: m.2.1,
            m31: m.0.2, m32: m.1.2, m33: m.2.2)
    }
}

public enum SkyRotation {
    /// J2000 equatorial (EQJ) → Core Motion reference frame (north, west, up)
    /// at `date`: precession, nutation, Earth rotation. Geometric (no refraction).
    public static func eqjToReference(at date: Date, observer: Observer) -> RotationMatrix {
        var time = AstroTime.from(date)
        return RotationMatrix(Astronomy_Rotation_EQJ_HOR(&time, observer.c))
    }

    /// astronomy-engine's `REFRACTION_NORMAL` (Saemundsson, as JPL Horizons),
    /// inlined for the per-frame star loop; below −1° it defers to the C code,
    /// which tapers refraction toward the nadir. Same numbers either way.
    @inline(__always)
    static func refractionDeg(_ altitude: Double) -> Double {
        guard altitude >= -1, altitude <= 90 else { return Astronomy_Refraction(REFRACTION_NORMAL, altitude) }
        return 1.02 / tan((altitude + 10.3 / (altitude + 5.11)) * .pi / 180) / 60
    }

    /// Galactic (l, b) → EQJ, constant.
    public static let galacticToEQJ = RotationMatrix(Astronomy_Rotation_GAL_EQJ())

    /// True equator of date → EQJ at `date`, whose third column is the
    /// celestial pole of date written in J2000 coordinates.
    public static func eqdToEQJ(at date: Date) -> RotationMatrix {
        var time = AstroTime.from(date)
        return RotationMatrix(Astronomy_Rotation_EQD_EQJ(&time))
    }

    /// Unit vector for a J2000 right ascension and declination.
    public static func vector(raDeg: Double, decDeg: Double) -> SIMD3<Double> {
        let ra = raDeg * .pi / 180, dec = decDeg * .pi / 180
        return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }

    /// A reference-frame direction lifted by standard refraction
    /// (astronomy-engine's `REFRACTION_NORMAL`, the same as `Horizon()`).
    public static func refracted(_ r: SIMD3<Double>) -> SIMD3<Double> {
        let horizontal = (r.x * r.x + r.y * r.y).squareRoot()
        guard horizontal > 1e-12 else { return r }
        let alt = atan2(r.z, horizontal) * 180 / .pi
        let lifted = (alt + refractionDeg(alt)) * .pi / 180
        let length = (horizontal * horizontal + r.z * r.z).squareRoot()
        let s = cos(lifted) * length / horizontal
        return SIMD3(r.x * s, r.y * s, sin(lifted) * length)
    }
}

/// The catalogue's stars as apparent J2000-frame unit vectors for one night.
public struct StarField: Sendable {
    public let catalog: StarCatalog
    public let epoch: Date
    /// In catalogue order: proper motion to `epoch`, then annual aberration.
    public let apparentEQJ: [SIMD3<Double>]
    /// Catalogue indices sorted from brightest to faintest.
    public let byBrightness: [Int]

    public init(catalog: StarCatalog, epoch: Date) {
        self.catalog = catalog
        self.epoch = epoch
        let years = epoch.timeIntervalSince(StarField.j2000) / (365.25 * 86400)
        let time = AstroTime.from(epoch)
        // Earth's barycentric velocity in EQJ, AU/day; v/c ≈ 1e-4 rad (20″).
        let earth = Astronomy_BaryState(BODY_EARTH, time)
        let beta = earth.status == ASTRO_SUCCESS
            ? SIMD3(earth.vx, earth.vy, earth.vz) / StarField.lightAUPerDay : .zero
        apparentEQJ = catalog.stars.map { star in
            let dec = star.decDeg + star.pmDecmas * years / 3.6e6
            let cosDec = max(cos(star.decDeg * .pi / 180), 1e-6)
            let ra = star.raDeg + star.pmRAmas * years / 3.6e6 / cosDec
            let v = SkyRotation.vector(raDeg: ra, decDeg: dec) + beta
            return v / (v * v).sum().squareRoot()
        }
        byBrightness = catalog.stars.indices.sorted { catalog.stars[$0].vmag < catalog.stars[$1].vmag }
    }

    static let j2000 = Date(timeIntervalSince1970: AstroTime.j2000UnixMs / 1000)
    static let lightAUPerDay = 173.1446326846693

    /// Apparent (refracted) position of catalogue star `index`.
    public func position(ofStarAt index: Int, at date: Date, observer: Observer) -> HorizontalPosition {
        let r = SkyRotation.eqjToReference(at: date, observer: observer) * apparentEQJ[index]
        return HorizontalPosition(reference: SkyRotation.refracted(r))
    }

    /// Apparent place of `index` on the true equator of date: RA in hours, Dec in degrees.
    public func equatorOfDate(ofStarAt index: Int, at date: Date) -> (raHours: Double, decDeg: Double) {
        let v = SkyRotation.eqdToEQJ(at: date).transposed * apparentEQJ[index]
        let ra = Geodesy.normalizedAzimuth(atan2(v.y, v.x) * 180 / .pi) / 15
        return (ra, asin(max(-1, min(1, v.z))) * 180 / .pi)
    }

    /// Unit J2000 direction of a constellation figure's centre (the mean of its stars).
    public func centre(of figure: ConstellationFigure) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        for hr in figure.starHRs {
            if let i = catalog.index(ofHR: hr) { sum += apparentEQJ[i] }
        }
        let n = (sum * sum).sum().squareRoot()
        return n > 0 ? sum / n : SkyRotation.vector(raDeg: figure.labelRADeg, decDeg: figure.labelDecDeg)
    }
}

/// A star placed on the screen for one frame.
public struct ProjectedStar: Sendable, Hashable {
    public let index: Int
    public let u: Double
    public let v: Double
    public let altitudeDeg: Double
    /// Catalogue V plus atmospheric extinction at this altitude.
    public let apparentMagnitude: Double
}

/// Terrain altitude by whole half-degree of azimuth, for per-star tests at display rate.
public struct HorizonLookup: Sendable, Hashable {
    let table: [Double]

    public init(_ profile: HorizonProfile?) {
        table = (0..<720).map { profile?.altitudeDeg(atAzimuth: Double($0) / 2) ?? 0 }
    }

    public func altitudeDeg(atAzimuth azimuthDeg: Double) -> Double {
        let i = Int((Geodesy.normalizedAzimuth(azimuthDeg) * 2).rounded()) % 720
        return table[i]
    }
}

extension StarField {
    /// Every star brighter than `magnitudeLimit` (after extinction) that is
    /// above the terrain and inside the view, expanded by `margin` points.
    /// `eqjToReference` is `SkyRotation.eqjToReference` for the frame's time.
    public func project(
        through projector: SkyProjector, eqjToReference rotation: RotationMatrix,
        magnitudeLimit: Double, extinction: Extinction, horizon: HorizonLookup, margin: Double = 8
    ) -> [ProjectedStar] {
        let k = projector.intrinsics
        let toDevice = projector.attitude.referenceToDevice
        // Everything a star needs in one matrix: EQJ → device.
        let eqjToDevice = toDevice * rotation
        // Refraction lifts a star by at most ~0.6°: cull on the geometric
        // place with that much slack before paying for it.
        let slack = margin + 0.011 * max(k.fx, k.fy)
        var out: [ProjectedStar] = []
        out.reserveCapacity(1024)
        for i in byBrightness {
            let vmag = catalog.stars[i].vmag
            if vmag > magnitudeLimit { break }
            let g = eqjToDevice * apparentEQJ[i]
            let gz = -g.z
            guard gz > 1e-3 else { continue }
            let gu = k.fx * g.x / gz + k.cx, gv = k.fy * -g.y / gz + k.cy
            guard gu > -slack, gu < k.width + slack, gv > -slack, gv < k.height + slack else { continue }
            let geometric = rotation * apparentEQJ[i]
            // Anything more than 2° below the horizon stays down after refraction.
            if geometric.z < -0.035 { continue }
            let r = SkyRotation.refracted(geometric)
            let alt = asin(max(-1, min(1, r.z))) * 180 / .pi
            let mag = vmag + extinction.deltaMagnitude(altitudeDeg: alt)
            if mag > magnitudeLimit { continue }
            let d = toDevice * r
            let cz = -d.z
            guard cz > 1e-6 else { continue }
            let u = k.fx * d.x / cz + k.cx
            let v = k.fy * -d.y / cz + k.cy
            guard u > -margin, u < k.width + margin, v > -margin, v < k.height + margin else { continue }
            let az = Geodesy.normalizedAzimuth(atan2(-r.y, r.x) * 180 / .pi)
            if alt < horizon.altitudeDeg(atAzimuth: az) { continue }
            out.append(ProjectedStar(index: i, u: u, v: v, altitudeDeg: alt, apparentMagnitude: mag))
        }
        return out
    }
}

extension SkyProjector {
    /// Pixel of a reference-frame direction, or nil behind the camera.
    public func pixel(ofReference r: SIMD3<Double>) -> PixelPoint? {
        let d = attitude.referenceToDevice * r
        guard -d.z > 1e-9 else { return nil }
        return PixelPoint(u: intrinsics.fx * d.x / -d.z + intrinsics.cx, v: intrinsics.fy * -d.y / -d.z + intrinsics.cy)
    }

    /// `projectPath` for reference-frame vectors (star trails, meteor hints):
    /// split where the path passes behind the camera, clipped at the near plane.
    public func projectPath(referenceVectors: [SIMD3<Double>]) -> [[PixelPoint]] {
        let near = Self.nearPlane
        let cams = referenceVectors.map { r -> SIMD3<Double> in
            let d = attitude.referenceToDevice * r
            return SIMD3(d.x, -d.y, -d.z)
        }
        func px(_ c: SIMD3<Double>) -> PixelPoint {
            PixelPoint(u: intrinsics.fx * c.x / c.z + intrinsics.cx, v: intrinsics.fy * c.y / c.z + intrinsics.cy)
        }
        var runs: [[PixelPoint]] = []
        var run: [PixelPoint] = []
        for (i, c) in cams.enumerated() {
            if i > 0 {
                let prev = cams[i - 1]
                if (prev.z >= near) != (c.z >= near) {
                    let crossing = px(prev + (c - prev) * ((near - prev.z) / (c.z - prev.z)))
                    if prev.z >= near {
                        run.append(crossing)
                        if run.count > 1 { runs.append(run) }
                        run = []
                    } else {
                        run = [crossing]
                    }
                }
            }
            if c.z >= near { run.append(px(c)) }
        }
        if run.count > 1 { runs.append(run) }
        return runs
    }
}
