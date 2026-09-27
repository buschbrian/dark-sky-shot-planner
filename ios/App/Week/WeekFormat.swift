import Foundation
import SkyCore
import SwiftUI

/// Text for Week numbers. Missing values read "unavailable", never 0.
enum WeekFormat {
    /// A model run time in UTC, forecasters' style: "18Z", or "Fri 18Z" when older than a day.
    static func run(_ run: Date, now: Date) -> String { Voice.run(run, now: now) }

    static func minutes(_ m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

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
