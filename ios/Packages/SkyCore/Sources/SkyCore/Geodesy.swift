import Foundation

/// A WGS84 geodetic position in degrees: latitude north-positive, longitude
/// east-positive in [-180, 180).
public struct GeoCoordinate: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        precondition(latitude.isFinite && (-90...90).contains(latitude), "latitude out of range")
        precondition(longitude.isFinite, "longitude must be finite")
        self.latitude = latitude
        self.longitude = Geodesy.normalizedLongitude(longitude)
    }
}

extension Observer {
    public var coordinate: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }
}

public struct GeodesicDirectResult: Sendable, Hashable {
    public let end: GeoCoordinate
    /// Forward azimuth at `end`, degrees clockwise from true north in [0, 360).
    public let finalAzimuthDeg: Double
}

public struct GeodesicInverseResult: Sendable, Hashable {
    public let distanceMeters: Double
    /// Degrees clockwise from true north in [0, 360).
    public let initialAzimuthDeg: Double
    public let finalAzimuthDeg: Double
}

/// Geodesics on the WGS84 ellipsoid by Vincenty's formulae (Survey Review
/// 23(176), 1975), with the direct problem iterated to 1e-12 rad. Against
/// GeographicLib (Karney 2013) the direct solution agrees to better than
/// 0.05 mm at 20,000 km, and to about a micrometre at map lengths. The
/// inverse fails to converge only for nearly antipodal points, which no pair
/// of Mountain West places is; it returns nil there.
public enum Geodesy {
    public static let wgs84SemiMajorAxisMeters = 6_378_137.0
    public static let wgs84Flattening = 1 / 298.257_223_563

    private static let a = wgs84SemiMajorAxisMeters
    private static let f = wgs84Flattening
    private static let b = a * (1 - f)
    private static let radian = Double.pi / 180

    /// The point `distanceMeters` along the geodesic leaving `start` at
    /// `azimuthDeg` (clockwise from true north).
    public static func direct(
        from start: GeoCoordinate, azimuthDeg: Double, distanceMeters s: Double
    ) -> GeodesicDirectResult {
        precondition(azimuthDeg.isFinite && s.isFinite && s >= 0, "azimuth and distance must be finite, distance >= 0")
        let alpha1 = azimuthDeg * radian
        let sinAlpha1 = sin(alpha1), cosAlpha1 = cos(alpha1)
        let tanU1 = (1 - f) * tan(start.latitude * radian)
        let cosU1 = 1 / (1 + tanU1 * tanU1).squareRoot()
        let sinU1 = tanU1 * cosU1
        let sigma1 = atan2(tanU1, cosAlpha1)
        let sinAlpha = cosU1 * sinAlpha1
        let cos2Alpha = 1 - sinAlpha * sinAlpha
        let (bigA, bigB) = seriesAB(cos2Alpha)

        var sigma = s / (b * bigA)
        var sinSigma = 0.0, cosSigma = 0.0, cos2SigmaM = 0.0
        for _ in 0..<200 {
            cos2SigmaM = cos(2 * sigma1 + sigma)
            sinSigma = sin(sigma)
            cosSigma = cos(sigma)
            let next = s / (b * bigA) + deltaSigma(bigB, sinSigma, cosSigma, cos2SigmaM)
            let done = abs(next - sigma) < 1e-12
            sigma = next
            if done { break }
        }
        cos2SigmaM = cos(2 * sigma1 + sigma)
        sinSigma = sin(sigma)
        cosSigma = cos(sigma)

        let x = sinU1 * sinSigma - cosU1 * cosSigma * cosAlpha1
        let lat2 = atan2(sinU1 * cosSigma + cosU1 * sinSigma * cosAlpha1, (1 - f) * (sinAlpha * sinAlpha + x * x).squareRoot())
        let lambda = atan2(sinSigma * sinAlpha1, cosU1 * cosSigma - sinU1 * sinSigma * cosAlpha1)
        let c = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
        let l = lambda - (1 - c) * f * sinAlpha
            * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
        return GeodesicDirectResult(
            end: GeoCoordinate(latitude: lat2 / radian, longitude: start.longitude + l / radian),
            finalAzimuthDeg: normalizedAzimuth(atan2(sinAlpha, -x) / radian))
    }

    /// Distance and azimuths from `start` to `end`; nil when the iteration
    /// does not converge (nearly antipodal points only).
    public static func inverse(from start: GeoCoordinate, to end: GeoCoordinate) -> GeodesicInverseResult? {
        let l = normalizedLongitude(end.longitude - start.longitude) * radian
        let u1 = atan((1 - f) * tan(start.latitude * radian))
        let u2 = atan((1 - f) * tan(end.latitude * radian))
        let sinU1 = sin(u1), cosU1 = cos(u1), sinU2 = sin(u2), cosU2 = cos(u2)

        var lambda = l
        var sinLambda = 0.0, cosLambda = 0.0
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0, cos2Alpha = 0.0, cos2SigmaM = 0.0
        var converged = false
        for _ in 0..<200 {
            sinLambda = sin(lambda)
            cosLambda = cos(lambda)
            let t1 = cosU2 * sinLambda
            let t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = (t1 * t1 + t2 * t2).squareRoot()
            if sinSigma == 0 {
                return GeodesicInverseResult(distanceMeters: 0, initialAzimuthDeg: 0, finalAzimuthDeg: 0)
            }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cos2Alpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cos2Alpha != 0 ? cosSigma - 2 * sinU1 * sinU2 / cos2Alpha : 0
            let c = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
            let next = l + (1 - c) * f * sinAlpha
                * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            let done = abs(next - lambda) < 1e-12
            lambda = next
            if done { converged = true; break }
        }
        guard converged else { return nil }
        sinLambda = sin(lambda)
        cosLambda = cos(lambda)

        let (bigA, bigB) = seriesAB(cos2Alpha)
        let s = b * bigA * (sigma - deltaSigma(bigB, sinSigma, cosSigma, cos2SigmaM))
        let alpha1 = atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        let alpha2 = atan2(cosU1 * sinLambda, -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda)
        return GeodesicInverseResult(
            distanceMeters: s,
            initialAzimuthDeg: normalizedAzimuth(alpha1 / radian),
            finalAzimuthDeg: normalizedAzimuth(alpha2 / radian))
    }

    /// `segments + 1` points evenly spaced along the geodesic, start and end
    /// included. MapLibre joins vertices with straight Web Mercator segments,
    /// so a line longer than a few tens of km should be drawn densified.
    public static func path(
        from start: GeoCoordinate, azimuthDeg: Double, distanceMeters: Double, segments: Int
    ) -> [GeoCoordinate] {
        precondition(segments >= 1, "segments must be at least 1")
        return (0...segments).map { i in
            i == 0 ? start : direct(
                from: start, azimuthDeg: azimuthDeg,
                distanceMeters: distanceMeters * Double(i) / Double(segments)).end
        }
    }

    /// Degrees in [0, 360).
    public static func normalizedAzimuth(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        let out = r < 0 ? r + 360 : r
        return out == 360 ? 0 : out
    }

    /// Degrees in (-180, 180].
    public static func signedAngle(_ deg: Double) -> Double {
        let r = normalizedAzimuth(deg)
        return r > 180 ? r - 360 : r
    }

    static func normalizedLongitude(_ deg: Double) -> Double {
        let r = normalizedAzimuth(deg + 180)
        return r - 180
    }

    private static func seriesAB(_ cos2Alpha: Double) -> (Double, Double) {
        let u2 = cos2Alpha * (a * a - b * b) / (b * b)
        let bigA = 1 + u2 / 16384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
        let bigB = u2 / 1024 * (256 + u2 * (-128 + u2 * (74 - 47 * u2)))
        return (bigA, bigB)
    }

    private static func deltaSigma(_ bigB: Double, _ sinSigma: Double, _ cosSigma: Double, _ cos2SigmaM: Double) -> Double {
        bigB * sinSigma * (cos2SigmaM + bigB / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
            - bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
    }
}
