import CoreLocation
import SkyCore
import SwiftData
import SwiftUI

/// M6 map planner. The map fills the tab; the panel is a bottom sheet over it
/// (review B-6). Everything the map can set (the place, the time, the layers)
/// is also set from the sheet (invariant 5). The map draws the shot plan's
/// target at the chosen time; the Sun/Moon/GC rise-transit-set fan is the
/// optional Compare view (product review §4).
struct MapScreen: View {
    @Environment(AppState.self) var state
    @Environment(\.palette) var palette
    @Query(sort: \Spot.createdAt) var spots: [Spot]

    @State var data = MapData()
    @State var controller = MapController()
    @State var plan: MapPlan?
    @State var darkness: TimeWindow?
    @State var moonFree: [TimeWindow] = []
    @State var time = Date.now
    @State var zoom = 5.0
    @State var shortSide = 390.0
    @State var styleURL: URL?
    @State var coordText = ""
    @State var coordError: String?
    @State var inspection: [MapInspection] = []
    @State var pinLand: [String]?
    @State var irIndex = 0
    @State var irPlaying = true
    @State var timing = ""
    @FocusState var coordFocused: Bool
    @State var eventFeatures: [MapLineFeature] = []
    @State var detent = MapSheetDetent.peek
    @State var peekHeight: CGFloat = 110
    @State var obstructions: [String: CGRect] = [:]
    @State var outerBottomInset: CGFloat = 0
    @State var hiddenLabels: [String] = []
    @State var shownLabelFrames: [CGRect] = []
    /// A long-press drops a candidate; nothing changes until "Plan here" (review B-9).
    @State var candidate: GeoCoordinate?
    @State var resolving = false
    @State var undo: UndoOffer?
    @AppStorage("map.visibleLayers") var visibleRaw = MapLayer.defaultVisible.map(\.rawValue).sorted().joined(separator: ",")
    @AppStorage("map.compare") var compare = false
    /// The shot window's target (`ShotWindowCard` writes it); the map draws its line.
    @AppStorage(ShotPlan.storageKey) var shotPlan = ShotPlan()

    struct UndoOffer: Identifiable {
        let id = UUID()
        let text: String
        let snapshot: AppState.PlaceSnapshot
    }

    init() {
        // UI tests start from the default layers, whatever a previous run left on.
        if ProcessInfo.processInfo.arguments.contains("-resetMapState") {
            UserDefaults.standard.removeObject(forKey: "map.visibleLayers")
            UserDefaults.standard.removeObject(forKey: "map.compare")
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // The field dock is a safe-area inset outside this stack, which
                // the stack doesn't pass on: keep the sheet above it by hand.
                let dock = max(0, outerBottomInset - geo.safeAreaInsets.bottom)
                ZStack(alignment: .top) {
                    mapArea(insets: mapInsets(geo, dock: dock))
                        .ignoresSafeArea()
                    topScrim(geo.safeAreaInsets.top)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            irBadge
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                        if detent != .full { bottomOverlays }
                        MapSheet(detent: $detent, peekHeight: $peekHeight, available: geo.size.height - dock) {
                            peek
                        } content: {
                            panel
                        }
                        .layoutPriority(1)
                    }
                    .padding(.bottom, dock)
                }
                .onPreferenceChange(MapObstructionKey.self) { obstructions = $0 }
            }
            .background(palette.background)
            .screenChrome("Map")
            // The map runs under the bar in both modes (a scrim keeps the title
            // legible), so the collapsed sheet leaves most of the screen to it.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { outerBottomInset = $0 }
        .onAppear {
            if MapTiming.tabAppeared == nil { MapTiming.tabAppeared = CACurrentMediaTime() }
            state.restoreRememberedPlace()
        }
        .task { await refreshLoop() }
        .task(id: planKey) { replan() }
        .onChange(of: lengthMeters) { rebuildEvents() }
        .onChange(of: coordFocused) { _, focused in
            if focused { withAnimation(.snappy(duration: 0.25)) { detent = .full } }
        }
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
        .task(id: undo?.id) {
            guard undo != nil else { return }
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { withAnimation { undo = nil } }
        }
    }

    // MARK: Map

    /// The map keeps its centre and lines clear of the bar and the resting sheet.
    private func mapInsets(_ geo: GeometryProxy, dock: CGFloat) -> UIEdgeInsets {
        let rest = MapSheet<EmptyView, EmptyView>.height(min(detent, .half), peek: peekHeight, available: geo.size.height - dock)
        return UIEdgeInsets(top: geo.safeAreaInsets.top, left: 0, bottom: geo.safeAreaInsets.bottom + dock + rest, right: 0)
    }

    @ViewBuilder private func mapArea(insets: UIEdgeInsets) -> some View {
        if let styleURL {
            PlannerMapView(
                snapshot: snapshot(styleURL, insets: insets),
                controller: controller,
                onLongPress: { c in
                    withAnimation(.snappy(duration: 0.2)) {
                        undo = nil
                        candidate = GeoCoordinate(latitude: c.latitude, longitude: c.longitude)
                    }
                },
                onCamera: { z, side in
                    zoom = z
                    shortSide = side
                },
                onInspect: { inspection = $0 },
                onPinLand: { pinLand = $0 },
                onTiming: { timing = $0 },
                onLabels: { hidden, shown in
                    hiddenLabels = hidden
                    shownLabelFrames = shown
                })
            .overlay {
                // Field mode: multiply everything the map draws by pure red, so
                // no basemap, raster or label pixel keeps any green or blue.
                if state.fieldMode {
                    Color(red: 1, green: 0, blue: 0).blendMode(.multiply).allowsHitTesting(false)
                }
            }
            .overlay {
                Color.clear.allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("map.timing")
                    .accessibilityLabel(timing)
            }
            .background {
                // Where the declutter put each shown label, for the UI tests.
                Color.clear
                    .accessibilityElement()
                    .accessibilityIdentifier("map.labelFrames")
                    .accessibilityLabel(shownLabelFrames.map { String(format: "%.0f,%.0f,%.0f,%.0f", $0.minX, $0.minY, $0.width, $0.height) }
                        .joined(separator: ";"))
            }
        } else {
            palette.background
        }
    }

    /// Keeps the title and field toggle legible over a light basemap.
    private func topScrim(_ height: CGFloat) -> some View {
        LinearGradient(colors: [palette.background.opacity(0.85), palette.background.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height + DS.Space.l)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private func snapshot(_ url: URL, insets: UIEdgeInsets) -> MapSnapshot {
        let tz = state.place?.timeZone ?? .current
        let target = targetLine
        let now = compareAtTime
        let events = compare ? eventFeatures : []
        var labels: [MapLabel] = []
        if let target, let pin = plan?.pin.coordinate {
            labels.append(MapLabel(key: "target", text: target.label, body: target.body, priority: 0, start: pin,
                                   end: target.coordinates[target.coordinates.count - 1], emphasized: true,
                                   stops: MapLabelLayout.midStops))
        }
        for f in now {
            labels.append(MapLabel(f, text: MapPlanner.label(for: f.line, timeZone: tz), priority: 1, stops: MapLabelLayout.midStops))
        }
        for f in events {
            labels.append(MapLabel(f, text: MapPlanner.label(for: f.line, timeZone: tz), priority: 2, stops: MapLabelLayout.endStops))
        }
        return MapSnapshot(
            styleURL: url, colors: colors,
            pin: state.place.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
            candidate: candidate,
            eventLines: events, atTimeLines: now, target: target, labels: labels,
            visible: visible, smoke: data.smoke, irFrames: data.irFrames, irIndex: irIndex,
            insets: insets, obstructions: Array(obstructions.values))
    }

    /// Line length for the current zoom, in 5% steps so small zooms don't rebuild the event lines.
    private var lengthMeters: Double {
        let m = MapPlanner.lineLengthMeters(zoom: zoom, latitude: state.place?.latitude ?? 39, viewportShortSidePoints: shortSide)
        return pow(1.05, (log(m) / log(1.05)).rounded())
    }

    /// The shot target at the scrubber's time: the map's main line.
    var targetLine: MapTargetLine? {
        guard let plan, let place = state.place, let p = try? shotPlan.target.position(plan.pin, at: time) else { return nil }
        let n = min(256, max(1, Int((lengthMeters / MapPlanner.maxSegmentMeters).rounded(.up))))
        let coords = Geodesy.path(from: plan.pin.coordinate, azimuthDeg: p.azimuthDeg, distanceMeters: lengthMeters, segments: n)
        let az = Int(Geodesy.normalizedAzimuth(p.azimuthDeg.rounded()))
        let alt = p.altitudeDeg < 0 ? "below horizon" : "\(Int(p.altitudeDeg.rounded()))° up"
        return MapTargetLine(
            name: shotPlan.target.name, body: CelestialBody(shotPlan.target), position: p, coordinates: coords,
            label: "\(shotPlan.target.shortName) \(MapPlanner.clock(time, timeZone: place.timeZone)) · \(az)° · \(alt)")
    }

    /// Compare view: Sun/Moon/GC at the scrubber's time, less the target's own body.
    var compareAtTime: [MapLineFeature] {
        guard compare, let plan else { return [] }
        let skip: SkyObject? = switch shotPlan.target {
        case .galacticCore: .galacticCenter
        case .moon: .moon
        default: nil
        }
        return AzimuthLines.mapObjects.filter { $0 != skip }.compactMap { object in
            plan.series[object].flatMap {
                AzimuthLines.line(object: object, series: $0, at: time, from: plan.pin.coordinate, lengthMeters: lengthMeters)
            }
        }.map { MapPlanner.feature($0) }
    }

    private func rebuildEvents() {
        guard let plan else { eventFeatures = []; return }
        eventFeatures = MapPlanner.features(plan.lines(at: nil, lengthMeters: lengthMeters))
    }

    /// Only time-sensitive imagery carries its age on the map: the IR loop's
    /// frame. Every other layer's age is on its row in the sheet.
    @ViewBuilder private var irBadge: some View {
        if visible.contains(.infrared) {
            let text = data.irFrames.isEmpty
                ? "IR \(Voice.unavailable)"
                : { let t = data.irFrames[irIndex % data.irFrames.count]
                    return "IR \(MapData.utc(t, withDate: false))Z · \(Voice.age(of: t, now: .now))" }()
            Text(text)
                .font(.dsData)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs)
                .floatingSurface(palette, shape: Capsule())
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .padding(DS.Space.s)
                .allowsHitTesting(false)
                .accessibilityIdentifier("map.ages")
                .mapObstruction("badge")
        }
    }

    // MARK: Over the map, above the sheet

    private var bottomOverlays: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s) {
            HStack(alignment: .bottom, spacing: DS.Space.s) {
                MapAttributionOverlay(controller: controller)
                    .mapObstruction("attribution")
                Spacer(minLength: 0)
                MapOverlayControls(
                    controller: controller, hasPin: state.place != nil,
                    centerOnPin: centerOnPin, planHere: planAtMyLocation)
                    .mapObstruction("controls")
            }
            if candidate != nil || resolving || undo != nil {
                banner.mapObstruction("banner")
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.bottom, DS.Space.s)
    }

    @ViewBuilder private var banner: some View {
        Group {
            if resolving {
                Text("Looking up the time zone…")
                    .font(.dsCallout).foregroundStyle(palette.primary)
                    .frame(maxWidth: .infinity, minHeight: DS.minTarget, alignment: .leading)
            } else if let c = candidate {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Plan for this point?").font(.dsHeadline).foregroundStyle(palette.primary)
                        Text(Format.coordinate(c.latitude, c.longitude))
                            .font(.dsData).foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("map.candidate.coordinates")
                    }
                    HStack(spacing: DS.Space.s) {
                        Button("Cancel") { withAnimation { candidate = nil } }
                            .buttonStyle(ActionButtonStyle(.secondary))
                            .accessibilityIdentifier("map.candidate.cancel")
                        Button("Plan here", action: confirmCandidate)
                            .buttonStyle(ActionButtonStyle(.primary))
                            .accessibilityIdentifier("map.candidate.confirm")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map.candidate")
            } else if let undo {
                HStack(spacing: DS.Space.s) {
                    Text(undo.text).font(.dsCallout).foregroundStyle(palette.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Undo") { restore(undo) }
                        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                        .accessibilityIdentifier("map.undo")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map.undoBar")
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingSurface(palette, shape: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: The sheet's peek: place, basemap, the target line

    private var peek: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            if let place = state.place {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(place.name).font(.dsHeadline).foregroundStyle(palette.primary).lineLimit(1)
                        // Coordinates, zone and night are in the Place card; VoiceOver hears them here.
                        .accessibilityLabel("\(place.name), \(placeDetail(place))")
                        .accessibilityIdentifier("map.placeLabel")
                    Spacer(minLength: DS.Space.s)
                    basemapName
                }
                if let t = targetLine {
                    HStack(spacing: DS.Space.s) {
                        LineSwatch(object: t.body, emphasized: true)
                        Text(t.label)
                            .font(.dsCallout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(t.position.altitudeDeg < 0 ? palette.secondary : palette.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("map.peekSummary")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text("No place yet").font(.dsHeadline).foregroundStyle(palette.primary)
                    Spacer(minLength: DS.Space.s)
                    basemapName
                }
                Text("Long-press the map to drop a pin, or open the panel to type coordinates.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }
            if let notice = sampleNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.dsFootnote)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("map.sampleNotice")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.screen)
        .padding(.bottom, DS.Space.s)
        // The peek sits over the map, so it caps its type like the map's other
        // overlays (DESIGN rule 7); the panel above it follows Dynamic Type in full.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    func placeDetail(_ place: Place) -> String {
        "\(CoordinateText.format(latitude: place.latitude, longitude: place.longitude)) · \(Format.zone(place.timeZone)) · night of \(Format.nightTitle(state.night()))"
    }

    private var basemapName: some View {
        Text(controller.basemap(field: state.fieldMode).title)
            .font(.dsData)
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .accessibilityLabel("Basemap: \(controller.basemap(field: state.fieldMode).title)")
            .accessibilityIdentifier("map.peekBasemap")
    }

    /// The one sample-data note (product review §3/§4). Nothing answers from these layers.
    var sampleNotice: String? {
        let shown = [MapLayer.lightPollution, .land].filter { visible.contains($0) && data.origin($0) != .real }
        guard !shown.isEmpty else { return nil }
        let names = shown.map { $0 == .land ? "land manager" : "light pollution" }.joined(separator: ", ")
        let unconfirmed = shown.allSatisfy { data.origin($0) == .unknown }
        return unconfirmed ? "Origin not confirmed yet: \(names)" : "Sample data on this build: \(names)"
    }

    var colors: MapColors { MapColors(palette, field: state.fieldMode) }

    // MARK: State

    var visible: Set<MapLayer> {
        Set(visibleRaw.split(separator: ",").compactMap { MapLayer(rawValue: String($0)) })
    }

    func binding(_ layer: MapLayer) -> Binding<Bool> {
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

    // MARK: Place changes (all through `AppState.choose`)

    func setTypedPlace() {
        coordFocused = false
        guard let c = CoordinateText.parse(coordText) else {
            coordError = "Enter latitude and longitude in degrees, e.g. 38.3740, -109.9654."
            return
        }
        coordError = nil
        Task {
            resolving = true
            let choice = await PlaceChoice.coordinates(latitude: c.latitude, longitude: c.longitude,
                                                       name: Format.coordinate(c.latitude, c.longitude))
            resolving = false
            state.choose(choice)
        }
    }

    private func confirmCandidate() {
        guard let c = candidate else { return }
        let before = state.placeSnapshot()
        resolving = true
        Task {
            let choice = await PlaceChoice.coordinates(latitude: c.latitude, longitude: c.longitude, name: "Dropped pin")
            state.choose(choice)
            withAnimation(.snappy(duration: 0.2)) {
                resolving = false
                candidate = nil
                undo = UndoOffer(text: "Planning for this pin", snapshot: before)
            }
        }
    }

    /// "Plan here" at the GPS fix: changes the planning place, not the camera.
    private func planAtMyLocation(_ c: CLLocationCoordinate2D) {
        let before = state.placeSnapshot()
        resolving = true
        Task {
            let choice = await PlaceChoice.coordinates(latitude: c.latitude, longitude: c.longitude, name: "My location")
            state.choose(choice)
            withAnimation(.snappy(duration: 0.2)) {
                resolving = false
                candidate = nil
                undo = UndoOffer(text: "Planning for your location", snapshot: before)
            }
        }
    }

    private func restore(_ offer: UndoOffer) {
        state.restore(offer.snapshot)
        withAnimation { undo = nil }
    }

    private func centerOnPin() {
        guard let p = state.place else { return }
        controller.center(on: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
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

extension MapSheetDetent: Comparable {
    static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Frames of what floats over the map, in window coordinates: line labels keep out of them.
struct MapObstructionKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func mapObstruction(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: MapObstructionKey.self, value: [id: g.frame(in: .global)])
        })
    }
}

/// A line's key: the body's color and pattern, as on the map.
struct LineSwatch: View {
    let object: CelestialBody
    var emphasized = false
    var below = false
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
            ctx.stroke(path, with: .color(CelestialStyle.color(object, palette).opacity(below ? 0.45 : 1)),
                       style: StrokeStyle(lineWidth: emphasized ? 3.5 : 2, lineCap: .round, dash: CelestialStyle.dash(object)))
        }
        .frame(width: 22, height: 8)
        .accessibilityHidden(true)
    }
}
