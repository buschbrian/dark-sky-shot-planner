import SkyCore
import SwiftUI

extension Palette {
    func color(_ level: VerdictLevel?) -> Color {
        switch level {
        case .go: good
        case .marginal: marginal
        case .noGo: poor
        case nil: secondary
        }
    }
}

enum VerdictSymbol {
    /// Shape as well as colour, since field mode tells levels apart by brightness only.
    static func name(_ level: VerdictLevel?) -> String {
        switch level {
        case .go: "checkmark.circle.fill"
        case .marginal: "minus.circle.fill"
        case .noGo: "xmark.circle.fill"
        case nil: "questionmark.circle"
        }
    }
}

/// Seven nights, one cell each: weekday, verdict, moon-free minutes.
struct WeekStrip: View {
    @Environment(\.palette) private var palette
    let week: SpotWeek
    let timeZone: TimeZone
    @Binding var selected: String?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week.nights) { night in
                let level = night.verdict?.level
                Button {
                    selected = night.night
                } label: {
                    VStack(spacing: 3) {
                        Text(weekday(night))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.secondary)
                        Image(systemName: VerdictSymbol.name(level))
                            .font(.title3)
                            .foregroundStyle(palette.color(level))
                        Text(night.headlineMinutes.map(String.init) ?? "–")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(palette.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected == night.night ? palette.surface : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == night.night ? palette.accent : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("night-\(night.night)")
                .accessibilityLabel("\(weekday(night)): \(night.verdict?.headline ?? "verdict unavailable"), \(night.headlineMinutes.map { "\($0) minutes moon-free" } ?? "moon-free minutes unavailable")")
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
        HStack(spacing: 3) {
            ForEach(week.nights) { night in
                Image(systemName: VerdictSymbol.name(night.verdict?.level))
                    .font(.caption)
                    .foregroundStyle(palette.color(night.verdict?.level))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.nights.map { $0.verdict?.shortLevel ?? "unavailable" }.joined(separator: ", "))
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
                ctx.fill(fill, with: .color(palette.surface))
                for az in stride(from: 90.0, to: 360, by: 90) {
                    ctx.stroke(Path { $0.move(to: point(az, bottom)); $0.addLine(to: point(az, top)) },
                               with: .color(palette.secondary.opacity(0.4)), lineWidth: 0.5)
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
                Text("\(Int(top))°").font(.caption2).foregroundStyle(palette.secondary).padding(2)
            }
            HStack {
                ForEach(["N", "E", "S", "W", "N"].indices, id: \.self) { i in
                    Text(["N", "E", "S", "W", "N"][i]).font(.caption2).foregroundStyle(palette.secondary)
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

    static func age(_ date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        if s < 90 { return "just now" }
        if s < 90 * 60 { return "\(Int((s / 60).rounded())) min ago" }
        if s < 36 * 3600 { return "\(Int((s / 3600).rounded())) h ago" }
        return "\(Int((s / 86400).rounded())) d ago"
    }
}

/// List/Form chrome from the palette, so field mode has no system grey or blue.
struct PaletteList: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let field = palette == .field
        content
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.primary)
            .tint(palette.accent)
            // The iOS 26 scroll-edge blur and the scroll indicator are grey.
            .scrollEdgeEffectHidden(field, for: .all)
            .scrollIndicators(field ? .hidden : .automatic)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackgroundVisibility(field ? .visible : .automatic, for: .navigationBar)
    }
}

extension View {
    func paletteList() -> some View { modifier(PaletteList()) }

    func paletteRow(_ palette: Palette) -> some View {
        listRowBackground(palette.surface).listRowSeparatorTint(palette.secondary.opacity(0.5))
    }

    /// An inline title in the palette's colour (the system title is white).
    func paletteTitle(_ title: String, _ palette: Palette) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.headline).foregroundStyle(palette.primary)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }

    /// In field mode the system back button's glass is grey; draw our own.
    func paletteBackButton(_ palette: Palette, dismiss: DismissAction) -> some View {
        navigationBarBackButtonHidden(palette == .field)
            .toolbar {
                if palette == .field {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel("Back")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}

extension Palette {
    /// Toolbar glass is grey, so field mode hides it.
    var toolbarGlass: Visibility { self == .field ? .hidden : .automatic }
}

/// A switch drawn from the palette (the system track is grey when off).
struct PaletteToggleStyle: ToggleStyle {
    let palette: Palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label.foregroundStyle(palette.primary)
                Spacer(minLength: 12)
                Capsule()
                    .fill(configuration.isOn ? palette.accent : palette.background)
                    .overlay(Capsule().stroke(palette.secondary, lineWidth: 1))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? (palette == .field ? palette.background : palette.primary) : palette.secondary).padding(4)
                    }
                    .frame(width: 50, height: 30)
                    .animation(.snappy(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A determinate bar without the system's grey track.
struct PaletteProgress: View {
    @Environment(\.palette) private var palette
    let value: Double

    var body: some View {
        Capsule().fill(palette.background)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(palette.accent).frame(width: g.size.width * min(max(value, 0), 1)) }
            }
            .overlay(Capsule().stroke(palette.secondary.opacity(0.6), lineWidth: 0.5))
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Row content plus a chevron in the palette (the List's disclosure chevron is grey).
struct Disclosure<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(palette.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    @Environment(\.palette) private var palette
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(palette.secondary)
    }
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
        case .astronomyOnly: nil
        case .checked: spot.week?.conditionsStatus.map { "\($0.summary(now: .now))." }
        case .partial:
            spot.week.map { week in
                let windows = "Conditions for \(week.fetchedWindows) of \(week.requestedWindows) forecast windows; other nights read unavailable."
                return week.conditionsStatus.map { "\($0.summary(now: .now)). \(windows)" } ?? windows
            }
        case .noConditions: "Conditions unavailable, so no night can be Go; verdicts are incomplete."
        case .interrupted: "iOS ended the background time; showing the previous check."
        }
    }
}
