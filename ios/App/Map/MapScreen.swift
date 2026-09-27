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
    @State private var plan: MapPlan?
    @State private var darkness: TimeWindow?
    @State private var moonFree: [TimeWindow] = []
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
                    VStack(spacing: DS.Space.cardGap) {
                        placeSection
                        linesSection
                        if !inspection.isEmpty { tappedSection }
                        layersSection
                        offlineSection
                    }
                    .padding(.horizontal, DS.Space.screen)
                    .padding(.top, DS.Space.xs)
                    .padding(.bottom, DS.Space.xl)
                }
            }
            .background(palette.background)
            .screenChrome("Map")
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
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, DS.Space.xs)
                    .floatingSurface(palette, shape: Capsule())
                    .padding(DS.Space.s)
                    .allowsHitTesting(false)
            }
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
            rows.append("IR \(MapData.utc(t, withDate: false))Z · \(Voice.age(of: t, now: now))")
        }
        if visible.contains(.smoke) {
            rows.append(data.smokeAnalysis.end.map { "Smoke \(MapData.utc($0, withDate: false))Z · \(Voice.age(of: $0, now: now))" }
                ?? "Smoke \(Voice.unavailable)")
        }
        for layer in [MapLayer.lightPollution, .land, .places] where visible.contains(layer) {
            let name = layer == .land ? "PAD-US" : layer == .places ? "dark-sky places" : "light pollution"
            switch data.origin(layer) {
            case .real: break
            case .fixture: rows.append("\(name.capitalizedFirst): sample fixture")
            case .unknown: rows.append("\(name.capitalizedFirst): origin not confirmed")
            }
        }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(rows, id: \.self) { Text($0) }
                }
                .font(.dsData)
                .foregroundStyle(palette.primary)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs + 2)
                .floatingSurface(palette, shape: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .padding(DS.Space.s)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.ages")
    }

    private var colors: MapColors { MapColors(palette, field: state.fieldMode) }

    @ViewBuilder private var scrubber: some View {
        if let plan {
            NightScrubber(window: plan.window, darkness: darkness, moonFree: moonFree,
                          timeZone: state.place?.timeZone ?? .current, time: $time)
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.s)
                .background(palette.background)
        }
    }

    // MARK: Panel

    private var placeSection: some View {
        SectionCard("Place") {
            if let place = state.place {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(place.name).font(.dsTitle).foregroundStyle(palette.primary)
                    Text("\(CoordinateText.format(latitude: place.latitude, longitude: place.longitude)) · \(Format.zone(place.timeZone)) · night of \(Format.nightTitle(state.night()))")
                        .font(.dsData)
                        .foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("map.placeLabel")
                }
                landAtPin
            } else {
                Text("No place yet. Type coordinates, pick a saved spot, or long-press the map.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                TextField("", text: $coordText, prompt: Text("lat, lon  e.g. 38.3740, -109.9654").foregroundStyle(palette.secondary))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.dsNumber)
                    .foregroundStyle(palette.primary)
                    .tint(palette.accent)
                    .padding(.horizontal, DS.Space.m)
                    .frame(minHeight: DS.minTarget)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .accessibilityIdentifier("map.coordinateField")
                    .focused($coordFocused)
                    .onSubmit(setTypedPlace)
                Button("Set", action: setTypedPlace)
                    .buttonStyle(ActionButtonStyle(.primary, compact: true))
                    .accessibilityLabel("Set place")
                    .accessibilityIdentifier("map.setPlace")
            }
            if let coordError {
                Text(coordError).font(.dsFootnote).foregroundStyle(palette.poor)
            }
            if !spots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(spots) { spot in
                            Button(spot.name) { state.place = spot.place }
                                .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                                .accessibilityLabel("Use saved spot \(spot.name)")
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
            Text(text).font(.dsFootnote).foregroundStyle(palette.primary)
        }
    }

    private var linesSection: some View {
        SectionCard("Azimuth lines") {
            if plan == nil {
                Text("Set a place to draw sun, moon and Galactic Center lines.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            } else {
                let tz = state.place?.timeZone ?? .current
                let features = drawnFeatures
                let summary = features.map { MapPlanner.label(for: $0.line, timeZone: tz) }
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: DS.Space.s) {
                        Capsule().fill(palette.color(for: f.line.object)).frame(width: 14, height: f.line.event == .atTime ? 5 : 3)
                        Text(summary[i])
                            .font(f.line.event == .atTime ? .dsCallout.weight(.semibold).monospacedDigit() : .dsFootnote.monospacedDigit())
                            .foregroundStyle(f.belowHorizon ? palette.tertiary : palette.primary)
                    }
                }
                ProvenanceChip(info: SourceInfo(source: "astronomy-engine", note: "\(Voice.onDevice), refracted, flat horizon"))
                Color.clear.frame(height: 0)
                    .accessibilityElement()
                    .accessibilityIdentifier("map.lineSummary")
                    .accessibilityLabel(summary.joined(separator: "; "))
            }
        }
    }

    private var tappedSection: some View {
        SectionCard("Tapped on the map") {
            ForEach(Array(inspection.enumerated()), id: \.offset) { _, item in
                Group {
                    switch item {
                    case let .place(name, designation, verified, _):
                        Text("\(name), \(designation)\(verified.map { " (verified \($0))" } ?? "")\(data.origin(.places).caveat.map { " \($0)" } ?? "")")
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
                .font(.dsFootnote)
                .foregroundStyle(palette.primary)
            }
        }
    }

    private var layersSection: some View {
        SectionCard("Layers") {
            ForEach(MapLayer.allCases) { layer in
                let p = data.provenance(layer)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Toggle(isOn: binding(layer)) {
                        Text(layer.title).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                    }
                    .toggleStyle(PaletteToggleStyle())
                    .accessibilityIdentifier("layer.\(layer.rawValue)")
                    ProvenanceChip(info: SourceInfo(source: p.source, asOf: layerAsOf(layer), freshness: p.freshness,
                                                    note: layerStatus(layer, p) ?? p.license))
                    if visible.contains(layer) { legend(layer) }
                    if layer == .infrared, visible.contains(.infrared), !data.irFrames.isEmpty {
                        HStack(spacing: DS.Space.s) {
                            Button { irPlaying.toggle() } label: {
                                Image(systemName: irPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                            .accessibilityLabel(irPlaying ? "Pause loop" : "Play loop")
                            Text("Frame \(MapData.utc(data.irFrames[irIndex % data.irFrames.count], withDate: true))")
                                .font(.dsData).foregroundStyle(palette.primary)
                        }
                    }
                }
                if layer != MapLayer.allCases.last {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                }
            }
            MoreInfo(title: "About these layers", id: "map.layerDetails") {
                ForEach(MapLayer.allCases) { layer in
                    let p = data.provenance(layer)
                    Text("\(layer.title): \(p.detail) License: \(p.license).")
                }
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
        SectionCard("Offline") {
            Text("Published layers are kept on the phone and work at every saved spot without signal. Smoke and the IR loop are live; offline they show their \(Voice.lastGood) with its age.")
                .font(.dsFootnote).foregroundStyle(palette.secondary)
            ForEach([MapLayer.lightPollution, .land, .places]) { layer in
                let a = data.archive(layer)
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(layer.title).font(.dsCallout).foregroundStyle(palette.primary)
                        Text(a.onPhone ? "On this phone\(a.bytes.map { ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")"
                            : "Not saved\(a.bytes.map { " (" + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + ")" } ?? "")")
                            .font(.dsData)
                            .foregroundStyle(a.onPhone ? palette.secondary : palette.marginal)
                            .accessibilityIdentifier("offline.\(layer.rawValue)")
                    }
                    Spacer()
                    if !a.onPhone {
                        Button { Task { await data.keepOffline(layer) } } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                        .accessibilityLabel("Keep \(layer.title) offline")
                    }
                }
            }
        }
    }

    /// What the chip counts the layer's age from (live layers only).
    private func layerAsOf(_ layer: MapLayer) -> Date? {
        switch layer {
        case .smoke: data.smokeAnalysis.end
        case .infrared: data.irFrames.last
        default: nil
        }
    }

    /// A short state in the one voice, or nil when there is nothing to say.
    private func layerStatus(_ layer: MapLayer, _ p: LayerProvenance) -> String? {
        switch layer {
        case .lightPollution, .land, .places:
            switch data.origin(layer) {
            case .fixture: return "sample fixture"
            case .unknown: return "origin not confirmed"
            case .real: return p.freshness == .unavailable ? Voice.unavailable : nil
            }
        case .smoke:
            if data.smoke == nil { return Voice.unavailable }
            return data.failed.contains("hms/smoke.geojson") ? Voice.lastGood : nil
        case .infrared:
            return data.irFrames.isEmpty ? Voice.unavailable : nil
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
            moonFree = []
            eventFeatures = []
            return
        }
        let night = state.night()
        guard let p = try? MapPlanner.plan(pin: pin, night: night, timeZone: place.timeZone) else { plan = nil; return }
        plan = p
        rebuildEvents()
        let report = try? Planner.planNight(pin, evening: night.evening(in: place.timeZone))
        darkness = report?.darkness
        moonFree = report?.moonFreeWindows.map { TimeWindow(start: $0.start, end: $0.end) } ?? []
        let now = Date.now
        let start = p.window.start <= now && now <= p.window.end ? now : (darkness?.start ?? p.window.start)
        time = TimeScrubber.snap(start, across: p.window, step: NightScrubber.step)
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
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(palette.hairline, lineWidth: 0.5))
                    Text(label).font(.caption).foregroundStyle(palette.secondary)
                }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
