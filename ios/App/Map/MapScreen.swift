import CoreLocation
import SkyCore
import SwiftData
import SwiftUI

/// M6 map planner. The map adds context; everything it can set (the place,
/// the time, the layers) is also set from the panel beneath it (invariant 5).
struct MapScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Query(sort: \Spot.createdAt) private var spots: [Spot]

    @State private var data = MapData()
    @State private var controller = MapController()
    @State private var plan: MapPlan?
    @State private var darkness: TimeWindow?
    @State private var time = Date.now
    @State private var zoom = 5.0
    @State private var shortSide = 390.0
    @State private var styleURL: URL?
    @State private var coordText = ""
    @State private var coordError: String?
    @State private var inspection: [MapInspection] = []
    @State private var pinLand: [String]?
    @State private var irIndex = 0
    @State private var irPlaying = true
    @State private var timing = ""
    @FocusState private var coordFocused: Bool
    @State private var eventFeatures: [MapLineFeature] = []
    @AppStorage("map.visibleLayers") private var visibleRaw = MapLayer.defaultVisible.map(\.rawValue).sorted().joined(separator: ",")

    init() {
        // UI tests start from the default layers, whatever a previous run left on.
        if ProcessInfo.processInfo.arguments.contains("-resetMapState") {
            UserDefaults.standard.removeObject(forKey: "map.visibleLayers")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                scrubber
                ScrollView {
                    VStack(spacing: 12) {
                        placeSection
                        linesSection
                        if !inspection.isEmpty { tappedSection }
                        BasemapSection(data: data, controller: controller)
                        layersSection
                        offlineSection
                        OfflineAreasSection(controller: controller)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Map").font(.headline).foregroundStyle(palette.primary)
                }
                ToolbarItem(placement: .topBarTrailing) { fieldToggle }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        .onAppear { if MapTiming.tabAppeared == nil { MapTiming.tabAppeared = CACurrentMediaTime() } }
        .task { await refreshLoop() }
        .task(id: planKey) { replan() }
        .onChange(of: lengthMeters) { rebuildEvents() }
        .task(id: StyleKey(field: state.fieldMode, revision: data.styleRevision)) {
            styleURL = MapStyle.write(data: data, colors: colors)
        }
        .task(id: irPlaying && visible.contains(.infrared) && data.irFrames.count > 1) {
            guard irPlaying, visible.contains(.infrared), data.irFrames.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                irIndex = (irIndex + 1) % data.irFrames.count
            }
        }
    }

    // MARK: Map

    @ViewBuilder private var mapArea: some View {
        if let styleURL {
            PlannerMapView(
                snapshot: snapshot(styleURL),
                controller: controller,
                onDropPin: dropPin,
                onCamera: { z, side in
                    zoom = z
                    shortSide = side
                },
                onInspect: { inspection = $0 },
                onPinLand: { pinLand = $0 },
                onTiming: { timing = $0 })
            .overlay {
                // Field mode: multiply everything the map draws by pure red, so
                // no basemap, raster or label pixel keeps any green or blue.
                if state.fieldMode {
                    Color(red: 1, green: 0, blue: 0).blendMode(.multiply).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) { ageBadge }
            .overlay {
                Color.clear.allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("map.timing")
                    .accessibilityLabel(timing)
            }
            .overlay(alignment: .bottomLeading) {
                Text(state.place == nil ? "Long-press to drop a pin" : "Long-press to move the pin")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
                    .padding(6)
                    .background(palette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) { MapAttributionOverlay(controller: controller) }
            .overlay(alignment: .bottomTrailing) { MapOverlayControls(controller: controller).padding(.bottom, 14) }
        } else {
            palette.background
        }
    }

    private func snapshot(_ url: URL) -> MapSnapshot {
        let now = atTimeFeatures
        let tz = state.place?.timeZone ?? .current
        return MapSnapshot(
            styleURL: url, colors: colors,
            pin: state.place.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
            eventLines: eventFeatures, atTimeLines: now,
            labels: (eventFeatures + now).map { MapPlanner.label(for: $0.line, timeZone: tz) },
            visible: visible, smoke: data.smoke, irFrames: data.irFrames, irIndex: irIndex)
    }

    /// Line length for the current zoom, in 5% steps so small zooms don't rebuild the event lines.
    private var lengthMeters: Double {
        let m = MapPlanner.lineLengthMeters(zoom: zoom, latitude: state.place?.latitude ?? 39, viewportShortSidePoints: shortSide)
        let step = pow(1.05, (log(m) / log(1.05)).rounded())
        return step
    }

    /// Only these three lines change as the scrubber moves.
    private var atTimeFeatures: [MapLineFeature] {
        guard let plan else { return [] }
        return AzimuthLines.mapObjects.compactMap { object in
            plan.series[object].flatMap {
                AzimuthLines.line(object: object, series: $0, at: time, from: plan.pin.coordinate, lengthMeters: lengthMeters)
            }
        }.map { MapPlanner.feature($0) }
    }

    private func rebuildEvents() {
        guard let plan else { eventFeatures = []; return }
        eventFeatures = MapPlanner.features(plan.lines(at: nil, lengthMeters: lengthMeters))
    }

    private var drawnFeatures: [MapLineFeature] { eventFeatures + atTimeFeatures }

    /// Age of what the map is showing, on the map itself (ADR-0006).
    private var ageBadge: some View {
        let now = Date.now
        var rows: [String] = []
        if visible.contains(.infrared), !data.irFrames.isEmpty {
            let t = data.irFrames[irIndex % data.irFrames.count]
            rows.append("IR \(MapData.utc(t, withDate: false))Z · \(MapData.age(t, now: now)) old")
        }
        if visible.contains(.smoke) {
            rows.append(data.smokeAnalysis.end.map { "Smoke analysis \(MapData.utc($0, withDate: false))Z · \(MapData.age($0, now: now)) old" }
                ?? "Smoke unavailable")
        }
        for layer in [MapLayer.lightPollution, .land, .places] where visible.contains(layer) {
            let name = layer == .land ? "PAD-US" : layer == .places ? "dark-sky places" : "light pollution"
            switch data.origin(layer) {
            case .real: break
            case .fixture: rows.append("Sample fixture: \(name)")
            case .unknown: rows.append("Unconfirmed origin: \(name)")
            }
        }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(rows, id: \.self) { Text($0) }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(palette.primary)
        .padding(rows.isEmpty ? 0 : 6)
        .background(palette.background.opacity(rows.isEmpty ? 0 : 0.8), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .allowsHitTesting(false)
        .accessibilityIdentifier("map.ages")
    }

    private var colors: MapColors { MapColors(palette, field: state.fieldMode) }

    @ViewBuilder private var scrubber: some View {
        if let plan {
            NightScrubber(window: plan.window, darkness: darkness, timeZone: state.place?.timeZone ?? .current, time: $time)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.background)
        }
    }

    // MARK: Panel

    private var placeSection: some View {
        MapSection(title: "Place") {
            if let place = state.place {
                Text(place.name).font(.headline).foregroundStyle(palette.primary)
                Text("\(CoordinateText.format(latitude: place.latitude, longitude: place.longitude)) · \(place.timeZoneID) · night of \(state.night().iso)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("map.placeLabel")
                landAtPin
            } else {
                Text("No place yet. Type coordinates, pick a saved spot, or long-press the map.")
                    .font(.footnote).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                TextField("", text: $coordText, prompt: Text("lat, lon  e.g. 38.3740, -109.9654").foregroundStyle(palette.secondary))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(palette.primary)
                    .tint(palette.accent)
                    .padding(8)
                    .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.secondary, lineWidth: 1))
                    .accessibilityIdentifier("map.coordinateField")
                    .focused($coordFocused)
                    .onSubmit(setTypedPlace)
                PaletteButton("Set", label: "Set place") { setTypedPlace() }
                    .accessibilityIdentifier("map.setPlace")
            }
            if let coordError {
                Text(coordError).font(.footnote).foregroundStyle(palette.poor)
            }
            if !spots.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(spots) { spot in
                            PaletteButton(spot.name, label: "Use saved spot \(spot.name)") { state.place = spot.place }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder private var landAtPin: some View {
        if visible.contains(.land) {
            let text: String = {
                switch data.origin(.land) {
                case .real: break
                case .fixture: return "Land manager: withheld, the PAD-US layer is a sample fixture."
                case .unknown: return "Land manager: withheld, the PAD-US layer's origin is not confirmed (data-status.json not loaded)."
                }
                guard let keys = pinLand else { return "Land manager: move the map so the pin is in view to read it." }
                if keys.isEmpty { return "Land manager: no PAD-US boundary here (private or undetermined)." }
                let labels = Array(Set(keys.map { ManagerTaxonomy.bundled.label(for: $0) })).sorted()
                return "Managed by \(labels.joined(separator: ", ")) (PAD-US). Check the manager's rules for camping and night access."
            }()
            Text(text).font(.footnote).foregroundStyle(palette.primary)
        }
    }

    private var linesSection: some View {
        MapSection(title: "Azimuth lines") {
            if plan == nil {
                Text("Set a place to draw sun, moon and Galactic Center lines.")
                    .font(.footnote).foregroundStyle(palette.secondary)
            } else {
                let tz = state.place?.timeZone ?? .current
                let features = drawnFeatures
                let summary = features.map { MapPlanner.label(for: $0.line, timeZone: tz) }
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: 8) {
                        Capsule().fill(palette.swatchFor(f.line.object)).frame(width: 14, height: f.line.event == .atTime ? 5 : 3)
                        Text(summary[i])
                            .font(f.line.event == .atTime ? .callout.weight(.semibold).monospacedDigit() : .footnote.monospacedDigit())
                            .foregroundStyle(f.belowHorizon ? palette.secondary : palette.primary)
                    }
                }
                Text("Computed on this phone (astronomy-engine); apparent positions with standard refraction, mathematical horizon.")
                    .font(.caption2).foregroundStyle(palette.secondary)
                Color.clear.frame(height: 0)
                    .accessibilityElement()
                    .accessibilityIdentifier("map.lineSummary")
                    .accessibilityLabel(summary.joined(separator: "; "))
            }
        }
    }

    private var tappedSection: some View {
        MapSection(title: "Tapped on the map") {
            ForEach(Array(inspection.enumerated()), id: \.offset) { _, item in
                Group {
                    switch item {
                    case let .place(name, designation, verified, _):
                        Text("\(name), \(designation)") + Text(verified.map { " (verified \($0))" } ?? "")
                            + Text(data.origin(.places).caveat.map { " \($0)" } ?? "")
                    case let .land(key):
                        if data.origin(.land) != .real {
                            Text("PAD-US: \(data.origin(.land) == .fixture ? "sample fixture" : "origin not confirmed"), land manager withheld.")
                        } else {
                            Text("Managed by \(ManagerTaxonomy.bundled.label(for: key)) (PAD-US). Check the manager's rules for camping and night access.")
                        }
                    case let .smoke(density, satellite, start, end):
                        Text("Smoke, \(density ?? "density not given") (HMS, \(satellite ?? "?"), \(start.flatMap(HMSSmoke.time).map { MapData.utc($0, withDate: false) } ?? "?")–\(end.flatMap(HMSSmoke.time).map { MapData.utc($0, withDate: true) } ?? "?"))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(palette.primary)
            }
        }
    }

    private var layersSection: some View {
        MapSection(title: "Layers") {
            ForEach(MapLayer.allCases) { layer in
                let p = data.provenance(layer)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: binding(layer)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.title).font(.callout.weight(.semibold)).foregroundStyle(palette.primary)
                            Text("\(p.source) · \(p.license) · \(p.freshness.label)")
                                .font(.caption).foregroundStyle(p.freshness == .fresh ? palette.secondary : palette.marginal)
                        }
                    }
                    .toggleStyle(MapToggleStyle())
                    .accessibilityIdentifier("layer.\(layer.rawValue)")
                    Text(p.detail).font(.caption2).foregroundStyle(palette.secondary)
                    legend(layer)
                    if layer == .infrared, visible.contains(.infrared), !data.irFrames.isEmpty {
                        HStack {
                            PaletteButton(systemImage: irPlaying ? "pause.fill" : "play.fill", label: irPlaying ? "Pause loop" : "Play loop") {
                                irPlaying.toggle()
                            }
                            Text("Frame \(MapData.utc(data.irFrames[irIndex % data.irFrames.count], withDate: true))")
                                .font(.caption.monospacedDigit()).foregroundStyle(palette.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func legend(_ layer: MapLayer) -> some View {
        switch layer {
        case .land:
            FlowSwatches(items: ManagerTaxonomy.bundled.entries.map { ($0.label, $0.color) }, field: state.fieldMode)
        case .lightPollution:
            FlowSwatches(items: RadianceLegend.bundled.map { ($0.label, $0.color) }, field: state.fieldMode)
        default:
            EmptyView()
        }
    }

    /// PMTiles archives are single AOI-wide files, so a whole copy on the phone
    /// covers every saved spot. MapLibre offline packs can't take them: its
    /// offline downloader rejects `pmtiles://` sources ("unsupported URL").
    private var offlineSection: some View {
        MapSection(title: "Offline") {
            Text("Published layers are kept on the phone as whole files and work at every saved spot without signal. Smoke and the IR loop are live; offline they show the last copy with its age.")
                .font(.caption2).foregroundStyle(palette.secondary)
            ForEach([MapLayer.lightPollution, .land, .places]) { layer in
                let a = data.archive(layer)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.title).font(.callout).foregroundStyle(palette.primary)
                        Text(a.onPhone ? "On this phone\(a.bytes.map { ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")"
                            : "Not saved\(a.bytes.map { " (" + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + ")" } ?? "")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(a.onPhone ? palette.secondary : palette.marginal)
                            .accessibilityIdentifier("offline.\(layer.rawValue)")
                    }
                    Spacer()
                    if !a.onPhone {
                        PaletteButton(systemImage: "arrow.down.circle", label: "Keep \(layer.title) offline") {
                            Task { await data.keepOffline(layer) }
                        }
                    }
                }
            }
        }
    }

    // MARK: State

    private var visible: Set<MapLayer> {
        Set(visibleRaw.split(separator: ",").compactMap { MapLayer(rawValue: String($0)) })
    }

    private func binding(_ layer: MapLayer) -> Binding<Bool> {
        Binding(
            get: { visible.contains(layer) },
            set: { on in
                var v = visible
                if on { v.insert(layer) } else { v.remove(layer) }
                visibleRaw = v.map(\.rawValue).sorted().joined(separator: ",")
            })
    }

    private var planKey: String {
        guard let p = state.place else { return "none" }
        return "\(p.latitude),\(p.longitude),\(p.timeZoneID),\(state.night().iso)"
    }

    private func replan() {
        guard let place = state.place, let pin = try? place.observer() else {
            plan = nil
            darkness = nil
            eventFeatures = []
            return
        }
        let night = state.night()
        guard let p = try? MapPlanner.plan(pin: pin, night: night, timeZone: place.timeZone) else { plan = nil; return }
        plan = p
        rebuildEvents()
        darkness = try? Planner.darknessWindow(pin, evening: night.evening(in: place.timeZone)).window
        let now = Date.now
        let start = p.window.start <= now && now <= p.window.end ? now : (darkness?.start ?? p.window.start)
        time = TimeScrubber.snap(start, across: p.window, step: NightScrubber.step)
    }

    /// Same state as the shell's `FieldModeToggle`, drawn from the palette so
    /// no glass or white glyph shows in field mode.
    private var fieldToggle: some View {
        @Bindable var state = state
        return Button { state.fieldMode.toggle() } label: {
            Image(systemName: "moon.stars")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 40, height: 40)
                .background(state.fieldMode ? palette.surface : palette.background, in: Circle())
                .overlay(Circle().stroke(palette.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Field mode")
        .accessibilityValue(state.fieldMode ? "On" : "Off")
        .accessibilityHint("Switches the whole app to dim red")
    }

    private func setTypedPlace() {
        coordFocused = false
        guard let c = CoordinateText.parse(coordText) else {
            coordError = "Enter latitude and longitude in degrees, e.g. 38.3740, -109.9654."
            return
        }
        coordError = nil
        setPlace(latitude: c.latitude, longitude: c.longitude, name: "Entered coordinates")
    }

    private func dropPin(_ c: CLLocationCoordinate2D) {
        setPlace(latitude: c.latitude, longitude: c.longitude, name: "Dropped pin")
    }

    private func setPlace(latitude: Double, longitude: Double, name: String) {
        let fallback = state.place?.timeZone ?? .current
        state.place = Place(name: name, latitude: latitude, longitude: longitude, timeZoneID: fallback.identifier)
        Task {
            let tz = await PlaceTimeZone.resolve(latitude: latitude, longitude: longitude, fallback: fallback)
            if let p = state.place, p.latitude == latitude, p.longitude == longitude, p.timeZoneID != tz.identifier {
                state.place = Place(name: p.name, latitude: latitude, longitude: longitude, timeZoneID: tz.identifier)
            }
        }
    }

    /// GIBS publishes a frame every 10 min, HMS a few analyses a day, the
    /// Pages layers monthly at most: each is checked on its own cadence.
    private func refreshLoop() async {
        await data.refreshAll()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await data.refreshDue(irVisible: visible.contains(.infrared))
        }
    }

    private struct StyleKey: Hashable {
        let field: Bool
        let revision: Int
    }
}

/// `radiance_mapping.breakpoints` from the bundled `config/app-config.json` (ADR-0005).
enum RadianceLegend {
    struct Entry: Decodable { let color: String; let label: String }
    private struct File: Decodable {
        struct Mapping: Decodable { let breakpoints: [Entry] }
        let radiance_mapping: Mapping
    }

    static let bundled: [Entry] = (try? JSONDecoder().decode(File.self, from: SharedResources.data("app-config.json")).radiance_mapping.breakpoints) ?? []
}

private struct FlowSwatches: View {
    let items: [(String, String)]
    let field: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.0) { label, hex in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.swatch(hex, field: field)).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.secondary, lineWidth: 0.5))
                    Text(label).font(.caption2).foregroundStyle(palette.secondary)
                }
            }
        }
    }
}

extension Palette {
    func swatchFor(_ object: SkyObject) -> Color {
        switch object {
        case .sun: marginal
        case .galacticCenter: accent
        default: primary
        }
    }
}
