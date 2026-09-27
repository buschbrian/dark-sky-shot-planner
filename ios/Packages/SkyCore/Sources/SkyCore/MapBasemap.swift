public import Foundation

/// A tile source a basemap draws from. Every one is keyless and public domain
/// (`docs/data-licensing.md`, checked 2026-09-26); the attribution is shown on
/// the map itself.
public struct BasemapSource: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case raster, rasterDEM }

    public let id: String
    public let kind: Kind
    /// MapLibre `{z}/{x}/{y}` template. ArcGIS caches order rows first (`{z}/{y}/{x}`).
    public let tileTemplate: String
    public let maxZoom: Int
    /// Short credit drawn on the map.
    public let attribution: String
    public let license: String
    /// Service description with its "Data refreshed …" text, when it has one.
    public let metadataURL: URL?
    /// Mean bytes per tile by zoom, sampled around Candlestick Camp on
    /// 2026-09-26 (four tiles per zoom); zooms not listed use the nearest one.
    let bytesPerTile: [Int: Int]

    public var encoding: String? { kind == .rasterDEM ? "terrarium" : nil }

    static let usgsBase = "https://basemap.nationalmap.gov/arcgis/rest/services"

    public static let usgsTopo = BasemapSource(
        id: "usgs-topo", kind: .raster, tileTemplate: "\(usgsBase)/USGSTopo/MapServer/tile/{z}/{y}/{x}", maxZoom: 16,
        attribution: "USGS The National Map", license: "Public domain (U.S. Government)",
        metadataURL: URL(string: "\(usgsBase)/USGSTopo/MapServer?f=json"),
        bytesPerTile: [8: 27_000, 11: 32_500, 12: 26_300, 13: 25_400, 14: 18_900, 15: 14_800, 16: 8_300])

    public static let usgsImageryTopo = BasemapSource(
        id: "usgs-imagery", kind: .raster, tileTemplate: "\(usgsBase)/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}", maxZoom: 16,
        attribution: "USGS The National Map: orthoimagery, US Topo", license: "Public domain (U.S. Government)",
        metadataURL: URL(string: "\(usgsBase)/USGSImageryTopo/MapServer?f=json"),
        bytesPerTile: [8: 20_500, 9: 27_300, 12: 22_900, 13: 22_800, 14: 21_100, 15: 17_300, 16: 16_900])

    /// Elevation for MapLibre's own hillshade (the same tiles Spots reads for horizons).
    public static let awsTerrain = BasemapSource(
        id: "aws-terrain", kind: .rasterDEM, tileTemplate: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
        maxZoom: 12, attribution: "Terrain: Mapzen/AWS Open Data, USGS 3DEP", license: "Public domain sources (USGS 3DEP, SRTM)",
        metadataURL: nil, bytesPerTile: [8: 85_400, 9: 78_200, 10: 66_000, 11: 139_900, 12: 127_600])

    public func bytes(atZoom z: Int) -> Int {
        if let b = bytesPerTile[z] { return b }
        let nearest = bytesPerTile.keys.min { abs($0 - z) < abs($1 - z) } ?? z
        return bytesPerTile[nearest] ?? 25_000
    }
}

/// The map's three base layers. Topo and Imagery are USGS caches as served;
/// Dark relief redraws the Topo tiles inverted and dimmed under MapLibre's
/// own hillshade, so it reads at night without another tile source.
public enum Basemap: String, CaseIterable, Sendable, Identifiable {
    case topo, imagery, darkRelief

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .topo: "Topo"
        case .imagery: "Imagery"
        case .darkRelief: "Dark relief"
        }
    }

    public var summary: String {
        switch self {
        case .topo: "USGS topographic map: relief, contours, roads, trails, names"
        case .imagery: "USGS aerial imagery with topo labels"
        case .darkRelief: "Topo inverted and dimmed with hillshade, for night"
        }
    }

    public var sources: [BasemapSource] {
        switch self {
        case .topo: [.usgsTopo]
        case .imagery: [.usgsImageryTopo]
        case .darkRelief: [.usgsTopo, .awsTerrain]
        }
    }

    /// One line of credit for the map's corner.
    public var attribution: String {
        sources.map(\.attribution).joined(separator: " · ")
    }

    /// The default for each mode: Topo by day, Dark relief in field mode.
    public static func defaultChoice(fieldMode: Bool) -> Basemap { fieldMode ? .darkRelief : .topo }

    /// Every source any basemap uses, once, in a stable order.
    public static let allSources: [BasemapSource] = [.usgsTopo, .usgsImageryTopo, .awsTerrain]
}

/// A lon/lat box.
public struct GeoBounds: Sendable, Equatable, Codable {
    public var west: Double, south: Double, east: Double, north: Double

    public init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west
        self.south = south
        self.east = east
        self.north = north
    }

    /// A square of `radiusMeters` half-side around a point (spherical, fine at this size).
    public static func around(latitude: Double, longitude: Double, radiusMeters: Double) -> GeoBounds {
        let dLat = radiusMeters / 111_320
        let dLon = radiusMeters / (111_320 * max(0.01, cos(latitude * .pi / 180)))
        return GeoBounds(west: longitude - dLon, south: latitude - dLat, east: longitude + dLon, north: latitude + dLat)
    }

    public var widthMeters: Double {
        (east - west) * 111_320 * cos((north + south) / 2 * .pi / 180)
    }

    public var heightMeters: Double { (north - south) * 111_320 }
}

/// Web-Mercator tile arithmetic for offline estimates.
public enum TileMath {
    public static func tileX(longitude: Double, zoom: Int) -> Int {
        let n = Double(1 << zoom)
        return min(Int(n) - 1, max(0, Int(floor((longitude + 180) / 360 * n))))
    }

    public static func tileY(latitude: Double, zoom: Int) -> Int {
        let n = Double(1 << zoom)
        let lat = min(85.0511, max(-85.0511, latitude)) * .pi / 180
        return min(Int(n) - 1, max(0, Int(floor((1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * n))))
    }

    /// Tiles covering `bounds` at one zoom.
    public static func count(_ b: GeoBounds, zoom: Int) -> Int {
        let x = tileX(longitude: b.east, zoom: zoom) - tileX(longitude: b.west, zoom: zoom) + 1
        let y = tileY(latitude: b.south, zoom: zoom) - tileY(latitude: b.north, zoom: zoom) + 1
        return max(0, x) * max(0, y)
    }
}

/// What an offline area will download: tiles and an estimate of bytes per
/// source, before anything is fetched.
public struct OfflineEstimate: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let sourceID: String
        public let tiles: Int
        public let bytes: Int
    }

    public let rows: [Row]
    public var tiles: Int { rows.reduce(0) { $0 + $1.tiles } }
    public var bytes: Int { rows.reduce(0) { $0 + $1.bytes } }

    /// MapLibre downloads each source from `minZoom` up to the lower of
    /// `maxZoom` and the source's own maximum (it overzooms past that).
    public static func make(bounds: GeoBounds, minZoom: Int, maxZoom: Int, sources: [BasemapSource]) -> OfflineEstimate {
        var rows: [Row] = []
        for s in sources {
            let top = min(maxZoom, s.maxZoom)
            var tiles = 0, bytes = 0
            if minZoom <= top {
                for z in minZoom...top {
                    let n = TileMath.count(bounds, zoom: z)
                    tiles += n
                    bytes += n * s.bytes(atZoom: z)
                }
            }
            rows.append(Row(sourceID: s.id, tiles: tiles, bytes: bytes))
        }
        return OfflineEstimate(rows: rows)
    }
}

/// Offline-area choices shared by the app and its tests.
public enum OfflineArea {
    /// Half-side of the box kept around a saved spot.
    public static let spotRadiusMeters = 5_000.0
    public static let spotZooms = 8...16
    /// Deepest zoom kept for "this view": the USGS caches end at 16.
    public static let maxZoom = 16

    /// Zooms kept for the current view: a little wider context than on
    /// screen, and every deeper level down to `maxZoom`.
    public static func viewZooms(currentZoom: Double) -> ClosedRange<Int> {
        let lo = max(5, min(maxZoom - 2, Int(floor(currentZoom)) - 2))
        return lo...maxZoom
    }

    /// The sources a pack takes: Topo's tiles also draw Dark relief, so a
    /// pack for either keeps both; Imagery is its own, larger download.
    public static func sources(includeImagery: Bool) -> [BasemapSource] {
        includeImagery ? [.usgsTopo, .awsTerrain, .usgsImageryTopo] : [.usgsTopo, .awsTerrain]
    }
}

/// The "Data refreshed …" phrase in a USGS basemap's `copyrightText`, e.g.
/// "Data refreshed September 4, 2026-v1.2" → "September 4, 2026".
public enum USGSServiceInfo {
    public static func refreshed(fromServiceJSON data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["copyrightText"] as? String else { return nil }
        return refreshed(fromCopyright: text)
    }

    public static func refreshed(fromCopyright text: String) -> String? {
        guard let m = text.firstMatch(of: /[Dd]ata [Rr]efreshed ([A-Z][a-z]+(?: \d{1,2})?,? \d{4})/) else { return nil }
        return String(m.1)
    }
}
