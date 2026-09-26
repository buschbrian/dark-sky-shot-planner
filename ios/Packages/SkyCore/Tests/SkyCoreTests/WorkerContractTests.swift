import Foundation
import Testing
@testable import SkyCore

/// `shared/golden/{conditions,space-weather}-response.json` are real Worker
/// output, written offline from its recorded fixtures by
/// `worker/test/golden-response.test.ts`. Decoding them here is the contract.
@Suite("Worker response contract")
struct WorkerContractTests {
    static func conditions() throws -> ConditionsResponse {
        try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
    }

    static func spaceWeather() throws -> SpaceWeatherResponse {
        try SpaceWeatherResponse.decode(Repo.data("shared/golden/space-weather-response.json"))
    }

    @Test("conditions: cell, window and every field decode")
    func conditionsDecode() throws {
        let r = try Self.conditions()
        #expect(r.cell == WorkerCell(lat: 38.35, lon: -109.95, roundingDeg: 0.05))
        #expect(r.window.startUTC == WorkerJSON.parse("2026-09-26T00:00:00Z"))
        #expect(r.window.endUTC == WorkerJSON.parse("2026-09-26T14:00:00Z"))
        for key in ["cloud_cover_total", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "temperature",
                    "dew_point", "wind_gust", "visibility", "aerosol_optical_depth", "pm2_5", "dust",
                    "smoke_column", "smoke_surface", "aqi_observed", "seeing", "transparency"] {
            #expect(r.fields[key] != nil, "missing \(key)")
        }
        #expect(!r.attribution.isEmpty)
    }

    @Test("every series carries source, model, model run, fetch time and status")
    func provenance() throws {
        let r = try Self.conditions()
        for (key, f) in r.fields {
            #expect(!f.source.isEmpty, "\(key)")
            for s in f.series {
                #expect(!s.model.isEmpty)
                if s.status == .ok {
                    #expect(s.fetchedUTC != nil, "\(key)/\(s.model)")
                    #expect(s.asOfUTC != nil, "\(key)/\(s.model)")
                }
            }
        }
        let cloud = try #require(r.fields["cloud_cover_total"])
        #expect(cloud.series.map(\.model) == ["hrrr", "gfs", "icon", "ecmwf"])
        #expect(cloud.series.allSatisfy { $0.modelRunUTC != nil && $0.values.count == 15 })
        let hrrr = cloud.series[0]
        #expect(hrrr.modelRunUTC == WorkerJSON.parse("2026-09-25T22:00:00Z"))
        #expect(hrrr.asOfUTC == hrrr.modelRunUTC)
    }

    @Test("unavailable series decode with their reason and no values, never zeros")
    func unavailable() throws {
        let vis = try #require(try Self.conditions().fields["visibility"])
        let icon = try #require(vis.series.first { $0.model == "icon" })
        #expect(icon.status == .unavailable)
        #expect(icon.reason == "model does not publish this variable here")
        #expect(icon.values.isEmpty)
    }

    @Test("refresh hints: next run per series and the soonest for the response")
    func refreshHints() throws {
        let r = try Self.conditions()
        let hrrrNext = WorkerJSON.parse("2026-09-26T00:45:21Z")
        #expect(r.nextUpdateExpectedUTC == hrrrNext)
        let cloud = try #require(r.fields["cloud_cover_total"])
        #expect(cloud.series[0].nextRunExpectedUTC == hrrrNext)
        for s in cloud.series {
            let run = try #require(s.modelRunUTC)
            let next = try #require(s.nextRunExpectedUTC, "\(s.model)")
            #expect(next > run, "\(s.model)")
        }
        let smoke = try #require(r.fields["smoke_column"])
        #expect(smoke.series[0].nextRunExpectedUTC == WorkerJSON.parse("2026-09-26T04:23:01Z"))
        // 7Timer! publishes no schedule.
        #expect(r.fields["seeing"]?.series[0].nextRunExpectedUTC == nil)
    }

    @Test("15-minute HRRR series sit beside the hourly ones, never inside them")
    func fifteenMinute() throws {
        let r = try Self.conditions()
        for key in ["temperature", "dew_point", "wind_speed", "wind_gust", "visibility"] {
            let f = try #require(r.fields[key])
            let near = try #require(f.series15Min?.first, "\(key)")
            #expect(near.model == "hrrr")
            #expect(near.resolutionMinutes == 15)
            #expect(near.values.count == 57)
            #expect(near.values[1].t.timeIntervalSince(near.values[0].t) == 15 * 60)
            #expect(f.series.map(\.model) == ["hrrr", "gfs", "icon", "ecmwf"])
            #expect(f.series.allSatisfy { $0.resolutionMinutes == nil })
        }
        #expect(r.fields["cloud_cover_total"]?.series15Min == nil)
    }

    @Test("source extras: AirNow observations, smoke calibration, 7Timer terms")
    func extras() throws {
        let r = try Self.conditions()
        let aqi = try #require(r.fields["aqi_observed"])
        #expect(aqi.preliminary == true)
        #expect(aqi.series.isEmpty)
        let obs = try #require(aqi.observations)
        #expect(obs.map(\.parameter).sorted() == ["OZONE", "PM2.5"])
        #expect(obs.allSatisfy { $0.observedUTC == WorkerJSON.parse("2026-09-25T23:00:00Z") })
        let smoke = try #require(r.fields["smoke_column"])
        #expect(smoke.unit == "mg/m²")
        #expect(smoke.calibrated == true)
        #expect(smoke.series[0].modelRunUTC == WorkerJSON.parse("2026-09-25T03:00:00Z"))
        let transparency = try #require(r.fields["transparency"])
        #expect(transparency.optional == true)
        #expect(transparency.terms == "non-commercial use only")
        #expect(r.fields["aerosol_optical_depth"]?.resolutionNote != nil)
    }

    @Test("round-trips through the snapshot encoder unchanged")
    func roundTrip() throws {
        let r = try Self.conditions()
        #expect(try ConditionsResponse.decode(WorkerJSON.encoder().encode(r)) == r)
        let sw = try Self.spaceWeather()
        #expect(try SpaceWeatherResponse.decode(WorkerJSON.encoder().encode(sw)) == sw)
    }

    @Test("null values stay nil through a round trip")
    func nullValues() throws {
        let json = #"{"t":"2026-09-26T00:00:00Z","v":null}"#
        let p = try WorkerJSON.decoder().decode(WorkerPoint.self, from: Data(json.utf8))
        #expect(p.v == nil)
        let again = try WorkerJSON.decoder().decode(WorkerPoint.self, from: WorkerJSON.encoder().encode(p))
        #expect(again.v == nil)
        #expect(String(decoding: try WorkerJSON.encoder().encode(p), as: UTF8.self).contains("\"v\":null"))
    }

    @Test("an unknown status reads as unavailable, never ok")
    func unknownStatus() throws {
        let s = try JSONDecoder().decode([WorkerStatus].self, from: Data(#"["ok","unavailable","degraded"]"#.utf8))
        #expect(s == [.ok, .unavailable, .unavailable])
    }

    @Test("fractional-second timestamps are accepted")
    func fractional() {
        #expect(WorkerJSON.parse("2026-09-26T00:00:00.500Z") == WorkerJSON.parse("2026-09-26T00:00:00Z")!.addingTimeInterval(0.5))
        #expect(WorkerJSON.parse("yesterday") == nil)
    }

    @Test("space weather: Kp blocks and the aurora summary decode")
    func spaceWeatherDecode() throws {
        let sw = try Self.spaceWeather()
        #expect(sw.kpObserved.status == .ok)
        #expect(!sw.kpObserved.values.isEmpty)
        #expect(sw.kpForecast.values.allSatisfy { $0.kind != "observed" })
        #expect(sw.kpForecast.values.contains { $0.kind == "predicted" })
        #expect(sw.aurora.status == .ok)
        let near = try #require(sw.aurora.nearCell)
        #expect(near.lat == 38.35 && near.lon == -109.95)
        #expect(near.probabilityPct == 0)
        #expect(sw.aurora.forecastTimeUTC == WorkerJSON.parse("2026-09-26T00:26:00Z"))
    }
}
