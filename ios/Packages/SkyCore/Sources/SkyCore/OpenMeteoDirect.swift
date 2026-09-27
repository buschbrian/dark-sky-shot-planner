public import Foundation

/// The app's fallback when the Worker is unset or unreachable (ADR-0010 point 6):
/// cloud cover straight from Open-Meteo for the Worker's named models, mapped
/// into a `ConditionsResponse` in which every other field is unavailable.
/// Mirrors `worker/src/sources/openmeteo.ts`; this file only builds URLs and
/// maps bytes, so it is testable offline.
public enum OpenMeteoDirect {
    public struct Model: Sendable, Hashable {
        public let id: String
        /// `models=` value for the forecast API.
        public let upstream: String
        /// `/data/{meta}/static/meta.json` id.
        public let meta: String
        public let label: String
    }

    /// Same list, order and ids as the Worker's `FORECAST_MODELS`.
    public static let models: [Model] = [
        Model(id: "hrrr", upstream: "ncep_hrrr_conus", meta: "ncep_hrrr_conus", label: "NOAA HRRR CONUS"),
        Model(id: "gfs", upstream: "gfs_global", meta: "ncep_gfs013", label: "NOAA GFS"),
        Model(id: "icon", upstream: "icon_global", meta: "dwd_icon", label: "DWD ICON Global"),
        Model(id: "ecmwf", upstream: "ecmwf_ifs025", meta: "ecmwf_ifs025", label: "ECMWF IFS 0.25°"),
    ]

    struct Variable {
        let field: String
        let om: String
        let unit: String
    }

    static let cloudVariables: [Variable] = [
        Variable(field: "cloud_cover_total", om: "cloud_cover", unit: "%"),
        Variable(field: "cloud_cover_low", om: "cloud_cover_low", unit: "%"),
        Variable(field: "cloud_cover_mid", om: "cloud_cover_mid", unit: "%"),
        Variable(field: "cloud_cover_high", om: "cloud_cover_high", unit: "%"),
    ]

    /// Every other field the Worker returns, with its unit and source, so the
    /// verdict names each one as unavailable instead of silently missing.
    static let otherFields: [(field: String, unit: String, source: String)] = [
        ("temperature", "°C", "Open-Meteo"),
        ("dew_point", "°C", "Open-Meteo"),
        ("relative_humidity", "%", "Open-Meteo"),
        ("wind_speed", "km/h", "Open-Meteo"),
        ("wind_gust", "km/h", "Open-Meteo"),
        ("visibility", "m", "Open-Meteo"),
        ("wind_speed_250hpa", "km/h", "Open-Meteo"),
        ("wind_speed_200hpa", "km/h", "Open-Meteo"),
        ("aerosol_optical_depth", "", "Open-Meteo Air Quality (CAMS Global; © ECMWF Copernicus)"),
        ("pm2_5", "µg/m³", "Open-Meteo Air Quality (CAMS Global; © ECMWF Copernicus)"),
        ("dust", "µg/m³", "Open-Meteo Air Quality (CAMS Global; © ECMWF Copernicus)"),
        ("smoke_surface", "µg/m³", "NOAA RAP-Smoke via NWS NDGD"),
        ("smoke_column", "mg/m²", "NOAA RAP-Smoke via NWS NDGD"),
        ("aqi_observed", "AQI", "EPA AirNow"),
        ("seeing", "index 1–8 (1 best)", "7Timer! ASTRO (Shanghai Astronomical Observatory)"),
        ("transparency", "index 1–8 (1 best)", "7Timer! ASTRO (Shanghai Astronomical Observatory)"),
    ]

    public static let host = URL(string: "https://api.open-meteo.com")!
    /// Shown as the cloud fields' source, so the screen says where they came from.
    /// Worded like `ConditionsStatus.workerSilentDirect` (review B-4).
    public static let source = "Open-Meteo (direct; the conditions service didn't answer)"
    /// What snapshots saved before 2026-09-27 carry; still read as a fallback.
    static let legacySource = "Open-Meteo (direct; Worker unreachable)"
    public static let otherFieldsReason = "the conditions service didn't answer; only cloud cover is fetched directly"
    /// With no Worker configured the direct fetch is the normal mode, not a fallback, so it says so calmly.
    public static let directSource = "Open-Meteo (direct)"
    public static let notSetUpReason = "no conditions Worker set up; only cloud cover is fetched directly"
    public static let attribution = ["Weather data by Open-Meteo.com (CC BY 4.0)"]

    public static func forecastURL(_ model: Model, _ request: ConditionsRequest) -> URL {
        host.appending(path: "v1/forecast").appending(queryItems: [
            URLQueryItem(name: "latitude", value: request.cell.latitudeText),
            URLQueryItem(name: "longitude", value: request.cell.longitudeText),
            URLQueryItem(name: "hourly", value: cloudVariables.map(\.om).joined(separator: ",")),
            URLQueryItem(name: "models", value: model.upstream),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "timeformat", value: "iso8601"),
            URLQueryItem(name: "start_date", value: request.startDate),
            URLQueryItem(name: "end_date", value: request.endDate),
        ])
    }

    public static func metaURL(_ model: Model) -> URL {
        host.appending(path: "data/\(model.meta)/static/meta.json")
    }

    /// What came back for one model. `forecast` nil means the request failed
    /// before any HTTP status (offline, timeout).
    public struct ModelFetch: Sendable {
        public let model: Model
        public let forecast: (status: Int, body: Data)?
        public let forecastError: String?
        public let meta: Data?

        public init(model: Model, forecast: (status: Int, body: Data)?, forecastError: String? = nil, meta: Data?) {
            self.model = model
            self.forecast = forecast
            self.forecastError = forecastError
            self.meta = meta
        }
    }

    /// The run time from a `meta.json` body; nil when it has none.
    public static func modelRun(_ meta: Data?) -> Date? {
        guard let meta,
              let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              obj["error"] as? Bool != true,
              let t = (obj["last_run_initialisation_time"] as? NSNumber)?.doubleValue
        else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    struct Hourly {
        var outsideDomain = false
        var units: [String: String] = [:]
        var times: [Date] = []
        var vars: [String: [Double?]] = [:]
    }

    static func parseHourly(status: Int, body: Data) -> Result<Hourly, FactorAssessor.Unavailable> {
        let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        if status == 400, let reason = obj?["reason"] as? String,
           reason.range(of: "no data is available", options: .caseInsensitive) != nil {
            return .success(Hourly(outsideDomain: true))
        }
        guard (200..<300).contains(status) else { return .failure(.init("HTTP \(status)")) }
        guard let obj, obj["error"] as? Bool != true, let hourly = obj["hourly"] as? [String: Any] else {
            return .failure(.init("unexpected response shape"))
        }
        guard let rawTimes = hourly["time"] as? [Any] else { return .failure(.init("hourly.time missing")) }
        var out = Hourly()
        for raw in rawTimes {
            guard let s = raw as? String, s.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/) != nil,
                  let t = WorkerJSON.parse("\(s):00Z")
            else { return .failure(.init("unexpected time format")) }
            out.times.append(t)
        }
        for (key, value) in hourly where key != "time" {
            guard let arr = value as? [Any] else { continue }
            out.vars[key] = arr.map { ($0 as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
        }
        for (key, value) in obj["hourly_units"] as? [String: Any] ?? [:] {
            if let s = value as? String { out.units[key] = s }
        }
        return .success(out)
    }

    static func pick(_ h: Hourly, _ v: Variable, _ model: Model, _ request: ConditionsRequest) -> Result<[WorkerPoint], FactorAssessor.Unavailable> {
        if h.outsideDomain { return .failure(.init("cell is outside this model's domain")) }
        let key = h.vars[v.om] != nil ? v.om : "\(v.om)_\(model.upstream)"
        guard let vals = h.vars[key], vals.contains(where: { $0 != nil }) else {
            return .failure(.init("model does not publish this variable here"))
        }
        if let unit = h.units[key], FactorAssessor.unit(unit) != FactorAssessor.unit(v.unit) {
            return .failure(.init("unexpected upstream unit \"\(unit)\""))
        }
        return .success(h.times.indices
            .map { WorkerPoint(t: h.times[$0], v: $0 < vals.count ? vals[$0] : nil) }
            .filter { request.contains($0.t) })
    }

    /// Maps what came back into the Worker's response shape. Clouds keep one
    /// series per model (never averaged); everything else is unavailable.
    public static func response(
        request: ConditionsRequest, fetches: [ModelFetch], fetchedUTC: Date, workerConfigured: Bool = true
    ) -> ConditionsResponse {
        let source = workerConfigured ? source : directSource
        let otherFieldsReason = workerConfigured ? otherFieldsReason : notSetUpReason
        let parsed: [(ModelFetch, Result<Hourly, FactorAssessor.Unavailable>)] = fetches.map { f in
            guard let forecast = f.forecast else { return (f, .failure(.init(f.forecastError ?? "no response"))) }
            return (f, parseHourly(status: forecast.status, body: forecast.body))
        }
        var fields: [String: WorkerField] = [:]
        for v in cloudVariables {
            let series = parsed.map { f, hourly -> WorkerSeries in
                let run = modelRun(f.meta)
                let points = hourly.flatMap { pick($0, v, f.model, request) }
                switch points {
                case .success(let values):
                    return WorkerSeries(
                        model: f.model.id, upstreamModel: f.model.upstream, modelRunUTC: run, fetchedUTC: fetchedUTC,
                        status: .ok, reason: nil, lastGoodUTC: nil, values: values)
                case .failure(let u):
                    let reached = f.forecast != nil
                    return WorkerSeries(
                        model: f.model.id, upstreamModel: f.model.upstream, modelRunUTC: reached ? run : nil,
                        fetchedUTC: reached ? fetchedUTC : nil, status: .unavailable, reason: u.reason,
                        lastGoodUTC: nil, values: [])
                }
            }
            let ok = series.contains { $0.status == .ok }
            fields[v.field] = field(
                unit: v.unit, source: source, status: ok ? .ok : .unavailable,
                fetchedUTC: ok ? fetchedUTC : nil, series: series,
                reason: ok ? nil : series.map { "\($0.model): \($0.reason ?? "unavailable")" }.joined(separator: "; "))
        }
        for other in otherFields {
            fields[other.field] = field(
                unit: other.unit, source: other.source, status: .unavailable, fetchedUTC: nil, series: [],
                reason: otherFieldsReason)
        }
        return ConditionsResponse(
            cell: WorkerCell(lat: request.cell.latitude, lon: request.cell.longitude, roundingDeg: ConditionsCell.stepDeg),
            window: .init(startUTC: request.start, endUTC: request.end),
            generatedUTC: fetchedUTC, fields: fields, attribution: attribution)
    }

    /// True when every model failed before answering: the caller should fall
    /// back to its cache instead of storing an all-unavailable snapshot.
    public static func nothingReached(_ fetches: [ModelFetch]) -> Bool {
        fetches.allSatisfy { $0.forecast == nil }
    }

    static func field(
        unit: String, source: String, status: WorkerStatus, fetchedUTC: Date?, series: [WorkerSeries], reason: String?
    ) -> WorkerField {
        WorkerField(
            unit: unit, source: source, status: status, fetchedUTC: fetchedUTC, series: series, reason: reason,
            lastGoodUTC: nil, observations: nil, preliminary: nil, attribution: nil, description: nil,
            valueKind: nil, calibrated: nil, calibration: nil, resolutionNote: nil, terms: nil, optional: nil)
    }
}

extension OpenMeteoDirect {
    public static let lastGoodReason = "the conditions service didn't answer; last good copy"

    /// ADR-0006: a failed feed shows its last good value with its age. Fields
    /// the fallback cannot fetch take the cached response's series for the same
    /// cell and window, marked unavailable with `last_good_utc`, exactly as the
    /// Worker marks its own last-good copies, so they are shown but never rated.
    public static func withLastGood(_ direct: ConditionsResponse, from cached: ConditionsResponse?) -> ConditionsResponse {
        guard let cached, cached.cell == direct.cell, cached.window == direct.window else { return direct }
        var fields = direct.fields
        for (name, field) in direct.fields where field.status == .unavailable && field.series.isEmpty {
            guard let old = cached.fields[name] else { continue }
            let series = old.series.compactMap { s -> WorkerSeries? in
                guard s.values.contains(where: { $0.v != nil }), let good = s.fetchedUTC ?? s.lastGoodUTC else { return nil }
                return WorkerSeries(
                    model: s.model, upstreamModel: s.upstreamModel, modelRunUTC: s.modelRunUTC, fetchedUTC: nil,
                    status: .unavailable, reason: lastGoodReason, lastGoodUTC: good, values: s.values)
            }
            guard !series.isEmpty else { continue }
            fields[name] = WorkerField(
                unit: old.unit, source: old.source, status: .unavailable, fetchedUTC: nil, series: series,
                reason: lastGoodReason, lastGoodUTC: series.compactMap(\.lastGoodUTC).max(),
                observations: nil, preliminary: old.preliminary, attribution: old.attribution,
                description: old.description, valueKind: old.valueKind, calibrated: old.calibrated,
                calibration: old.calibration, resolutionNote: old.resolutionNote, terms: old.terms, optional: old.optional)
        }
        return ConditionsResponse(
            cell: direct.cell, window: direct.window, generatedUTC: direct.generatedUTC, fields: fields,
            attribution: direct.attribution)
    }
}

extension ConditionsResponse {
    /// Built by `OpenMeteoDirect` rather than received from the Worker.
    public var isDirectFallback: Bool {
        let source = fields["cloud_cover_total"]?.source
        return source == OpenMeteoDirect.source || source == OpenMeteoDirect.legacySource
            || source == OpenMeteoDirect.directSource
    }
}
