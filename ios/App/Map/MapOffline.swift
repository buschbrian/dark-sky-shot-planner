import Foundation
import MapLibre
import Observation
import SkyCore

/// Basemap areas kept on the phone as MapLibre offline packs. Only the HTTP
/// basemap sources go in a pack (the PMTiles layers are kept whole by
/// `MapData`), and a pack's style uses the map's own tile URLs, so the map
/// finds the saved tiles without signal.
@Observable
final class OfflineAreas {
    nonisolated struct Context: Codable, Equatable {
        var name: String
        /// "view" or "spot".
        var kind: String
        var spotKey: String?
        var includeImagery: Bool
        var estimateBytes: Int
        var minZoom: Int
        var maxZoom: Int
        var bounds: GeoBounds
        var created: Date
    }

    struct Area: Identifiable, Equatable {
        let id: String
        let context: Context
        let state: MLNOfflinePackState
        let completed: UInt64
        let expected: UInt64
        let bytes: UInt64
        let error: String?

        var fraction: Double { expected == 0 ? 0 : min(1, Double(completed) / Double(expected)) }
        var isComplete: Bool { state == .complete }

        var status: String {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            if let error { return "Stopped: \(error)" }
            switch state {
            case .complete: return "Saved · \(size) · \(completed) files"
            case .active: return "Downloading \(Int((fraction * 100).rounded())) % · \(completed)/\(expected) · \(size)"
            case .inactive: return completed > 0 ? "Paused at \(Int((fraction * 100).rounded())) % · \(size)" : "Waiting"
            case .invalid: return "Unreadable pack"
            case .unknown: return "Checking…"
            @unknown default: return "Checking…"
            }
        }
    }

    /// Refuse downloads beyond this (the phone keeps many areas; the Mac's disk and the phone's are finite).
    static let maxBytes = 150 << 20

    private(set) var areas: [Area] = []
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var packsObservation: NSKeyValueObservation?
    @ObservationIgnored private var errors: [String: String] = [:]

    init() {
        MapNetwork.configure()
        let center = NotificationCenter.default
        for name in [Notification.Name.MLNOfflinePackProgressChanged, .MLNOfflinePackError, .MLNOfflinePackMaximumMapboxTilesReached] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.object as? MLNOfflinePack).flatMap(Self.context).map(Self.key)
                let message = (note.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError)?.localizedDescription
                MainActor.assumeIsolated {
                    if let id, let message { self?.errors[id] = message }
                    self?.reload()
                }
            })
        }
        packsObservation = MLNOfflineStorage.shared.observe(\.packs, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for p in MLNOfflineStorage.shared.packs ?? [] where p.state == .unknown { p.requestProgress() }
                    self?.reload()
                }
            }
        }
    }

    isolated deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    func area(forSpot key: String) -> Area? { areas.first { $0.context.spotKey == key } }

    func estimate(bounds: GeoBounds, zooms: ClosedRange<Int>, includeImagery: Bool) -> OfflineEstimate {
        OfflineEstimate.make(bounds: bounds, minZoom: zooms.lowerBound, maxZoom: zooms.upperBound,
                             sources: OfflineArea.sources(includeImagery: includeImagery))
    }

    /// Starts a download; returns why not, when it can't.
    @discardableResult
    func add(name: String, kind: String, spotKey: String? = nil, bounds: GeoBounds, zooms: ClosedRange<Int>, includeImagery: Bool) -> String? {
        let e = estimate(bounds: bounds, zooms: zooms, includeImagery: includeImagery)
        guard e.bytes <= Self.maxBytes else {
            return "About \(ByteCountFormatter.string(fromByteCount: Int64(e.bytes), countStyle: .file)): zoom in to keep a smaller area."
        }
        guard let styleURL = MapStyle.writeOffline(sources: OfflineArea.sources(includeImagery: includeImagery)) else {
            return "Couldn't write the offline style."
        }
        let ctx = Context(name: name, kind: kind, spotKey: spotKey, includeImagery: includeImagery, estimateBytes: e.bytes,
                          minZoom: zooms.lowerBound, maxZoom: zooms.upperBound, bounds: bounds, created: .now)
        guard let data = try? JSONEncoder().encode(ctx) else { return "Couldn't encode the area." }
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: MLNCoordinateBounds(sw: .init(latitude: bounds.south, longitude: bounds.west),
                                        ne: .init(latitude: bounds.north, longitude: bounds.east)),
            fromZoomLevel: Double(zooms.lowerBound), toZoomLevel: Double(zooms.upperBound))
        MLNOfflineStorage.shared.addPack(for: region, withContext: data) { [weak self] pack, error in
            nonisolated(unsafe) let pack = pack
            MainActor.assumeIsolated {
                if let error { self?.errors[Self.key(ctx)] = error.localizedDescription }
                pack?.resume()
                self?.reload()
            }
        }
        return nil
    }

    func remove(_ area: Area) {
        guard let pack = (MLNOfflineStorage.shared.packs ?? []).first(where: { Self.context($0).map(Self.key) == area.id }) else { return }
        errors[area.id] = nil
        pack.suspend()
        MLNOfflineStorage.shared.removePack(pack) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func resumeAll() {
        for p in MLNOfflineStorage.shared.packs ?? [] where p.state == .inactive && !MapNetwork.offline { p.resume() }
    }

    private func reload() {
        let next = (MLNOfflineStorage.shared.packs ?? []).compactMap { pack -> Area? in
            guard let ctx = Self.context(pack) else { return nil }
            let p = pack.progress
            let id = Self.key(ctx)
            return Area(id: id, context: ctx, state: pack.state, completed: p.countOfResourcesCompleted,
                        expected: p.countOfResourcesExpected, bytes: p.countOfBytesCompleted,
                        error: pack.state == .complete ? nil : errors[id])
        }.sorted { $0.context.created < $1.context.created }
        if next != areas { areas = next }
    }

    nonisolated private static func context(_ pack: MLNOfflinePack) -> Context? {
        try? JSONDecoder().decode(Context.self, from: pack.context)
    }

    nonisolated private static func key(_ c: Context) -> String { "\(c.name)@\(c.created.timeIntervalSince1970)" }

    static func spotKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f,%.5f", latitude, longitude)
    }
}
