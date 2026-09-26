import Foundation
import SkyCore
import SwiftUI

/// Text for Week numbers. Missing values read "unavailable", never 0.
enum WeekFormat {
    static func age(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.down))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) days ago"
    }

    /// A model run time in UTC, forecasters' style: "18Z", or "Fri 18Z" when older than a day.
    static func run(_ run: Date, now: Date) -> String {
        var hour = Date.FormatStyle().hour(.twoDigits(amPM: .omitted))
        hour.timeZone = TimeZone(identifier: "UTC")!
        let z = "\(run.formatted(hour))Z"
        guard now.timeIntervalSince(run) > 86_400 else { return z }
        var day = Date.FormatStyle().weekday(.abbreviated)
        day.timeZone = TimeZone(identifier: "UTC")!
        return "\(run.formatted(day)) \(z)"
    }

    static func minutes(_ m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    static func level(_ level: VerdictLevel) -> String {
        switch level {
        case .go: "Go"
        case .marginal: "Marginal"
        case .noGo: "No-go"
        }
    }

    static func color(_ level: VerdictLevel, _ palette: Palette) -> Color {
        switch level {
        case .go: palette.good
        case .marginal: palette.marginal
        case .noGo: palette.poor
        }
    }

    /// A factor's value with its unit, e.g. "38%", "0.14", "25 km/h".
    static func value(_ v: Double, unit: String) -> String {
        let digits = abs(v) < 1 ? 2 : abs(v) < 10 ? 1 : 0
        let number = v.formatted(.number.precision(.fractionLength(0...digits)))
        switch unit {
        case "": return number
        case "%": return "\(number)%"
        case "°": return "\(number)°"
        default: return "\(number) \(unit)"
        }
    }

    /// "Cloud cover 38%", "Wind gusts unavailable".
    static func factor(_ f: FactorAssessment) -> String {
        guard let v = f.value else { return "\(f.factor.label) unavailable" }
        return "\(f.factor.label) \(value(v, unit: f.factor.unit))"
    }

    /// The limiting factor, always shown next to the level (ios/AGENTS.md).
    static func limiting(_ verdict: Verdict) -> String {
        switch verdict.cause {
        case .rating:
            verdict.level == .go ? "Closest to its limit: \(factor(verdict.limiting))" : "Limited by \(factor(verdict.limiting))"
        case .incompleteData: "Incomplete data: \(factor(verdict.limiting))"
        case .staleData: "Stale data: \(factor(verdict.limiting))"
        }
    }

    static func aurora(_ outlook: AuroraOutlook) -> String {
        switch outlook {
        case .possible(let kp, let visible, let basis):
            let when = switch basis {
            case .observedNow: "observed now"
            case .observedInWindow: "observed"
            case .forecastInWindow: "forecast"
            }
            return "Aurora possible: Kp \(kpText(kp)) \(when) (visible here from Kp \(kpText(visible)))"
        case .notExpected(let maxKp, let visible):
            return "Aurora not expected: Kp up to \(kpText(maxKp)), needs \(kpText(visible))"
        case .unavailable(.noKpData): return "Aurora unavailable: no Kp data"
        case .unavailable(.kpDoesNotCoverNight): return "Aurora unavailable: Kp forecast does not reach this night"
        case .unavailable(.noAstronomicalDarkness): return "Aurora unavailable: no astronomical darkness"
        case .outOfRange: return "Aurora: too far from the pole to rate"
        }
    }

    static func kpText(_ kp: Double) -> String { kp.formatted(.number.precision(.fractionLength(0...2))) }

    static func nightTitle(_ night: NightOutlook, place: Place, isTonight: Bool) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide).day().month(.abbreviated)
        style.timeZone = place.timeZone
        let date = night.evening.formatted(style)
        return isTonight ? "Tonight, \(date)" : date
    }
}
