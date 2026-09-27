import Foundation
import SkyCore

/// UI-test conditions, chosen with the launch argument `-stubConditions go`
/// (every gating factor good, fresh), `-stubConditions revalidated` (a copy
/// fetched two hours ago that the Worker just confirmed with a 304) or
/// `-stubConditions unavailable`.
/// Release builds never stub.
enum DebugConditions {
    static var override: (any ConditionsProviding)? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-stubConditions"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "go": return ClearSkyConditions()
        case "revalidated": return RevalidatedConditions()
        case "unavailable": return UnavailableConditions()
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// A Worker-shaped response with clear, calm, clean air for any window,
/// decoded through SkyCore's own Worker models.
struct ClearSkyConditions: ConditionsProviding {
    /// How long ago the device received this copy (`ConditionsSnapshot.fetchedUTC`).
    var receivedAgo: TimeInterval = 0

    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        let now = Date.now
        let iso = ISO8601DateFormatter()
        let start = window.start.timeIntervalSince1970 - window.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)
        let hours = stride(from: start, through: window.end.timeIntervalSince1970 + 3600, by: 3600).map {
            iso.string(from: Date(timeIntervalSince1970: $0))
        }
        func field(_ unit: String, _ source: String, _ model: String, _ value: Double) -> [String: Any] {
            let fetched = iso.string(from: now)
            return [
                "unit": unit, "source": source, "status": "ok", "fetched_utc": fetched,
                "series": [[
                    "model": model, "upstream_model": model, "model_run_utc": iso.string(from: now.addingTimeInterval(-3600)),
                    "fetched_utc": fetched, "status": "ok",
                    "values": hours.map { ["t": $0, "v": value] },
                ]],
            ]
        }
        let lat = (place.latitude / 0.05).rounded() * 0.05, lon = (place.longitude / 0.05).rounded() * 0.05
        let json: [String: Any] = [
            "cell": ["lat": lat, "lon": lon, "rounding_deg": 0.05],
            "window": ["start_utc": hours.first!, "end_utc": hours.last!],
            "generated_utc": iso.string(from: now),
            "attribution": ["UI-test stub"],
            "fields": [
                "cloud_cover_total": field("%", "Stub", "hrrr", 0),
                "wind_gust": field("km/h", "Stub", "hrrr", 5),
                "temperature": field("°C", "Stub", "hrrr", 15),
                "dew_point": field("°C", "Stub", "hrrr", 0),
                "aerosol_optical_depth": field("", "Stub", "cams_global", 0.03),
                "smoke_column": field("mg/m²", "Stub", "rap_smoke", 0.5),
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? ConditionsSnapshot(workerJSON: data, fetchedUTC: now.addingTimeInterval(-receivedAgo))
    }

    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? { nil }
}

/// Review B-4's case: the saved copy is two hours old and the Worker answers
/// 304, so the body and its `fetchedUTC` stay old while the status is live.
struct RevalidatedConditions: LiveConditionsProviding {
    let copy = ClearSkyConditions(receivedAgo: 2 * 3600)
    var workerConfigured: Bool { true }

    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        await fetch(for: place, window: window).snapshot
    }

    func cachedConditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        await copy.conditions(for: place, window: window)
    }

    func latestRuns() async -> [String: ModelRunInfo] { [:] }

    func fetch(for place: Place, window: DateInterval) async -> ConditionsFetch {
        ConditionsFetch(
            snapshot: await copy.conditions(for: place, window: window),
            status: .liveWorker(confirmedAt: .now, revalidated: true),
            nextRefresh: .now.addingTimeInterval(15 * 60), workerHTTPStatus: 304)
    }

    func nextRefresh(for place: Place, window: DateInterval, now: Date) async -> Date {
        now.addingTimeInterval(15 * 60)
    }

    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? { nil }
}
#endif
