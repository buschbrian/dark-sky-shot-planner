#if DEBUG
import SkyCore
import SwiftUI

/// Every design-system piece on one screen, in the current palette. Open it
/// with the launch argument `-DSTab gallery` (Debug builds), or in Xcode's
/// canvas via the previews below.
struct DesignGallery: View {
    @Environment(\.palette) private var palette
    @State private var toggle = true
    @State private var choice = 2

    private let now = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    SectionCard("Status") {
                        HStack(spacing: DS.Space.s) {
                            StatusBadge(level: .go)
                            StatusBadge(level: .marginal)
                            StatusBadge(level: .noGo)
                        }
                        StatusBadge(level: .unavailable, qualifier: "no verdict")
                        StatusBadge(level: .marginal, qualifier: "incomplete data", large: true)
                    }
                    SectionCard("Metrics") {
                        HStack(alignment: .top) {
                            MetricTile(label: "Cloud", value: "8", unit: "%",
                                       source: SourceInfo(source: "Open-Meteo", model: "HRRR", run: now.addingTimeInterval(-7200),
                                                          asOf: now.addingTimeInterval(-7200), freshness: .fresh), now: now)
                            MetricTile(label: "Smoke", value: nil,
                                       source: SourceInfo(source: "RAP-Smoke", freshness: .unavailable), now: now)
                        }
                        UnavailableValue(reason: "needs the live conditions service, which is not set up in this build")
                    }
                    SectionCard("Provenance") {
                        ProvenanceChip(info: SourceInfo(source: "Open-Meteo", model: "HRRR", run: now.addingTimeInterval(-3 * 3600),
                                                        asOf: now.addingTimeInterval(-3 * 3600), freshness: .fresh), now: now)
                        ProvenanceChip(info: SourceInfo(source: "CAMS", asOf: now.addingTimeInterval(-30 * 3600), freshness: .aging), now: now)
                        ProvenanceChip(info: SourceInfo(source: "RAP-Smoke", asOf: now.addingTimeInterval(-80 * 3600),
                                                        freshness: .stale, note: Voice.lastGood), now: now)
                        ProvenanceChip(info: .onDevice)
                        ForEach([ConditionsSourceStatus.service(fetched: now), .direct(serviceConfigured: true),
                                 .direct(serviceConfigured: false), .lastGood(fetched: now.addingTimeInterval(-5400), refreshing: false)],
                                id: \.debugDescription) { s in
                            DataStatusLine(symbol: s.symbol, text: s.text(now: now), tone: s.tone)
                        }
                    }
                    SectionCard("Night bar") {
                        let dusk = now, dawn = now.addingTimeInterval(9 * 3600)
                        NightBar(span: TimeWindow(start: dusk.addingTimeInterval(-7200), end: dawn.addingTimeInterval(7200)),
                                 darkness: TimeWindow(start: dusk, end: dawn),
                                 moonFree: [TimeWindow(start: dusk.addingTimeInterval(3 * 3600), end: dawn)],
                                 timeZone: .current, now: dusk.addingTimeInterval(3600))
                        NightBarLegend()
                        HStack(spacing: DS.Space.m) {
                            SeriesKey(.moon)
                            SeriesKey(.galacticCenter)
                            SeriesKey(.sun)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                    }
                    SectionCard("Controls") {
                        Toggle("A palette switch", isOn: $toggle).toggleStyle(PaletteToggleStyle())
                        HStack {
                            Button("Primary") {}.buttonStyle(ActionButtonStyle(.primary))
                            Button("Secondary") {}.buttonStyle(ActionButtonStyle(.secondary))
                            Button("Quiet") {}.buttonStyle(ActionButtonStyle(.quiet))
                        }
                        ChoiceRow(label: "Choice row", options: [(1, "One"), (2, "Two"), (3, "Three")],
                                  selection: $choice, id: "gallery.choice")
                        Grid(horizontalSpacing: KeypadMetrics.spacing, verticalSpacing: KeypadMetrics.spacing) {
                            GridRow {
                                ForEach(["7", "8", "9"], id: \.self) { k in Button(k) {}.buttonStyle(KeypadKeyStyle()) }
                                Button("clear") {}.buttonStyle(KeypadKeyStyle(emphasized: true))
                            }
                        }
                        PaletteProgress(value: 0.4)
                    }
                    SectionCard("Type") {
                        Text("Moon-free darkness").eyebrow(palette)
                        DisplayNumber(value: "212", unit: "min")
                        Text("Title").font(.dsTitle)
                        Text("Headline").font(.dsHeadline)
                        Text("Body text reads like this.").font(.dsBody)
                        Text("Callout and footnote").font(.dsCallout)
                        Text("Open-Meteo · run 18Z · 2 h old").font(.dsData).foregroundStyle(palette.secondary)
                    }
                    .foregroundStyle(palette.primary)
                    MoreInfo(title: "More info") { Text("Secondary detail lives behind a disclosure.") }
                    EmptyState(symbol: "mappin.and.ellipse", title: "Empty state", message: "Says what to do next.",
                               actionTitle: "Do it", action: {})
                }
                .padding(DS.Space.screen)
            }
            .background(palette.background)
            .screenChrome("Design")
        }
    }
}

private extension ConditionsSourceStatus {
    var debugDescription: String { "\(self)" }
}

#Preview("Gallery, standard") {
    DesignGallery()
        .environment(AppState())
        .environment(\.palette, .standard)
        .preferredColorScheme(.dark)
}

#Preview("Gallery, field") {
    DesignGallery()
        .environment(AppState())
        .environment(\.palette, .field)
        .preferredColorScheme(.dark)
}
#endif
