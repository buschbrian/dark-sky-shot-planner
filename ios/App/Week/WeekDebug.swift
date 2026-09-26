#if DEBUG
import Foundation
import SkyCore

/// Launch-environment hooks for UI tests and screenshots (Debug builds only).
/// `DS_PLACE=name|lat|lon|tz` sets the place when none is set;
/// `DS_FIXTURE_CONDITIONS=1` swaps in synthetic conditions so every row state renders.
enum WeekDebug {
    static let env = ProcessInfo.processInfo.environment

    static func applyLaunchPlace(to state: AppState) {
        guard state.place == nil, let spec = env["DS_PLACE"] else { return }
        let parts = spec.split(separator: "|").map(String.init)
        guard parts.count == 4, let lat = Double(parts[1]), let lon = Double(parts[2]) else { return }
        state.place = Place(name: parts[0], latitude: lat, longitude: lon, timeZoneID: parts[3])
    }

    static let fixtureProvider: (any ConditionsProviding)? =
        env["DS_FIXTURE_CONDITIONS"] == "1" ? FixtureConditions(epoch: .now) : nil
}

/// Synthetic Worker responses: four models whose cloud differs by day, HRRR
/// only for the first 48 h, nothing past day 4, and a 24 h Kp 8 forecast from +52 h.
struct FixtureConditions: ConditionsProviding {
    let epoch: Date

    /// hrrr, gfs, icon, ecmwf cloud % by day after `epoch`.
    static let cloudByDay: [[Double]] = [[4, 12, 8, 15], [62, 85, 70, 78], [10, 25, 18, 40], [30, 45, 20, 55], [6, 9, 12, 8]]
    static let models = ["hrrr", "gfs", "icon", "ecmwf"]

    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        guard window.start < epoch.addingTimeInterval(Double(Self.cloudByDay.count) * 86_400 - 43_200) else { return nil }
        let start = Date(timeIntervalSince1970: (window.start.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let hours = stride(from: start, through: window.end.addingTimeInterval(3600), by: 3600).map { $0 }
        let run = iso(epoch.addingTimeInterval(-3 * 3600))
        let fetched = iso(epoch.addingTimeInterval(-3600))

        func day(_ t: Date) -> Int { max(0, Int(t.timeIntervalSince(epoch.addingTimeInterval(-43_200)) / 86_400)) }
        func series(_ model: String, _ value: (Date) -> Double?) -> [String: Any] {
            ["model": model, "model_run_utc": run, "fetched_utc": fetched, "status": "ok",
             "values": hours.map { ["t": iso($0), "v": value($0).map { $0 as Any } ?? NSNull()] }]
        }
        func field(_ unit: String, _ source: String, _ s: [[String: Any]]) -> [String: Any] {
            ["unit": unit, "source": source, "status": "ok", "fetched_utc": fetched, "series": s]
        }
        let clouds = Self.models.enumerated().map { i, model in
            series(model) { t in
                let d = day(t)
                guard d < Self.cloudByDay.count else { return nil }
                if model == "hrrr" && t > epoch.addingTimeInterval(48 * 3600) { return nil }
                return Self.cloudByDay[d][i]
            }
        }
        let json: [String: Any] = [
            "cell": ["lat": 38.35, "lon": -109.95, "rounding_deg": 0.05],
            "window": ["start_utc": iso(window.start), "end_utc": iso(window.end)],
            "generated_utc": fetched,
            "attribution": ["Fixture data (Debug build)"],
            "fields": [
                "cloud_cover_total": field("%", "Open-Meteo", clouds),
                "aerosol_optical_depth": field("", "Open-Meteo Air Quality (CAMS Global)", [series("cams_global") { _ in 0.05 }]),
                "smoke_column": field("mg/m²", "NOAA RAP-Smoke via NWS NDGD", [series("rap_smoke") { _ in 3 }]),
                "wind_gust": field("km/h", "Open-Meteo", Self.models.map { m in series(m) { _ in 14 } }),
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? ConditionsSnapshot(workerJSON: data, fetchedUTC: epoch.addingTimeInterval(-600))
    }

    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? {
        let fetched = iso(epoch.addingTimeInterval(-2 * 3600))
        let base = (epoch.timeIntervalSince1970 / 10_800).rounded(.down) * 10_800
        let observed = (-8..<0).map { ["t": iso(Date(timeIntervalSince1970: base + Double($0) * 10_800)), "v": 2.33] }
        let forecast = (0..<32).map { i -> [String: Any] in
            let t = Date(timeIntervalSince1970: base + Double(i) * 10_800)
            let storm = (52...76).contains(t.timeIntervalSince(epoch) / 3600)
            return ["t": iso(t), "v": storm ? 8.0 : 2.67, "kind": "predicted"]
        }
        func block(_ values: [[String: Any]]) -> [String: Any] {
            ["source": "NOAA Space Weather Prediction Center", "unit": "Kp", "status": "ok", "fetched_utc": fetched, "values": values]
        }
        let json: [String: Any] = [
            "generated_utc": fetched, "cache": "fixture",
            "kp_observed": block(observed), "kp_forecast": block(forecast),
            "aurora": ["source": "NOAA SWPC OVATION", "status": "unavailable", "reason": "fixture"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? SpaceWeatherResponse.decode(data)
    }

    private func iso(_ d: Date) -> String { d.formatted(Date.ISO8601FormatStyle()) }
}
#endif
