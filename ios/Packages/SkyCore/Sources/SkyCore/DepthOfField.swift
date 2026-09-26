import Foundation

/// A depth-of-field limit: a finite distance, or infinity.
public enum FocusLimit: Sendable, Hashable, Codable {
    case meters(Double)
    case infinity

    public var meters: Double? {
        if case let .meters(m) = self { return m }
        return nil
    }
}

public struct DepthOfFieldLimits: Sendable, Hashable, Codable {
    public let focusDistanceMeters: Double
    public let hyperfocalMeters: Double
    public let nearMeters: Double
    public let far: FocusLimit

    /// Far minus near; nil when the far limit is infinity.
    public var depthMeters: Double? { far.meters.map { $0 - nearMeters } }
}

/// Hyperfocal distance and depth of field for a thin lens, with distances
/// measured from the lens. Equations: Greenleaf, *Photographic Optics* (1950),
/// pp. 25–27, as published by DOFMaster (dofmaster.com/equations.html).
public enum DepthOfField {
    /// CoC = sensor diagonal ÷ 1500, i.e. 0.029 mm on full frame (Wikipedia, "Circle of confusion").
    public static let defaultCoCDivisor = 1500.0

    /// Circle of confusion in mm from the sensor diagonal: c = d / divisor (Wikipedia, "Circle of confusion").
    public static func circleOfConfusionMM(sensorDiagonalMM: Double, divisor: Double = defaultCoCDivisor) throws(ExposureError) -> Double {
        let d = try requirePositive(.sensorDiagonal, sensorDiagonalMM)
        return d / (try requirePositive(.cocDivisor, divisor))
    }

    /// H = f² / (N·c) + f (Greenleaf 1950 via DOFMaster; Wikipedia "Hyperfocal distance", definition 1).
    public static func hyperfocalMeters(focalLengthMM: Double, fNumber: Double, circleOfConfusionMM: Double) throws(ExposureError) -> Double {
        let f = try requirePositive(.focalLength, focalLengthMM)
        let n = try requireFNumber(fNumber)
        let c = try requirePositive(.circleOfConfusion, circleOfConfusionMM)
        return (f * f / (n * c) + f) / 1000
    }

    /// Near limit Dn = s(H − f) / (H + s − 2f); far limit Df = s(H − f) / (H − s),
    /// infinite once s ≥ H (Greenleaf 1950 via DOFMaster).
    public static func limits(
        focalLengthMM: Double, fNumber: Double, circleOfConfusionMM: Double, focusDistanceMeters: Double
    ) throws(ExposureError) -> DepthOfFieldLimits {
        let hMeters = try hyperfocalMeters(focalLengthMM: focalLengthMM, fNumber: fNumber, circleOfConfusionMM: circleOfConfusionMM)
        let f = focalLengthMM
        let s = try require(.focusDistance, focusDistanceMeters) { $0 * 1000 > f } * 1000
        let h = hMeters * 1000
        let near = s * (h - f) / (h + s - 2 * f)
        let far: FocusLimit = s >= h ? .infinity : .meters(s * (h - f) / (h - s) / 1000)
        return DepthOfFieldLimits(focusDistanceMeters: s / 1000, hyperfocalMeters: hMeters, nearMeters: near / 1000, far: far)
    }
}

// MARK: - Saved gear

extension DepthOfField {
    /// Hyperfocal distance for a saved camera and lens, CoC = diagonal / 1500.
    public static func hyperfocalMeters(camera: CameraProfile, lens: LensProfile, fNumber: Double? = nil) throws(ExposureError) -> Double {
        try hyperfocalMeters(focalLengthMM: lens.focalLengthMM, fNumber: lens.aperture(fNumber),
                             circleOfConfusionMM: camera.circleOfConfusionMM)
    }

    public static func limits(
        camera: CameraProfile, lens: LensProfile, fNumber: Double? = nil, focusDistanceMeters: Double
    ) throws(ExposureError) -> DepthOfFieldLimits {
        try limits(focalLengthMM: lens.focalLengthMM, fNumber: lens.aperture(fNumber),
                   circleOfConfusionMM: camera.circleOfConfusionMM, focusDistanceMeters: focusDistanceMeters)
    }
}
