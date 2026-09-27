import SkyCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SpotDetail: View {
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var conditions
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Query private var spots: [Spot]

    @Bindable var spot: Spot

    @State private var selectedNight: String?
    @State private var checking = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var widgetShared: Bool?

    /// Re-check on open when the stored week is older than this.
    static let staleAfter: TimeInterval = 15 * 60

    var inUse: Bool { state.place == spot.place }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("\(String(format: "%.5f, %.5f", spot.latitude, spot.longitude)) · \(Format.zone(spot.place.timeZone))")
                        .font(.dsData)
                        .foregroundStyle(palette.secondary)
                    if !spot.notes.isEmpty {
                        Text(spot.notes).font(.dsCallout).foregroundStyle(palette.primary).padding(.top, DS.Space.xs)
                    }
                }
                Button {
                    state.place = spot.place
                } label: {
                    Label(inUse ? "In use on Tonight and Week" : "Use this spot",
                          systemImage: inUse ? "checkmark.circle.fill" : "location.circle")
                }
                .disabled(inUse)
                .accessibilityIdentifier("use-spot")
                Toggle(isOn: Binding(get: { spot.isPinned }, set: pin)) {
                    Label("Show in widget", systemImage: "rectangle.on.rectangle")
                }
                .toggleStyle(PaletteToggleStyle())
                .accessibilityIdentifier("pin-spot")
                if spot.isPinned, widgetShared == false {
                    DataStatusLine(symbol: "exclamationmark.triangle",
                                   text: "The widget can't read shared data in this build (App Group not set up), so it will ask you to pin a spot.",
                                   tone: .caution)
                }
            }
            .paletteRow(palette)

            weekSection
            HorizonSection(spot: spot, onChange: { Task { await check() } })
            AlertSection(spot: spot)

            Section {
                Button(confirmDelete ? "Tap again to delete \(spot.name)" : "Delete spot", role: .destructive) {
                    if confirmDelete { delete() } else { confirmDelete = true }
                }
                .foregroundStyle(palette.poor)
                .accessibilityIdentifier("delete-spot")
            }
            .paletteRow(palette)
        }
        .paletteList()
        .screenChrome(spot.name, pushed: true) {
            Button("Edit") { editing = true }.accessibilityIdentifier("edit-spot")
        }
        .sheet(isPresented: $editing) { SpotEditor(spot: spot) }
        .task(id: "\(spot.latitude),\(spot.longitude),\(spot.timeZoneID)") {
            if spot.lastAttemptAt.map({ Date.now.timeIntervalSince($0) > Self.staleAfter }) ?? true || spot.week == nil {
                await check()
            }
        }
    }

    @ViewBuilder var weekSection: some View {
        Section {
            if let week = spot.week {
                WeekStrip(week: week, timeZone: spot.place.timeZone, selected: $selectedNight)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                let night = week.nights.first { $0.night == selectedNight } ?? week.nights.first
                if let date = night?.date {
                    ShotWindowLine(place: spot.place, night: date, horizon: spot.horizonProfile)
                }
                if let night { NightDetail(night: night, timeZone: spot.place.timeZone, terrainAware: week.terrainAware) }
            } else {
                Text(checking ? "Checking the week…" : "Not checked yet").font(.dsCallout).foregroundStyle(palette.secondary)
            }
            Button { Task { await check() } } label: {
                Label(checking ? "Checking…" : "Re-check now", systemImage: "arrow.clockwise")
            }
            .disabled(checking)
            .accessibilityIdentifier("recheck-spot")
        } header: {
            SectionHeader("This week")
        } footer: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                CheckStatus(spot: spot).accessibilityIdentifier("week-checked")
                Text("Moon-free minutes: astronomy-engine on this phone\(spot.week?.terrainAware == true ? ", above this spot's skyline" : ", flat horizon (\(Voice.estimated))"). Verdict: the worst gating factor over moon-free darkness.")
            }
            .font(.dsFootnote)
            .foregroundStyle(palette.secondary)
        }
        .paletteRow(palette)
    }

    func check() async {
        guard !checking else { return }
        checking = true
        await SpotRefresh.check(spot, conditions: conditions, background: false)
        try? context.save()
        checking = false
    }

    func pin(_ on: Bool) {
        for other in spots where other.isPinned && other !== spot { other.isPinned = false }
        spot.isPinned = on
        widgetShared = WidgetBridge.publish(on ? spot : nil)
        try? context.save()
    }

    func delete() {
        if spot.isPinned { WidgetBridge.publish(nil) }
        context.delete(spot)
        try? context.save()
        dismiss()
    }
}

/// The selected night: verdict, limiting factor with source and age, minutes.
struct NightDetail: View {
    @Environment(\.palette) private var palette
    let night: NightSummary
    let timeZone: TimeZone
    let terrainAware: Bool

    @ViewBuilder private var minutesLine: some View {
        if terrainAware, let sky = night.skylineMoonFreeMinutes {
            minutes(sky, "min above the skyline")
            // The comparison only when the skyline changes something.
            if let flat = night.moonFreeMinutes, flat != sky {
                Text("flat horizon \(flat) min (\(sky - flat > 0 ? "+" : "")\(sky - flat))")
                    .font(.dsData).foregroundStyle(palette.secondary)
            }
        } else if let flat = night.moonFreeMinutes {
            minutes(flat, "min moon-free, flat horizon")
        } else {
            UnavailableValue(reason: "moon-free minutes")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text(night.date.map { SpotRefresh.weekdayLabel($0, timeZone: timeZone) } ?? night.night)
                    .font(.dsHeadline)
                    .foregroundStyle(palette.primary)
                Spacer()
                let level = StatusLevel(night.verdict?.level, moonFreeMinutes: night.headlineMinutes)
                StatusBadge(level: level, qualifier: level == .moonUp ? nil : qualifier)
                    .accessibilityIdentifier("night-verdict")
            }
            if let v = night.verdict {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("\(v.level == .go ? "Closest to its limit" : "Limited by") \(v.limitingLine)")
                        .font(.dsCallout)
                        .foregroundStyle(palette.primary)
                    ProvenanceChip(info: SourceInfo(source: v.limitingSource, asOf: v.limitingAsOf, freshness: v.freshness))
                }
            }
            // One line while it fits; the flat-horizon comparison goes under it at large sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { minutesLine }
                VStack(alignment: .leading, spacing: DS.Space.xxs) { minutesLine }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("night-minutes")
        }
    }

    var qualifier: String? {
        switch night.verdict?.cause {
        case .incompleteData: "incomplete data"
        case .staleData: "stale data"
        default: nil
        }
    }

    func minutes(_ n: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text("\(n)").font(.dsMetric).foregroundStyle(palette.primary)
            Text(label).font(.dsFootnote).foregroundStyle(palette.secondary)
        }
    }
}

/// Attach, compute, show and remove the spot's horizon profile (M9).
struct HorizonSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Bindable var spot: Spot
    let onChange: () -> Void

    @State private var importing = false
    @State private var error: String?
    @State private var phase: TerrainHorizon.Phase?
    @State private var job: Task<Void, Never>?

    var atCandlestick: Bool { MeasuredHorizons.isAtCandlestick(latitude: spot.latitude, longitude: spot.longitude) }
    var nearCandlestick: Bool { MeasuredHorizons.offersCandlestick(latitude: spot.latitude, longitude: spot.longitude) }
    var computed: Bool { spot.horizonSource?.hasPrefix("Computed") == true }

    var body: some View {
        Section {
            if let profile = spot.horizonProfile {
                let measured = atCandlestick && computed ? MeasuredHorizons.candlestickProfile() : nil
                SkylineChart(profile: profile, reference: measured)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(String(format: "Skyline %.1f° to %.1f°", profile.minAltitudeDeg, profile.maxAltitudeDeg))
                        .font(.dsCallout)
                    if let source = spot.horizonSource { Text(source).font(.dsData).foregroundStyle(palette.secondary) }
                    if let measured {
                        let c = MeasuredHorizons.compare(profile, to: measured)
                        Text(String(format: "Against the measured profile (dashed): RMS %.3f°, mean %+.2f°", c.rms, c.mean))
                            .font(.dsData)
                            .accessibilityIdentifier("horizon-rms")
                    }
                }
            } else {
                Text("No horizon profile: moon-free minutes are \(Voice.estimated) with a flat horizon.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }

            if let phase {
                VStack(alignment: .leading, spacing: 4) {
                    PaletteProgress(value: phase.fraction)
                    HStack {
                        Text(phase.label).font(.caption).foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("horizon-progress")
                        Spacer()
                        Button("Cancel") { job?.cancel() }.accessibilityIdentifier("horizon-cancel")
                    }
                }
            } else {
                if nearCandlestick {
                    Button(atCandlestick ? "Use the measured Candlestick Camp profile"
                           : "Reuse Candlestick Camp's measured profile (surveyed nearby)") { useMeasured() }
                        .accessibilityIdentifier("horizon-measured")
                }
                Button(spot.horizonCSV == nil ? "Compute from terrain" : "Recompute from terrain") { compute() }
                    .accessibilityIdentifier("horizon-compute")
                Button("Import CSV…") { importing = true }
                    .accessibilityIdentifier("horizon-import")
                if spot.horizonCSV != nil {
                    Button("Remove profile", role: .destructive) { set(nil, source: nil) }
                        .foregroundStyle(palette.poor)
                        .accessibilityIdentifier("horizon-remove")
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(palette.poor).accessibilityIdentifier("horizon-error")
            }
        } header: {
            SectionHeader("Horizon")
        } footer: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Computing downloads about 36 AWS Terrain Tiles (z12, ~5 MB) around this spot's 0.05° cell and traces terrain within 16 km, with earth curvature and refraction. The profile is saved with the spot, so it works offline.")
                if computed || phase != nil {
                    Text(TerrainHorizon.attribution)
                    Link("Terrain data sources", destination: TerrainHorizon.attributionURL)
                }
                Text("CSV format: azimuth_deg,horizon_alt_deg (config/horizon-profiles).")
            }
            .font(.caption)
            .foregroundStyle(palette.secondary)
        }
        .paletteRow(palette)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            importCSV(result)
        }
        .onDisappear { job?.cancel() }
    }

    func set(_ profile: HorizonProfile?, source: String?) {
        spot.horizonCSV = profile?.csv()
        spot.horizonSource = source
        spot.horizonUpdatedAt = profile == nil ? nil : .now
        try? context.save()
        onChange()
    }

    func useMeasured() {
        error = nil
        guard let p = MeasuredHorizons.candlestickProfile() else {
            error = "The bundled Candlestick profile is unavailable."
            return
        }
        set(p, source: MeasuredHorizons.candlestickSource(latitude: spot.latitude, longitude: spot.longitude))
    }

    func importCSV(_ result: Result<URL, any Error>) {
        error = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            let profile = try HorizonProfile.parse(csv: text)
            set(profile, source: "Imported from \(url.lastPathComponent), \(Date.now.formatted(date: .abbreviated, time: .omitted))")
        } catch let e as HorizonProfile.ParseError {
            error = "Not a horizon profile: \(Self.describe(e))"
        } catch {
            self.error = "Could not read that file: \(error.localizedDescription)"
        }
    }

    func compute() {
        error = nil
        let (lat, lon) = (spot.latitude, spot.longitude)
        phase = .downloading(done: 0, total: TerrainHorizon.tileIDs(latitude: lat, longitude: lon).count)
        job = Task {
            do {
                let out = try await TerrainHorizon.compute(latitude: lat, longitude: lon) { p in
                    Task { @MainActor in if phase != nil { phase = p } }
                }
                phase = nil
                set(out.profile, source: String(
                    format: "Computed on this phone from AWS Terrain Tiles (z12, 16 km), %@; %d tiles (%d downloaded) in %.2f s, traced in %.2f s",
                    Date.now.formatted(date: .abbreviated, time: .shortened), out.tileCount, out.downloaded,
                    out.loadSeconds, out.traceSeconds))
            } catch is CancellationError {
                phase = nil
                error = "Cancelled; the previous profile is unchanged."
            } catch {
                phase = nil
                self.error = "Could not compute: \(error.localizedDescription)"
            }
        }
    }

    static func describe(_ e: HorizonProfile.ParseError) -> String {
        switch e {
        case .badHeader(let h): "the first line must be azimuth_deg,horizon_alt_deg (found \"\(h.prefix(40))\")"
        case .badRow(let line, _): "line \(line) is not two numbers"
        case .azimuthOutOfRange(let line, _): "line \(line): azimuth outside 0–359"
        case .altitudeOutOfRange(let line, _): "line \(line): altitude outside −90–90"
        case .azimuthsNotIncreasing(let line): "line \(line): azimuths must increase"
        case .empty: "no rows"
        }
    }
}
