import Foundation
@testable import SkyCore

/// Synthetic Worker responses for verdict tests. Hourly samples from `t0`
/// (2026-09-26 00Z) to +14 h; "now" is +1 h; the default moon-free window is
/// 03Z–09Z. Every default value is good against the bundled thresholds, so a
/// case changes only what it tests.
enum Sky {
    static let t0 = WorkerJSON.parse("2026-09-26T00:00:00Z")!
    static let now = at(1)
    static let cloudModels = ["hrrr", "gfs", "icon", "ecmwf"]
    static let aqSource = "Open-Meteo Air Quality (CAMS Global; © ECMWF Copernicus)"

    static func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    static func night(_ windows: [(Double, Double)] = [(3, 9)], gc: Double? = 25) -> NightReport {
        let mf = windows.map { a, b in MoonFreeWindow(start: at(a), end: at(b), minutes: Int(((b - a) * 60).rounded())) }
        return NightReport(
            darkness: TimeWindow(start: at(2), end: at(10.5)), noAstronomicalDarkness: false,
            moonIllumFraction: 0.1, moonset: nil, moonrise: nil, moonFreeWindows: mf,
            moonFreeMinutes: mf.reduce(0) { $0 + $1.minutes },
            gc: GCVisibility(maxAltitudeDeg: windows.isEmpty ? nil : gc, maxAltitudeAt: nil, risesDuringDarkness: gc != nil))
    }

    static func flat(_ v: Double?, count: Int = 15) -> [Double?] { Array(repeating: v, count: count) }

    static func series(
        _ model: String, _ values: [Double?], step: Int = 1,
        run: Date? = at(-2), fetched: Date? = at(0.8),
        status: WorkerStatus = .ok, reason: String? = nil, lastGood: Date? = nil
    ) -> WorkerSeries {
        WorkerSeries(
            model: model, upstreamModel: nil, modelRunUTC: run, fetchedUTC: fetched, status: status,
            reason: reason, lastGoodUTC: lastGood,
            values: values.enumerated().map { i, v in WorkerPoint(t: at(Double(i * step)), v: v) })
    }

    static func field(
        _ unit: String, _ source: String, _ series: [WorkerSeries],
        status: WorkerStatus? = nil, reason: String? = nil, observations: [AirNowObservation]? = nil
    ) -> WorkerField {
        let ok = series.contains { $0.status == .ok }
        return WorkerField(
            unit: unit, source: source, status: status ?? (ok ? .ok : .unavailable),
            fetchedUTC: at(0.8), series: series, reason: reason, lastGoodUTC: nil,
            observations: observations, preliminary: nil, attribution: nil, description: nil,
            valueKind: nil, calibrated: nil, calibration: nil, resolutionNote: nil, terms: nil, optional: nil)
    }

    static func models(_ unit: String, _ v: Double) -> WorkerField {
        field(unit, "Open-Meteo", cloudModels.map { series($0, flat(v)) })
    }

    static func cams(_ unit: String, _ values: [Double?], run: Date? = at(-2)) -> WorkerField {
        field(unit, aqSource, [series("cams_global", values, run: run)])
    }

    static func sevenTimer(_ v: Double?) -> WorkerField {
        field("index 1–8 (1 best)", "7Timer! ASTRO", [series("7timer_astro", flat(v, count: 5), step: 3)])
    }

    static func observation(_ parameter: String, _ aqi: Double) -> AirNowObservation {
        AirNowObservation(
            parameter: parameter, aqi: aqi, category: "", categoryNumber: 1, reportingArea: nil,
            siteName: nil, reportingAgency: nil, observedLocal: "2026-09-25T18:00", localTimeZone: "MDT",
            observedUTC: at(0))
    }

    static func aqi(_ rows: [AirNowObservation]) -> WorkerField {
        field("AQI", "EPA AirNow", [], status: rows.isEmpty ? .unavailable : .ok, observations: rows)
    }

    static func goodFields() -> [String: WorkerField] {
        [
            "cloud_cover_total": models("%", 5),
            "temperature": models("°C", 10),
            "dew_point": models("°C", 0),
            "wind_gust": models("km/h", 10),
            "aerosol_optical_depth": cams("", flat(0.05)),
            "pm2_5": cams("µg/m³", flat(3)),
            "dust": cams("µg/m³", flat(2)),
            "smoke_column": field("mg/m²", "NOAA RAP-Smoke via NWS NDGD", [series("rap_smoke", flat(1))]),
            "transparency": sevenTimer(2),
            "seeing": sevenTimer(2),
            "aqi_observed": aqi([observation("PM2.5", 20)]),
        ]
    }

    static func response(_ edit: (inout [String: WorkerField]) -> Void = { _ in }) -> ConditionsResponse {
        var fields = goodFields()
        edit(&fields)
        return ConditionsResponse(
            cell: WorkerCell(lat: 38.35, lon: -109.95, roundingDeg: 0.05),
            window: .init(startUTC: at(0), endUTC: at(14)), generatedUTC: at(0.9),
            fields: fields, attribution: [])
    }

    static let config: VerdictConfig = try! .bundled()

    static func evaluate(
        night: NightReport = night(), conditions: ConditionsResponse? = response(),
        aurora: AuroraOutlook? = nil, config: VerdictConfig = config, now: Date = now,
        galacticCoreIsTarget: Bool = false
    ) throws -> Verdict {
        try Verdict.evaluate(
            night: night, conditions: conditions, aurora: aurora, config: config, now: now,
            galacticCoreIsTarget: galacticCoreIsTarget)
    }

    /// The bundled thresholds file with edits applied, decoded as SkyCore would.
    static func thresholds(_ edit: (inout [String: Any]) -> Void) throws -> ConditionsThresholds {
        var json = try JSONSerialization.jsonObject(with: SharedResources.data("conditions-thresholds.json")) as! [String: Any]
        edit(&json)
        return try ConditionsThresholds.decode(JSONSerialization.data(withJSONObject: json))
    }

    static func editFactor(_ json: inout [String: Any], _ key: String, _ edit: (inout [String: Any]) -> Void) {
        var factors = json["factors"] as! [String: Any]
        var f = factors[key] as? [String: Any] ?? [:]
        edit(&f)
        factors[key] = f
        json["factors"] = factors
    }
}
