import Foundation
import MapLibre
import Observation
import SkyCore

/// `data/out/<layer>/manifest.json`, as the web app reads it (`ManifestJson`).
struct LayerManifest: Codable, Equatable {
    struct Artifact: Codable, Equatable {
        let path: String
        let bytes: Int?
    }

    let layer_id: String
    let source_name: String
    let source_url: String
    let license: String
    let publication_date: String?
    let artifacts: [Artifact]?
}

/// The map's layers, in the order the list shows them.
enum MapLayer: String, CaseIterable, Identifiable {
    case lightPollution, land, places, smoke, infrared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightPollution: "Light pollution"
        case .land: "Land manager (PAD-US)"
        case .places: "Dark-sky places"
        case .smoke: "Smoke polygons (HMS)"
        case .infrared: "Cloud IR loop (GOES)"
        }
    }

    /// Directory under `data/out/` and the `freshness_days` / data-status key.
    var pages: (dir: String, layerId: String, artifact: String)? {
        switch self {
        case .lightPollution: ("light_pollution", "light_pollution", "light-pollution.pmtiles")
        case .land: ("padus", "land_ownership", "padus.pmtiles")
        case .places: ("darksky_places", "darksky_places", "darksky-places.geojson")
        case .smoke, .infrared: nil
        }
    }

    static let defaultVisible: Set<MapLayer> = [.lightPollution, .land, .places, .smoke]
}

/// Everything the map shows that comes over the network: the Pages site's
/// `data/out/` artifacts, HMS smoke polygons and GIBS frame times. Each is
/// cached on disk, so offline the map shows the last copy with its age.
@Observable
final class MapData {
    static let pagesBase = URL(string: "https://buschbrian.github.io/dark-sky-shot-planner/")!
    /// Whole archives above this stay remote (range requests, MapLibre's own cache).
    static let maxCachedArchiveBytes = 64 << 20
    /// MapLibre's HTTP cache (IR frames, remote PMTiles ranges); set before any map loads.
    static let ambientCacheBytes: UInt = 128 << 20
    static let irFrameCount = 6
    static let irFrameSpacing: TimeInterval = 20 * 60

    private(set) var manifests: [String: LayerManifest] = [:]
    /// Empty (every layer `unknown`) until data-status.json has been read.
    private(set) var dataStatus = PagesDataStatus(data: nil)
    private(set) var smoke: Data?
    private(set) var smokeAnalysis: (start: Date?, end: Date?) = (nil, nil)
    private(set) var irFrames: [Date] = []
    /// When each cached file was last written (its age when offline).
    private(set) var fetched: [String: Date] = [:]
    private(set) var failed: Set<String> = []
    /// Bumped when an artifact the style references changes location.
    private(set) var styleRevision = 0

    private let cacheDir: URL
    private let session: URLSession

    init(cacheDir: URL? = nil) {
        MapNetwork.configure()
        let base = cacheDir ?? URL.applicationSupportDirectory.appending(path: "MapData", directoryHint: .isDirectory)
        self.cacheDir = base
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(Self.ambientCacheBytes) { _ in }
        loadFromDisk()
    }

    // MARK: Sources for the style

    /// A local copy when there is one, else the published URL.
    func artifactURL(_ layer: MapLayer) -> URL? {
        guard let p = layer.pages else { return nil }
        let rel = "\(p.dir)/\(p.artifact)"
        return cachedFile(rel) ?? Self.pagesBase.appending(path: rel)
    }

    func origin(_ layer: MapLayer) -> PagesOrigin {
        guard let id = layer.pages?.layerId else { return .unknown }
        return dataStatus.origin(id)
    }

    /// Bytes of the whole archive per the manifest, and whether a full copy is on the phone.
    func archive(_ layer: MapLayer) -> (bytes: Int?, onPhone: Bool) {
        guard let p = layer.pages else { return (nil, false) }
        let bytes = manifests[p.layerId]?.artifacts?.first { $0.path == p.artifact }?.bytes
        let rel = "\(p.dir)/\(p.artifact)"
        return (bytes, cachedFile(rel) != nil && (bytes == nil || fileSize(rel) == bytes))
    }

    /// Saves one archive whole, whatever its size (the owner asked for it).
    func keepOffline(_ layer: MapLayer) async {
        guard let p = layer.pages else { return }
        let rel = "\(p.dir)/\(p.artifact)"
        let hadCopy = cachedFile(rel) != nil
        if await fetch(Self.pagesBase.appending(path: rel), to: rel), !hadCopy { styleRevision += 1 }
    }

    // MARK: Refresh

    private var lastAttempt: [String: Date] = [:]

    func refreshDue(irVisible: Bool, now: Date = .now) async {
        func due(_ key: String, _ every: TimeInterval) -> Bool {
            guard now.timeIntervalSince(lastAttempt[key] ?? .distantPast) >= every else { return false }
            lastAttempt[key] = now
            return true
        }
        if irVisible, due("ir", 5 * 60) { await refreshInfrared(now: now) }
        if due("smoke", 15 * 60) { await refreshSmoke() }
        if due("pages", 6 * 3600) { await refreshPages() }
    }

    func refreshAll() async {
        let now = Date.now
        for key in ["ir", "smoke", "pages"] { lastAttempt[key] = now }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshPages() }
            group.addTask { await self.refreshSmoke() }
            group.addTask { await self.refreshInfrared() }
        }
    }

    func refreshPages() async {
        for s in Basemap.allSources {
            if let u = s.metadataURL { _ = await fetch(u, to: "basemap/\(s.id).json") }
        }
        _ = await fetch(Self.pagesBase.appending(path: "data-status.json"), to: "data-status.json")
        for layer in MapLayer.allCases {
            guard let p = layer.pages else { continue }
            _ = await fetch(Self.pagesBase.appending(path: "\(p.dir)/manifest.json"), to: "\(p.dir)/manifest.json")
        }
        loadFromDisk()
        for layer in MapLayer.allCases {
            guard let p = layer.pages else { continue }
            let rel = "\(p.dir)/\(p.artifact)"
            let bytes = manifests[p.layerId]?.artifacts?.first { $0.path == p.artifact }?.bytes
            guard let bytes, bytes <= Self.maxCachedArchiveBytes else { continue }
            let hadCopy = cachedFile(rel) != nil
            // Re-download only when the manifest says the archive changed size or the copy is a day old.
            if hadCopy, fileSize(rel) == bytes, let t = fetched[rel], Date.now.timeIntervalSince(t) < 86_400 { continue }
            if await fetch(Self.pagesBase.appending(path: rel), to: rel), !hadCopy { styleRevision += 1 }
        }
    }

    func refreshSmoke() async {
        guard let a = (try? AppConfig.bundled())?.aoi.bbox else { return }
        let gotPolygons = await fetch(HMSSmoke.queryURL(west: a.west, south: a.south, east: a.east, north: a.north), to: "hms/smoke.geojson")
        let gotStats = await fetch(HMSSmoke.statsURL, to: "hms/stats.json")
        if gotPolygons || gotStats { loadFromDisk() }
    }

    func refreshInfrared(now: Date = .now) async {
        let url = GIBSTimeDomain.describeDomainsURL(from: now.addingTimeInterval(-6 * 3600), to: now)
        if await fetch(url, to: "gibs/domains.xml") { loadFromDisk() }
    }

    // MARK: Disk cache

    private func loadFromDisk() {
        let dec = JSONDecoder()
        dataStatus = PagesDataStatus(data: read("data-status.json"))
        var m: [String: LayerManifest] = [:]
        for layer in MapLayer.allCases {
            guard let p = layer.pages,
                  let man = read("\(p.dir)/manifest.json").flatMap({ try? dec.decode(LayerManifest.self, from: $0) }) else { continue }
            m[p.layerId] = man
        }
        manifests = m
        smoke = read("hms/smoke.geojson")
        smokeAnalysis = read("hms/stats.json").map(HMSSmoke.analysisWindow(fromStats:)) ?? (nil, nil)
        let xml = read("gibs/domains.xml").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        irFrames = GIBSTimeDomain.loopFrames(
            GIBSTimeDomain.times(fromDescribeDomains: xml), count: Self.irFrameCount, minSpacing: Self.irFrameSpacing)
        var f: [String: Date] = [:]
        if let e = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in e {
                guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                f[String(url.path(percentEncoded: false).dropFirst(cacheDir.path(percentEncoded: false).count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))] = d
            }
        }
        fetched = f
    }

    /// "Data refreshed …" for a USGS basemap source, from its cached service description.
    func refreshed(_ source: BasemapSource) -> String? {
        read("basemap/\(source.id).json").flatMap(USGSServiceInfo.refreshed(fromServiceJSON:))
    }

    private func fetch(_ url: URL, to rel: String) async -> Bool {
        // -DarkSkyOffline: behave exactly as with no signal (the cached copies stay).
        if MapNetwork.offline {
            failed.insert(rel)
            return false
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                failed.insert(rel)
                return false
            }
            // An ArcGIS error arrives as HTTP 200 with an "error" object.
            if url.host()?.contains("arcgis") == true, data.prefix(64).contains(Data("\"error\"".utf8)) {
                failed.insert(rel)
                return false
            }
            let dest = cacheDir.appending(path: rel)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            failed.remove(rel)
            fetched[rel] = .now
            return true
        } catch {
            failed.insert(rel)
            return false
        }
    }

    private func read(_ rel: String) -> Data? { try? Data(contentsOf: cacheDir.appending(path: rel)) }

    private func cachedFile(_ rel: String) -> URL? {
        let url = cacheDir.appending(path: rel)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func fileSize(_ rel: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: cacheDir.appending(path: rel).path(percentEncoded: false)))?[.size] as? Int
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool { range(of: other) != nil }
}
