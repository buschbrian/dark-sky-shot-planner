import SkyCore
import SwiftUI

/// The headline: minutes of moon-free astronomical darkness.
struct AnswerCard: View {
    let report: NightReport
    let timeZone: TimeZone
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Moon-free darkness")
                .font(.subheadline)
                .foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(report.moonFreeMinutes)")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("min").font(.title2.weight(.semibold))
            }
            .foregroundStyle(palette.primary)
            Text(detail)
                .font(.body)
                .foregroundStyle(palette.primary)
        }
        .card(palette)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("tonight.headline")
    }

    private var windows: [String] {
        report.moonFreeWindows.map { Format.span($0.start, $0.end, timeZone) }
    }

    private var detail: String {
        if report.noAstronomicalDarkness { return "No astronomical darkness: the sun never gets 18° below the horizon." }
        if windows.isEmpty { return "The moon is up all through astronomical darkness." }
        let longest = report.moonFreeMinutes >= 60 ? "\(Format.duration(minutes: report.moonFreeMinutes)) · " : ""
        return longest + windows.joined(separator: " and ")
    }

    private var spoken: String {
        let head = "\(report.moonFreeMinutes) minutes of moon-free darkness"
        if report.noAstronomicalDarkness || windows.isEmpty { return "\(head). \(detail)" }
        let spans = report.moonFreeWindows.map {
            "from \(Format.clock($0.start, timeZone)) to \(Format.clock($0.end, timeZone))"
        }
        return "\(head), \(spans.joined(separator: ", and "))."
    }
}

/// Darkness window, moon and Galactic Center, all computed on the phone.
struct AstronomyDetails: View {
    let report: NightReport
    let timeZone: TimeZone
    let config: AppConfig?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Darkness", icon: "moon.haze", darkness, id: "tonight.darkness")
            row("Moon", icon: "moonphase.waxing.gibbous", moon, id: "tonight.moon")
            row("Galactic Center", icon: "sparkles", galacticCenter, id: "tonight.gc")
            Text("Computed on this phone with astronomy-engine; no network needed.")
                .font(.footnote)
                .foregroundStyle(palette.secondary)
        }
        .card(palette)
    }

    private func row(_ title: String, icon: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(palette.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondary)
                Text(value).foregroundStyle(palette.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var darkness: String {
        guard let d = report.darkness else { return "None: the sun never gets 18° below the horizon" }
        return "\(Format.span(d.start, d.end, timeZone)) (astronomical, sun 18° down)"
    }

    private var moon: String {
        var parts = ["\(Int((report.moonIllumFraction * 100).rounded()))% lit"]
        if let r = report.moonrise { parts.append("rises \(Format.clock(r, timeZone))") }
        if let s = report.moonset { parts.append("sets \(Format.clock(s, timeZone))") }
        if report.moonrise == nil, report.moonset == nil, let d = report.darkness {
            let free = report.moonFreeWindows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
            if report.moonFreeWindows.isEmpty {
                parts.append("up all through darkness")
            } else if abs(free - d.duration) < 120 {
                parts.append("down all through darkness")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var galacticCenter: String {
        let gc = report.gc
        guard let peak = gc.maxAltitudeDeg, let at = gc.maxAltitudeAt else {
            return "No moon-free darkness to see it in"
        }
        let threshold = config?.gcMinUsefulAltitudeDeg
        if !gc.risesDuringDarkness {
            return "Out of season: below the horizon in moon-free darkness"
        }
        if let threshold, peak < threshold {
            return "Out of season: peaks at \(Format.value(peak, unit: "°")) at \(Format.clock(at, timeZone)), under the \(Format.value(threshold, unit: "°")) useful altitude"
        }
        return "Peaks at \(Format.value(peak, unit: "°")) at \(Format.clock(at, timeZone)) in moon-free darkness"
    }
}
