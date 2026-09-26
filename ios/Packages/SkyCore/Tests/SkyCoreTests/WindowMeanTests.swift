import Foundation
import Testing
@testable import SkyCore

@Suite("Cloud window mean")
struct WindowMeanTests {
    let t0 = Date(timeIntervalSince1970: 1_789_999_200) // on the hour

    func hour(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    func series(_ values: [Double?]) -> HourlySeries {
        HourlySeries(model: "m", samples: values.enumerated().map { HourlySample(time: hour(Double($0)), value: $1) })
    }

    @Test func completeWindowIsTimeWeighted() {
        // Window 01:00-03:00: hour 1 counts half (00:30-01:30 overlaps 30 min), hour 2 full, hour 3 half.
        let mean = WindowMean.of(series([90, 20, 40, 80, 90]), over: [TimeWindow(start: hour(1), end: hour(3))])
        #expect(mean.status == .complete)
        #expect(mean.coveredFraction == 1)
        #expect(mean.mean == (20 * 0.5 + 40 + 80 * 0.5) / 2)
    }

    @Test("a missing hour is left out, never read as 0% cloud")
    func missingHourIsExcluded() throws {
        let mean = WindowMean.of(series([60, nil, 60]), over: [TimeWindow(start: hour(0), end: hour(2))])
        #expect(mean.status == .partial)
        #expect(mean.mean == 60)
        #expect(mean.completeMean == nil)
        #expect(abs(mean.coveredFraction - 1.0 / 2) < 1e-12)
    }

    @Test func nonFiniteValuesAreMissing() {
        let mean = WindowMean.of(series([.nan, .infinity]), over: [TimeWindow(start: hour(0), end: hour(1))])
        #expect(mean == WindowMean(status: .unavailable, mean: nil, coveredFraction: 0))
    }

    @Test("all hours missing, or a series that ends before the window, is unavailable")
    func allMissingIsUnavailable() {
        let window = [TimeWindow(start: hour(10), end: hour(12))]
        #expect(WindowMean.of(series([nil, nil, nil]), over: window).status == .unavailable)
        #expect(WindowMean.of(series([0, 0, 0]), over: window).status == .unavailable)
        #expect(WindowMean.of(HourlySeries(model: "m", samples: []), over: window).status == .unavailable)
    }

    @Test("a series ending mid-window is partial")
    func seriesEndingMidWindow() {
        let mean = WindowMean.of(series([10, 10]), over: [TimeWindow(start: hour(0), end: hour(4))])
        #expect(mean.status == .partial)
        #expect(mean.mean == 10)
        #expect(mean.coveredFraction == 1.5 / 4)
    }

    @Test("several moon-free windows are averaged together, by duration")
    func severalWindows() {
        let mean = WindowMean.of(
            series([0, 0, 100, 100, 50, 50]),
            over: [TimeWindow(start: hour(0.5), end: hour(1.5)), TimeWindow(start: hour(3.5), end: hour(5.5))])
        #expect(mean.status == .complete)
        // Hour 3 (100%) ends at 03:30, where the second window starts.
        let expected: Double = (0 * 1 + 50 * 2) / 3
        #expect(mean.mean == expected)
    }

    @Test func noWindowAndDuplicateSamples() {
        #expect(WindowMean.of(series([10]), over: []).status == .noWindow)
        #expect(WindowMean.of(series([10]), over: [TimeWindow(start: hour(1), end: hour(1))]).status == .noWindow)
        let dup = HourlySeries(model: "m", samples: [.init(time: hour(0), value: 10), .init(time: hour(0), value: 90)])
        #expect(WindowMean.of(dup, over: [TimeWindow(start: hour(-0.25), end: hour(0.25))]).mean == 10)
    }
}
