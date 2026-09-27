import SkyCore
import SwiftUI

/// Seven nights, one cell each: weekday, verdict, moon-free minutes.
struct WeekStrip: View {
    @Environment(\.palette) private var palette
    let week: SpotWeek
    let timeZone: TimeZone
    @Binding var selected: String?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(week.nights) { night in
                let level = StatusLevel(night.verdict?.level, moonFreeMinutes: night.headlineMinutes)
                let isSelected = selected == night.night || (selected == nil && night.id == week.nights.first?.id)
                Button {
                    selected = night.night
                } label: {
                    VStack(spacing: DS.Space.xs) {
                        Text(weekday(night))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                        Image(systemName: level.symbol)
                            .font(.title3)
                            .foregroundStyle(level.color(palette))
                        Text(night.headlineMinutes.map(String.init) ?? "–")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(palette.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(isSelected ? palette.raised : .clear))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(isSelected ? palette.accent : .clear, lineWidth: DS.Stroke.focus))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("night-\(night.night)")
                .accessibilityLabel("\(weekday(night)): \(level == .moonUp ? "moon up all through darkness" : night.verdict?.headline ?? "verdict unavailable"), \(night.headlineMinutes.map { "\($0) minutes moon-free" } ?? "moon-free minutes unavailable")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    func weekday(_ night: NightSummary) -> String {
        guard let date = night.date else { return night.night }
        return date.evening(in: timeZone).formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
    }
}

/// The list row's glance: one symbol per night.
struct MiniWeekStrip: View {
    @Environment(\.palette) private var palette
    let week: SpotWeek

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(week.nights) { night in
                let level = StatusLevel(night.verdict?.level, moonFreeMinutes: night.headlineMinutes)
                Image(systemName: level.symbol)
                    .font(.caption)
                    .foregroundStyle(level.color(palette))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.nights.map { night in
            StatusLevel(night.verdict?.level, moonFreeMinutes: night.headlineMinutes) == .moonUp
                ? "moon up" : night.verdict?.shortLevel ?? "unavailable"
        }.joined(separator: ", "))
    }
}

/// Terrain altitude against azimuth, north at both ends.
struct SkylineChart: View {
    @Environment(\.palette) private var palette
    let profile: HorizonProfile
    /// Drawn dashed for comparison (a measured profile under a computed one).
    var reference: HorizonProfile?

    var body: some View {
        let top = max(10, ((max(profile.maxAltitudeDeg, reference?.maxAltitudeDeg ?? 0)) / 5).rounded(.up) * 5)
        let bottom = min(0, (min(profile.minAltitudeDeg, reference?.minAltitudeDeg ?? 0)).rounded(.down))
        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, size in
                func point(_ az: Double, _ alt: Double) -> CGPoint {
                    CGPoint(x: az / 360 * size.width, y: size.height * (1 - (alt - bottom) / (top - bottom)))
                }
                func path(_ p: HorizonProfile) -> Path {
                    Path { path in
                        for az in stride(from: 0.0, through: 360, by: 1) {
                            let pt = point(az, p.altitudeDeg(atAzimuth: az))
                            az == 0 ? path.move(to: pt) : path.addLine(to: pt)
                        }
                    }
                }
                var fill = path(profile)
                fill.addLine(to: point(360, bottom))
                fill.addLine(to: point(0, bottom))
                fill.closeSubpath()
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.data.darkness))
                ctx.fill(fill, with: .color(palette.data.twilight))
                for az in stride(from: 90.0, to: 360, by: 90) {
                    ctx.stroke(Path { $0.move(to: point(az, bottom)); $0.addLine(to: point(az, top)) },
                               with: .color(palette.data.grid), lineWidth: 0.5)
                }
                ctx.stroke(Path { $0.move(to: point(0, 0)); $0.addLine(to: point(360, 0)) },
                           with: .color(palette.secondary), lineWidth: 0.5)
                if let reference {
                    ctx.stroke(path(reference), with: .color(palette.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ctx.stroke(path(profile), with: .color(palette.primary), lineWidth: 1.5)
            }
            .frame(height: 90)
            .overlay(alignment: .topLeading) {
                Text("\(Int(top))°").font(.dsData).foregroundStyle(palette.data.axisLabel).padding(DS.Space.xs)
            }
            HStack {
                ForEach(["N", "E", "S", "W", "N"].indices, id: \.self) { i in
                    Text(["N", "E", "S", "W", "N"][i]).font(.dsData).foregroundStyle(palette.data.axisLabel)
                    if i < 4 { Spacer() }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("skyline-chart")
        .accessibilityLabel(String(format: "Skyline from %.1f° to %.1f° above horizontal", profile.minAltitudeDeg, profile.maxAltitudeDeg))
    }
}

/// "3 h ago" that re-renders as time passes.
struct AgeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(Self.age(date, now: context.date))
        }
    }

    static func age(_ date: Date, now: Date = .now) -> String { Voice.ago(date, now: now) }
}

/// What the last check did. "Couldn't check" never reads as "checked, no Go".
struct CheckStatus: View {
    @Environment(\.palette) private var palette
    let spot: Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let at = spot.lastAttemptAt, let outcome = spot.lastOutcome {
                HStack(spacing: 4) {
                    Text(outcome.counts ? "Checked" : outcome == .interrupted ? "Couldn't finish" : "Couldn't check")
                    AgeText(date: at)
                    Text(spot.lastCheckedInBackground ? "(background)" : "(in app)")
                }
                .foregroundStyle(outcome.counts ? palette.secondary : palette.poor)
                if let note = note(outcome) { Text(note) }
                if !outcome.counts {
                    HStack(spacing: 4) {
                        Text("Last complete check:")
                        if let last = spot.lastCheckedAt { AgeText(date: last) } else { Text("never") }
                    }
                }
            } else {
                Text("Not checked yet")
            }
        }
        .accessibilityElement(children: .combine)
    }

    func note(_ outcome: CheckOutcome) -> String? {
        switch outcome {
        case .checked, .astronomyOnly: nil
        case .partial:
            spot.week.map { "Conditions for \($0.fetchedWindows) of \($0.requestedWindows) forecast windows; other nights read unavailable." }
        case .noConditions: "Conditions unavailable, so no night can be Go; verdicts have incomplete data."
        case .interrupted: "iOS ended the background time; showing the previous check."
        }
    }
}
