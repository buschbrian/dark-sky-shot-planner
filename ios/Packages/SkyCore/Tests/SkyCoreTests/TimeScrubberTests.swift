import Foundation
import Testing
@testable import SkyCore

@Suite("Time scrubber shared by map and AR")
struct TimeScrubberTests {
    @Test("hour ticks land on the hour, bracketed by the window's edges")
    func hourTicks() throws {
        let window = TimeWindow(start: try ISO.date("2026-06-16T04:42:18.530Z"), end: try ISO.date("2026-06-16T10:10:00Z"))
        let times = TimeScrubber.times(across: window, step: 3600)
        #expect(times.first == window.start)
        #expect(times.last == window.end)
        #expect(times.count == 8)
        let hours = try (5...10).map { try ISO.date("2026-06-16T\(String(format: "%02d", $0)):00:00Z") }
        #expect(Array(times.dropFirst().dropLast()) == hours)
    }

    @Test("a window ending on a tick does not repeat it")
    func noDuplicateEnd() throws {
        let window = TimeWindow(start: try ISO.date("2026-06-16T05:00:00Z"), end: try ISO.date("2026-06-16T06:00:00Z"))
        #expect(TimeScrubber.times(across: window, step: 900).count == 5)
        #expect(TimeScrubber.times(across: TimeWindow(start: window.start, end: window.start), step: 900) == [window.start])
    }

    @Test("covers the planner's darkness window with no gap longer than the step")
    func darknessWindow() throws {
        let (window, _) = try Planner.darknessWindow(observer(38.374031, -109.965416), evening: ISO.date("2026-06-16T03:00:00Z"))
        let dark = try #require(window)
        let times = TimeScrubber.times(across: dark, step: 900)
        #expect(times.first == dark.start && times.last == dark.end)
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b > a && b.timeIntervalSince(a) <= 900)
        }
    }

    @Test func clampAndSnap() throws {
        let window = TimeWindow(start: try ISO.date("2026-06-16T04:42:00Z"), end: try ISO.date("2026-06-16T10:10:00Z"))
        #expect(TimeScrubber.clamp(try ISO.date("2026-06-16T03:00:00Z"), to: window) == window.start)
        #expect(TimeScrubber.clamp(try ISO.date("2026-06-16T11:00:00Z"), to: window) == window.end)
        #expect(TimeScrubber.snap(try ISO.date("2026-06-16T06:07:00Z"), across: window, step: 900) == (try ISO.date("2026-06-16T06:00:00Z")))
        #expect(TimeScrubber.snap(try ISO.date("2026-06-16T04:43:00Z"), across: window, step: 900) == window.start)
        #expect(TimeScrubber.snap(try ISO.date("2026-06-16T04:44:00Z"), across: window, step: 900) == (try ISO.date("2026-06-16T04:45:00Z")))
        #expect(TimeScrubber.snap(try ISO.date("2026-06-16T12:00:00Z"), across: window, step: 900) == window.end)
    }
}
