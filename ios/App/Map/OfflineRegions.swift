import CoreLocation
import Foundation
import MapLibre
import Observation

/// MapLibre offline packs around saved spots: the Pages layers (light
/// pollution, PAD-US, dark-sky places) for a small box, so the map still
/// draws at the spot without signal. Live layers (smoke, IR) are not packed.
@Observable
final class OfflineRegions {
    struct Region: Identifiable, Equatable {
        let id: String
        var completed: UInt64
        var expected: UInt64
        var bytes: UInt64
        var state: MLNOfflinePackState
        var error: String?

        var done: Bool { state == .complete }
        var fraction: Double { expected == 0 ? 0 : Double(completed) / Double(expected) }
    }

    static let radiusDeg = 0.25
    static let zooms: ClosedRange<Double> = 5...13

    private(set) var regions: [String: Region] = [:]
    private var observation: NSKeyValueObservation?
    private var tokens: [any NSObjectProtocol] = []

    /// Room for a trip's worth of IR frames and panned tiles; set before any map loads.
    static let ambientCacheBytes: UInt = 128 << 20

    init() {
        let storage = MLNOfflineStorage.shared
        storage.setMaximumAmbientCacheSize(Self.ambientCacheBytes) { _ in }
        observation = storage.observe(\.packs, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.reload() }
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: .MLNOfflinePackProgressChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        tokens.append(center.addObserver(forName: .MLNOfflinePackError, object: nil, queue: .main) { [weak self] n in
            let name = (n.object as? MLNOfflinePack).flatMap(OfflineRegions.name(of:))
            let message = (n.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError)?.localizedDescription
            MainActor.assumeIsolated {
                guard let self, let name else { return }
                self.reload()
                self.regions[name]?.error = message
            }
        })
    }

    /// Tiles per source a region would hold (every zoom, the box around the spot).
    static func estimatedTiles(latitude: Double) -> Int {
        (Int(zooms.lowerBound)...Int(zooms.upperBound)).reduce(0) { total, z in
            let n = pow(2, Double(z))
            let x = Int(ceil(2 * radiusDeg / 360 * n)) + 1
            let latRad = latitude * .pi / 180
            let yPerDeg = n / (2 * .pi) / cos(latRad) * .pi / 180
            let y = Int(ceil(2 * radiusDeg * yPerDeg)) + 1
            return total + x * y
        }
    }

    func download(name: String, latitude: Double, longitude: Double, styleURL: URL) {
        remove(name: name)
        let r = Self.radiusDeg
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: latitude - r, longitude: longitude - r),
            ne: CLLocationCoordinate2D(latitude: latitude + r, longitude: longitude + r))
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL, bounds: bounds, fromZoomLevel: Self.zooms.lowerBound, toZoomLevel: Self.zooms.upperBound)
        let context = (try? JSONEncoder().encode(["name": name])) ?? Data()
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] _, error in
            let message = error?.localizedDescription
            MainActor.assumeIsolated {
                if let message {
                    self?.regions[name] = Region(id: name, completed: 0, expected: 0, bytes: 0, state: .invalid, error: message)
                    return
                }
                for pack in MLNOfflineStorage.shared.packs ?? [] where Self.name(of: pack) == name && pack.state == .inactive {
                    pack.resume()
                }
                self?.reload()
            }
        }
    }

    func remove(name: String) {
        for pack in MLNOfflineStorage.shared.packs ?? [] where Self.name(of: pack) == name {
            MLNOfflineStorage.shared.removePack(pack) { _ in }
        }
        regions[name] = nil
    }

    private func reload() {
        var out: [String: Region] = [:]
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            guard let name = Self.name(of: pack) else { continue }
            if pack.state == .unknown { pack.requestProgress() }
            let p = pack.progress
            out[name] = Region(
                id: name, completed: p.countOfResourcesCompleted, expected: p.countOfResourcesExpected,
                bytes: p.countOfBytesCompleted, state: pack.state, error: regions[name]?.error)
        }
        regions = out
    }

    nonisolated static func name(of pack: MLNOfflinePack) -> String? {
        (try? JSONDecoder().decode([String: String].self, from: pack.context))?["name"]
    }
}
