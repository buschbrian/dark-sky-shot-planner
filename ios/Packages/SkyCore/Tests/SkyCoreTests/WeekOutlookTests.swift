import Foundation
import Testing
@testable import SkyCore

/// One night from the web planner, produced on 2026-09-26 by running
/// `app/src/astronomy/planner.ts` (astronomy-engine 2.1.19) under
/// `TZ=America/Denver` with the web app's evening rule,
/// `new Date(\`${iso}T21:00:00\`)` (`eveningUtcFor` in `app/src/main.ts`).
struct WebNight: Sendable, CustomTestStringConvertible {
    let iso: String
    let evening: String
    let moonFreeMinutes: Int
    var darkness: (String, String)?
    var gcPeakDeg: Double?

    var testDescription: String { iso }
}

private let denver = TimeZone(identifier: "America/Denver")!
private let moab = (lat: 38.57, lon: -109.55)
private let slc = (lat: 40.76, lon: -111.89)

/// DST ends 2026-11-01 02:00 MDT: the evening moves from 03:00Z to 04:00Z.
private let moabFallBackWeek: [WebNight] = [
    .init(iso: "2026-10-29", evening: "2026-10-30T03:00:00Z", moonFreeMinutes: 79,
          darkness: ("2026-10-30T01:50:48.624Z", "2026-10-30T12:13:21.038Z"), gcPeakDeg: 8),
    .init(iso: "2026-10-30", evening: "2026-10-31T03:00:00Z", moonFreeMinutes: 151,
          darkness: ("2026-10-31T01:49:45.881Z", "2026-10-31T12:14:17.732Z"), gcPeakDeg: 7.6),
    .init(iso: "2026-10-31", evening: "2026-11-01T03:00:00Z", moonFreeMinutes: 226,
          darkness: ("2026-11-01T01:48:44.686Z", "2026-11-01T12:15:14.481Z"), gcPeakDeg: 7.3),
    .init(iso: "2026-11-01", evening: "2026-11-02T04:00:00Z", moonFreeMinutes: 301,
          darkness: ("2026-11-02T01:47:45.064Z", "2026-11-02T12:16:11.280Z"), gcPeakDeg: 6.9),
    .init(iso: "2026-11-02", evening: "2026-11-03T04:00:00Z", moonFreeMinutes: 372,
          darkness: ("2026-11-03T01:46:47.039Z", "2026-11-03T12:17:08.126Z"), gcPeakDeg: 6.5),
    .init(iso: "2026-11-03", evening: "2026-11-04T04:00:00Z", moonFreeMinutes: 440,
          darkness: ("2026-11-04T01:45:50.633Z", "2026-11-04T12:18:05.011Z"), gcPeakDeg: 6),
    .init(iso: "2026-11-04", evening: "2026-11-05T04:00:00Z", moonFreeMinutes: 507,
          darkness: ("2026-11-05T01:44:55.869Z", "2026-11-05T12:19:01.926Z"), gcPeakDeg: 5.6),
]

/// Crosses September into October; the first night is full-moon with no moon-free time.
private let moabMonthBoundaryWeek: [WebNight] = [
    .init(iso: "2026-09-28", evening: "2026-09-29T03:00:00Z", moonFreeMinutes: 0,
          darkness: ("2026-09-29T02:33:38.854Z", "2026-09-29T11:44:00.371Z"), gcPeakDeg: nil),
    .init(iso: "2026-09-29", evening: "2026-09-30T03:00:00Z", moonFreeMinutes: 2,
          darkness: ("2026-09-30T02:32:00.974Z", "2026-09-30T11:44:58.461Z"), gcPeakDeg: 16.7),
    .init(iso: "2026-09-30", evening: "2026-10-01T03:00:00Z", moonFreeMinutes: 48,
          darkness: ("2026-10-01T02:30:23.841Z", "2026-10-01T11:45:56.363Z"), gcPeakDeg: 16.5),
    .init(iso: "2026-10-01", evening: "2026-10-02T03:00:00Z", moonFreeMinutes: 105,
          darkness: ("2026-10-02T02:28:47.485Z", "2026-10-02T11:46:54.092Z"), gcPeakDeg: 16.2),
    .init(iso: "2026-10-02", evening: "2026-10-03T03:00:00Z", moonFreeMinutes: 171,
          darkness: ("2026-10-03T02:27:11.932Z", "2026-10-03T11:47:51.664Z"), gcPeakDeg: 16),
    .init(iso: "2026-10-03", evening: "2026-10-04T03:00:00Z", moonFreeMinutes: 244,
          darkness: ("2026-10-04T02:25:37.211Z", "2026-10-04T11:48:49.094Z"), gcPeakDeg: 15.8),
    .init(iso: "2026-10-04", evening: "2026-10-05T03:00:00Z", moonFreeMinutes: 320,
          darkness: ("2026-10-05T02:24:03.349Z", "2026-10-05T11:49:46.395Z"), gcPeakDeg: 15.6),
]

/// Salt Lake City; DST starts 2026-03-08 02:00 MST: the evening moves from 04:00Z to 03:00Z.
private let slcSpringForwardWeek: [WebNight] = [
    .init(iso: "2026-03-05", evening: "2026-03-06T04:00:00Z", moonFreeMinutes: 73),
    .init(iso: "2026-03-06", evening: "2026-03-07T04:00:00Z", moonFreeMinutes: 136),
    .init(iso: "2026-03-07", evening: "2026-03-08T04:00:00Z", moonFreeMinutes: 200),
    .init(iso: "2026-03-08", evening: "2026-03-09T03:00:00Z", moonFreeMinutes: 262),
    .init(iso: "2026-03-09", evening: "2026-03-10T03:00:00Z", moonFreeMinutes: 323),
    .init(iso: "2026-03-10", evening: "2026-03-11T03:00:00Z", moonFreeMinutes: 380),
    .init(iso: "2026-03-11", evening: "2026-03-12T03:00:00Z", moonFreeMinutes: 431),
]

private let moabYearBoundaryWeek: [WebNight] = [
    .init(iso: "2026-12-29", evening: "2026-12-30T04:00:00Z", moonFreeMinutes: 320),
    .init(iso: "2026-12-30", evening: "2026-12-31T04:00:00Z", moonFreeMinutes: 384),
    .init(iso: "2026-12-31", evening: "2027-01-01T04:00:00Z", moonFreeMinutes: 448),
    .init(iso: "2027-01-01", evening: "2027-01-02T04:00:00Z", moonFreeMinutes: 511),
    .init(iso: "2027-01-02", evening: "2027-01-03T04:00:00Z", moonFreeMinutes: 573),
    .init(iso: "2027-01-03", evening: "2027-01-04T04:00:00Z", moonFreeMinutes: 632),
    .init(iso: "2027-01-04", evening: "2027-01-05T04:00:00Z", moonFreeMinutes: 676),
]

@Suite("Week outlook")
struct WeekOutlookTests {
    static let weeks: [(String, Double, Double, [WebNight])] = [
        ("Moab, fall back", moab.lat, moab.lon, moabFallBackWeek),
        ("Moab, Sep to Oct", moab.lat, moab.lon, moabMonthBoundaryWeek),
        ("SLC, spring forward", slc.lat, slc.lon, slcSpringForwardWeek),
        ("Moab, 2026 to 2027", moab.lat, moab.lon, moabYearBoundaryWeek),
    ]

    /// Web values carry milliseconds; the golden parity reached < 1 ms, so 1 s is generous.
    static let timeToleranceSeconds: TimeInterval = 1

    @Test("seven consecutive nights match the web planner", arguments: [0, 1, 2, 3])
    func matchesWebPlanner(_ index: Int) throws {
        let (_, lat, lon, expected) = Self.weeks[index]
        let first = try #require(NightDate(iso: expected[0].iso))
        let rows = try WeekOutlook.build(
            observer: observer(lat, lon), timeZone: denver, now: first.evening(in: denver), first: first,
            clouds: [], kp: nil, auroraRule: AuroraRule.bundled(), verdict: { _ in () })
        #expect(rows.count == 7)
        for (row, web) in zip(rows, expected) {
            #expect(row.night.date.iso == web.iso)
            #expect(row.night.evening == (try ISO.date(web.evening)), "\(web.iso)")
            #expect(row.night.moonFreeMinutes == web.moonFreeMinutes, "\(web.iso)")
            if let (start, end) = web.darkness {
                let dark = try #require(row.night.darkness)
                #expect(abs(dark.start.timeIntervalSince(try ISO.date(start))) < Self.timeToleranceSeconds)
                #expect(abs(dark.end.timeIntervalSince(try ISO.date(end))) < Self.timeToleranceSeconds)
                #expect(row.night.gcPeak.maxAltitudeDeg == web.gcPeakDeg, "\(web.iso)")
            }
        }
    }

    @Test func eachRowIsPlanNightForItsEvening() throws {
        let obs = try observer(moab.lat, moab.lon)
        let first = try #require(NightDate(iso: "2026-10-29"))
        let rows = try WeekOutlook.build(
            observer: obs, timeZone: denver, now: first.evening(in: denver), first: first,
            clouds: [], kp: nil, auroraRule: AuroraRule.bundled(), verdict: { _ in () })
        for row in rows {
            #expect(row.night.report == (try Planner.planNight(obs, evening: row.night.evening)))
        }
    }

    @Test("the first night defaults to the night containing now at the spot")
    func defaultFirstNight() throws {
        let rule = try AuroraRule.bundled()
        let obs = try observer(moab.lat, moab.lon)
        // 02:00 MDT on the 30th is still the night of the 29th.
        let rows = try WeekOutlook.build(
            observer: obs, timeZone: denver, now: ISO.date("2026-10-30T08:00:00Z"), count: 2,
            clouds: [], kp: nil, auroraRule: rule, verdict: { _ in () })
        #expect(rows.map(\.night.date.iso) == ["2026-10-29", "2026-10-30"])
        #expect(try WeekOutlook.build(
            observer: obs, timeZone: denver, now: Date(), count: 0,
            clouds: [], kp: nil, auroraRule: rule, verdict: { _ in () }).isEmpty)
    }

    @Test("cloud mean covers the moon-free dark window; a missing hour is not clear")
    func cloudMeanOverMoonFreeWindow() throws {
        // Night of 2026-10-29 at Moab: moon-free 01:50:48Z-03:09:33Z (79 min).
        let t = { (h: Int) in try ISO.date(String(format: "2026-10-30T%02d:00:00Z", h)) }
        let full = HourlySeries(model: "hrrr", samples: [
            .init(time: try t(1), value: 100), .init(time: try t(2), value: 0),
            .init(time: try t(3), value: 0), .init(time: try t(4), value: 100),
        ])
        let gap = HourlySeries(model: "gfs", samples: [
            .init(time: try t(1), value: 100), .init(time: try t(2), value: 0),
            .init(time: try t(3), value: nil), .init(time: try t(4), value: 100),
        ])
        let empty = HourlySeries(model: "icon", samples: [.init(time: try t(2), value: nil)])
        let night = try WeekOutlook.night(
            #require(NightDate(iso: "2026-10-29")), observer: observer(moab.lat, moab.lon), timeZone: denver,
            clouds: [full, gap, empty])
        let window = try #require(night.moonFreeDarkness.first)
        #expect(night.moonFreeDarkness.count == 1)
        #expect(night.cloud.map(\.model) == ["hrrr", "gfs", "icon"])

        #expect(night.cloud[0].mean == WindowMean(status: .complete, mean: 0, coveredFraction: 1))
        let partial = night.cloud[1].mean
        #expect(partial.status == .partial)
        #expect(partial.mean == 0)
        #expect(partial.completeMean == nil)
        let covered = try t(2).addingTimeInterval(1800).timeIntervalSince(window.start)
        #expect(abs(partial.coveredFraction - covered / window.duration) < 1e-9)
        #expect(night.cloud[2].mean == WindowMean(status: .unavailable, mean: nil, coveredFraction: 0))
    }

    @Test("a night without moon-free darkness has no window to average")
    func fullMoonHasNoCloudWindow() throws {
        let series = HourlySeries(model: "hrrr", samples: (0..<24).map { h in
            HourlySample(time: Date(timeIntervalSince1970: 1_790_640_000 + Double(h) * 3600), value: 10)
        })
        let night = try WeekOutlook.night(
            #require(NightDate(iso: "2026-09-28")), observer: observer(moab.lat, moab.lon), timeZone: denver,
            clouds: [series])
        #expect(night.moonFreeMinutes == 0)
        #expect(night.cloud[0].mean.status == .noWindow)
        #expect(night.cloud[0].mean.mean == nil)
    }

    @Test("aurora is attached per night and never reaches the verdict")
    func auroraPerNightAndNeverInVerdict() throws {
        let rule = try AuroraRule.bundled()
        let obs = try observer(moab.lat, moab.lon)
        let first = try #require(NightDate(iso: "2026-10-29"))
        let start = try ISO.date("2026-10-29T00:00:00Z")
        // Observed through 21Z on the 29th, then predicted through 2026-11-01T24Z.
        var kp: [KpReading] = (0..<8).map {
            KpReading(start: start.addingTimeInterval(Double($0) * KpReading.interval), kp: 2, kind: .observed)
        }
        kp[6] = KpReading(start: kp[6].start, kp: 8, kind: .observed)
        kp += (8..<32).map {
            KpReading(start: start.addingTimeInterval(Double($0) * KpReading.interval), kp: 3, kind: .predicted)
        }
        let now = try ISO.date("2026-10-29T20:00:00Z")
        let verdict = { (n: NightOutlook) in n.moonFreeMinutes >= 120 }
        let rows = try WeekOutlook.build(
            observer: obs, timeZone: denver, now: now, first: first,
            clouds: [], kp: kp, auroraRule: rule, verdict: verdict)
        let quiet = try WeekOutlook.build(
            observer: obs, timeZone: denver, now: now, first: first,
            clouds: [], kp: nil, auroraRule: rule, verdict: verdict)

        #expect(rows.map(\.verdict) == quiet.map(\.verdict))
        #expect(rows[0].aurora == .possible(kp: 8, visibleKp: 7.67, basis: .observedNow))
        #expect(rows[1].aurora == .notExpected(maxKp: 3, visibleKp: 7.67))
        #expect(rows[2].aurora == .notExpected(maxKp: 3, visibleKp: 7.67))
        #expect(rows[3...].allSatisfy { $0.aurora == .unavailable(.kpDoesNotCoverNight) })
        #expect(quiet.allSatisfy { $0.aurora == .unavailable(.noKpData) })
    }

    @Test("after dawn, Kp observed now applies to the coming night, not the one just ended")
    func observedNowAfterDawn() throws {
        let rule = try AuroraRule.bundled()
        let now = try ISO.date("2026-10-30T16:00:00Z") // 10:00 MDT
        let kp = [KpReading(start: try ISO.date("2026-10-30T15:00:00Z"), kp: 9, kind: .observed)]
        // Stepped back to the night that just ended (review B-2 made it no longer the default).
        let rows = try WeekOutlook.build(
            observer: observer(moab.lat, moab.lon), timeZone: denver, now: now,
            first: NightDate(iso: "2026-10-29"), count: 2,
            clouds: [], kp: kp, auroraRule: rule, verdict: { _ in () })
        #expect(rows[0].night.date.iso == "2026-10-29")
        #expect(rows[0].aurora == .unavailable(.kpDoesNotCoverNight))
        #expect(rows[1].aurora == .possible(kp: 9, visibleKp: 7.67, basis: .observedNow))

        // By default, after dawn the week starts at the coming night (B-2).
        let byDefault = try WeekOutlook.build(
            observer: observer(moab.lat, moab.lon), timeZone: denver, now: now, count: 2,
            clouds: [], kp: kp, auroraRule: rule, verdict: { _ in () })
        #expect(byDefault[0].night.date.iso == "2026-10-30")
        #expect(byDefault[0].aurora == .possible(kp: 9, visibleKp: 7.67, basis: .observedNow))
    }
}
