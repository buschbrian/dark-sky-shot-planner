import Foundation
import Testing
@testable import SkyCore

/// M11: the verdict re-run over the shot window, not the whole night. The
/// real Candlestick case (2026-05-06, GC clears the ridge 06:15Z, Moon over
/// the ridge 07:37Z) with synthetic hourly conditions.
@Suite("Shot-window verdict")
struct ShotVerdictTests {
    static let t0 = WorkerJSON.parse("2026-05-07T00:00:00Z")!
    static let now = at(2)
    static let denver = TimeZone(identifier: "America/Denver")!

    static func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    static func series(_ model: String, _ values: [Double?], status: WorkerStatus = .ok, reason: String? = nil) -> WorkerSeries {
        WorkerSeries(
            model: model, upstreamModel: nil, modelRunUTC: at(0), fetchedUTC: at(1.5), status: status,
            reason: reason, lastGoodUTC: nil,
            values: status == .ok ? values.enumerated().map { WorkerPoint(t: at(Double($0.offset)), v: $0.element) } : [])
    }

    static func field(_ unit: String, _ series: [WorkerSeries], source: String = "Open-Meteo") -> WorkerField {
        WorkerField(
            unit: unit, source: source, status: series.contains { $0.status == .ok } ? .ok : .unavailable,
            fetchedUTC: at(1.5), series: series, reason: nil, lastGoodUTC: nil, observations: nil, preliminary: nil,
            attribution: nil, description: nil, valueKind: nil, calibrated: nil, calibration: nil,
            resolutionNote: nil, terms: nil, optional: nil)
    }

    /// Hour-by-hour cloud per model, 00Z–12Z.
    static func clouds(_ perModel: [String: (Int) -> Double]) -> WorkerField {
        field("%", ["hrrr", "gfs", "icon", "ecmwf"].map { m in series(m, (0...12).map { perModel[m]!($0) }) })
    }

    static func flat(_ v: Double) -> [Double?] { Array(repeating: v, count: 13) }

    static func response(clouds: WorkerField, edit: (inout [String: WorkerField]) -> Void = { _ in }) -> ConditionsResponse {
        let models = ["hrrr", "gfs", "icon", "ecmwf"]
        var fields: [String: WorkerField] = [
            "cloud_cover_total": clouds,
            "wind_gust": field("km/h", models.map { series($0, flat(8)) }),
            "temperature": field("°C", models.map { series($0, flat(12)) }),
            "dew_point": field("°C", models.map { series($0, flat(-2)) }),
            "aerosol_optical_depth": field("", [series("cams_global", flat(0.04))], source: "CAMS"),
            "smoke_column": field("mg/m²", [series("rap_smoke", flat(2))], source: "RAP-Smoke"),
        ]
        edit(&fields)
        return ConditionsResponse(
            cell: WorkerCell(lat: 38.35, lon: -109.95, roundingDeg: 0.05),
            window: .init(startUTC: at(0), endUTC: at(12)), generatedUTC: at(1.5), fields: fields, attribution: [])
    }

    func shot() throws -> ShotWindow {
        try ShotWindow.compute(
            observer(38.374031, -109.965416), evening: ISO.date("2026-05-07T03:00:00Z"),
            horizon: HorizonProfile.bundled("candlestick-camp"), target: .galacticCore)
    }

    /// Thick cloud until 06Z, then 10–25 % across the models.
    static let clearingLate = clouds([
        "hrrr": { $0 < 6 ? 95 : 10 }, "gfs": { $0 < 6 ? 90 : 25 },
        "icon": { $0 < 6 ? 85 : 15 }, "ecmwf": { $0 < 6 ? 90 : 20 },
    ])

    @Test("cloud before the core clears does not count against the shot; it does against the night")
    func sameMinutes() throws {
        let shot = try shot()
        let conditions = Self.response(clouds: Self.clearingLate)
        let config = try VerdictConfig.bundled()
        let shotVerdict = try shot.verdict(conditions: conditions, config: config, now: Self.now)
        let nightVerdict = try Verdict.evaluate(night: shot.night, conditions: conditions, config: config, now: Self.now)

        #expect(nightVerdict.level == .noGo)
        #expect(nightVerdict.limiting.key.hasPrefix("cloud_cover"))
        #expect(shotVerdict.level == .marginal)
        #expect(shotVerdict.factor("cloud_cover_max_hour")?.rating == .good)
        #expect(shotVerdict.windows.count == 1)
        #expect(shotVerdict.windows[0].minutes == 81)
        // The shot's own minutes and the core's altitude in them gate a GC shot.
        #expect(shotVerdict.factor("moon_free_minutes")?.value == 81)
        #expect(shotVerdict.factor("gc_max_altitude")?.gatesVerdict == true)
        #expect(shotVerdict.factor("gc_max_altitude")?.value == 14.1)
    }

    @Test("a cloud spike inside the window makes the shot no-go and names it")
    func spikeInside() throws {
        let spiky = Self.clouds([
            "hrrr": { $0 == 7 ? 85 : 5 }, "gfs": { _ in 5 }, "icon": { _ in 5 }, "ecmwf": { _ in 5 },
        ])
        let readout = ShotReadout(try shot().verdict(
            conditions: Self.response(clouds: spiky), config: .bundled(), now: Self.now))
        #expect(readout.level == .noGo)
        #expect(readout.limiting.key == "cloud_cover_max_hour")
        #expect(ShotText.verdictLine(readout) == "No-go: cloud cover (worst hour) 85 %")
        let lines = ShotText.modelLines(readout)
        #expect(lines.count == 4)
        #expect(lines[0] == "HRRR 85 % (run 00Z, 2 h old)")
    }

    @Test("the headline: when, how long, and the cloud spread with the reference run and age")
    func headline() throws {
        let shot = try shot()
        let readout = ShotReadout(try shot.verdict(
            conditions: Self.response(clouds: Self.clearingLate), config: .bundled(), now: Self.now))
        let spread = try #require(readout.clouds)
        #expect(spread.band == 10...25)
        #expect(spread.usableModels == 4)
        #expect(spread.reference?.model == "hrrr")
        let age = try #require(spread.reference?.age)
        #expect(abs(age - 2 * 3600) < 1e-6, "age \(age)")
        #expect(ShotText.headline(shot, readout: readout, clock: ShotText.clock24(Self.denver))
            == "Core clears the ridge 00:15, 1 h 21 min moon-free, clouds 10–25 % across 4 models (HRRR run 00Z, 2 h old)")
    }

    @Test("missing inputs are listed, and a missing gating field caps the verdict")
    func missing() throws {
        let conditions = Self.response(clouds: Self.clearingLate) { fields in
            var gust = fields["wind_gust"]!
            gust = Self.field("km/h", gust.series.map {
                $0.model == "ecmwf" ? Self.series("ecmwf", [], status: .unavailable, reason: "no data here") : $0
            })
            fields["wind_gust"] = gust
            fields["smoke_column"] = nil
        }
        let readout = ShotReadout(try shot().verdict(conditions: conditions, config: .bundled(), now: Self.now))
        #expect(readout.missing.contains("Wind gusts: ECMWF — no data here"))
        #expect(readout.missing.contains { $0.hasPrefix("Smoke overhead") && $0.hasSuffix("not in the Worker response") })
        #expect(readout.flags.contains(.incompleteData))
        #expect(readout.level <= .marginal)
    }

    @Test("with no conditions at all the clouds are unavailable, never clear")
    func noConditions() throws {
        let shot = try shot()
        let readout = ShotReadout(try shot.verdict(conditions: nil, config: .bundled(), now: Self.now))
        #expect(readout.clouds?.band == nil)
        #expect(ShotText.clouds(readout.clouds) == "clouds unavailable")
        #expect(ShotText.headline(shot, readout: readout, clock: ShotText.clock24(Self.denver)).hasSuffix("clouds unavailable"))
        #expect(readout.flags.contains(.incompleteData))
        #expect(readout.level <= .marginal)
    }

    @Test("no usable window is no-go on astronomy alone")
    func noWindow() throws {
        let shot = try ShotWindow.compute(
            observer(38.374031, -109.965416), evening: ISO.date("2026-05-07T03:00:00Z"), horizon: .flat(60),
            target: .galacticCore)
        let verdict = try shot.verdict(conditions: Self.response(clouds: Self.clearingLate), config: .bundled(), now: Self.now)
        #expect(verdict.level == .noGo)
        #expect(verdict.factor("moon_free_minutes")?.value == 0)
    }

    static let ageCases: [(TimeInterval, String)] = [
        (2400, "40 min old"), (9180, "2 h 33 min old"), (30, "just now"), (259_200, "3 d old"),
    ]

    @Test("age wording", arguments: ageCases)
    func ages(_ seconds: TimeInterval, _ text: String) {
        #expect(ShotText.age(seconds) == text)
    }

    @Test func cloudWording() {
        let one = ShotReadout.Spread(
            key: "cloud_cover_total", label: "Cloud", unit: "%", band: 12...12, usableModels: 3, totalModels: 4,
            reference: nil)
        #expect(ShotText.clouds(one) == "clouds 12 % across 3 of 4 models")
        #expect(ShotText.runHour(WorkerJSON.parse("2026-09-26T20:00:00Z")!) == "20Z")
    }
}
