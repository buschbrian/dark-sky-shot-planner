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

    init(_ p: Palette, field: Bool) {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func ui(_ c: Color) -> UIColor { UIColor(c).resolvedColor(with: dark) }
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

/// The base style: a plain background (the web app uses no basemap, so there
/// is no third-party basemap license or attribution to carry) plus the Pages
/// site's layers. Smoke, IR frames and planner lines are added at runtime.
enum MapStyle {
    static let layerIds: [MapLayer: [String]] = [
        .lightPollution: ["lp-layer"],
        .land: ["land-fill", "land-line"],
        .places: ["places-circle"],
        .smoke: ["smoke-fill", "smoke-line"],
    ]

    static func json(data: MapData, colors: MapColors) -> [String: Any] {
        var sources: [String: Any] = [:]
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
        if sources["lp"] != nil {
            layers.append(["id": "lp-layer", "type": "raster", "source": "lp", "paint": ["raster-opacity": 0.9]])
        }
        if sources["land"] != nil {
            layers.append([
                "id": "land-fill", "type": "fill", "source": "land", "source-layer": "padus",
                "paint": ["fill-color": match, "fill-opacity": 0.25],
            ])
            layers.append([
                "id": "land-line", "type": "line", "source": "land", "source-layer": "padus",
                "paint": ["line-color": match, "line-width": 1],
            ])
        }
        if sources["places"] != nil {
            layers.append([
                "id": "places-circle", "type": "circle", "source": "places",
                "paint": [
                    "circle-radius": 6, "circle-color": colors.good.css,
                    "circle-stroke-color": colors.primary.css, "circle-stroke-width": 1.5,
                ],
            ])
        }
        return ["version": 8, "name": "Dark Sky map", "sources": sources, "layers": layers]
    }

    /// Writes the style where MapLibre (and offline packs) can load it by URL.
    static func write(data: MapData, colors: MapColors) -> URL? {
        let url = URL.cachesDirectory.appending(path: "map-style-\(colors.field ? "field" : "standard")-\(data.styleRevision).json")
        guard let bytes = try? JSONSerialization.data(withJSONObject: json(data: data, colors: colors), options: [.sortedKeys]) else { return nil }
        if (try? Data(contentsOf: url)) != bytes { try? bytes.write(to: url, options: .atomic) }
        return url
    }
}
