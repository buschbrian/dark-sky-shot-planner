public import Foundation

public struct TimelapsePlan: Sendable, Hashable, Codable {
    public let exposure: TimeInterval
    /// Shutter-release to shutter-release.
    public let interval: TimeInterval
    public let frames: Int
    public let fps: Double
    /// Length of the finished clip: frames ÷ fps.
    public let clipSeconds: Double
    /// Time spent shooting: frames × interval.
    public let eventDuration: TimeInterval
}

/// Timelapse arithmetic: frames = clip length × fps, shooting time = frames ×
/// interval, interval = shooting time ÷ frames (Enlaps, "Time Lapse Calculator",
/// enlaps.io/us/guide/time-lapse-calculator). Every plan rejects an interval
/// shorter than exposure + buffer, since the camera cannot start the next frame
/// before it has finished and written the last.
public enum Timelapse {
    /// Camera write/readout time allowed between frames unless the owner sets one.
    public static let defaultBufferSeconds: TimeInterval = 1
    static let maxFrames = 1_000_000.0

    public static func minimumInterval(exposure: TimeInterval, buffer: TimeInterval = defaultBufferSeconds) throws(ExposureError) -> TimeInterval {
        let t = try requirePositive(.exposure, exposure)
        let b = try require(.buffer, buffer) { $0 >= 0 }
        return t + b
    }

    /// Given the interval and the clip you want: frames = ⌈clip × fps⌉, shooting time = frames × interval.
    public static func plan(
        exposure: TimeInterval, interval: TimeInterval, fps: Double, clipSeconds: Double,
        buffer: TimeInterval = defaultBufferSeconds
    ) throws(ExposureError) -> TimelapsePlan {
        let i = try checkedInterval(interval, exposure: exposure, buffer: buffer)
        let rate = try requirePositive(.fps, fps)
        let clip = try requirePositive(.clipLength, clipSeconds)
        let n = try frameCount(ceilTolerant(clip * rate), .clipLength, clip)
        return make(exposure, i, n, rate)
    }

    /// Given the interval and how long you can shoot: frames = ⌊duration ÷ interval⌋, clip = frames ÷ fps.
    public static func plan(
        exposure: TimeInterval, interval: TimeInterval, fps: Double, eventDuration: TimeInterval,
        buffer: TimeInterval = defaultBufferSeconds
    ) throws(ExposureError) -> TimelapsePlan {
        let i = try checkedInterval(interval, exposure: exposure, buffer: buffer)
        let rate = try requirePositive(.fps, fps)
        let duration = try requirePositive(.eventDuration, eventDuration)
        let n = try frameCount(floorTolerant(duration / i), .eventDuration, duration)
        return make(exposure, i, n, rate)
    }

    /// Given how long you can shoot and the clip you want: interval = duration ÷ ⌈clip × fps⌉.
    public static func plan(
        exposure: TimeInterval, fps: Double, clipSeconds: Double, eventDuration: TimeInterval,
        buffer: TimeInterval = defaultBufferSeconds
    ) throws(ExposureError) -> TimelapsePlan {
        let rate = try requirePositive(.fps, fps)
        let clip = try requirePositive(.clipLength, clipSeconds)
        let duration = try requirePositive(.eventDuration, eventDuration)
        let n = try frameCount(ceilTolerant(clip * rate), .clipLength, clip)
        let i = try checkedInterval(duration / Double(n), exposure: exposure, buffer: buffer)
        return make(exposure, i, n, rate)
    }

    private static func checkedInterval(_ interval: TimeInterval, exposure: TimeInterval, buffer: TimeInterval) throws(ExposureError) -> TimeInterval {
        let minimum = try minimumInterval(exposure: exposure, buffer: buffer)
        let i = try requirePositive(.interval, interval)
        guard i >= minimum - 1e-9 else { throw .intervalTooShort(intervalSeconds: i, minimumSeconds: minimum) }
        return i
    }

    private static func frameCount(_ frames: Double, _ parameter: ExposureParameter, _ input: Double) throws(ExposureError) -> Int {
        guard frames >= 1, frames <= maxFrames else { throw .invalid(parameter, input) }
        return Int(frames)
    }

    private static func make(_ exposure: TimeInterval, _ interval: TimeInterval, _ frames: Int, _ fps: Double) -> TimelapsePlan {
        TimelapsePlan(exposure: exposure, interval: interval, frames: frames, fps: fps,
                      clipSeconds: Double(frames) / fps, eventDuration: Double(frames) * interval)
    }
}
