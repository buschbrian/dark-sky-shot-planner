import Foundation
import Testing
@testable import SkyCore

/// PLAN.md §Verdict, rule by rule, against the bundled thresholds. No
/// threshold value is restated here: cases pick values far from the edges or
/// derive them from the config.
@Suite("Verdict")
struct VerdictTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        var night: NightReport = Sky.night()
        let edit: @Sendable (inout [String: WorkerField]) -> Void
        let level: VerdictLevel
        let limiting: String
        let cause: Verdict.Cause
        var flags: Set<VerdictFlag> = []
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "all good: go, limited by the factor nearest its edge",
             edit: { _ in }, level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "worst gating factor wins: AOD 0.41 is a no-go",
             edit: { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.41)) },
             level: .noGo, limiting: "aerosol_optical_depth", cause: .rating),
        Case(name: "marginal factor gives marginal",
             edit: { $0["smoke_column"] = Sky.field("mg/m²", "RAP", [Sky.series("rap_smoke", Sky.flat(25))]) },
             level: .marginal, limiting: "smoke_column", cause: .rating),
        Case(name: "cloud mean over the window",
             edit: { $0["cloud_cover_total"] = Sky.models("%", 30) },
             level: .marginal, limiting: "cloud_cover_total", cause: .rating),
        Case(name: "one bad hour trips the worst-hour factor, not the mean",
             edit: { f in
                 var v = Sky.flat(5); v[5] = 80
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, v) })
             },
             level: .noGo, limiting: "cloud_cover_max_hour", cause: .rating),
        Case(name: "hours outside the moon-free window are ignored",
             edit: { f in
                 let v: [Double?] = (0..<15).map { (3...9).contains($0) ? 5 : 100 }
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, v) })
             },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "the samples bracketing the window edges count",
             night: Sky.night([(3.5, 8.5)]),
             edit: { f in
                 var v = Sky.flat(5); v[3] = 100
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, v) })
             },
             level: .noGo, limiting: "cloud_cover_max_hour", cause: .rating),
        Case(name: "every moon-free window is evaluated",
             night: Sky.night([(3, 5), (7, 9)]),
             edit: { f in
                 var v = Sky.flat(5); v[8] = 100
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, v) })
             },
             level: .noGo, limiting: "cloud_cover_max_hour", cause: .rating),
        Case(name: "one cloudy model among clear ones: worst model, not the average",
             edit: { f in
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", [
                     Sky.series("hrrr", Sky.flat(90)), Sky.series("gfs", Sky.flat(5)),
                     Sky.series("icon", Sky.flat(5)), Sky.series("ecmwf", Sky.flat(5)),
                 ])
             },
             level: .noGo, limiting: "cloud_cover_total", cause: .rating),
        Case(name: "one model down: rated on the others",
             edit: { f in
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", [
                     Sky.series("hrrr", [], fetched: nil, status: .unavailable, reason: "HTTP 500"),
                     Sky.series("gfs", Sky.flat(5)), Sky.series("icon", Sky.flat(5)), Sky.series("ecmwf", Sky.flat(5)),
                 ])
             },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "unavailable gating factor: at best marginal, incomplete data",
             edit: { $0["smoke_column"] = nil },
             level: .marginal, limiting: "smoke_column", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "7Timer down: transparency is advisory, so the verdict is not capped",
             edit: { f in
                 f["transparency"] = Sky.field("index 1–8 (1 best)", "7Timer! ASTRO", [
                     Sky.series("7timer_astro", [], run: nil, fetched: nil, status: .unavailable, reason: "disabled by configuration"),
                 ])
             },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "gating field missing from the response",
             edit: { $0["wind_gust"] = nil },
             level: .marginal, limiting: "wind_gust", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "unavailable does not hide a poor factor",
             edit: { $0["wind_gust"] = nil; $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.5)) },
             level: .noGo, limiting: "aerosol_optical_depth", cause: .rating, flags: [.incompleteData]),
        Case(name: "unavailable plus marginal names the rated factor",
             edit: { $0["wind_gust"] = nil; $0["cloud_cover_total"] = Sky.models("%", 30) },
             level: .marginal, limiting: "cloud_cover_total", cause: .rating, flags: [.incompleteData]),
        Case(name: "a null inside the window is missing, never good",
             edit: { f in
                 var v = Sky.flat(5); v[5] = nil
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, v) })
             },
             level: .marginal, limiting: "cloud_cover_max_hour", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "a series that stops before the window ends is unavailable",
             edit: { $0["cloud_cover_total"] = Sky.field("%", "Open-Meteo", Sky.cloudModels.map { Sky.series($0, Sky.flat(5, count: 7)) }) },
             level: .marginal, limiting: "cloud_cover_max_hour", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "the Worker's last good copy is shown, not rated",
             edit: { f in
                 f["aerosol_optical_depth"] = Sky.field("", Sky.aqSource, [
                     Sky.series("cams_global", Sky.flat(0.05), fetched: nil, status: .unavailable, reason: "HTTP 502", lastGood: Sky.at(-5)),
                 ])
             },
             level: .marginal, limiting: "aerosol_optical_depth", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "unit mismatch is unavailable, not converted",
             edit: { $0["wind_gust"] = Sky.models("m/s", 3) },
             level: .marginal, limiting: "wind_gust", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "data without a timestamp cannot be aged, so it is unavailable",
             edit: { $0["smoke_column"] = Sky.field("mg/m²", "RAP", [Sky.series("rap_smoke", Sky.flat(1), run: nil, fetched: nil)]) },
             level: .marginal, limiting: "smoke_column", cause: .incompleteData, flags: [.incompleteData]),
        Case(name: "stale gating data caps at marginal",
             edit: { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.05), run: Sky.at(-24 * 10)) },
             level: .marginal, limiting: "aerosol_optical_depth", cause: .staleData, flags: [.staleData]),
        Case(name: "stale never raises a poor rating",
             edit: { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.5), run: Sky.at(-24 * 10)) },
             level: .noGo, limiting: "aerosol_optical_depth", cause: .rating, flags: [.staleData]),
        Case(name: "one stale model makes the factor stale",
             edit: { f in
                 f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", [
                     Sky.series("hrrr", Sky.flat(5)), Sky.series("gfs", Sky.flat(5)),
                     Sky.series("icon", Sky.flat(5)), Sky.series("ecmwf", Sky.flat(5), run: Sky.at(-24 * 10)),
                 ])
             },
             level: .marginal, limiting: "cloud_cover_max_hour", cause: .staleData, flags: [.staleData]),
        Case(name: "stale advisory data does not cap",
             edit: { $0["pm2_5"] = Sky.cams("µg/m³", Sky.flat(3), run: Sky.at(-24 * 10)) },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "advisories never gate: dew, PM2.5 and observed AQI all poor",
             edit: { f in
                 f["dew_point"] = Sky.models("°C", 9.9)
                 f["pm2_5"] = Sky.cams("µg/m³", Sky.flat(300))
                 f["aqi_observed"] = Sky.aqi([Sky.observation("PM2.5", 400)])
             },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "missing advisories are not incomplete data",
             edit: { $0["pm2_5"] = nil; $0["aqi_observed"] = nil; $0["temperature"] = nil; $0["seeing"] = nil },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "null thresholds (dust) are shown, never rated",
             edit: { $0["dust"] = Sky.cams("µg/m³", Sky.flat(5000)) },
             level: .go, limiting: "smoke_column", cause: .rating),
        Case(name: "short moon-free darkness is a no-go",
             night: Sky.night([(3, 3.5)]),
             edit: { _ in }, level: .noGo, limiting: "moon_free_minutes", cause: .rating),
        Case(name: "no moon-free darkness at all is a no-go",
             night: Sky.night([]),
             edit: { _ in }, level: .noGo, limiting: "moon_free_minutes", cause: .rating, flags: [.incompleteData]),
    ]

    @Test("rules", arguments: cases)
    func rule(_ c: Case) throws {
        let v = try Sky.evaluate(night: c.night, conditions: Sky.response(c.edit))
        #expect(v.level == c.level)
        #expect(v.limiting.key == c.limiting)
        #expect(v.cause == c.cause)
        #expect(v.flags == c.flags)
        #expect(v.limiting.gatesVerdict)
    }

    @Test("no conditions at all (Worker down, no snapshot): marginal, incomplete data")
    func noConditions() throws {
        let v = try Sky.evaluate(conditions: nil)
        #expect(v.level == .marginal)
        #expect(v.cause == .incompleteData)
        #expect(v.flags == [.incompleteData])
        #expect(v.limiting.isUnavailable)
        #expect(v.factor("moon_free_minutes")?.rating == .good)
        #expect(v.factors.filter { $0.key != "moon_free_minutes" && $0.key != "gc_max_altitude" }.allSatisfy { $0.isUnavailable })
    }

    @Test("the limiting factor carries its value, source, model and age")
    func limitingProvenance() throws {
        let v = try Sky.evaluate(conditions: Sky.response { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.41)) })
        #expect(v.limiting.value == 0.41)
        let p = try #require(v.limiting.provenance)
        #expect(p.source == Sky.aqSource)
        #expect(p.model == "cams_global")
        #expect(p.modelRunUTC == Sky.at(-2))
        #expect(p.fetchedUTC == Sky.at(0.8))
        #expect(p.age == Sky.now.timeIntervalSince(Sky.at(-2)))
        #expect(abs(try #require(p.age) - 3 * 3600) < 0.001)
        #expect(p.freshness == .fresh)
    }

    @Test("model disagreement is kept as a band with the worst model named")
    func modelBand() throws {
        let v = try Sky.evaluate(conditions: Sky.response { f in
            f["cloud_cover_total"] = Sky.field("%", "Open-Meteo", [
                Sky.series("hrrr", Sky.flat(90)), Sky.series("gfs", Sky.flat(5)),
                Sky.series("icon", Sky.flat(30)), Sky.series("ecmwf", [], status: .unavailable, reason: "HTTP 500"),
            ])
        })
        let cloud = try #require(v.factor("cloud_cover_total"))
        #expect(cloud.value == 90)
        #expect(cloud.provenance?.model == "hrrr")
        #expect(cloud.band == 5...90)
        #expect(cloud.readings.map(\.model) == ["hrrr", "gfs", "icon", "ecmwf"])
        #expect(cloud.readings.map(\.value) == [90, 5, 30, nil])
        #expect(cloud.unavailableModels == ["ecmwf"])
        #expect(cloud.rating == .poor)
    }

    @Test("the last good copy keeps its value for display")
    func lastGood() throws {
        let v = try Sky.evaluate(conditions: Sky.response { f in
            f["aerosol_optical_depth"] = Sky.field("", Sky.aqSource, [
                Sky.series("cams_global", Sky.flat(0.05), fetched: nil, status: .unavailable, reason: "HTTP 502", lastGood: Sky.at(-5)),
            ])
        })
        let aod = try #require(v.factor("aerosol_optical_depth"))
        #expect(aod.isUnavailable && aod.value == nil)
        #expect(aod.readings[0].isLastGood)
        #expect(aod.readings[0].value == 0.05)
        #expect(aod.readings[0].provenance.fetchedUTC == Sky.at(-5))
    }

    @Test("dew-point spread is temperature minus dew point, worst hour, per model")
    func dewSpread() throws {
        let v = try Sky.evaluate(conditions: Sky.response { f in
            var dew = Sky.flat(0); dew[6] = 9
            f["dew_point"] = Sky.field("°C", "Open-Meteo", [Sky.series("hrrr", dew), Sky.series("gfs", Sky.flat(0))])
        })
        let d = try #require(v.factor("dew_point_spread"))
        #expect(d.value == 1)
        #expect(d.provenance?.model == "hrrr")
        #expect(d.readings.map(\.model) == ["hrrr", "gfs", "icon", "ecmwf"])
        #expect(d.unavailableModels == ["icon", "ecmwf"])
        #expect(!d.gatesVerdict)
        #expect(v.advisories.map(\.key).contains("dew_point_spread") == (d.rating != .good))
    }

    @Test("observed AQI uses PM2.5 rows only; ozone is ignored")
    func observedAQI() throws {
        let both = try Sky.evaluate(conditions: Sky.response {
            $0["aqi_observed"] = Sky.aqi([Sky.observation("OZONE", 300), Sky.observation("PM2.5", 40), Sky.observation("PM2.5", 30)])
        })
        #expect(both.factor("aqi_pm25_observed")?.value == 40)
        let ozoneOnly = try Sky.evaluate(conditions: Sky.response { $0["aqi_observed"] = Sky.aqi([Sky.observation("OZONE", 300)]) })
        let aqi = try #require(ozoneOnly.factor("aqi_pm25_observed"))
        #expect(aqi.isUnavailable)
        #expect(ozoneOnly.level == .go && ozoneOnly.flags.isEmpty)
    }

    @Test("advisories list the non-gating factors rated below good")
    func advisories() throws {
        let v = try Sky.evaluate(conditions: Sky.response { f in
            f["pm2_5"] = Sky.cams("µg/m³", Sky.flat(300))
            f["aqi_observed"] = Sky.aqi([Sky.observation("PM2.5", 400)])
            f["dew_point"] = Sky.models("°C", 9.9)
        })
        #expect(Set(v.advisories.map(\.key)) == ["pm2_5", "aqi_pm25_observed", "dew_point_spread"])
        #expect(v.advisories.allSatisfy { $0.rating == .poor })
    }

    @Test("dust is shown with value and source, never rated")
    func shownOnly() throws {
        let dust = try #require(try Sky.evaluate().factor("dust"))
        #expect(dust.status == .shownOnly)
        #expect(dust.value == 2)
        #expect(dust.provenance?.source == Sky.aqSource)
        #expect(dust.rating == nil)
    }

    // MARK: Aurora (M5's AuroraRule is the one rule; the verdict only carries its flag)

    static let outlooks: [AuroraOutlook] = [
        .possible(kp: 8, visibleKp: 7.67, basis: .forecastInWindow),
        .possible(kp: 8, visibleKp: 7.67, basis: .observedNow),
        .notExpected(maxKp: 3, visibleKp: 7.67),
        .unavailable(.noKpData),
        .unavailable(.kpDoesNotCoverNight),
        .outOfRange(geomagneticLatDeg: 30),
    ]

    @Test("aurora adds a flag and never changes the level",
          arguments: zip([0.05, 0.2, 0.5], [VerdictLevel.go, .marginal, .noGo]))
    func auroraFlag(_ aod: Double, _ level: VerdictLevel) throws {
        let conditions = Sky.response { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(aod)) }
        let without = try Sky.evaluate(conditions: conditions)
        for outlook in Self.outlooks {
            let signal = AuroraSignal(outlook: outlook, source: "SWPC", asOfUTC: Sky.at(0.5))
            let with = try Sky.evaluate(conditions: conditions, aurora: signal)
            #expect(with.level == level)
            #expect(with.level == without.level)
            #expect(with.limiting.key == without.limiting.key)
            #expect(with.cause == without.cause)
            #expect(with.flags.contains(.auroraPossible) == outlook.isPossible)
            #expect(with.flags.subtracting([.auroraPossible]) == without.flags)
            #expect(with.aurora?.source == "SWPC")
            #expect(with.aurora?.age(at: Sky.now) == Sky.now.timeIntervalSince(Sky.at(0.5)))
            #expect(without.withAurora(signal) == with)
        }
    }

    @Test("withAurora swaps only the flag")
    func withAurora() throws {
        let possible = AuroraSignal(outlook: Self.outlooks[0], source: "SWPC", asOfUTC: Sky.now)
        let v = try Sky.evaluate(aurora: possible)
        #expect(v.flags == [.auroraPossible])
        let cleared = v.withAurora(nil)
        #expect(cleared.flags.isEmpty && cleared.aurora == nil)
        #expect(cleared.level == v.level && cleared.limiting == v.limiting && cleared.factors == v.factors)
    }

    @Test("missing space weather is no flag and not incomplete data")
    func auroraMissing() throws {
        let v = try Sky.evaluate(aurora: nil)
        #expect(v.level == .go && v.flags.isEmpty)
        let none = AuroraSignal(
            spaceWeather: nil, rule: try AuroraRule.bundled(), observer: try observer(38.35, -109.95),
            darkness: Sky.night().darkness, now: Sky.now, isNextDarkWindow: true)
        #expect(none.outlook == .unavailable(.noKpData))
        #expect(none.asOfUTC == nil)
        #expect(try Sky.evaluate(aurora: none).flags.isEmpty)
    }

    @Test("the recorded space-weather response runs through AuroraRule")
    func auroraFromSpaceWeather() throws {
        let sw = try WorkerContractTests.spaceWeather()
        let rule = try AuroraRule.bundled()
        let obs = try observer(38.35, -109.95)
        let darkness = Sky.night().darkness
        #expect(sw.kpReadings.count == sw.kpObserved.values.count + sw.kpForecast.values.count)
        #expect(sw.kpReadings.filter { $0.kind == .predicted }.count == sw.kpForecast.values.filter { $0.kind == "predicted" }.count)
        let signal = AuroraSignal(spaceWeather: sw, rule: rule, observer: obs, darkness: darkness, now: sw.generatedUTC, isNextDarkWindow: true)
        #expect(signal.outlook == rule.outlook(obs, darkness: darkness, readings: sw.kpReadings, now: sw.generatedUTC, isNextDarkWindow: true))
        #expect(!signal.isPossible)
        #expect(signal.source == "NOAA Space Weather Prediction Center")
        #expect(signal.asOfUTC == WorkerJSON.parse("2026-09-25T23:39:36Z"))
    }

    @Test("a storm in the Worker's last-good copy never raises the flag")
    func auroraLastGood() throws {
        let sw = try WorkerContractTests.spaceWeather()
        let rule = try AuroraRule.bundled()
        let obs = try observer(38.35, -109.95)
        let darkness = try #require(Sky.night().darkness)
        let storm = [SpaceWeatherResponse.KpPoint(t: darkness.start, v: 9, kind: "predicted", noaaScale: "G5")]
        func response(_ status: WorkerStatus) -> SpaceWeatherResponse {
            let f = sw.kpForecast
            let block = SpaceWeatherResponse.KpBlock(
                source: f.source, unit: f.unit, status: status, reason: status == .ok ? nil : "HTTP 503",
                fetchedUTC: status == .ok ? f.fetchedUTC : nil, lastGoodUTC: status == .ok ? nil : f.fetchedUTC,
                values: storm)
            return SpaceWeatherResponse(generatedUTC: sw.generatedUTC, cache: sw.cache, kpObserved: sw.kpObserved, kpForecast: block, aurora: sw.aurora)
        }
        func signal(_ status: WorkerStatus) -> AuroraSignal {
            AuroraSignal(spaceWeather: response(status), rule: rule, observer: obs, darkness: darkness, now: Sky.now, isNextDarkWindow: false)
        }
        #expect(signal(.ok).isPossible)
        #expect(!signal(.unavailable).isPossible)
    }

    // MARK: Week outlook (M5) driven by this verdict

    @Test("WeekOutlook.build rates each night with this verdict; aurora stays out of it")
    func weekOutlookWiring() throws {
        let conditions = try WorkerContractTests.conditions()
        let now = conditions.generatedUTC
        let obs = try observer(conditions.cell.lat, conditions.cell.lon)
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        let first = try #require(NightDate(iso: "2026-09-25"))
        let sw = try WorkerContractTests.spaceWeather()
        let rater = Verdict.weekRater(conditions: conditions, config: Sky.config, now: now)
        func build(_ kp: [KpReading]?) throws -> [WeekRow<Result<Verdict, Verdict.EvaluationError>>] {
            try WeekOutlook.build(
                observer: obs, timeZone: denver, now: now, first: first, count: 3,
                clouds: [], kp: kp, auroraRule: AuroraRule.bundled(), verdict: rater)
        }
        let rows = try build(sw.kpReadings)
        #expect(rows.count == 3)
        #expect(rows.map(\.verdict) == (try build(nil)).map(\.verdict))
        for row in rows {
            let direct = try Verdict.evaluate(row.night, conditions: conditions, config: Sky.config, now: now)
            #expect(try row.verdict.get() == direct)
            #expect(try direct == Verdict.evaluate(night: row.night.report, conditions: conditions, config: Sky.config, now: now))
            let shown = row.verdict.map {
                $0.withAurora(AuroraSignal(outlook: row.aurora, source: sw.kpForecast.source, asOfUTC: sw.kpAsOfUTC))
            }
            #expect(try shown.get().level == direct.level)
            #expect(try shown.get().flags.contains(.auroraPossible) == row.aurora.isPossible)
        }
    }

    // MARK: Driven by the thresholds file

    @Test("bundled config: advisories don't gate, dust has null edges, rule and window are supported")
    func bundledConfig() throws {
        let t = try ConditionsThresholds.bundled()
        #expect(t == Sky.config.thresholds)
        for key in ["pm2_5", "aqi_pm25_observed", "dew_point_spread"] {
            #expect(t.factors[key]?.gatesVerdict == false, "\(key)")
        }
        #expect(t.factors["dust"]?.isRatable == false)
        #expect(Set(t.factors.keys).isSubset(of: Set(FactorAssessor.sources.keys)), "a factor SkyCore cannot compute")
    }

    @Test("every factor rates at, between and past its own edges", arguments: try! ConditionsThresholds.bundled().factors.sorted { $0.key < $1.key }.map(\.value))
    func ratingEdges(_ f: ConditionsThresholds.Factor) {
        guard let good = f.good, let marginal = f.marginal else {
            #expect(f.rate(1) == nil)
            return
        }
        let past = marginal + (marginal - good) * 0.01
        let beyondGood = good - (marginal - good)
        #expect(f.rate(good) == .good)
        #expect(f.rate(beyondGood) == .good)
        #expect(f.rate((good + marginal) / 2) == .marginal)
        #expect(f.rate(marginal) == .marginal)
        #expect(f.rate(past) == .poor)
        #expect(f.rate(.nan) == nil)
        #expect(f.severity(good) == 0)
        #expect(f.severity(marginal) == 1)
    }

    @Test("changing the config, not the code, changes the verdict")
    func configDriven() throws {
        let strict = try Sky.thresholds { j in Sky.editFactor(&j, "cloud_cover_total") { $0["good"] = 1; $0["marginal"] = 2 } }
        let config = VerdictConfig(thresholds: strict, freshness: Sky.config.freshness)
        let v = try Sky.evaluate(config: config)
        #expect(v.level == .noGo && v.limiting.key == "cloud_cover_total")

        let gating7Timer = try Sky.thresholds { j in Sky.editFactor(&j, "transparency") { $0["gates_verdict"] = true } }
        let noTransparency = Sky.response { $0["transparency"] = nil }
        #expect(try Sky.evaluate(conditions: noTransparency).level == .go)
        #expect(try Sky.evaluate(conditions: noTransparency, config: VerdictConfig(thresholds: gating7Timer, freshness: Sky.config.freshness)).level == .marginal)
    }

    @Test("freshness windows come from config too")
    func freshnessDriven() throws {
        let aod = Sky.response { $0["aerosol_optical_depth"] = Sky.cams("", Sky.flat(0.05), run: Sky.at(-24 * 10)) }
        #expect(try Sky.evaluate(conditions: aod).level == .marginal)
        let lenient = VerdictConfig(
            thresholds: Sky.config.thresholds,
            freshness: FreshnessWindow(layerId: "test", freshMaxDays: 30, agingMaxDays: 60, staleMaxDays: 90))
        #expect(try Sky.evaluate(conditions: aod, config: lenient).level == .go)
    }

    @Test("a gating factor SkyCore has no source for is unavailable, never skipped")
    func unknownFactor() throws {
        let t = try Sky.thresholds { j in
            Sky.editFactor(&j, "sky_quality_meter") {
                $0 = ["label": "SQM", "unit": "mag/arcsec²", "better": "higher", "good": 21.5, "marginal": 21, "gates_verdict": true]
            }
        }
        let v = try Sky.evaluate(config: VerdictConfig(thresholds: t, freshness: Sky.config.freshness))
        #expect(v.level == .marginal && v.cause == .incompleteData && v.limiting.key == "sky_quality_meter")
    }

    @Test("a gating factor with null edges cannot rate the night: incomplete")
    func gatingWithNullEdges() throws {
        let t = try Sky.thresholds { j in Sky.editFactor(&j, "dust") { $0["gates_verdict"] = true } }
        let v = try Sky.evaluate(config: VerdictConfig(thresholds: t, freshness: Sky.config.freshness))
        #expect(v.level == .marginal && v.limiting.key == "dust" && v.flags == [.incompleteData])
    }

    @Test("Galactic Center altitude gates only when the core is the target")
    func galacticCoreTarget() throws {
        let low = Sky.night(gc: 5)
        #expect(try Sky.evaluate(night: low).level == .go)
        let v = try Sky.evaluate(night: low, galacticCoreIsTarget: true)
        #expect(v.level == .noGo && v.limiting.key == "gc_max_altitude")
        #expect(v.limiting.provenance?.source == FactorAssessor.onDeviceSource)
    }

    @Test("unsupported rule or window in the config is refused")
    func unsupportedRule() {
        #expect(throws: ConditionsThresholds.ConfigError.unsupportedRule("weighted_score")) {
            try Sky.thresholds { $0["verdict_rule"] = "weighted_score" }
        }
        #expect(throws: ConditionsThresholds.ConfigError.unsupportedWindow("astronomical_darkness")) {
            try Sky.thresholds { $0["window"] = "astronomical_darkness" }
        }
    }

    @Test("a config with no gating factor is refused")
    func noGating() throws {
        let t = try Sky.thresholds { j in
            var factors = j["factors"] as! [String: [String: Any]]
            for k in factors.keys { factors[k]?["gates_verdict"] = false }
            j["factors"] = factors
        }
        #expect(throws: Verdict.EvaluationError.noGatingFactors) {
            try Sky.evaluate(config: VerdictConfig(thresholds: t, freshness: Sky.config.freshness))
        }
    }

    // MARK: End to end on real Worker output

    @Test("recorded Worker response over a 04Z–10Z window")
    func goldenEndToEnd() throws {
        let r = try WorkerContractTests.conditions()
        let night = Sky.night([(4, 10)])
        let v = try Sky.evaluate(night: night, conditions: r, now: r.generatedUTC)
        #expect(v.level == .noGo)
        #expect(v.limiting.key == "cloud_cover_total")
        #expect(v.limiting.provenance?.model == "hrrr")
        #expect(abs(try #require(v.limiting.value) - 596.0 / 7) < 1e-9)
        #expect(v.flags.isEmpty)
        let cloud = try #require(v.factor("cloud_cover_total"))
        #expect(abs(try #require(cloud.band?.lowerBound) - 19) < 1e-9)
        #expect(v.factor("cloud_cover_max_hour")?.value == 100)
        #expect(v.factor("aqi_pm25_observed")?.value == 38)
        #expect(v.factor("transparency")?.value == 2)
        #expect(v.factor("aerosol_optical_depth")?.value == 0.08)
        #expect(v.factor("smoke_column")?.rating == .good)
        #expect(abs(try #require(v.factor("dew_point_spread")?.value) - 6.4) < 1e-9)
        #expect(v.factor("dew_point_spread")?.provenance?.model == "icon")
        #expect(v.factors.filter { $0.freshness != .unavailable }.allSatisfy { $0.freshness == .fresh })
        #expect(v.factors.allSatisfy { !$0.isUnavailable })
    }
}
