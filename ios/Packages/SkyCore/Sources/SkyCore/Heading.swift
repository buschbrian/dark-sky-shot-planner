import Foundation

/// Whether the AR overlay may draw itself as confident, from
/// `CLHeading.headingAccuracy` (degrees; negative means the heading is
/// invalid) and `ar_overlay.heading_accuracy_confident_max_deg` in
/// `config/app-config.json`.
public enum HeadingConfidence: Sendable, Hashable {
    case unavailable
    case poor(accuracyDeg: Double)
    case confident(accuracyDeg: Double)

    public init(headingAccuracyDeg accuracy: Double, config: AROverlayConfig) {
        if !accuracy.isFinite || accuracy < 0 {
            self = .unavailable
        } else if accuracy <= config.headingAccuracyConfidentMaxDeg {
            self = .confident(accuracyDeg: accuracy)
        } else {
            self = .poor(accuracyDeg: accuracy)
        }
    }

    public var isConfident: Bool {
        if case .confident = self { true } else { false }
    }
}

/// A heading correction learned by lining a known target up in the camera:
/// the Moon, a planet, or a peak whose azimuth comes from `Geodesy.inverse`.
public struct HeadingCalibration: Sendable, Hashable, Codable {
    /// Degrees in (-180, 180] to ADD to every sensor azimuth.
    public let offsetDeg: Double

    public static let none = HeadingCalibration(offsetDeg: 0)

    public init(offsetDeg: Double) {
        self.offsetDeg = Geodesy.signedAngle(offsetDeg)
    }

    /// `computedAzimuthDeg` is where the target really is; `alignedAzimuthDeg`
    /// is the azimuth the sensors report for the spot where the user placed
    /// it (usually `SkyProjector.boresight` with the target on the crosshair).
    /// Wraps across north: computed 5°, aligned 355° gives +10°.
    public init(computedAzimuthDeg: Double, alignedAzimuthDeg: Double) {
        self.init(offsetDeg: computedAzimuthDeg - alignedAzimuthDeg)
    }

    /// Corrected azimuth in [0, 360).
    public func correct(azimuthDeg: Double) -> Double {
        Geodesy.normalizedAzimuth(azimuthDeg + offsetDeg)
    }
}
