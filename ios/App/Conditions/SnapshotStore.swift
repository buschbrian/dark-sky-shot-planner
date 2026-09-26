import Foundation
import SkyCore

/// Conditions snapshots on disk in Application Support, one file per grid cell
/// and window start, so the newest copy of each night survives a relaunch
/// with no signal. Space weather keeps only its latest response.
actor SnapshotStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func applicationSupport() -> SnapshotStore {
        SnapshotStore(directory: URL.applicationSupportDirectory.appending(path: "Conditions", directoryHint: .isDirectory))
    }

    static func temporary() -> SnapshotStore {
        SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "Conditions-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    func save(_ snapshot: ConditionsSnapshot) {
        let window = snapshot.response.window
        let cell = ConditionsCell(latitude: snapshot.response.cell.lat, longitude: snapshot.response.cell.lon)
        let stamp = window.startUTC.formatted(Date.ISO8601FormatStyle()).replacingOccurrences(of: ":", with: "")
        write(try? snapshot.encoded(), to: "conditions_\(cell.key)_\(stamp).json")
        prune(now: snapshot.fetchedUTC)
    }

    func best(for cell: ConditionsCell, window: DateInterval) -> ConditionsSnapshot? {
        ConditionsSnapshot.best(for: cell, window: window, in: all())
    }

    /// The saved answer to exactly this request (same cell and hour-aligned
    /// window), whose `ETag` may be sent back as `If-None-Match`.
    func exact(for cell: ConditionsCell, window: DateInterval) -> ConditionsSnapshot? {
        ConditionsSnapshot.newest(all().filter { s in
            cell.matches(s.response.cell)
                && s.response.window.startUTC == window.start && s.response.window.endUTC == window.end
        })
    }

    func saveSpaceWeather(_ data: Data) {
        write(data, to: "space-weather.json")
    }

    func spaceWeather() -> SpaceWeatherResponse? {
        guard let data = try? Data(contentsOf: directory.appending(path: "space-weather.json")) else { return nil }
        return try? SpaceWeatherResponse.decode(data)
    }

    private func all() -> [ConditionsSnapshot] {
        files().compactMap { url in (try? Data(contentsOf: url)).flatMap { try? ConditionsSnapshot.decode($0) } }
    }

    private func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("conditions_") }
    }

    private func prune(now: Date) {
        for url in files() {
            guard let data = try? Data(contentsOf: url), let s = try? ConditionsSnapshot.decode(data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if !ConditionsSnapshot.expired([s], now: now).isEmpty { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func write(_ data: Data?, to name: String) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }
}
