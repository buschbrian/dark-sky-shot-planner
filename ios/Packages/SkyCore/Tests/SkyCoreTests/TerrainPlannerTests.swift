import Foundation
import Testing
@testable import SkyCore

/// Mirrors `app/tests/horizon.test.ts` (planNight over terrain).
@Suite("Planner over terrain")
struct TerrainPlannerTests {
    static let camp = (lat: 38.374031, lon: -109.965416)

    func campObserver() throws -> Observer { try observer(Self.camp.lat, Self.camp.lon) }

    @Test("nil profile is exactly today's planNight", arguments: try GoldenFile.load().cases)
    func nilProfileIsUnchanged(_ golden: GoldenFile.Case) throws {
        let obs = try observer(golden.latitude, golden.longitude)
        let evening = try ISO.date(golden.evening_utc)
        let report = try Planner.planNight(obs, evening: evening, horizon: nil)
        #expect(report == (try Planner.planNight(obs, evening: evening)))
        #expect(report.terrain == nil)
    }

    @Test("a flat 0° skyline stays within the golden tolerances of the flat planner", arguments: [
        "2026-05-07T03:00:00Z", "2026-06-25T03:00:00Z", "2026-09-16T03:00:00Z",
    ])
    func zeroProfileMatchesFlat(_ evening: String) throws {
        let obs = try campObserver()
        let flat = try Planner.planNight(obs, evening: ISO.date(evening))
        let zero = try Planner.planNight(obs, evening: ISO.date(evening), horizon: .flat(0))
        for (a, b) in [(zero.moonrise, flat.moonrise), (zero.moonset, flat.moonset)] {
            #expect((a == nil) == (b == nil))
            if let a, let b { #expect(abs(a.timeIntervalSince(b)) < 60) }
        }
        #expect(abs(zero.moonFreeMinutes - flat.moonFreeMinutes) <= 2)
        #expect(abs(try #require(zero.gc.maxAltitudeDeg) - #require(flat.gc.maxAltitudeDeg)) <= 0.1 + 1e-9)
    }

    @Test("the Candlestick skyline delays moonrise and adds moon-free minutes")
    func candlestickDelaysMoonrise() throws {
        let obs = try campObserver()
        let evening = try ISO.date("2026-05-07T03:00:00Z")
        let horizon = try HorizonProfile.bundled("candlestick-camp")
        let flat = try Planner.planNight(obs, evening: evening)
        let report = try Planner.planNight(obs, evening: evening, horizon: horizon)
        #expect(try #require(report.moonrise) > #require(flat.moonrise).addingTimeInterval(20 * 60))
        #expect(report.moonFreeMinutes > flat.moonFreeMinutes + 20)
        let config = try AppConfig.bundled()
        #expect(!flat.gc.isUsable(config))
        #expect(report.gc.isUsable(config))

        let dark = try #require(report.darkness)
        let up = try Planner.moonUpIntervals(obs, horizon: horizon, from: dark.start, to: dark.end)
        for w in report.moonFreeWindows {
            for u in up { #expect(w.end <= u.start || u.end <= w.start) }
        }
        let terrain = try #require(report.terrain)
        let clears = try #require(terrain.gcClearsSkyline)
        #expect(terrain.gcAboveSkyline.first?.start == clears)
        #expect(terrain.gcMinutes == terrain.gcWindows.map(\.minutes).max())
        #expect(terrain.gcWindows.allSatisfy { $0.start >= clears })
    }

    @Test func candlestickBringsMoonsetForward() throws {
        let obs = try campObserver()
        let evening = try ISO.date("2026-06-25T03:00:00Z")
        let flat = try Planner.planNight(obs, evening: evening)
        let report = try Planner.planNight(obs, evening: evening, horizon: HorizonProfile.bundled("candlestick-camp"))
        #expect(try #require(report.moonset) < #require(flat.moonset).addingTimeInterval(-10 * 60))
        #expect(report.moonFreeMinutes > flat.moonFreeMinutes)
    }

    @Test func wallHidesMoonAndGC() throws {
        let report = try Planner.planNight(campObserver(), evening: ISO.date("2026-05-07T03:00:00Z"), horizon: .flat(60))
        let dark = try #require(report.darkness)
        #expect(report.moonrise == nil)
        #expect(report.moonFreeMinutes == Int(jsRound(dark.duration / 60)))
        #expect(report.gc == GCVisibility(maxAltitudeDeg: nil, maxAltitudeAt: nil, risesDuringDarkness: false))
        #expect(report.terrain?.gcAboveSkyline == [])
        #expect(report.terrain?.gcMinutes == 0)
    }

    @Test func dippedSkylineKeepsMoonUpLonger() throws {
        let obs = try campObserver()
        let evening = try ISO.date("2026-05-07T03:00:00Z")
        let flat = try Planner.planNight(obs, evening: evening)
        let dipped = try Planner.planNight(obs, evening: evening, horizon: .flat(-2))
        #expect(try #require(dipped.moonrise) < #require(flat.moonrise))
        #expect(dipped.moonFreeMinutes < flat.moonFreeMinutes)
    }

    @Test func noDarknessGivesEmptyTerrain() throws {
        let report = try Planner.planNight(
            observer(48.99, -114.0), evening: ISO.date("2026-06-21T04:00:00Z"), horizon: .flat(2))
        #expect(report.noAstronomicalDarkness)
        #expect(report.terrain == TerrainReport.none)
        #expect(report.moonFreeMinutes == 0)
    }
}
