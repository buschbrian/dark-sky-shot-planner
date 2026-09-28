import SkyCore
import SwiftUI

/// One identity per sky body, used wherever the body is drawn: the map's
/// azimuth lines, chart series and the Sky overlay. Color never carries the
/// identity alone: each body also has its own line pattern, which is all
/// field mode (red levels only) has to tell them apart. Status colors
/// (`good`, `marginal`, `poor`) are never a body's color.
///
/// Sun, Moon and GC read `palette.data`, so charts that already use those
/// tokens match the map without change. Planets and fixed targets (stars,
/// deep-sky objects) are new here.
enum CelestialBody: Hashable, CaseIterable {
    case sun, moon, galacticCenter, planet, fixed

    init(_ object: SkyObject) {
        switch object {
        case .sun: self = .sun
        case .moon: self = .moon
        case .galacticCenter: self = .galacticCenter
        case .mercury, .venus, .mars, .jupiter, .saturn: self = .planet
        }
    }

    /// The Milky Way arch belongs with the core it runs through.
    init(_ target: ShotTarget) {
        switch target {
        case .galacticCore, .milkyWayArch: self = .galacticCenter
        case .moon: self = .moon
        case .planet: self = .planet
        case .fixed: self = .fixed
        }
    }
}

enum CelestialStyle {
    /// The body's color in this palette.
    static func color(_ body: CelestialBody, _ p: Palette) -> Color {
        switch body {
        case .sun: p.data.sun
        case .moon: p.data.moon
        case .galacticCenter: p.data.galacticCenter
        case .planet: p.isField ? .red(0.74) : Color(hex: 0x3DB5A6)
        case .fixed: p.isField ? .red(0.5) : Color(hex: 0xD9B98C)
        }
    }

    /// Dash pattern in points (empty = solid). The Moon is always the solid line.
    static func dash(_ body: CelestialBody) -> [CGFloat] {
        switch body {
        case .sun: DataPalette.sunDash
        case .moon: DataPalette.moonDash
        case .galacticCenter: DataPalette.gcDash
        case .planet: [5, 2, 1, 2]
        case .fixed: [1, 4]
        }
    }

    /// MapLibre measures dashes in line widths; this keeps the pattern's
    /// length in points the same at any width.
    static func mapDash(_ body: CelestialBody, width: Double) -> [Double]? {
        let d = dash(body)
        return d.isEmpty ? nil : d.map { Double($0) / max(0.5, width) }
    }
}
