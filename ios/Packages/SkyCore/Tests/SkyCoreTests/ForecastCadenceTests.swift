import Foundation
import Testing
@testable import SkyCore

/// Review 2026-09-26 §1 (P1): HRRR's native 15-minute series must reach the
/// verdict, with explicit coverage, null and weighting rules, and the charts
/// must read the same points. Uses the May 6 Candlestick GC shot
/// (06:15:44Z–07:37Z) from `ShotVerdictTests`.
@Suite("Forecast cadence")
struct ForecastCadenceTests {
    typealias F = ShotVerdictTests

    static func fine(_ model: String = "hrrr", from h0: Double, to h1: Double, status: WorkerStatus = .ok,
                     reason: String? = nil, _ value: (Int) -> Double?) -> WorkerSeries {
        let n = Int(((h1 - h0) * 4).rounded())
        return WorkerSeries(
            model: model, upstreamModel: nil, modelRunUTC: F.at(0), fetchedUTC: F.at(1.5), status: status,
            reason: reason, lastGoodUTC: nil,
            values: status == .ok ? (0...n).map { WorkerPoint(t: F.at(h0 + Double($0) / 4), v: value($0)) } : [],
            resolutionMinutes: 15)
    }

    static func withFine(_ field: String, _ series: WorkerSeries, hourly: [Double?]? = nil) -> ConditionsResponse {
        F.response(clouds: F.clearingLate) { fields in
            var f = fields[field]!
            if let hourly {
                f = F.field(f.unit, f.series.map { $0.model == "hrrr" ? F.series("hrrr", hourly) : $0 })
            }
            f.series15Min = [series]
            fields[field] = f
        }
    }

    @Test("review probe: a 90 km/h native gust at 06:45Z inside the shot makes it no-go")
    func nativeGustSpike() throws {
        let shot = try F().shot()
        let response = Self.withFine("wind_gust", Self.fine(from: 6, to: 8) { $0 == 3 ? 90 : 8 })
        let snapshot = ConditionsSnapshot(response: response, fetchedUTC: F.at(1.5))
        #expect(snapshot.nearTerm("wind_gust")?.values.map { $0.v ?? 0 }.max() == 90)
        let best = try #require(shot.best)
        #expect(best.start < F.at(6.75) && best.end > F.at(6.75))
        let verdict = try shot.verdict(conditions: response, config: .bundled(), now: F.now)
        let gust = try #require(verdict.factor("wind_gust"))
        #expect(gust.value == 90)
        #expect(gust.rating == .poor)
        #expect(verdict.level == .noGo)
        let hrrr = try #require(gust.readings.first { $0.model == "hrrr" })
        #expect(hrrr.cadence == "15-min to 08:00Z, hourly after")
        #expect(gust.readings.first { $0.model == "gfs" }?.cadence == nil)
    }

    @Test("a fine series with a null falls back to hourly and says so")
    func nullFineFallsBack() throws {
        let response = Self.withFine("wind_gust", Self.fine(from: 6, to: 8) { $0 == 3 ? 90 : $0 == 5 ? nil : 8 })
        let verdict = try F().shot().verdict(conditions: response, config: .bundled(), now: F.now)
        let hrrr = try #require(verdict.factor("wind_gust")?.readings.first { $0.model == "hrrr" })
        #expect(hrrr.value == 8)
        #expect(hrrr.cadence == "15-min series has missing values; hourly used")
    }

    @Test("an unavailable fine series falls back to hourly and gives its reason")
    func unavailableFineFallsBack() throws {
        let response = Self.withFine(
            "wind_gust", Self.fine(from: 6, to: 8, status: .unavailable, reason: "not published") { _ in nil })
        let verdict = try F().shot().verdict(conditions: response, config: .bundled(), now: F.now)
        let hrrr = try #require(verdict.factor("wind_gust")?.readings.first { $0.model == "hrrr" })
        #expect(hrrr.value == 8)
        #expect(hrrr.cadence == "15-min series unavailable (not published); hourly used")
        #expect(hrrr.status == .rated(.good))
    }

    @Test("handoff: 15-minute points replace hourly ones inside their span; hourly carries on after")
    func handoff() throws {
        // Hourly HRRR says 70 km/h at 06Z and 07Z (inside the fine span) and 45 at 08Z (after it).
        var hourly: [Double?] = Array(repeating: 8, count: 13)
        hourly[6] = 70; hourly[7] = 70; hourly[8] = 45
        let response = Self.withFine("wind_gust", Self.fine(from: 6, to: 7) { _ in 8 }, hourly: hourly)
        let selection = try #require(ForecastCadence.select(response, field: "wind_gust", model: "hrrr"))
        #expect(selection.points.map(\.t) == (0...5).map { F.at(Double($0)) }
            + (0...4).map { F.at(6 + Double($0) / 4) } + (8...12).map { F.at(Double($0)) })
        #expect(selection.fineSpan == TimeWindow(start: F.at(6), end: F.at(7)))
        let verdict = try F().shot().verdict(conditions: response, config: .bundled(), now: F.now)
        // 70 is gone (replaced by 15-minute 8s); the 08Z hourly point brackets the 07:37Z end.
        #expect(verdict.factor("wind_gust")?.readings.first { $0.model == "hrrr" }?.value == 45)
    }

    @Test("time weighting: four 15-minute points do not outweigh the hour after them")
    func timeWeightedMean() {
        var samples: [Date: Double] = [:]
        for q in 0..<4 { samples[F.at(6 + Double(q) / 4)] = 40 }
        samples[F.at(7)] = 0
        samples[F.at(8)] = 0
        let window = [TimeWindow(start: F.at(6), end: F.at(8))]
        let unweighted = samples.values.reduce(0, +) / Double(samples.count)
        let weighted = try! #require(ForecastCadence.timeWeightedMean(samples, over: window))
        // 06:00 stands for 7.5 min inside the window, 06:15–06:45 for 15 each, 07:00 for 37.5, 08:00 for 30.
        #expect(abs(weighted - 40 * 52.5 / 120) < 1e-9)
        #expect(abs(unweighted - 160.0 / 6) < 1e-9)
        #expect(weighted < unweighted)
        // Evenly spaced hourly data: the two ends count half, as a trapezoid.
        let hourly: [Date: Double] = [F.at(6): 10, F.at(7): 20, F.at(8): 60]
        #expect(ForecastCadence.timeWeightedMean(hourly, over: window) == (10 * 0.5 + 20 + 60 * 0.5) / 2)
    }

    @Test("dew spread pairs temperature and dew point at matching 15-minute times")
    func dewSpreadPaired() throws {
        let response = F.response(clouds: F.clearingLate) { fields in
            var t = fields["temperature"]!, d = fields["dew_point"]!
            t.series15Min = [Self.fine(from: 6, to: 8) { $0 == 3 ? 1 : 12 }]
            d.series15Min = [Self.fine(from: 6, to: 8) { $0 == 3 ? 0.5 : -2 }]
            fields["temperature"] = t
            fields["dew_point"] = d
        }
        let verdict = try F().shot().verdict(conditions: response, config: .bundled(), now: F.now)
        let hrrr = try #require(verdict.factor("dew_point_spread")?.readings.first { $0.model == "hrrr" })
        #expect(hrrr.value == 0.5)
        #expect(hrrr.cadence == "15-min to 08:00Z, hourly after")
    }

    @Test("with only one of the pair at 15 minutes, both use hourly and say why")
    func dewSpreadUnpaired() throws {
        let response = F.response(clouds: F.clearingLate) { fields in
            var t = fields["temperature"]!
            t.series15Min = [Self.fine(from: 6, to: 8) { $0 == 3 ? 1 : 12 }]
            fields["temperature"] = t
        }
        let verdict = try F().shot().verdict(conditions: response, config: .bundled(), now: F.now)
        let hrrr = try #require(verdict.factor("dew_point_spread")?.readings.first { $0.model == "hrrr" })
        #expect(hrrr.value == 14)
        #expect(hrrr.cadence == "15-min temperature and dew point not at matching times; hourly used")
    }

    @Test("charts read exactly the verdict's points")
    func chartsMatchVerdict() throws {
        let response = Self.withFine("wind_gust", Self.fine(from: 6, to: 8) { $0 == 3 ? 90 : 8 })
        let snapshot = ConditionsSnapshot(response: response, fetchedUTC: F.at(1.5))
        let selection = try #require(ForecastCadence.select(response, field: "wind_gust", model: "hrrr"))
        #expect(snapshot.finestPoints("wind_gust") == selection.points)
        #expect(snapshot.finestPoints("wind_gust").contains { $0.v == 90 })
        let nulls = Self.withFine("wind_gust", Self.fine(from: 6, to: 8) { $0 == 5 ? nil : 8 })
        #expect(ConditionsSnapshot(response: nulls, fetchedUTC: F.at(1.5)).finestPoints("wind_gust").count == 13)
    }

    @Test("provenance: the combined data is as old as the older series")
    func provenance() throws {
        let old = WorkerSeries(
            model: "hrrr", upstreamModel: nil, modelRunUTC: F.at(-3), fetchedUTC: F.at(1.5), status: .ok,
            reason: nil, lastGoodUTC: nil, values: [WorkerPoint(t: F.at(6), v: 8)], resolutionMinutes: 15)
        let selection = ForecastCadence.select(hourly: F.series("hrrr", F.flat(8)), fine: old)
        #expect(selection.asOfUTC == F.at(-3))
        // A fine series from another model is never spliced in.
        let other = ForecastCadence.select(hourly: F.series("gfs", F.flat(8)), fine: Self.fine(from: 6, to: 7) { _ in 90 })
        #expect(other.fineSpan == nil && other.note == nil)
    }

    @Test("the evidence lines name the cadence the value came from")
    func evidenceNamesCadence() throws {
        let response = Self.withFine("wind_gust", Self.fine(from: 6, to: 8) { $0 == 3 ? 90 : 8 })
        let readout = ShotReadout(try F().shot().verdict(conditions: response, config: .bundled(), now: F.now))
        #expect(readout.limiting.key == "wind_gust")
        #expect(ShotText.modelLines(readout).first == "HRRR 90 km/h (run 00Z, 2 h old, 15-min to 08:00Z, hourly after)")
    }

    @Test("with several windows the verdict's scope is stated; with one it is not")
    func verdictScope() throws {
        let one = try F().shot()
        #expect(ShotText.verdictScope(one) == nil)
        // The full Moon of 2026-09-26 passes behind a 60° wall due south around midnight: two windows.
        let many = try ShotWindow.compute(
            observer(38.374031, -109.965416), evening: ISO.date("2026-09-27T03:00:00Z"),
            horizon: HorizonProfile(samples: [
                .init(azimuthDeg: 0, altitudeDeg: 0), .init(azimuthDeg: 150, altitudeDeg: 0),
                .init(azimuthDeg: 160, altitudeDeg: 60), .init(azimuthDeg: 200, altitudeDeg: 60),
                .init(azimuthDeg: 210, altitudeDeg: 0),
            ]),
            target: .moon)
        try #require(many.windows.count == 2)
        #expect(ShotText.verdictScope(many) == "Verdict for this window only; 1 other window below")
        #expect(many.windows[0].closesBy == .targetDrops && many.windows[1].opensBy == .targetClears)
    }

    /// The same two-window Moon night (coordinator decision 2026-09-27): each
    /// window's verdict reads only its own minutes, so thick cloud in the
    /// first window no longer sinks a clear second one, and vice versa.
    @Test("the verdict describes the selected window only")
    func perWindowVerdict() throws {
        let shot = try ShotWindow.compute(
            observer(38.374031, -109.965416), evening: ISO.date("2026-09-27T03:00:00Z"),
            horizon: HorizonProfile(samples: [
                .init(azimuthDeg: 0, altitudeDeg: 0), .init(azimuthDeg: 150, altitudeDeg: 0),
                .init(azimuthDeg: 160, altitudeDeg: 60), .init(azimuthDeg: 200, altitudeDeg: 60),
                .init(azimuthDeg: 210, altitudeDeg: 0),
            ]),
            target: .moon)
        try #require(shot.windows.count == 2)
        let split = shot.windows[0].end.addingTimeInterval(shot.windows[1].start.timeIntervalSince(shot.windows[0].end) / 2)
        // Hourly cloud 00Z–14Z on 2026-09-27: 95 % before the gap, 5 % after, every model.
        let t0 = try ISO.date("2026-09-27T00:00:00Z")
        let hours = (0...14).map { t0.addingTimeInterval(Double($0) * 3600) }
        func series(_ m: String, _ v: (Date) -> Double) -> WorkerSeries {
            WorkerSeries(model: m, upstreamModel: nil, modelRunUTC: t0, fetchedUTC: t0.addingTimeInterval(1800), status: .ok,
                         reason: nil, lastGoodUTC: nil, values: hours.map { WorkerPoint(t: $0, v: v($0)) })
        }
        let models = ["hrrr", "gfs", "icon", "ecmwf"]
        func field(_ unit: String, _ v: @escaping (Date) -> Double) -> WorkerField {
            F.field(unit, models.map { series($0, v) })
        }
        let response = ConditionsResponse(
            cell: WorkerCell(lat: 38.35, lon: -109.95, roundingDeg: 0.05),
            window: .init(startUTC: hours.first!, endUTC: hours.last!), generatedUTC: t0.addingTimeInterval(1800),
            fields: [
                "cloud_cover_total": field("%") { $0 < split ? 95 : 5 },
                "wind_gust": field("km/h") { _ in 8 },
                "temperature": field("°C") { _ in 12 },
                "dew_point": field("°C") { _ in -2 },
                "aerosol_optical_depth": F.field("", [series("cams_global") { _ in 0.04 }], source: "CAMS"),
                "smoke_column": F.field("mg/m²", [series("rap_smoke") { _ in 2 }], source: "RAP-Smoke"),
            ],
            attribution: [])
        let now = t0.addingTimeInterval(3600)
        let first = try shot.verdict(conditions: response, config: .bundled(), now: now, window: 0)
        let second = try shot.verdict(conditions: response, config: .bundled(), now: now, window: 1)
        #expect(first.level == .noGo)
        #expect(first.limiting.key.hasPrefix("cloud_cover"))
        #expect(second.level != .noGo, "\(second.level) \(second.limiting.key)")
        #expect(second.factor("cloud_cover_max_hour")?.rating == .good)
        #expect(first.windows.count == 1 && second.windows.count == 1)
        #expect(shot.nightForVerdict(window: 1).moonFreeMinutes == shot.windows[1].minutes)
        // No index means the longest window, as before.
        let longest = try #require(shot.bestIndex)
        #expect(shot.nightForVerdict == shot.nightForVerdict(window: longest))
        #expect(shot.tracks.count == 2)
        #expect(shot.tracks[1].first?.date == shot.windows[1].start && shot.tracks[1].last?.date == shot.windows[1].end)
        let clock = ShotText.clock24(F.denver)
        let second1 = ShotText.astronomy(shot, window: 1, clock: clock)
        #expect(second1.hasPrefix("Moon ") && second1.contains(clock(shot.windows[1].start)), "\(second1)")
        #expect(second1.contains(ShotText.duration(minutes: shot.windows[1].minutes)), "\(second1)")
    }
}
