import SkyCore
import SwiftUI
import UIKit

/// Palette colors resolved for MapLibre, which takes UIColor or CSS strings.
struct MapColors: Equatable {
    let background: UIColor
    let surface: UIColor
    let primary: UIColor
    let secondary: UIColor
    let accent: UIColor
    let good: UIColor
    let marginal: UIColor
    let field: Bool

    /// Field mode caps what the map draws at this share of full red, so the
    /// brightest map pixel stays well under a glare at night.
    static let fieldCap: CGFloat = 0.6

    init(_ p: Palette, field: Bool) {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func ui(_ c: Color) -> UIColor {
            let u = UIColor(c).resolvedColor(with: dark)
            guard field else { return u }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: min(r, 1) * Self.fieldCap, green: 0, blue: 0, alpha: a)
        }
        background = ui(p.background)
        surface = ui(p.surface)
        primary = ui(p.primary)
        secondary = ui(p.secondary)
        accent = ui(p.accent)
        good = ui(p.good)
        marginal = ui(p.marginal)
        self.field = field
    }

    func line(for object: SkyObject) -> UIColor {
        switch object {
        case .sun: marginal
        case .galacticCenter: accent
        default: primary
        }
    }
}

extension UIColor {
    var css: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return "rgba(\(c(r)),\(c(g)),\(c(b)),\(String(format: "%.3f", a)))"
    }
}

/// `manager_taxonomy` from the bundled `config/app-config.json` (ADR-0004):
/// the map and its text share one source of labels and colors.
struct ManagerTaxonomy {
    struct Entry: Decodable { let key: String; let label: String; let color: String }
    private struct File: Decodable { let manager_taxonomy: [Entry] }

    let entries: [Entry]

    static let bundled = ManagerTaxonomy(
        entries: (try? JSONDecoder().decode(File.self, from: SharedResources.data("app-config.json")).manager_taxonomy) ?? [])

    func label(for key: String?) -> String {
        entries.first { $0.key == key }?.label ?? "Unknown"
    }
}

/// The base style: the three basemaps (hidden until the map shows the chosen
/// one), then the Pages site's layers. Smoke, IR frames and planner lines are
/// added at runtime. Every basemap source is public domain and keyless
/// (`docs/data-licensing.md`); its credit is drawn on the map.
enum MapStyle {
    static let layerIds: [MapLayer: [String]] = [
        .lightPollution: ["lp-layer"],
        .land: ["land-fill", "land-line"],
        .places: ["places-circle"],
        .smoke: ["smoke-fill", "smoke-line"],
    ]

    static let basemapLayerIds: [Basemap: [String]] = [
        .topo: ["basemap-topo"],
        .imagery: ["basemap-imagery"],
        .darkRelief: ["basemap-dark", "basemap-hillshade"],
    ]

    /// Raster, DEM and attribution for one basemap source, shared by the
    /// map's style and the offline packs' styles so both use the same tile URLs
    /// (MapLibre keys cached tiles by URL template).
    static func source(_ s: BasemapSource) -> [String: Any] {
        var src: [String: Any] = [
            "type": s.kind == .rasterDEM ? "raster-dem" : "raster",
            "tiles": [s.tileTemplate], "tileSize": 256, "maxzoom": s.maxZoom, "attribution": s.attribution,
        ]
        if let e = s.encoding { src["encoding"] = e }
        return src
    }

    /// Basemap layers, all hidden; the coordinator shows the chosen one.
    static func basemapLayers(field: Bool) -> [[String: Any]] {
        let hidden: [String: Any] = ["visibility": "none"]
        // Field mode: every basemap tops out near 55 % brightness before the red multiply.
        var topoPaint: [String: Any] = ["raster-fade-duration": 150]
        var imageryPaint: [String: Any] = ["raster-fade-duration": 150]
        if field {
            topoPaint["raster-brightness-max"] = 0.5
            imageryPaint["raster-brightness-max"] = 0.5
        }
        return [
            ["id": "basemap-topo", "type": "raster", "source": BasemapSource.usgsTopo.id, "layout": hidden, "paint": topoPaint],
            ["id": "basemap-imagery", "type": "raster", "source": BasemapSource.usgsImageryTopo.id, "layout": hidden, "paint": imageryPaint],
            // Dark relief: the Topo tiles in grey, contrast raised so the light
            // relief shading and paper drop to black, then inverted so names,
            // roads and trails come out light on a dark ground.
            [
                "id": "basemap-dark", "type": "raster", "source": BasemapSource.usgsTopo.id, "layout": hidden,
                "paint": [
                    "raster-saturation": -1, "raster-contrast": field ? 0.5 : 0.45,
                    "raster-brightness-min": field ? 0.6 : 0.92, "raster-brightness-max": field ? 0.03 : 0.07,
                    "raster-fade-duration": 150,
                ] as [String: Any],
            ],
            // Relief as moonlit slopes over the dark ground (highlights only, so
            // shadows never hide a label).
            [
                "id": "basemap-hillshade", "type": "hillshade", "source": BasemapSource.awsTerrain.id, "layout": hidden,
                "paint": [
                    "hillshade-exaggeration": 0.55,
                    "hillshade-shadow-color": "rgba(0,0,0,0.35)",
                    "hillshade-highlight-color": field ? "rgba(150,150,150,0.35)" : "rgba(170,178,200,0.34)",
                    "hillshade-accent-color": "rgba(0,0,0,0)",
                    "hillshade-illumination-anchor": "map",
                ] as [String: Any],
            ],
        ]
    }

    static func json(data: MapData, colors: MapColors) -> [String: Any] {
        var sources: [String: Any] = [:]
        for s in Basemap.allSources { sources[s.id] = source(s) }
        if let u = data.artifactURL(.lightPollution) {
            sources["lp"] = ["type": "raster", "url": "pmtiles://\(u.absoluteString)", "tileSize": 256]
        }
        if let u = data.artifactURL(.land) {
            sources["land"] = ["type": "vector", "url": "pmtiles://\(u.absoluteString)"]
        }
        if let u = data.artifactURL(.places) {
            sources["places"] = ["type": "geojson", "data": u.absoluteString]
        }
        var match: [Any] = ["match", ["get", "manager"]]
        for e in ManagerTaxonomy.bundled.entries { match += [e.key, e.color] }
        match.append("#555555")

        var layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": colors.background.css]],
        ]
        layers += basemapLayers(field: colors.field)
        if sources["lp"] != nil {
            // Over a basemap the radiance has to leave the ground readable.
            layers.append(["id": "lp-layer", "type": "raster", "source": "lp", "paint": ["raster-opacity": 0.6]])
        }
        if sources["land"] != nil {
            layers.append([
                "id": "land-fill", "type": "fill", "source": "land", "source-layer": "padus",
                "paint": ["fill-color": match, "fill-opacity": 0.2],
            ])
            layers.append([
                "id": "land-line", "type": "line", "source": "land", "source-layer": "padus",
                "paint": ["line-color": match, "line-width": 1.5],
            ])
        }
        if sources["places"] != nil {
            layers.append([
                "id": "places-circle", "type": "circle", "source": "places",
                "paint": [
                    "circle-radius": 7, "circle-color": colors.good.css,
                    "circle-stroke-color": colors.background.css, "circle-stroke-width": 2,
                ],
            ])
        }
        return ["version": 8, "name": "Dark Sky map", "sources": sources, "layers": layers]
    }

    /// Writes the style where MapLibre can load it by URL.
    static func write(data: MapData, colors: MapColors) -> URL? {
        let url = URL.cachesDirectory.appending(path: "map-style-\(colors.field ? "field" : "standard")-\(data.styleRevision).json")
        guard let bytes = try? JSONSerialization.data(withJSONObject: json(data: data, colors: colors), options: [.sortedKeys]) else { return nil }
        if (try? Data(contentsOf: url)) != bytes { try? bytes.write(to: url, options: .atomic) }
        return url
    }

    /// The style an offline pack downloads: basemap sources only (the PMTiles
    /// archives are kept whole elsewhere, and MapLibre's downloader rejects
    /// `pmtiles://`). Its layers are visible so every source is fetched.
    static func writeOffline(sources: [BasemapSource]) -> URL? {
        var src: [String: Any] = [:]
        var layers: [[String: Any]] = []
        for s in sources {
            src[s.id] = source(s)
            layers.append(["id": "pack-\(s.id)", "type": s.kind == .rasterDEM ? "hillshade" : "raster", "source": s.id])
        }
        let json: [String: Any] = ["version": 8, "name": "Dark Sky offline basemap", "sources": src, "layers": layers]
        let dir = URL.applicationSupportDirectory.appending(path: "MapOffline", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "pack-style-\(sources.map(\.id).joined(separator: "+")).json")
        guard let bytes = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return nil }
        if (try? Data(contentsOf: url)) != bytes { try? bytes.write(to: url, options: .atomic) }
        return url
    }
}
