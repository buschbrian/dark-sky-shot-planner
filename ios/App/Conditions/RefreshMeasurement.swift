import Foundation
import OSLog
import SkyCore

#if DEBUG
/// `-DarkSkyMeasureRefresh` (debug builds): times real refreshes against the
/// configured Worker through the client's own code path, three rounds of
///  - cold: a grid cell the Worker has probably not cached, no saved copy;
///  - warm: the same request from an empty store (Worker cache, full 200);
///  - 304: the same request again, now with the saved copy's ETag.
/// Each line goes to the log (subsystem DarkSky, category perf) and stdout.
nonisolated enum RefreshMeasurement {
    static let argument = "-DarkSkyMeasureRefresh"
    static let log = Logger(subsystem: "DarkSky", category: "perf")

    static func runIfAsked(_ arguments: [String], workerBase: URL?) {
        guard arguments.contains(argument) else { return }
        guard let workerBase else {
            report("refresh-timing skipped: no Worker configured")
            return
        }
        Task.detached(priority: .userInitiated) {
            for round in 1...3 { await measure(workerBase, round: round) }
            report("refresh-timing done")
        }
    }

    static func measure(_ base: URL, round: Int) async {
        // A random grid point in the Colorado Plateau: rarely asked for, so cold at the Worker.
        let lat = 37.0 + Double(Int.random(in: 0..<60)) * 0.05
        let lon = -112.5 + Double(Int.random(in: 0..<60)) * 0.05
        let zone = TimeZone(identifier: "America/Denver")!
        let place = Place(name: "measure", latitude: lat, longitude: lon, timeZoneID: zone.identifier)
        let window = ConditionsRequest.nightWindow(NightDate.containing(.now, in: zone), in: zone)

        let first = ConditionsClient(workerBase: base, networkEnabled: true, store: .temporary())
        let second = ConditionsClient(workerBase: base, networkEnabled: true, store: .temporary())
        for (label, client) in [("cold", first), ("warm", second), ("304", second)] {
            let clock = ContinuousClock.now
            let result = await client.fetch(for: place, window: window)
            let total = ContinuousClock.now - clock
            let http = result.workerDuration.map { "\(ConditionsClient.ms($0)) ms" } ?? "-"
            report("refresh-timing round=\(round) \(label) status=\(result.workerHTTPStatus.map(String.init) ?? "none") http=\(http) total=\(ConditionsClient.ms(total)) ms cell=\(String(format: "%.2f,%.2f", lat, lon)) source=\(result.status)")
        }
    }

    static func report(_ line: String) {
        log.notice("\(line, privacy: .public)")
        print(line)
    }
}
#endif
