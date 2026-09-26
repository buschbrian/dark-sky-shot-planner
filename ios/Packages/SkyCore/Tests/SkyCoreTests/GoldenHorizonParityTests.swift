import Foundation
import Testing
@testable import SkyCore

/// The `horizon_cases` of `shared/golden/night-report.json` (M9): the web
/// planner with a measured skyline. Same file, same tolerances.
struct GoldenHorizonFile: Decodable {
    struct Terrain: Decodable, Sendable {
        let gc_above_skyline: [GoldenFile.Window]
        let gc_clears_skyline: String?
        let gc_drops_behind_skyline: String?
        let gc_windows: [GoldenFile.Window]
        let gc_minutes: Int
    }
    struct Expected: Decodable, Sendable {
        let darkness: GoldenFile.Window?
        let no_astronomical_darkness: Bool
        let moon_illum_fraction: Double
        let moonset: String?
        let moonrise: String?
        let moon_free_windows: [GoldenFile.Window]
        let moon_free_minutes: Int
        let gc: GoldenFile.GC
        let terrain: Terrain
    }
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let latitude: Double
        let longitude: Double
        let evening_utc: String
        let horizon_profile: String
        let expected: Expected
        var testDescription: String { id }
    }

    let tolerance: GoldenFile.Tolerance
    let horizon_cases: [Case]

    static func load() throws -> GoldenHorizonFile {
        try JSONDecoder().decode(GoldenHorizonFile.self, from: Repo.data("shared/golden/night-report.json"))
    }
}

@Suite("Golden horizon-profile parity with the web planner")
struct GoldenHorizonParityTests {
    @Test("the golden file has the Candlestick Camp horizon cases")
    func hasCandlestick() throws {
        let cases = try GoldenHorizonFile.load().horizon_cases
        #expect(cases.count == 2)
        #expect(cases.allSatisfy { $0.id.hasPrefix("candlestick-") })
    }

    @Test("the case reads the same profile SkyCore bundles")
    func profileIsTheBundledOne() throws {
        for c in try GoldenHorizonFile.load().horizon_cases {
            #expect(try Repo.data(c.horizon_profile) == SharedResources.data("horizon-profiles/candlestick-camp.csv"))
        }
    }

    @Test("planNight(horizon:) matches within the file's tolerances", arguments: try GoldenHorizonFile.load().horizon_cases)
    func matches(_ golden: GoldenHorizonFile.Case) throws {
        let tol = try GoldenHorizonFile.load().tolerance
        let horizon = try HorizonProfile.parse(csv: String(decoding: Repo.data(golden.horizon_profile), as: UTF8.self))
        let report = try Planner.planNight(
            observer(golden.latitude, golden.longitude), evening: ISO.date(golden.evening_utc), horizon: horizon)
        let exp = golden.expected

        func expectTime(_ actual: Date?, _ expected: String?, _ label: String) throws {
            let expectedDate = try ISO.date(expected)
            #expect((actual == nil) == (expectedDate == nil), "\(label): presence")
            if let actual, let expectedDate {
                let delta = abs(actual.timeIntervalSince(expectedDate))
                #expect(delta <= tol.time_s, "\(label): off by \(delta) s")
            }
        }
        func expectWindows(_ actual: [(Date, Date, Int?)], _ expected: [GoldenFile.Window], _ label: String) throws {
            try #require(actual.count == expected.count, "\(label): count")
            for (a, e) in zip(actual, expected) {
                try expectTime(a.0, e.start, "\(label).start")
                try expectTime(a.1, e.end, "\(label).end")
                if let minutes = a.2 { #expect(abs(minutes - (e.minutes ?? -1)) <= tol.minutes) }
            }
        }

        #expect(report.noAstronomicalDarkness == exp.no_astronomical_darkness)
        try expectTime(report.darkness?.start, exp.darkness?.start, "darkness.start")
        try expectTime(report.darkness?.end, exp.darkness?.end, "darkness.end")
        #expect(abs(report.moonIllumFraction - exp.moon_illum_fraction) <= tol.illum_fraction)
        try expectTime(report.moonset, exp.moonset, "moonset")
        try expectTime(report.moonrise, exp.moonrise, "moonrise")
        try expectWindows(report.moonFreeWindows.map { ($0.start, $0.end, $0.minutes) }, exp.moon_free_windows, "window")
        #expect(abs(report.moonFreeMinutes - exp.moon_free_minutes) <= tol.minutes)

        #expect((report.gc.maxAltitudeDeg == nil) == (exp.gc.max_altitude_deg == nil))
        if let actual = report.gc.maxAltitudeDeg, let expected = exp.gc.max_altitude_deg {
            #expect(abs(actual - expected) <= tol.altitude_deg)
        }
        try expectTime(report.gc.maxAltitudeAt, exp.gc.max_altitude_at, "gc.max_altitude_at")
        #expect(report.gc.risesDuringDarkness == exp.gc.rises_during_darkness)

        let terrain = try #require(report.terrain)
        try expectWindows(terrain.gcAboveSkyline.map { ($0.start, $0.end, nil) }, exp.terrain.gc_above_skyline, "gc_above_skyline")
        try expectTime(terrain.gcClearsSkyline, exp.terrain.gc_clears_skyline, "gc_clears_skyline")
        try expectTime(terrain.gcDropsBehindSkyline, exp.terrain.gc_drops_behind_skyline, "gc_drops_behind_skyline")
        try expectWindows(terrain.gcWindows.map { ($0.start, $0.end, $0.minutes) }, exp.terrain.gc_windows, "gc_windows")
        #expect(abs(terrain.gcMinutes - exp.terrain.gc_minutes) <= tol.minutes)
    }
}
