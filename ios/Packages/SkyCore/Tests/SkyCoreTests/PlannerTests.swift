import Foundation
import Testing
@testable import SkyCore

/// Behavioural checks mirrored from `app/tests/planner.test.ts`.
@Suite("Planner")
struct PlannerTests {
    @Test func darknessAtSaltLakeCityInSeptember() throws {
        let (window, noDarkness) = try Planner.darknessWindow(
            observer(40.76, -111.89), evening: ISO.date("2026-09-16T03:00:00Z"))
        #expect(!noDarkness)
        let w = try #require(window)
        let hours = w.duration / 3600
        #expect(hours > 8 && hours < 11)
        let midnight = try ISO.date("2026-09-16T06:00:00Z")
        #expect(w.start < midnight && w.end > midnight)
    }

    @Test func noDarknessAtSummerSolsticeAt49N() throws {
        let (window, noDarkness) = try Planner.darknessWindow(
            observer(48.99, -114.0), evening: ISO.date("2026-06-21T04:00:00Z"))
        #expect(noDarkness)
        #expect(window == nil)
    }

    @Test func moonIlluminationAtKnownPhases() throws {
        #expect(try Planner.moonIllumination(at: ISO.date("2026-01-18T12:00:00Z")) < 0.05)
        #expect(try Planner.moonIllumination(at: ISO.date("2026-01-03T10:00:00Z")) > 0.95)
    }

    @Test func newMoonBeatsFullMoon() throws {
        let obs = try observer(38.5, -109.9)
        let full = try Planner.planNight(obs, evening: ISO.date("2026-08-28T04:00:00Z"))
        let fresh = try Planner.planNight(obs, evening: ISO.date("2026-08-12T04:00:00Z"))
        #expect(full.moonIllumFraction > 0.9)
        #expect(fresh.moonIllumFraction < 0.1)
        #expect(fresh.moonFreeMinutes > full.moonFreeMinutes + 60)
    }

    /// Mirrors planner.test.ts: the scan start falls ~53 s after moonrise (top
    /// limb) while the refracted centre is still below 0°; the moon sets four
    /// hours into darkness.
    @Test func moonUpSeedUsesLastRiseSet() throws {
        let obs = try observer(38.44, -111.89)
        let report = try Planner.planNight(obs, evening: ISO.date("2026-04-22T03:00:00Z"))
        let dark = try #require(report.darkness)
        let moonset = try #require(report.moonset)
        #expect(moonset > dark.start.addingTimeInterval(3 * 3600))
        let up = try Planner.moonUpIntervals(obs, from: dark.start, to: dark.end)
        let first = try #require(up.first)
        #expect(first.start < dark.start)
        #expect(abs(first.end.timeIntervalSince(moonset)) < 1)
        let window = try #require(report.moonFreeWindows.first)
        #expect(abs(window.start.timeIntervalSince(moonset)) < 1)
    }

    @Test func moonFreeWindowsIntersection() throws {
        let t0 = try ISO.date("2026-08-08T04:00:00Z")
        let dark = TimeWindow(start: t0, end: t0.addingTimeInterval(6 * 3600))
        let up = [TimeWindow(start: t0.addingTimeInterval(2 * 3600), end: t0.addingTimeInterval(3 * 3600))]
        let windows = Planner.moonFreeWindows(darkness: dark, moonUp: up)
        #expect(windows.map(\.minutes) == [120, 180])
        #expect(Planner.moonFreeWindows(darkness: dark, moonUp: [dark]).isEmpty)
    }

    @Test func jsRoundingMatchesMathRound() {
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(-2.6) == -3)
    }

    @Test func rejectsInvalidObserver() {
        #expect(throws: ObserverError.latitudeOutOfRange(91)) { try Observer(latitude: 91, longitude: 0) }
        #expect(throws: ObserverError.longitudeOutOfRange(-181)) { try Observer(latitude: 0, longitude: -181) }
    }
}
