public import Foundation

public struct StackPlan: Sendable, Hashable, Codable {
    public let frames: Int
    public let subExposure: TimeInterval
    /// Shutter-open time summed over the stack (frames × sub-exposure).
    public let totalIntegration: TimeInterval
    /// SNR of the stack relative to one frame (√frames, at least the target).
    public let snrGain: Double
}

/// Frames to average for a target SNR improvement. Averaging N frames with
/// uncorrelated noise multiplies SNR by √N (Siril tutorial "Signal to noise
/// ratio", siril.org/tutorials/signal-to-noise; C. Stark, "Signal to Noise",
/// Cloudy Nights, 2009). Holds for random noise only; fixed-pattern noise
/// needs darks or dithering, which this does not model.
public enum Stacking {
    /// Upper bound on the requested gain (a million frames); beyond it the plan is not a field plan.
    public static let maxSNRGain = 1000.0

    /// SNR gain of an N-frame stack: √N (Siril, "Signal to noise ratio").
    public static func snrGain(frames: Int) throws(ExposureError) -> Double {
        guard frames >= 1 else { throw .invalid(.frames, Double(frames)) }
        return Double(frames).squareRoot()
    }

    /// Smallest N with √N ≥ gain: N = ⌈gain²⌉ (Siril, "Signal to noise ratio").
    public static func framesNeeded(snrGain gain: Double) throws(ExposureError) -> Int {
        let g = try require(.snrGain, gain) { (1...maxSNRGain).contains($0) }
        return Int(ceilTolerant(g * g))
    }

    public static func plan(snrGain gain: Double, subExposure: TimeInterval) throws(ExposureError) -> StackPlan {
        let n = try framesNeeded(snrGain: gain)
        let t = try requirePositive(.exposure, subExposure)
        return StackPlan(frames: n, subExposure: t, totalIntegration: Double(n) * t, snrGain: Double(n).squareRoot())
    }
}
