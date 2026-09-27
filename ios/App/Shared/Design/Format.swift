import SkyCore
import SwiftUI

/// Text for numbers, times and places, shared by every screen. Missing values
/// never come through here as 0: callers show `UnavailableValue` instead.
enum Format {
    static func clock(_ date: Date, _ tz: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz))
    }

    static func span(_ start: Date, _ end: Date, _ tz: TimeZone) -> String {
        "\(clock(start, tz))–\(clock(end, tz))"
    }

    /// "45 min", "3 h", "3 h 12 min".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Data age: "just now", "12 min old", "3 h old" (see `Voice`).
    static func age(_ seconds: TimeInterval) -> String { Voice.age(seconds) }

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

    /// "MDT", or the zone ID when it has no abbreviation.
    static func zone(_ tz: TimeZone, at date: Date = .now) -> String {
        tz.abbreviation(for: date) ?? tz.identifier
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
    var word: String { StatusLevel(self).word }

    func color(_ p: Palette) -> Color { StatusLevel(self).color(p) }
}

extension Palette {
    func color(_ rating: Rating?) -> Color {
        switch rating {
        case .good: good
        case .marginal: marginal
        case .poor: poor
        case nil: secondary
        }
    }

    func color(_ level: VerdictLevel?) -> Color { StatusLevel(level).color(self) }
}
