import Foundation

/// Ground elevation lookups for horizon computation. Implementations must be
/// deterministic; `TerrariumElevationSampler` is the tile-backed one.
public protocol ElevationSampler {
    /// Metres above sea level, or nil where there is no data.
    func elevationMeters(latitude: Double, longitude: Double) -> Double?
}

public enum HorizonComputeError: Error, Sendable, Hashable {
    /// No elevation at a point the march needed. A partial skyline would read
    /// lower (better) than the real one, so the whole computation fails.
    case missingElevation(latitude: Double, longitude: Double)
}

/// Computes a `HorizonProfile` by marching rays outward over a DEM (M9).
///
/// Each azimuth's skyline is the largest elevation angle to any sampled
/// ground point. Earth curvature and standard terrestrial refraction use the
/// effective-radius model: light bends with curvature `k / R`, equivalent to
/// straight rays over a sphere of radius `R / (1 − k)`. `k = 0.13` is Gauss's
/// coefficient, the standard value in geodetic levelling (Hirt et al. 2010,
/// "Monitoring of the refraction coefficient in the lower atmosphere",
/// J. Geophys. Res. 115, D21102) and the default refraction factor of ArcGIS
/// 3D Analyst's Skyline and Viewshed tools.
public struct HorizonRayMarch: Sendable, Hashable {
    /// IUGG mean Earth radius.
    public static let earthRadiusMeters = 6_371_008.8

    public var azimuthCount = 360
    public var minDistanceMeters = 20.0
    public var maxDistanceMeters = 100_000.0
    /// Step = max(minStep, distance × stepGrowth): fine near the observer,
    /// a constant ~1% angular resolution in distance far away.
    public var minStepMeters = 10.0
    public var stepGrowth = 0.01
    public var eyeHeightMeters = 1.7
    public var refractionCoefficient = 0.13

    public init() {}

    var effectiveRadiusMeters: Double { Self.earthRadiusMeters / (1 - refractionCoefficient) }

    /// Distances along each ray, in metres.
    func sampleDistances() -> [Double] {
        var out: [Double] = []
        var d = minDistanceMeters
        while d <= maxDistanceMeters {
            out.append(d)
            d += max(minStepMeters, d * stepGrowth)
        }
        return out
    }

    /// Apparent elevation angle (deg) of ground at `targetElevation` a surface
    /// distance `distance` away, seen from an eye at `observerElevation`
    /// (all metres), with curvature and refraction.
    public func elevationAngleDeg(observerElevation: Double, targetElevation: Double, distance: Double) -> Double {
        let re = effectiveRadiusMeters
        let phi = distance / re
        let up = (re + targetElevation) * cos(phi) - (re + observerElevation)
        let across = (re + targetElevation) * sin(phi)
        return atan2(up, across) * 180 / .pi
    }

    /// The point `distance` metres from (lat, lon) along initial bearing `azimuthDeg` (sphere).
    public static func destination(
        latitude: Double, longitude: Double, azimuthDeg: Double, distance: Double
    ) -> (latitude: Double, longitude: Double) {
        let r = Double.pi / 180
        let delta = distance / earthRadiusMeters
        let theta = azimuthDeg * r
        let phi1 = latitude * r
        let lambda1 = longitude * r
        let sinPhi2 = sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta)
        let phi2 = asin(sinPhi2)
        let lambda2 = lambda1 + atan2(sin(theta) * sin(delta) * cos(phi1), cos(delta) - sin(phi1) * sinPhi2)
        var lon = lambda2 / r
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return (phi2 / r, lon)
    }

    /// The skyline around (latitude, longitude). The eye sits `eyeHeightMeters`
    /// above `groundElevationMeters`, or above the sampled ground when nil.
    public func profile(
        latitude: Double,
        longitude: Double,
        groundElevationMeters: Double? = nil,
        sampler: some ElevationSampler
    ) throws(HorizonComputeError) -> HorizonProfile {
        precondition(azimuthCount > 0 && minDistanceMeters > 0 && maxDistanceMeters >= minDistanceMeters)
        precondition(minStepMeters > 0 && refractionCoefficient < 1)
        guard let ground = groundElevationMeters ?? sampler.elevationMeters(latitude: latitude, longitude: longitude) else {
            throw .missingElevation(latitude: latitude, longitude: longitude)
        }
        let eye = ground + eyeHeightMeters
        let distances = sampleDistances()
        var samples: [HorizonProfile.Sample] = []
        samples.reserveCapacity(azimuthCount)
        for i in 0..<azimuthCount {
            let az = 360 * Double(i) / Double(azimuthCount)
            var best = -Double.infinity
            for d in distances {
                let p = Self.destination(latitude: latitude, longitude: longitude, azimuthDeg: az, distance: d)
                guard let z = sampler.elevationMeters(latitude: p.latitude, longitude: p.longitude) else {
                    throw .missingElevation(latitude: p.latitude, longitude: p.longitude)
                }
                best = max(best, elevationAngleDeg(observerElevation: eye, targetElevation: z, distance: d))
            }
            samples.append(HorizonProfile.Sample(azimuthDeg: az, altitudeDeg: best))
        }
        // Cannot throw: azimuths increase in [0, 360) and every angle is in [-90, 90].
        return try! HorizonProfile(samples: samples)
    }
}
