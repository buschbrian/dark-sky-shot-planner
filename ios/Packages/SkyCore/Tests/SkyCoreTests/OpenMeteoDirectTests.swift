import Foundation
import Testing
@testable import SkyCore

/// The direct fallback, driven by the Worker's own recorded Open-Meteo
/// fixtures (cell 38.35, −109.95; window 2026-09-26 00Z–14Z). The golden
/// Worker response was built from the same files, so the cloud series must match it.
@Suite struct OpenMeteoDirectTests {
    static let fixtures = "worker/test/fixtures"

    static func body(_ path: String) throws -> (status: Int, body: Data) {
        let obj = try JSONSerialization.jsonObject(with: Repo.data("\(fixtures)/\(path)")) as! [String: Any]
        let status = obj["status"] as! Int
        let body = obj["body"]!
        let data = try (body as? String).map { Data($0.utf8) } ?? JSONSerialization.data(withJSONObject: body)
        return (status, data)
    }

    static func request() throws -> ConditionsRequest {
        let window = DateInterval(start: try ISO.date("2026-09-26T00:00:00Z"), end: try ISO.date("2026-09-26T14:00:00Z"))
        return try ConditionsRequest.make(
            latitude: 38.3712, longitude: -109.9588, window: window, now: try ISO.date("2026-09-25T23:39:36Z")).get()
    }

    static func recordedFetches() throws -> [OpenMeteoDirect.ModelFetch] {
        try OpenMeteoDirect.models.map { m in
            OpenMeteoDirect.ModelFetch(
                model: m, forecast: try body("recorded/open-meteo-forecast-\(m.upstream).json"),
                meta: try body("recorded/open-meteo-meta-\(m.meta).json").body)
        }
    }

    static let fetched = WorkerJSON.parse("2026-09-25T23:39:36Z")!

    @Test func requestURLsMatchTheWorkersForTheSameCell() throws {
        let req = try Self.request()
        let hrrr = OpenMeteoDirect.models[0]
        #expect(OpenMeteoDirect.forecastURL(hrrr, req).absoluteString
            == "https://api.open-meteo.com/v1/forecast?latitude=38.35&longitude=-109.95&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high&models=ncep_hrrr_conus&timezone=GMT&timeformat=iso8601&start_date=2026-09-26&end_date=2026-09-26")
        #expect(OpenMeteoDirect.metaURL(OpenMeteoDirect.models[2]).absoluteString
            == "https://api.open-meteo.com/data/dwd_icon/static/meta.json")
    }

    @Test func modelListMatchesTheWorker() throws {
        let ts = String(decoding: try Repo.data("worker/src/sources/openmeteo.ts"), as: UTF8.self)
        for m in OpenMeteoDirect.models {
            #expect(ts.contains("{ id: \"\(m.id)\", upstream: \"\(m.upstream)\", meta: \"\(m.meta)\""), "\(m.id)")
        }
    }

    @Test func cloudSeriesMatchTheGoldenWorkerResponse() throws {
        let golden = try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
        let direct = OpenMeteoDirect.response(request: try Self.request(), fetches: try Self.recordedFetches(), fetchedUTC: Self.fetched)
        #expect(direct.cell == golden.cell)
        #expect(direct.window == golden.window)
        for name in ["cloud_cover_total", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high"] {
            let d = try #require(direct.fields[name])
            let g = try #require(golden.fields[name])
            #expect(d.status == .ok)
            #expect(d.unit == g.unit)
            #expect(d.source == OpenMeteoDirect.source)
            #expect(d.series.map(\.model) == g.series.map(\.model))
            for (ds, gs) in zip(d.series, g.series) {
                #expect(ds.values == gs.values, "\(name) \(ds.model)")
                #expect(ds.modelRunUTC == gs.modelRunUTC, "\(name) \(ds.model)")
                #expect(ds.values.count == 15)
            }
        }
        #expect(direct.isDirectFallback)
        #expect(!golden.isDirectFallback)

        // Snapshots saved before the review B-4 rewording still read as a fallback.
        let saved = try String(decoding: ConditionsSnapshot(response: direct, fetchedUTC: Self.fetched).encoded(), as: UTF8.self)
        let legacy = saved.replacingOccurrences(of: "the conditions service didn't answer", with: "Worker unreachable")
        #expect(legacy != saved)
        #expect(try ConditionsSnapshot.decode(Data(legacy.utf8)).response.isDirectFallback)
    }

    @Test func everyOtherWorkerFieldIsUnavailableNeverZero() throws {
        let golden = try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
        let direct = OpenMeteoDirect.response(request: try Self.request(), fetches: try Self.recordedFetches(), fetchedUTC: Self.fetched)
        #expect(Set(direct.fields.keys) == Set(golden.fields.keys))
        for (name, f) in direct.fields where !name.hasPrefix("cloud_cover") {
            #expect(f.status == .unavailable, "\(name)")
            #expect(f.series.isEmpty)
            #expect(f.reason == OpenMeteoDirect.otherFieldsReason)
            #expect(f.unit == golden.fields[name]!.unit, "\(name)")
        }
    }

    @Test func verdictOnTheFallbackIsCappedByIncompleteData() throws {
        let direct = OpenMeteoDirect.response(request: try Self.request(), fetches: try Self.recordedFetches(), fetchedUTC: Self.fetched)
        let night = Sky.night()
        let v = try Verdict.evaluate(night: night, conditions: direct, config: .bundled(), now: Sky.now)
        #expect(v.level <= .marginal)
        #expect(v.flags.contains(.incompleteData))
        #expect(v.factor("cloud_cover_total")?.isUnavailable == false)
        #expect(v.factor("wind_gust")?.isUnavailable == true)
        #expect(v.factor("aerosol_optical_depth")?.isUnavailable == true)
    }

    @Test func outsideDomainAndServerErrorsAreUnavailablePerModel() throws {
        let req = try Self.request()
        var fetches = try Self.recordedFetches()
        fetches[0] = .init(model: fetches[0].model, forecast: try Self.body("down/open-meteo-forecast-no-data.json"), meta: fetches[0].meta)
        fetches[1] = .init(model: fetches[1].model, forecast: try Self.body("down/open-meteo-forecast.json"), meta: nil)
        fetches[2] = .init(model: fetches[2].model, forecast: nil, forecastError: "offline", meta: nil)
        let r = OpenMeteoDirect.response(request: req, fetches: fetches, fetchedUTC: Self.fetched)
        let total = try #require(r.fields["cloud_cover_total"])
        #expect(total.status == .ok, "ECMWF still answered")
        #expect(total.series[0].status == .unavailable)
        #expect(total.series[0].reason == "cell is outside this model's domain")
        #expect(total.series[1].reason == "HTTP 502")
        #expect(total.series[2].reason == "offline")
        #expect(total.series[2].fetchedUTC == nil)
        #expect(total.series.allSatisfy { $0.status == .ok || $0.values.isEmpty })
        #expect(total.series[3].status == .ok)
    }

    @Test func nullHoursStayNil() throws {
        let req = try Self.request()
        let json = """
        {"hourly_units":{"time":"iso8601","cloud_cover":"%","cloud_cover_low":"%","cloud_cover_mid":"%","cloud_cover_high":"%"},
         "hourly":{"time":["2026-09-26T00:00","2026-09-26T01:00","2026-09-26T15:00"],
           "cloud_cover":[0,null,50],"cloud_cover_low":[null,null,null],"cloud_cover_mid":[1,2,3],"cloud_cover_high":[4,5,6]}}
        """
        let fetch = OpenMeteoDirect.ModelFetch(model: OpenMeteoDirect.models[0], forecast: (200, Data(json.utf8)), meta: nil)
        let r = OpenMeteoDirect.response(request: req, fetches: [fetch], fetchedUTC: Self.fetched)
        let total = try #require(r.fields["cloud_cover_total"]?.series.first)
        #expect(total.values.map(\.v) == [0, nil], "15Z is outside the window; the null hour stays nil")
        #expect(total.modelRunUTC == nil, "no meta.json: run unknown, age from the fetch")
        #expect(r.fields["cloud_cover_low"]?.series.first?.status == .unavailable)
    }

    @Test func fallbackKeepsTheWorkersLastGoodValuesShownButNotRated() throws {
        let golden = try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
        let direct = OpenMeteoDirect.response(request: try Self.request(), fetches: try Self.recordedFetches(), fetchedUTC: Self.fetched)
        let merged = OpenMeteoDirect.withLastGood(direct, from: golden)
        let wind = try #require(merged.fields["wind_gust"])
        #expect(wind.status == .unavailable)
        #expect(wind.series.map(\.values) == golden.fields["wind_gust"]!.series.map(\.values))
        #expect(wind.series.allSatisfy { $0.status == .unavailable && $0.fetchedUTC == nil && $0.lastGoodUTC != nil })
        #expect(merged.fields["cloud_cover_total"] == direct.fields["cloud_cover_total"], "fresh clouds win")
        #expect(merged.fields["visibility"]!.series.count == 2, "series with no values stay out")
        #expect(merged.isDirectFallback)

        let v = try Verdict.evaluate(night: Sky.night(), conditions: merged, config: .bundled(), now: Sky.now)
        #expect(v.factor("wind_gust")?.isUnavailable == true, "a last-good copy is never rated")
        #expect(v.factor("wind_gust")?.readings.first?.isLastGood == true)
        let row = try #require(StripRow.rows(from: merged).first { $0.kind == .wind })
        #expect(!row.points.isEmpty && row.unavailableReason == nil && row.source.hasSuffix("(last good copy)"))

        var otherCell = try Self.request()
        otherCell = try ConditionsRequest.make(latitude: 40, longitude: -111, window: otherCell.window, now: Self.fetched).get()
        let elsewhere = OpenMeteoDirect.response(request: otherCell, fetches: [], fetchedUTC: Self.fetched)
        #expect(OpenMeteoDirect.withLastGood(elsewhere, from: golden) == elsewhere, "never borrow another cell's data")
    }

    @Test func nothingReachedMeansUseTheCache() {
        let offline = OpenMeteoDirect.models.map { OpenMeteoDirect.ModelFetch(model: $0, forecast: nil, forecastError: "offline", meta: nil) }
        #expect(OpenMeteoDirect.nothingReached(offline))
    }

    @Test func snapshotRoundTripsThroughTheCacheEncoding() throws {
        let direct = OpenMeteoDirect.response(request: try Self.request(), fetches: try Self.recordedFetches(), fetchedUTC: Self.fetched)
        let snap = ConditionsSnapshot(response: direct, fetchedUTC: Self.fetched)
        #expect(try ConditionsSnapshot.decode(snap.encoded()) == snap)
    }
}

@Suite struct SnapshotSelectionTests {
    static func snapshot(lat: Double, lon: Double, start: Double, end: Double, fetched: Double) throws -> ConditionsSnapshot {
        let req = try ConditionsRequest.make(
            latitude: lat, longitude: lon,
            window: DateInterval(start: Sky.at(start), end: Sky.at(end)), now: Sky.at(0)).get()
        let r = OpenMeteoDirect.response(request: req, fetches: [], fetchedUTC: Sky.at(fetched))
        return ConditionsSnapshot(response: r, fetchedUTC: Sky.at(fetched))
    }

    @Test func newestOverlappingSnapshotForTheSameCellWins() throws {
        let cell = ConditionsCell(latitude: 38.36, longitude: -109.96)
        let all = [
            try Self.snapshot(lat: 38.35, lon: -109.95, start: 0, end: 18, fetched: -5),
            try Self.snapshot(lat: 38.35, lon: -109.95, start: 0, end: 18, fetched: -1),
            try Self.snapshot(lat: 38.40, lon: -109.95, start: 0, end: 18, fetched: 0),
            try Self.snapshot(lat: 38.35, lon: -109.95, start: 24, end: 42, fetched: 0),
        ]
        let best = ConditionsSnapshot.best(for: cell, window: DateInterval(start: Sky.at(2), end: Sky.at(16)), in: all)
        #expect(best?.fetchedUTC == Sky.at(-1))
        #expect(ConditionsSnapshot.best(for: cell, window: DateInterval(start: Sky.at(48), end: Sky.at(60)), in: all) == nil)
    }

    @Test func expiresAfterEightDays() throws {
        let old = try Self.snapshot(lat: 38.35, lon: -109.95, start: 0, end: 18, fetched: -24 * 9)
        let recent = try Self.snapshot(lat: 38.35, lon: -109.95, start: 0, end: 18, fetched: -24 * 7)
        #expect(ConditionsSnapshot.expired([old, recent], now: Sky.at(0)) == [old])
    }
}
