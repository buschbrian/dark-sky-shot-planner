import SkyCore
import SwiftUI

/// The answer, first: minutes of moon-free astronomical darkness, the night
/// as a bar, then the verdict with its limiting factor and that factor's
/// source and age, and where the conditions came from.
struct AnswerCard: View {
    let report: NightReport
    let strip: NightStrip
    let timeZone: TimeZone
    let now: Date
    let verdict: Verdict?
    let origin: ConditionsSourceStatus
    let workerConfigured: Bool
    let showFactors: () -> Void
    let refresh: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        SectionCard {
            headline
            NightBar(span: strip.span, darkness: strip.darkness, moonFree: strip.moonFree, timeZone: timeZone, now: now)
                .accessibilityIdentifier("tonight.nightBar")
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.vertical, DS.Space.xs)
            VerdictBlock(verdict: verdict, now: now, workerConfigured: workerConfigured)
            DataStatusLine(symbol: origin.symbol, text: origin.text(now: now), tone: origin.tone)
                .accessibilityIdentifier("tonight.conditionsOrigin")
            HStack(spacing: DS.Space.s) {
                Button(action: showFactors) {
                    Label("Every factor", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                .disabled(verdict == nil)
                .accessibilityHint("Shows every factor with its source and age")
                .accessibilityIdentifier("tonight.factors")
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                .accessibilityLabel("Refresh conditions")
                .accessibilityIdentifier("tonight.refresh")
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                RoundedRectangle(cornerRadius: 2).fill(palette.data.moonFree).frame(width: 10, height: 10)
                Text("Moon-free darkness").eyebrow(palette)
            }
            DisplayNumber(value: "\(report.moonFreeMinutes)", unit: "min")
            Text(detail)
                .font(.dsCallout)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return windows.joined(separator: " and ")
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

/// Darkness, moon and Galactic Center, all computed on the phone.
struct AstronomyDetails: View {
    let report: NightReport
    let timeZone: TimeZone
    let config: AppConfig?
    @Environment(\.palette) private var palette

    var body: some View {
        SectionCard("Sky tonight") {
            FactRow(icon: "moon.haze", label: "Astronomical darkness", value: darkness)
                .accessibilityIdentifier("tonight.darkness")
            FactRow(icon: moonSymbol, label: "Moon", value: moon)
                .accessibilityIdentifier("tonight.moon")
            FactRow(icon: "sparkles", label: "Galactic Center", value: galacticCenter)
                .accessibilityIdentifier("tonight.gc")
            ProvenanceChip(info: SourceInfo(source: "astronomy-engine", note: Voice.onDevice))
        }
    }

    private var moonSymbol: String {
        let f = report.moonIllumFraction
        if f < 0.03 { return "moonphase.new.moon" }
        if f > 0.97 { return "moonphase.full.moon" }
        return "moon"
    }

    private var darkness: String {
        guard let d = report.darkness else { return "None: the sun never gets 18° below the horizon" }
        return Format.span(d.start, d.end, timeZone)
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
