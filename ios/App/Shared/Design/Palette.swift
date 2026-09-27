import SwiftUI

/// Every color the app draws comes from here, never a literal in a view.
///
/// Standard is a cool night-sky dark scheme. Field mode (ios/AGENTS.md
/// invariant 5) is pure red on black: green and blue are exactly 0 in every
/// token, so nothing the app draws can emit them. Pure red tops out at 5.25:1
/// against black, so field hierarchy comes from size and weight more than from
/// brightness; `secondary` still clears 4:1.
///
/// Contrast on `surface` (WCAG): standard primary 15.6, secondary 8.1,
/// tertiary 5.0, accent 8.4; field primary 5.1, secondary 4.0.
struct Palette: Equatable {
    /// The window behind everything.
    let background: Color
    /// Cards and grouped rows.
    let surface: Color
    /// Controls and cells on a card (keys, chips, tracks).
    let raised: Color
    /// Strokes, dividers and chart gridlines.
    let hairline: Color
    let primary: Color
    let secondary: Color
    /// Non-essential text only (captions under a value that is also spoken).
    let tertiary: Color
    /// Interactive elements, and the moon-free window in charts.
    let accent: Color
    /// Filled controls (primary button, selected choice, switch track). In
    /// field mode a large fill is the brightest thing on a dark-adapted eye,
    /// so it is dim, outlined by `accentEdge`, and its text stays bright.
    let accentFill: Color
    /// The outline on an `accentFill`: clear in standard, red 60 % in field.
    let accentEdge: Color
    /// Text and glyphs on an `accentFill`.
    let onAccent: Color
    /// Status colors: go, marginal and no-go only. Never a chart series.
    let good: Color
    let marginal: Color
    let poor: Color
    /// Chart and night-bar colors, separate from status (dataviz rule).
    let data: DataPalette
    let colorScheme: ColorScheme
    let isField: Bool

    static let standard = Palette(
        background: Color(hex: 0x0A0C11), surface: Color(hex: 0x14171E), raised: Color(hex: 0x1D212A),
        hairline: Color(hex: 0x2A303B),
        primary: Color(hex: 0xECEFF4), secondary: Color(hex: 0xA7AFBD), tertiary: Color(hex: 0x7F8898),
        accent: Color(hex: 0x9AAEFF), accentFill: Color(hex: 0x9AAEFF), accentEdge: .clear, onAccent: Color(hex: 0x0A0C11),
        good: Color(hex: 0x5BCB8F), marginal: Color(hex: 0xF2B14C), poor: Color(hex: 0xFF7A70),
        data: .standard, colorScheme: .dark, isField: false)

    static let field = Palette(
        background: .black, surface: .red(0.07), raised: .red(0.14), hairline: .red(0.28),
        primary: .red(1.0), secondary: .red(0.86), tertiary: .red(0.62),
        // Fill 20 % with red text at 100 %: 4.6:1, and no fill brighter than the 60 % edge.
        accent: .red(1.0), accentFill: .red(0.2), accentEdge: .red(0.6), onAccent: .red(1.0),
        good: .red(1.0), marginal: .red(0.86), poor: .red(0.62),
        data: .field, colorScheme: .dark, isField: true)
}

/// Series and fills for charts and the night bar. Standard series were run
/// through the dataviz validator on `surface` (all pairs): sun, GC and the
/// moon-free window clear CVD ΔE 8.7 and normal-vision ΔE 19. The moon is
/// neutral silver on purpose and is always the solid line, so it never relies
/// on hue. In field mode every series is a red level plus its dash pattern.
struct DataPalette: Equatable {
    let sun: Color
    let moon: Color
    let galacticCenter: Color
    /// The headline window: moon-free astronomical darkness.
    let moonFree: Color
    /// Astronomical darkness with the moon up.
    let moonlit: Color
    /// Astronomical darkness, behind everything else.
    let darkness: Color
    /// Twilight and day on the night bar and scrubber track.
    let twilight: Color
    let grid: Color
    let axisLabel: Color
    /// Heat-map cells: one neutral hue, brighter is worse.
    let cell: Color

    static let standard = DataPalette(
        sun: Color(hex: 0xC98500), moon: Color(hex: 0xC9CFD9), galacticCenter: Color(hex: 0xD55181),
        moonFree: Color(hex: 0x6F84F2), moonlit: Color(hex: 0x262C3B), darkness: Color(hex: 0x07090E),
        twilight: Color(hex: 0x3D4556), grid: Color(hex: 0x2A303B), axisLabel: Color(hex: 0xA7AFBD),
        cell: Color(hex: 0xECEFF4))

    static let field = DataPalette(
        sun: .red(0.6), moon: .red(1.0), galacticCenter: .red(0.86),
        moonFree: .red(0.85), moonlit: .red(0.18), darkness: .black,
        twilight: .red(0.32), grid: .red(0.24), axisLabel: .red(0.86),
        cell: .red(1.0))

    /// Dash patterns: identity never rests on color alone.
    static let sunDash: [CGFloat] = [6, 3]
    static let moonDash: [CGFloat] = []
    static let gcDash: [CGFloat] = [1.5, 3]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A pure red level for field mode: green and blue are exactly zero.
    static func red(_ level: Double) -> Color { Color(.sRGB, red: level, green: 0, blue: 0) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.standard
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
