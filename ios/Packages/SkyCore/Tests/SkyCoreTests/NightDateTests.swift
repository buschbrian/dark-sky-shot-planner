import Foundation
import Testing
@testable import SkyCore

@Suite("Night date")
struct NightDateTests {
    let denver = TimeZone(identifier: "America/Denver")!

    @Test func parsesTheWebAppsDateFormatOnly() {
        #expect(NightDate(iso: "2026-09-26")?.iso == "2026-09-26")
        #expect(NightDate(iso: "2028-02-29") != nil)
        #expect(NightDate(iso: "2026-02-29") == nil)
        #expect(NightDate(iso: "2026-9-26") == nil)
        #expect(NightDate(iso: "2026-09-26T21:00") == nil)
        #expect(NightDate(iso: "") == nil)
    }

    @Test func addsDaysAcrossMonthYearAndLeapDay() throws {
        let d = { (s: String) in try #require(NightDate(iso: s)) }
        #expect(try d("2026-09-30").adding(days: 1) == d("2026-10-01"))
        #expect(try d("2026-12-31").adding(days: 1) == d("2027-01-01"))
        #expect(try d("2028-02-28").adding(days: 1) == d("2028-02-29"))
        #expect(try d("2026-03-01").adding(days: -1) == d("2026-02-28"))
        #expect(try d("2026-10-29").adding(days: 6) == d("2026-11-04"))
        #expect(try d("2026-10-29") < d("2026-11-01"))
    }

    @Test("evening is 21:00 local on the date, through DST changes")
    func eveningFollowsLocalTime() throws {
        let cases: [(String, String)] = [
            ("2026-10-31", "2026-11-01T03:00:00Z"), // MDT
            ("2026-11-01", "2026-11-02T04:00:00Z"), // MST, the day DST ends
            ("2026-03-07", "2026-03-08T04:00:00Z"),
            ("2026-03-08", "2026-03-09T03:00:00Z"), // the day DST starts
        ]
        for (iso, utc) in cases {
            #expect(try #require(NightDate(iso: iso)).evening(in: denver) == ISO.date(utc), "\(iso)")
        }
        let phoenix = try #require(TimeZone(identifier: "America/Phoenix"))
        #expect(try #require(NightDate(iso: "2026-11-01")).evening(in: phoenix) == ISO.date("2026-11-02T04:00:00Z"))
    }

    @Test("an instant belongs to the evening's night until local noon")
    func nightContainingInstant() throws {
        let cases: [(String, String)] = [
            ("2026-09-26T17:59:00Z", "2026-09-25"), // 11:59 MDT
            ("2026-09-26T18:00:00Z", "2026-09-26"), // 12:00 MDT
            ("2026-09-27T03:00:00Z", "2026-09-26"), // 21:00 MDT
            ("2026-09-27T06:30:00Z", "2026-09-26"), // 00:30 MDT, past local midnight
            ("2026-11-01T08:30:00Z", "2026-10-31"), // 01:30 MST, after the fall-back hour
            ("2027-01-01T07:00:00Z", "2026-12-31"), // 00:00 MST on New Year's Day
        ]
        for (instant, night) in cases {
            #expect(NightDate.containing(try ISO.date(instant), in: denver).iso == night, "\(instant)")
        }
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        #expect(NightDate.containing(try ISO.date("2026-09-26T10:00:00Z"), in: auckland).iso == "2026-09-26")
    }

    struct TonightFile: Decodable {
        struct Tolerance: Decodable { let time_s: Double }
        struct Case: Decodable {
            let id: String, latitude: Double, longitude: Double, time_zone: String
            let instant_utc: String, tonight: String
        }
        struct End: Decodable {
            let id: String, latitude: Double, longitude: Double, time_zone: String
            let night: String, end_utc: String?
        }
        let tolerance: Tolerance
        let cases: [Case]
        let darkness_end: [End]
    }

    static let golden: TonightFile = {
        // A missing or malformed file fails every test that reads it.
        (try? JSONDecoder().decode(TonightFile.self, from: Repo.data("shared/golden/tonight.json")))
            ?? TonightFile(tolerance: .init(time_s: 0), cases: [], darkness_end: [])
    }()

    @Test("the golden file is present and covers the review's morning cases")
    func goldenFileLoads() {
        let ids = Set(Self.golden.cases.map(\.id))
        #expect(ids.isSuperset(of: ["candlestick-0300", "candlestick-0730", "glacier-solstice-0300", "fairbanks-solstice-0200"]))
        #expect(Self.golden.darkness_end.count >= 3)
    }

    @Test("tonight is last night only while it is still dark (shared/golden/tonight.json)",
          arguments: golden.cases.map(\.id))
    func currentNight(_ id: String) throws {
        let c = try #require(Self.golden.cases.first { $0.id == id })
        let zone = try #require(TimeZone(identifier: c.time_zone))
        let observer = try Observer(latitude: c.latitude, longitude: c.longitude)
        let instant = try ISO.date(c.instant_utc)
        #expect(NightDate.current(at: instant, observer: observer, timeZone: zone).iso == c.tonight)
        let span = NightDate.currentSpan(at: instant, observer: observer, timeZone: zone)
        #expect(span.contains(instant))
        #expect(span.night.iso == c.tonight)
        // Just outside the span, the neighbouring night.
        #expect(NightDate.current(at: span.until, observer: observer, timeZone: zone) == span.night.adding(days: 1))
        #expect(NightDate.current(at: span.from.addingTimeInterval(-1), observer: observer, timeZone: zone) == span.night.adding(days: -1))
    }

    @Test("darkness ends at astronomical dawn, else civil dawn, else never (shared/golden/tonight.json)",
          arguments: golden.darkness_end.map(\.id))
    func darknessEnd(_ id: String) throws {
        let c = try #require(Self.golden.darkness_end.first { $0.id == id })
        let zone = try #require(TimeZone(identifier: c.time_zone))
        let observer = try Observer(latitude: c.latitude, longitude: c.longitude)
        let end = try #require(NightDate(iso: c.night)).darknessEnd(observer: observer, timeZone: zone)
        if let expected = try ISO.date(c.end_utc) {
            let got = try #require(end)
            #expect(abs(got.timeIntervalSince(expected)) <= Self.golden.tolerance.time_s)
        } else {
            #expect(end == nil)
        }
    }

    @Test("the calendar rule is unchanged for callers that mean it")
    func containingKeepsTheNoonRule() throws {
        // 07:30 MDT: the calendar still says last night; "tonight" does not.
        let instant = try ISO.date("2026-09-27T13:30:00Z")
        let candlestick = try Observer(latitude: 38.374031, longitude: -109.965416)
        #expect(NightDate.containing(instant, in: denver).iso == "2026-09-26")
        #expect(NightDate.current(at: instant, observer: candlestick, timeZone: denver).iso == "2026-09-27")
    }
}

