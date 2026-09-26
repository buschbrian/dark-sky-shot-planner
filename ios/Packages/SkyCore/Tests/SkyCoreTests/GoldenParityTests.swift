import Foundation
import Testing
@testable import SkyCore

/// `shared/golden/night-report.json` is the web/iOS contract (ADR-0009 §3).
/// Tolerances come from the file and are never loosened here.
struct GoldenFile: Decodable {
    struct Tolerance: Decodable {
        let time_s: Double
        let altitude_deg: Double
        let illum_fraction: Double
        let minutes: Int
    }
    struct Window: Decodable { let start: String; let end: String; let minutes: Int? }
    struct GC: Decodable {
        let max_altitude_deg: Double?
        let max_altitude_at: String?
        let rises_during_darkness: Bool
    }
    struct Expected: Decodable {
        let darkness: Window?
        let no_astronomical_darkness: Bool
        let moon_illum_fraction: Double
        let moonset: String?
        let moonrise: String?
        let moon_free_windows: [Window]
        let moon_free_minutes: Int
        let gc: GC
    }
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let latitude: Double
        let longitude: Double
        let evening_utc: String
        let expected: Expected
        var testDescription: String { id }
    }

    let astronomy_engine: String
    let tolerance: Tolerance
    let cases: [Case]

    static func load() throws -> GoldenFile {
        try JSONDecoder().decode(GoldenFile.self, from: Repo.data("shared/golden/night-report.json"))
    }
}

extension GoldenFile.Expected: Sendable {}
extension GoldenFile.Window: Sendable {}
extension GoldenFile.GC: Sendable {}
extension GoldenFile.Tolerance: Sendable {}

/// The astronomy-engine tag recorded in `Sources/CAstronomy/VENDORED.md`.
enum VendoredAstronomy {
    static func version() throws -> String {
        let text = try #require(String(
            data: Repo.data("ios/Packages/SkyCore/Sources/CAstronomy/VENDORED.md"), encoding: .utf8))
        let match = try #require(text.firstMatch(of: /\| Tag \| `v([0-9]+\.[0-9]+\.[0-9]+)`/))
        return String(match.1)
    }
}

@Suite("Golden files were written by the vendored astronomy-engine version")
struct GoldenVersionTests {
    @Test func nightReport() throws {
        #expect(try GoldenFile.load().astronomy_engine == VendoredAstronomy.version())
    }

    @Test func gcHorizon() throws {
        #expect(try GCHorizonFile.load().astronomy_engine == VendoredAstronomy.version())
    }
}

@Suite("Golden night-report parity with the web planner")
struct GoldenParityTests {
    @Test("the golden file has the 8 contracted cases")
    func caseCount() throws {
        #expect(try GoldenFile.load().cases.count == 8)
    }

    @Test("planNight matches within the file's tolerances", arguments: try GoldenFile.load().cases)
    func planNightMatches(_ golden: GoldenFile.Case) throws {
        let tol = try GoldenFile.load().tolerance
        let report = try Planner.planNight(
            observer(golden.latitude, golden.longitude), evening: ISO.date(golden.evening_utc))
        let exp = golden.expected

        func expectTime(_ actual: Date?, _ expected: String?, _ label: String) throws {
            let expectedDate = try ISO.date(expected)
            #expect((actual == nil) == (expectedDate == nil), "\(label): presence")
            if let actual, let expectedDate {
                let delta = abs(actual.timeIntervalSince(expectedDate))
                #expect(delta <= tol.time_s, "\(label): off by \(delta) s")
            }
        }

        #expect(report.noAstronomicalDarkness == exp.no_astronomical_darkness)
        try expectTime(report.darkness?.start, exp.darkness?.start, "darkness.start")
        try expectTime(report.darkness?.end, exp.darkness?.end, "darkness.end")
        #expect(abs(report.moonIllumFraction - exp.moon_illum_fraction) <= tol.illum_fraction)
        try expectTime(report.moonset, exp.moonset, "moonset")
        try expectTime(report.moonrise, exp.moonrise, "moonrise")

        try #require(report.moonFreeWindows.count == exp.moon_free_windows.count)
        for (actual, expected) in zip(report.moonFreeWindows, exp.moon_free_windows) {
            try expectTime(actual.start, expected.start, "window.start")
            try expectTime(actual.end, expected.end, "window.end")
            #expect(abs(actual.minutes - (expected.minutes ?? -1)) <= tol.minutes)
        }
        #expect(abs(report.moonFreeMinutes - exp.moon_free_minutes) <= tol.minutes)

        #expect((report.gc.maxAltitudeDeg == nil) == (exp.gc.max_altitude_deg == nil))
        if let actual = report.gc.maxAltitudeDeg, let expected = exp.gc.max_altitude_deg {
            #expect(abs(actual - expected) <= tol.altitude_deg)
        }
        try expectTime(report.gc.maxAltitudeAt, exp.gc.max_altitude_at, "gc.max_altitude_at")
        #expect(report.gc.risesDuringDarkness == exp.gc.rises_during_darkness)
    }
}

struct GCHorizonFile: Decodable {
    struct Tolerance: Decodable { let altitude_deg: Double; let azimuth_deg: Double }
    struct Point: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let latitude: Double
        let longitude: Double
        let utc: String
        let altitude_deg: Double
        let azimuth_deg: Double
        var testDescription: String { id }
    }
    let astronomy_engine: String
    let tolerance: Tolerance
    let points: [Point]

    static func load() throws -> GCHorizonFile {
        try JSONDecoder().decode(GCHorizonFile.self, from: Repo.data("shared/golden/gc-horizon.json"))
    }
}

@Suite("GC alt/az spot checks against the web app's gcAltitude/gcAzimuth")
struct GCHorizonTests {
    @Test(arguments: try GCHorizonFile.load().points)
    func matchesWeb(_ point: GCHorizonFile.Point) throws {
        let tol = try GCHorizonFile.load().tolerance
        let obs = try observer(point.latitude, point.longitude)
        let when = try ISO.date(point.utc)
        for position in [
            Planner.gcPosition(obs, at: when),
            try SkyPositions.position(of: .galacticCenter, at: when, observer: obs, refraction: .none),
        ] {
            #expect(abs(position.altitudeDeg - point.altitude_deg) <= tol.altitude_deg)
            #expect(azimuthDelta(position.azimuthDeg, point.azimuth_deg) <= tol.azimuth_deg)
        }
    }
}
