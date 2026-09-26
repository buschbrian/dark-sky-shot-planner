import SkyCore
import SwiftUI

extension View {
    /// Field-mode belt and braces for Tonight's views: multiplying by pure red
    /// turns any stray system white into red and any blue into black. The
    /// status bar and home indicator are hidden (they cannot be recolored).
    func fieldSafe(_ on: Bool) -> some View {
        colorMultiply(on ? Color(red: 1, green: 0, blue: 0) : .white)
            .statusBarHidden(on)
            .persistentSystemOverlays(on ? .hidden : .automatic)
    }

    func card(_ palette: Palette) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A button drawn only with palette colors (no system tint fill or white label).
struct PaletteButtonStyle: ButtonStyle {
    let palette: Palette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? palette.onAccent : palette.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(prominent ? palette.accent : palette.surface)
                    .opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.accent.opacity(prominent ? 0 : 0.5)))
    }
}

enum Format {
    static func clock(_ date: Date, _ tz: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    }

    static func span(_ start: Date, _ end: Date, _ tz: TimeZone) -> String {
        "\(clock(start, tz))–\(clock(end, tz))"
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "just now", "12 min", "3 h", "2 d".
    static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min old" }
        if s < 2 * 86_400 { return "\(Int(s / 3600)) h old" }
        return "\(Int(s / 86_400)) d old"
    }

    /// A reading with its unit; the unit text comes from the data.
    static func value(_ v: Double, unit: String) -> String {
        let number: String
        switch unit {
        case "%", "min", "AQI", "km/h", "m": number = String(format: "%.0f", v)
        case "°C", "°": number = String(format: "%.1f", v)
        case "": number = String(format: "%.2f", v)
        default: number = abs(v) < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        }
        if unit.isEmpty { return number }
        if unit == "%" || unit == "°" { return number + unit }
        if unit.hasPrefix("index") { return "\(number) of 8" }
        return "\(number) \(unit)"
    }

    static func nightTitle(_ night: NightDate) -> String {
        noon(night).formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated))
    }

    static func nightSpoken(_ night: NightDate) -> String {
        noon(night).formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide))
    }

    static func noon(_ night: NightDate) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal.date(from: DateComponents(year: night.year, month: night.month, day: night.day, hour: 12))!
    }

    static func coordinate(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.4f, %.4f", lat, lon)
    }

    static func model(_ id: String?) -> String? {
        id.map(StripRow.modelLabel)
    }
}

extension Rating {
    var word: String {
        switch self {
        case .good: "good"
        case .marginal: "marginal"
        case .poor: "poor"
        }
    }
}

extension VerdictLevel {
    var word: String {
        switch self {
        case .go: "Go"
        case .marginal: "Marginal"
        case .noGo: "No-go"
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .go: p.good
        case .marginal: p.marginal
        case .noGo: p.poor
        }
    }
}

extension Palette {
    /// Text on an accent fill: black on field red, the primary text color otherwise.
    var onAccent: Color { self == .field ? background : primary }

    func color(_ rating: Rating?) -> Color {
        switch rating {
        case .good: good
        case .marginal: marginal
        case .poor: poor
        case nil: secondary
        }
    }
}
