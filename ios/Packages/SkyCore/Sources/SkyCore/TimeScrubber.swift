public import Foundation

/// Times for the scrubber shared by the map planner and Night AR.
public enum TimeScrubber {
    /// The window's start, every multiple of `step` since the Unix epoch
    /// strictly inside it, then its end. Steps that divide an hour land on
    /// round local times in any whole-hour zone (all of the Mountain West),
    /// so `step: 3600` gives the GC's hour ticks.
    public static func times(across window: TimeWindow, step: TimeInterval) -> [Date] {
        precondition(step > 0, "step must be positive")
        guard window.end > window.start else { return [window.start] }
        let startS = window.start.timeIntervalSince1970
        let endS = window.end.timeIntervalSince1970
        var out = [window.start]
        var k = (startS / step).rounded(.down) + 1
        while k * step < endS {
            out.append(Date(timeIntervalSince1970: k * step))
            k += 1
        }
        out.append(window.end)
        return out
    }

    public static func clamp(_ date: Date, to window: TimeWindow) -> Date {
        min(max(date, window.start), window.end)
    }

    /// The scrubber time nearest `date` (ties go to the earlier one).
    public static func snap(_ date: Date, across window: TimeWindow, step: TimeInterval) -> Date {
        let t = clamp(date, to: window)
        return times(across: window, step: step).min {
            abs($0.timeIntervalSince(t)) < abs($1.timeIntervalSince(t))
        } ?? t
    }
}

extension SkyPositions {
    /// Position at `date` between two samples of a date-ordered series, by
    /// normalised linear interpolation of the ENU unit vectors (safe across
    /// north and near the zenith). Nil outside the series.
    public static func interpolated(_ series: [SkySample], at date: Date) -> HorizontalPosition? {
        guard let first = series.first, let last = series.last, date >= first.date, date <= last.date else { return nil }
        let i = series.firstIndex { $0.date >= date } ?? series.count - 1
        let b = series[i]
        if b.date == date || i == 0 { return b.position }
        let a = series[i - 1]
        let t = date.timeIntervalSince(a.date) / b.date.timeIntervalSince(a.date)
        return HorizontalPosition(enu: a.position.enuVector * (1 - t) + b.position.enuVector * t)
    }
}
