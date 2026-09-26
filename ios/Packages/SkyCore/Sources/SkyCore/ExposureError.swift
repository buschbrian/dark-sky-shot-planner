import Foundation

/// The input a calculator rejected. Every exposure tool validates its inputs
/// and throws rather than returning NaN or a silently clamped number.
public enum ExposureParameter: String, Sendable, Hashable, Codable, CaseIterable {
    case focalLength, fNumber, pixelPitch
    case sensorWidth, sensorHeight, sensorDiagonal, imageWidth, imageHeight
    case declination, npfK, cropFactor
    case circleOfConfusion, cocDivisor, focusDistance
    case exposure, snrGain, frames, interval, buffer, fps, clipLength, eventDuration
}

public enum ExposureError: Error, Sendable, Hashable {
    /// Non-finite, or outside the parameter's physical range.
    case invalid(ExposureParameter, Double)
    /// A camera needs either its image width in pixels or a stated pixel pitch.
    case missingPixelPitch
    /// The requested f-number is wider than the lens can open.
    case fNumberWiderThanLens(fNumber: Double, maxFNumber: Double)
    /// A timelapse interval shorter than the exposure plus the camera's buffer time.
    case intervalTooShort(intervalSeconds: Double, minimumSeconds: Double)
}

func require(
    _ parameter: ExposureParameter, _ value: Double, _ isValid: (Double) -> Bool
) throws(ExposureError) -> Double {
    guard value.isFinite, isValid(value) else { throw .invalid(parameter, value) }
    return value
}

func requirePositive(_ parameter: ExposureParameter, _ value: Double) throws(ExposureError) -> Double {
    try require(parameter, value) { $0 > 0 }
}

func requireFNumber(_ value: Double) throws(ExposureError) -> Double {
    try require(.fNumber, value) { $0 >= LensProfile.minimumFNumber }
}

func requireDeclination(_ value: Double) throws(ExposureError) -> Double {
    try require(.declination, value) { (-90...90).contains($0) }
}

/// `ceil` that ignores floating-point dust, so 2.0000000000000004 frames is 2.
func ceilTolerant(_ x: Double) -> Double {
    (x - 1e-9 * max(1, abs(x))).rounded(.up)
}

/// `floor` that ignores floating-point dust, so 299.99999999999994 frames is 300.
func floorTolerant(_ x: Double) -> Double {
    (x + 1e-9 * max(1, abs(x))).rounded(.down)
}
