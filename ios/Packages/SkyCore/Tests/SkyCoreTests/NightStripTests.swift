import Foundation
import Testing
@testable import SkyCore

@Suite struct NightStripTests {
    static let denver = TimeZone(identifier: "America/Denver")!

    static func strip(_ date: String) throws -> (NightStrip, NightReport) {
        let obs = try observer(38.35, -109.95)
        let evening = NightDate(iso: date)!.evening(in: denver)
        let report = try Planner.planNight(obs, evening: evening)
        return (try NightStrip.build(report: report, observer: obs, evening: evening), report)
    }

    @Test func spansTwoHoursEitherSideOfDarkness() throws {
        let (strip, report) = try Self.strip("2026-10-10")
        let dark = try #require(report.darkness)
        #expect(strip.span.start <= dark.start.addingTimeInterval(-2 * 3600))
        #expect(strip.span.end >= dark.end.addingTimeInterval(2 * 3600))
        #expect(strip.sun.first?.date == strip.span.start)
        #expect(strip.sun.count == strip.moon.count && strip.moon.count == strip.galacticCenter.count)
        #expect(zip(strip.sun, strip.sun.dropFirst()).allSatisfy { $1.date.timeIntervalSince($0.date) == NightStrip.step })
    }

    @Test func sunIsBelowAstronomicalTwilightInsideDarkness() throws {
        let (strip, report) = try Self.strip("2026-10-10")
        let dark = try #require(report.darkness)
        let inside = strip.sun.filter { $0.date > dark.start.addingTimeInterval(600) && $0.date < dark.end.addingTimeInterval(-600) }
        #expect(!inside.isEmpty)
        #expect(inside.allSatisfy { $0.position.altitudeDeg < -18 })
        #expect(strip.sun.first!.position.altitudeDeg > -18)
    }

    @Test func galacticCenterPeakAgreesWithThePlanner() throws {
        // A new-moon night in season: the GC is up during moon-free darkness.
        let (strip, report) = try Self.strip("2026-07-14")
        let peak = try #require(report.gc.maxAltitudeDeg)
        let inWindows = strip.galacticCenter.filter { s in strip.moonFree.contains { s.date >= $0.start && s.date <= $0.end } }
        let stripPeak = try #require(inWindows.map(\.position.altitudeDeg).max())
        #expect(abs(stripPeak - peak) < 0.5, "strip \(stripPeak) vs planner \(peak)")
    }

    @Test func midnightSunStillGivesAStrip() throws {
        let obs = try observer(69.65, 18.96)
        let evening = NightDate(iso: "2026-06-21")!.evening(in: TimeZone(identifier: "Europe/Oslo")!)
        let report = try Planner.planNight(obs, evening: evening)
        #expect(report.darkness == nil)
        let strip = try NightStrip.build(report: report, observer: obs, evening: evening)
        #expect(strip.span.duration == 13 * 3600)
        #expect(strip.sun.allSatisfy { $0.position.altitudeDeg > -18 })
    }
}

@Suite struct StripRowTests {
    @Test func cloudsGetOneRowPerModelAndTheRestOneEach() throws {
        let golden = try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
        let rows = StripRow.rows(from: golden)
        #expect(rows.filter { $0.kind == .cloudLow }.map(\.model) == ["hrrr", "gfs", "icon", "ecmwf"])
        #expect(rows.filter { $0.kind == .cloudHigh }.count == 4)
        for kind in [StripRow.Kind.aerosol, .transparency, .wind, .dewSpread] {
            #expect(rows.filter { $0.kind == kind }.count == 1, "\(kind)")
        }
        #expect(rows.allSatisfy { $0.unavailableReason == nil })
        #expect(rows.first { $0.kind == .aerosol }?.source.hasPrefix("Open-Meteo Air Quality") == true)
        #expect(rows.first { $0.kind == .transparency }?.model == "7timer_astro")
    }

    @Test func dewSpreadIsTemperatureMinusDewPointHourByHour() throws {
        let golden = try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
        let row = try #require(StripRow.rows(from: golden).first { $0.kind == .dewSpread })
        let t = golden.fields["temperature"]!.series[0]
        let d = golden.fields["dew_point"]!.series[0]
        #expect(row.model == "hrrr")
        for (i, p) in row.points.enumerated() {
            #expect(p.v == t.values[i].v! - d.values[i].v!)
        }
        #expect(row.asOfUTC == [t.asOfUTC!, d.asOfUTC!].min())
    }

    @Test func missingDataIsUnavailableNeverZero() throws {
        let none = StripRow.rows(from: nil)
        #expect(none.count == 7)
        #expect(none.allSatisfy { $0.points.isEmpty && $0.unavailableReason == "no conditions data" })

        let direct = OpenMeteoDirect.response(
            request: try OpenMeteoDirectTests.request(), fetches: try OpenMeteoDirectTests.recordedFetches(),
            fetchedUTC: OpenMeteoDirectTests.fetched)
        let rows = StripRow.rows(from: direct)
        #expect(rows.filter { $0.kind == .cloudMid }.allSatisfy { $0.unavailableReason == nil })
        for kind in [StripRow.Kind.aerosol, .transparency, .wind, .dewSpread] {
            let row = try #require(rows.first { $0.kind == kind })
            #expect(row.points.isEmpty)
            #expect(row.unavailableReason == OpenMeteoDirect.otherFieldsReason, "\(kind)")
        }
    }
}
