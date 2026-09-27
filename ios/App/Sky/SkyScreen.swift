import SkyCore
import SwiftData
import SwiftUI

/// Night AR (M7): the Milky Way, the GC's path by hour, the Moon, planets,
/// cardinal points and the terrain horizon over the back camera, placed by
/// Core Motion attitude against true north (not ARKit world tracking).
struct SkyScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Spot.createdAt) private var spots: [Spot]

    @State private var sensors = SkySensors()
    @State private var camera = SkyCamera()
    @State private var session = SkySession()
    @State private var fallback = SkyFallbackCache()
    @State private var meter = FrameMeter(enabled: SimulatedSky.showsFrameStats)
    @State private var summaries = SummaryThrottle()
    @State private var model: SkyModel?
    @State private var scrubTime: Date?
    @State private var simulatedByChoice = false
    @State private var calibrating = false
    @State private var calibrationChoice: CalibrationTarget?
    @State private var visible = false
    @State private var layers = SkyLayers()
    @State private var panel: SkyPanel?
    @State private var findTarget: SkyFindTarget?
    @State private var trail: StarTrailSequence?
    @State private var look = SimulatedLook()
    @State private var lookAtDragStart: SimulatedLook?
    @State private var lookAtPinchStart: SimulatedLook?
    @State private var realismCache = SkyRealismCache()
    @State private var readout = SkyFrameReadout()
    @Environment(\.skyRadiants) private var radiantProvider

    static let arConfig = try? AppConfig.bundled().arOverlay

    /// Why the view is simulated, or nil for real sensors. Never chosen
    /// silently on a device: only the Simulator or the owner's tap gets here.
    private var simulatedReason: String? {
        #if targetEnvironment(simulator)
        return "The Simulator has no camera or motion sensors."
        #else
        return simulatedByChoice ? "Chosen instead of the sensors." : nil
        #endif
    }

    private var isLive: Bool { simulatedReason == nil }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            content
        }
        .statusBarHidden(state.fieldMode)
        .onAppear {
            visible = true
            updateSensors()
        }
        .onDisappear {
            visible = false
            updateSensors()
        }
        .onChange(of: scenePhase) { updateSensors() }
        .onChange(of: simulatedByChoice) { updateSensors() }
        .onChange(of: state.fieldMode, initial: true) { sensors.allowsSystemHeadingPrompt = !state.fieldMode }
    }

    @ViewBuilder private var content: some View {
        if let reason = simulatedReason {
            let demo = SimulatedSky.place(state.place)
            sky(place: demo.place, horizon: demo.horizon ?? horizon(for: demo.place), simulated: reason)
        } else if !sensors.motionHardware {
            explanation(
                "This iPhone can't tell where it's pointing",
                "The Sky view needs the motion sensors and compass, and they are not available right now.",
                "gyroscope")
        } else {
            switch sensors.locationAccess {
            case .denied, .restricted:
                explanation(
                    "Location is off for Dark Sky",
                    "The Sky view needs your location for true north and to work out where the Milky Way, Moon and planets are. It never leaves the phone.",
                    "location.slash", settings: true)
            case .notDetermined:
                explanation("Allow location to start", "Dark Sky asks once. Your location stays on the phone.", "location")
            case .granted:
                if let place = state.place ?? sensors.here {
                    sky(place: place, horizon: horizon(for: place), simulated: nil)
                } else {
                    explanation("Finding your location…", "Waiting for a first fix. Under open sky this takes a few seconds.", "location.magnifyingglass")
                }
            }
        }
    }

    private func explanation(_ title: String, _ message: String, _ image: String, settings: Bool = false) -> some View {
        SkyExplanation(title: title, message: message, systemImage: image) {
            if settings { OpenSettingsButton() }
            Button("Show simulated view") { simulatedByChoice = true }.buttonStyle(SkyButtonStyle())
        }
    }

    // MARK: - The sky

    private func sky(place: Place, horizon: HorizonProfile?, simulated: String?) -> some View {
        let pinned = simulated == nil ? nil : SimulatedSky.pinnedTime
        let night = pinned.map { NightDate.containing($0, in: place.timeZone) }
            ?? state.chosenNight ?? NightDate.containing(.now, in: place.timeZone)
        // Live: the span also covers the next hours from now, refreshed hourly.
        let liveHour = simulated == nil ? Int(Date.now.timeIntervalSince1970 / 3600) : nil
        let key = SkyModel.Key(place: place, night: night, liveHour: liveHour)
        return Group {
            if let model, model.key.matches(place, night) {
                sky(place: place, model: model, horizon: horizon, simulated: simulated, pinned: pinned)
            } else {
                SkyExplanation(title: "Working out tonight's sky…", message: place.name, systemImage: "sparkles") { EmptyView() }
            }
        }
        .task(id: key) {
            let computed = await SkyModel.compute(key)
            if let computed {
                model = computed
                meter.recordModel(computed.computeTime, samples: computed.ephemeris.span.duration / 60 + 1)
            } else if model?.key.matches(place, night) != true { model = nil }
            restoreCalibration(for: place, simulated: simulated != nil)
        }
    }

    @ViewBuilder
    private func sky(place: Place, model: SkyModel, horizon: HorizonProfile?, simulated: String?, pinned: Date?) -> some View {
        let demoTime = pinned ?? SimulatedSky.defaultTime(model.track)
        GeometryReader { geo in
            ZStack {
                backdrop(simulated: simulated != nil)
                if simulated != nil, !SimulatedSky.sweeps {
                    overlay(place: place, model: model, horizon: horizon, size: geo.size,
                            attitude: look.attitude, time: scrubTime ?? demoTime, simulated: true)
                        .contentShape(Rectangle())
                        .gesture(lookGesture(size: geo.size))
                } else {
                    TimelineView(.animation) { tick in
                        if simulated != nil {
                            overlay(place: place, model: model, horizon: horizon, size: geo.size,
                                    attitude: SimulatedSky.sweepAttitude(at: tick.date), time: scrubTime ?? demoTime, simulated: true)
                        } else if let attitude = sensors.attitude() {
                            overlay(place: place, model: model, horizon: horizon, size: geo.size,
                                    attitude: attitude, time: scrubTime ?? tick.date, simulated: false)
                        } else {
                            waitingForMotion(since: sensors.motionStartedAt, now: tick.date)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .overlay {
            controls(place: place, model: model, horizon: horizon, simulated: simulated,
                     time: scrubTime ?? (simulated != nil ? demoTime : .now))
        }
    }

    @ViewBuilder private func backdrop(simulated: Bool) -> some View {
        Group {
            if simulated || layers.planetarium {
                // The simulated sky is drawn per frame by the overlay's backdrop shader.
                Color.black
            } else if camera.access == .granted {
                CameraPreview(camera: camera)
            } else {
                palette.background
            }
        }
        .modifier(FieldTint(on: state.fieldMode, tint: palette.accent))
        .accessibilityHidden(true)
    }

    private func overlay(
        place: Place, model: SkyModel, horizon: HorizonProfile?, size: CGSize,
        attitude raw: DeviceAttitude, time: Date, simulated: Bool
    ) -> some View {
        let start = ContinuousClock.now
        let scene = model.ephemeris.scene(at: time) ?? fallback.scene(place: place, at: time)
        let planetarium = simulated || layers.planetarium
        var backdropParams: SkyBackdropParams?
        let input = scene.map { scene in
            let projector = SkyProjector(attitude: raw.applying(session.calibration), intrinsics: viewIntrinsics(size: size, simulated: simulated))
            var input = SkyOverlayInput(
                projector: projector,
                scene: scene, track: model.track, horizon: horizon,
                style: style(simulated: simulated), timeZone: place.timeZone, crosshair: calibrating,
                planetarium: planetarium, showsMilkyWayBand: layers.milkyWay)
            if let stars = model.stars, let observer = try? place.observer() {
                let built = SkyRealismBuilder(
                    stars: stars, observer: observer, projector: projector, time: time, scene: scene, layers: layers,
                    horizon: realismCache.horizonLookup(horizon), horizonProfile: horizon, planetarium: planetarium,
                    fieldMode: state.fieldMode, find: findTarget, trail: trail,
                    radiants: radiants(at: time), cache: realismCache
                ).build()
                input.realism = built.frame
                backdropParams = built.backdrop
                readout.find = built.frame.find.map { ($0.name, $0.guidance) }
                readout.trails = built.frame.trails
                readout.limitingMagnitude = built.frame.limitingMagnitude
                readout.announceFindProgress()
            }
            return input
        }
        let summary = input.map { summaries.summary(for: $0) } ?? ""
        meter.recordPrepare(ContinuousClock.now - start)
        return ZStack {
            if let backdropParams {
                SkyBackdropView(params: backdropParams)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            if let input {
                SkyOverlayView(input: input, summary: summary, meter: meter)
            }
        }
    }

    private func radiants(at time: Date) -> [SkyRadiant] {
        (radiantProvider ?? SimulatedSky.demoRadiants)?.radiants(activeAt: time) ?? []
    }

    /// Drag to look around the simulated sky, pinch to change the lens.
    private func lookGesture(size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { g in
                let base = lookAtDragStart ?? look
                if lookAtDragStart == nil { lookAtDragStart = look }
                let degPerPoint = base.fieldOfViewDeg / max(size.height, 1)
                look = base.panned(dx: g.translation.width * degPerPoint, dy: g.translation.height * degPerPoint)
            }
            .onEnded { _ in lookAtDragStart = nil }
        let pinch = MagnifyGesture()
            .onChanged { g in
                let base = lookAtPinchStart ?? look
                if lookAtPinchStart == nil { lookAtPinchStart = look }
                look = base.zoomed(by: g.magnification)
            }
            .onEnded { _ in lookAtPinchStart = nil }
        return drag.simultaneously(with: pinch)
    }

    /// The camera model in view points: from where the preview layer says
    /// it draws the image when it can, else the same aspect-fill arithmetic.
    private func viewIntrinsics(size: CGSize, simulated: Bool) -> CameraIntrinsics {
        if simulated {
            return CameraIntrinsics(longSideFieldOfViewDeg: look.fieldOfViewDeg, width: 1080, height: 1920)
                .aspectFilled(toWidth: size.width, height: size.height)
        }
        let lens = camera.lens ?? .assumed
        if lens.source != .assumed, let rect = camera.displayedImageRect() {
            return lens.intrinsics.placed(
                inImageRectX: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                viewWidth: size.width, viewHeight: size.height)
        }
        return lens.intrinsics.aspectFilled(toWidth: size.width, height: size.height)
    }

    private func waitingForMotion(since: Date?, now: Date) -> some View {
        let stalled = since.map { now.timeIntervalSince($0) > 4 } ?? false
        return SkyExplanation(
            title: stalled ? "No motion data yet" : "Starting the motion sensors…",
            message: stalled
                ? "Core Motion has not reported an attitude. True north needs a location fix; step away from the car and wait, or reopen the Sky tab."
                : "Hold the phone upright and point it at the sky.",
            systemImage: "gyroscope") { EmptyView() }
    }

    // MARK: - Controls

    private func controls(place: Place, model: SkyModel, horizon: HorizonProfile?, simulated: String?, time: Date) -> some View {
        let style = style(simulated: simulated != nil)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sky").font(.title2.weight(.bold)).foregroundStyle(palette.primary)
                    Text(place.name + (horizon != nil ? " · terrain horizon" : ""))
                        .font(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                FieldModeToggle().tint(palette.accent).accessibilityIdentifier("sky.fieldMode")
            }
            if let simulated {
                SkyPill(text: "Simulated view · \(SimulatedSky.sweeps ? "sweeping around S" : look.description) · \(simulated)", color: palette.primary)
                    .accessibilityIdentifier("sky.simulated")
            }
            if findTarget != nil {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    if let find = readout.find {
                        SkyPill(text: "\(find.name): \(find.guidance.spoken)", color: palette.accent)
                            .accessibilityIdentifier("sky.find.guidance")
                    }
                }
            }
            HStack(spacing: 8) {
                HeadingBadge(text: headingText(simulated: simulated != nil), style: style)
                Button(calibrating ? "Calibrating" : "Calibrate") {
                    calibrationChoice = nil
                    calibrating.toggle()
                }
                .buttonStyle(SkyButtonStyle())
                .accessibilityIdentifier("sky.calibrate")
            }
            if isLive, camera.access == .denied || camera.access == .restricted {
                HStack {
                    Text("Camera is off for Dark Sky, so the overlay is drawn on black.")
                        .font(.caption).foregroundStyle(palette.secondary)
                    OpenSettingsButton()
                }
            }
            if !style.isConfident {
                Text(approximateNote(style))
                    .font(.caption).foregroundStyle(palette.marginal)
                    .padding(8)
                    .background(palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("sky.approximate")
            }
            if meter.enabled {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    SkyPill(text: meter.summary, color: palette.secondary)
                        .accessibilityIdentifier("sky.frameStats")
                }
            }
            Spacer()
            if !calibrating {
                HStack(spacing: 8) {
                    panelButton("Find", .find, "sky.find")
                    panelButton("Trails", .trails, "sky.trails")
                    panelButton("Show", .layers, "sky.layers")
                }
            }
            if !calibrating, let panel {
                Group {
                    switch panel {
                    case .find:
                        SkyFindPanel(
                            items: { findItems($0, place: place, model: model, time: time) }, target: $findTarget,
                            canPoint: simulated != nil, onPoint: { pointSimulated(at: findTarget, place: place, model: model, time: time) },
                            onClose: { self.panel = nil })
                    case .trails:
                        SkyTrailPanel(
                            sequence: $trail, start: time, timeZone: place.timeZone, readout: readout,
                            canPoint: simulated != nil, onPointAtPole: { pointSimulatedAtPole(place: place, time: time) },
                            onClose: { self.panel = nil })
                    case .layers:
                        SkyLayersPanel(layers: $layers, isLive: simulated == nil, limitingMagnitude: readout.limitingMagnitude,
                                       onClose: { self.panel = nil })
                    }
                }
                .padding(12)
                .background(palette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
            }
            Group {
                if calibrating {
                    CalibrationPanel(
                        targets: calibrationTargets(place: place, model: model, at: simulated == nil ? .now : time),
                        choice: $calibrationChoice,
                        isCalibrated: session.isCalibrated,
                        onAlign: { align($0, place: place, time: simulated == nil ? .now : time, simulated: simulated != nil) },
                        onReset: {
                            session.reset(persist: simulated == nil)
                            calibrating = false
                        },
                        onCancel: { calibrating = false })
                } else {
                    // Live "Now" keeps ticking without redrawing the whole screen.
                    TimelineView(.periodic(from: .now, by: 15)) { tick in
                        SkyScrubber(
                            window: model.window, time: simulated == nil && scrubTime == nil ? tick.date : time,
                            timeZone: place.timeZone,
                            isLive: simulated == nil && scrubTime == nil, canGoLive: simulated == nil,
                            onScrub: { scrubTime = $0 }, onLive: { scrubTime = nil })
                    }
                }
            }
            .padding(12)
            .background(palette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func panelButton(_ title: String, _ which: SkyPanel, _ id: String) -> some View {
        Button(title) { panel = panel == which ? nil : which }
            .buttonStyle(SkyButtonStyle(prominent: panel == which))
            .accessibilityAddTraits(panel == which ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    // MARK: - Find

    private func findItems(_ kind: SkyFindPanel.Kind, place: Place, model: SkyModel, time: Date) -> [SkyFindItem] {
        guard let stars = model.stars, let observer = try? place.observer(),
              let scene = model.ephemeris.scene(at: time) ?? fallback.scene(place: place, at: time) else { return [] }
        let builder = SkyRealismBuilder(
            stars: stars, observer: observer, projector: SkyProjector(attitude: look.attitude, intrinsics: LensModel.assumed.intrinsics),
            time: time, scene: scene, layers: layers, horizon: HorizonLookup(nil), horizonProfile: nil, planetarium: false,
            fieldMode: false, find: nil, trail: nil, radiants: radiants(at: time), cache: realismCache)
        let rotation = SkyRotation.eqjToReference(at: time, observer: observer)
        let targets: [SkyFindTarget] = switch kind {
        case .constellations: stars.catalog.constellations.map { .constellation($0.abbreviation) }
        case .stars: stars.catalog.names.keys.sorted { stars.catalog.star(hr: $0)!.vmag < stars.catalog.star(hr: $1)!.vmag }.map { .star(hr: $0) }
        case .planets: NightSkyScene.objects.map { .body($0) }
        case .showers: radiants(at: time).map { .radiant(id: $0.id) }
        }
        let items = targets.compactMap { t in
            builder.resolve(t, rotation: rotation).map { SkyFindItem(target: t, name: $0.0, altitudeDeg: $0.1.altitudeDeg) }
        }
        // What is up first, then alphabetical (constellations) or by brightness (stars).
        let up = items.filter { $0.altitudeDeg > 0 }, down = items.filter { $0.altitudeDeg <= 0 }
        return kind == .constellations
            ? up.sorted { $0.name < $1.name } + down.sorted { $0.name < $1.name }
            : up + down
    }

    private func pointSimulated(at target: SkyFindTarget?, place: Place, model: SkyModel, time: Date) {
        guard let target, let stars = model.stars, let observer = try? place.observer(),
              let scene = model.ephemeris.scene(at: time) ?? fallback.scene(place: place, at: time) else { return }
        let builder = SkyRealismBuilder(
            stars: stars, observer: observer, projector: SkyProjector(attitude: look.attitude, intrinsics: LensModel.assumed.intrinsics),
            time: time, scene: scene, layers: layers, horizon: HorizonLookup(nil), horizonProfile: nil, planetarium: false,
            fieldMode: false, find: nil, trail: nil, radiants: radiants(at: time), cache: realismCache)
        guard let (_, position) = builder.resolve(target, rotation: SkyRotation.eqjToReference(at: time, observer: observer)) else { return }
        look.point(at: position)
    }

    private func pointSimulatedAtPole(place: Place, time: Date) {
        guard let observer = try? place.observer() else { return }
        look.point(at: StarTrails.pole(at: time, observer: observer))
    }

    private func headingAccuracy(simulated: Bool) -> Double {
        simulated ? SimulatedSky.headingAccuracyDeg : sensors.headingAccuracyDeg
    }

    private func style(simulated: Bool) -> OverlayStyle {
        guard let config = Self.arConfig else { return .approximate(uncertaintyDeg: nil) }
        let heading = HeadingConfidence(headingAccuracyDeg: headingAccuracy(simulated: simulated), config: config)
        return OverlayStyle(heading: heading, calibrated: session.isCalibrated)
    }

    private func headingText(simulated: Bool) -> String {
        let accuracy = headingAccuracy(simulated: simulated)
        var text = simulated ? "Simulated compass" : "Compass"
        if accuracy >= 0, accuracy.isFinite {
            text += " ±\(Int(accuracy.rounded()))°"
        } else {
            text += simulated ? " invalid" : (sensors.headingHardware ? " not valid yet" : " unavailable")
        }
        if let target = session.calibratedOn {
            text += String(format: " · calibrated on %@ (%+.1f°)", target, session.calibration.offsetDeg)
            if session.restored { text += ", restored" }
        }
        return text
    }

    private func approximateNote(_ style: OverlayStyle) -> String {
        let why = if case .approximate(let u?) = style {
            "The compass reports ±\(Int(u.rounded()))°, so positions are approximate (rings show the error)."
        } else {
            "No valid compass heading, so positions may be far off."
        }
        return why + " Calibrate on the Moon, a planet or a saved peak."
    }

    // MARK: - Calibration

    private func calibrationTargets(place: Place, model: SkyModel, at date: Date) -> [CalibrationTarget] {
        var out: [CalibrationTarget] = []
        if let scene = model.ephemeris.scene(at: date) ?? fallback.scene(place: place, at: date) {
            for body in scene.bodies where body.object != .galacticCenter && body.position.altitudeDeg > 0 {
                out.append(.body(body.object))
            }
        }
        let here = GeoCoordinate(latitude: place.latitude, longitude: place.longitude)
        for spot in spots {
            let there = GeoCoordinate(latitude: spot.latitude, longitude: spot.longitude)
            // A landmark must be far enough that a few metres of standing position don't matter.
            guard let d = Geodesy.inverse(from: here, to: there)?.distanceMeters, d > 500, d < 150_000 else { continue }
            out.append(.landmark(name: spot.name, latitude: spot.latitude, longitude: spot.longitude))
        }
        return out
    }

    private func align(_ target: CalibrationTarget, place: Place, time: Date, simulated: Bool) {
        let raw = simulated ? look.attitude : sensors.attitude()
        guard let raw, let computed = target.azimuthDeg(from: place, at: time) else { return }
        let aligned = SkyProjector(attitude: raw, intrinsics: LensModel.assumed.intrinsics).boresight.azimuthDeg
        session.calibrate(
            HeadingCalibration(computedAzimuthDeg: computed, alignedAzimuthDeg: aligned), on: target.name,
            at: place, persist: !simulated)
        calibrating = false
    }

    private func restoreCalibration(for place: Place, simulated: Bool) {
        guard !simulated, !session.isCalibrated else { return }
        session.restore(at: place)
    }

    // MARK: - Lifecycle

    private func updateSensors() {
        let run = visible && isLive && scenePhase == .active
        if run {
            sensors.start()
            camera.start()
        } else {
            sensors.stop()
            camera.stop()
        }
        UIApplication.shared.isIdleTimerDisabled = run
    }

    private func horizon(for place: Place) -> HorizonProfile? {
        guard let spot = spots.first(where: { $0.place == place }), let csv = spot.horizonCSV else { return nil }
        return fallback.horizon(csv: csv)
    }
}

/// Dims the picture and keeps only red in field mode, so no white or blue
/// pixel from the camera reaches the screen.
private struct FieldTint: ViewModifier {
    let on: Bool
    let tint: Color

    func body(content: Content) -> some View {
        if on {
            content.colorMultiply(tint).opacity(0.5)
        } else {
            content
        }
    }
}

/// The night the overlay draws, computed off the main actor: the scrubber's
/// window, the GC's path and per-minute positions to interpolate each frame.
nonisolated struct SkyModel: Sendable {
    /// Plain values: `Place` and its conformances are main-actor isolated.
    struct Key: Hashable, Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timeZoneID: String
        let night: NightDate
        /// Live mode also covers the hours from now (for daytime or after-dawn use).
        let liveHour: Int?

        @MainActor init(place: Place, night: NightDate, liveHour: Int?) {
            name = place.name
            latitude = place.latitude
            longitude = place.longitude
            timeZoneID = place.timeZoneID
            self.night = night
            self.liveHour = liveHour
        }

        @MainActor func matches(_ place: Place, _ night: NightDate) -> Bool {
            name == place.name && latitude == place.latitude && longitude == place.longitude && self.night == night
        }
    }

    let key: Key
    let window: TimeWindow
    let track: GCTrack
    let ephemeris: SkyEphemeris
    let stars: SkyStars?
    let computeTime: Duration


    @concurrent
    static func compute(_ key: Key) async -> SkyModel? {
        let clock = ContinuousClock.now
        guard let observer = try? Observer(latitude: key.latitude, longitude: key.longitude),
              let window = try? Planner.skyNightWindow(
                observer, night: key.night, timeZone: TimeZone(identifier: key.timeZoneID) ?? .current),
              let track = try? GCTrack.across(window, observer: observer) else { return nil }
        var start = window.start, end = window.end
        if let hour = key.liveHour {
            let now = Date(timeIntervalSince1970: Double(hour) * 3600)
            start = min(start, now)
            end = max(end, now.addingTimeInterval(3 * 3600))
        }
        guard let ephemeris = try? SkyEphemeris.compute(observer: observer, span: TimeWindow(start: start, end: end)) else { return nil }
        let stars = SkyStars.compute(epoch: window.start.addingTimeInterval(window.duration / 2))
        return SkyModel(key: key, window: window, track: track, ephemeris: ephemeris, stars: stars, computeTime: ContinuousClock.now - clock)
    }
}

/// Where the simulated view looks: drag to turn, pinch to zoom. Starts
/// facing south, 20° up, through a typical phone lens.
struct SimulatedLook: Equatable {
    var azimuthDeg = 180.0
    var pitchDeg = 20.0
    var fieldOfViewDeg = 68.0

    var attitude: DeviceAttitude { .upright(facingAzimuth: azimuthDeg, pitchDeg: pitchDeg) }

    var description: String {
        "facing \(CompassPoint.abbreviation(forAzimuth: azimuthDeg)), \(Int(pitchDeg.rounded()))° up, \(Int(fieldOfViewDeg.rounded()))° lens · drag to look, pinch to zoom"
    }

    /// Content follows the finger: dragging right turns left.
    func panned(dx: Double, dy: Double) -> SimulatedLook {
        var next = self
        next.azimuthDeg = Geodesy.normalizedAzimuth(azimuthDeg - dx)
        next.pitchDeg = min(max(pitchDeg + dy, -10), 89)
        return next
    }

    func zoomed(by magnification: Double) -> SimulatedLook {
        var next = self
        next.fieldOfViewDeg = min(max(fieldOfViewDeg / max(magnification, 0.1), 15), 120)
        return next
    }

    mutating func point(at position: HorizontalPosition) {
        azimuthDeg = position.azimuthDeg
        pitchDeg = min(max(position.altitudeDeg, -10), 89)
    }
}

/// The fixed, labelled stand-in for the sensors.
enum SimulatedSky {
    /// `-SkyDemoRadiants YES`: a Perseids radiant with typical IMO values
    /// (labelled "demo", not checked against the 2026 calendar) so the
    /// radiant drawing can be tested before the events code supplies real ones.
    static var demoRadiants: (any SkyRadiantProviding)? {
        guard defaults.bool(forKey: "SkyDemoRadiants") else { return nil }
        func d(_ s: String) -> Date { (try? Date(s, strategy: .iso8601)) ?? .distantPast }
        return StaticRadiants([SkyRadiant(
            id: "PER", name: "Perseids (demo)", raDeg: 48, decDeg: 58,
            activeFrom: d("2026-07-17T00:00:00Z"), activeUntil: d("2026-08-24T00:00:00Z"), peak: d("2026-08-13T01:00:00Z"),
            zhr: 100, populationIndex: 2.2, driftRADegPerDay: 1.35, driftDecDegPerDay: 0.12)])
    }

    /// Candlestick Camp (public NPS site) with its measured skyline, when no place is chosen.
    static func place(_ chosen: Place?) -> (place: Place, horizon: HorizonProfile?) {
        if let chosen { return (chosen, nil) }
        return (Place(name: "Candlestick Camp (demo)", latitude: 38.374031, longitude: -109.965416, timeZoneID: "America/Denver"),
                try? HorizonProfile.bundled("candlestick-camp"))
    }

    private static let defaults = UserDefaults.standard

    /// `-SkyDemoTime <ISO 8601>` pins the time for screenshots and UI tests.
    static var pinnedTime: Date? {
        defaults.string(forKey: "SkyDemoTime").flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// `-SkyDemoHeadingAccuracy <deg | invalid>` simulates a poor or invalid compass.
    static var headingAccuracyDeg: Double {
        guard let value = defaults.string(forKey: "SkyDemoHeadingAccuracy") else { return 3 }
        return value == "invalid" ? -1 : Double(value) ?? -1
    }

    /// `-SkyDemoSweep YES` swings the simulated phone around the south at
    /// display rate, exercising the same per-frame path as the sensors.
    static var sweeps: Bool { defaults.bool(forKey: "SkyDemoSweep") }

    /// `-SkyFrameStats YES` shows the frame-time meter.
    static var showsFrameStats: Bool { defaults.bool(forKey: "SkyFrameStats") }

    static func sweepAttitude(at date: Date) -> DeviceAttitude {
        let t = date.timeIntervalSinceReferenceDate
        return .upright(facingAzimuth: 180 + 35 * sin(t * 0.5), pitchDeg: 20 + 10 * sin(t * 0.31))
    }

    /// When the GC stands highest during darkness.
    static func defaultTime(_ track: GCTrack) -> Date {
        track.samples.max { $0.position.altitudeDeg < $1.position.altitudeDeg }?.date ?? track.window.start
    }
}

/// For a time outside the precomputed span (rare: the live clock ran past
/// it before the hourly refresh): one direct scene per 30 s, plus the
/// parsed horizon.
final class SkyFallbackCache {
    private var sceneKey: (Place, Date)?
    private var sceneValue: NightSkyScene?
    private var horizonKey: String?
    private var horizonValue: HorizonProfile?

    func scene(place: Place, at date: Date) -> NightSkyScene? {
        let bucket = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 30).rounded(.down) * 30)
        if let key = sceneKey, key == (place, bucket) { return sceneValue }
        sceneKey = (place, bucket)
        sceneValue = try? NightSkyScene.at(bucket, observer: place.observer())
        return sceneValue
    }

    func horizon(csv: String) -> HorizonProfile? {
        if csv == horizonKey { return horizonValue }
        horizonKey = csv
        horizonValue = try? HorizonProfile.parse(csv: csv)
        return horizonValue
    }
}

/// VoiceOver reads the summary on demand; rebuilding it at display rate
/// would cost more than the drawing. Refreshed twice a second, or at once
/// when the style or the displayed time changes.
final class SummaryThrottle {
    private var text = ""
    private var builtAt = ContinuousClock.now - .seconds(10)
    private var key: (OverlayStyle, Date)?

    func summary(for input: SkyOverlayInput) -> String {
        let now = ContinuousClock.now
        let newKey = (input.style, input.scene.date)
        let changed = key.map { $0.0 != newKey.0 || abs($0.1.timeIntervalSince(newKey.1)) > 1 } ?? true
        if changed || now - builtAt > .milliseconds(500) {
            text = input.accessibilitySummary
            builtAt = now
            key = newKey
        }
        return text
    }
}

/// Per-frame timing: main-actor preparation (interpolation, projector),
/// Canvas drawing, and the interval between drawn frames. Not observed, so
/// measuring never causes a redraw.
final class FrameMeter {
    let enabled: Bool
    private var prepare: [Double] = []
    private var draw: [Double] = []
    private var interval: [Double] = []
    private var lastDraw: ContinuousClock.Instant?
    private var model = ""

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func recordPrepare(_ d: Duration) {
        guard enabled else { return }
        push(&prepare, d.milliseconds)
    }

    func recordModel(_ d: Duration, samples: Double) {
        guard enabled else { return }
        model = String(format: " · night model %.0f ms off-main (%.0f one-minute samples)", d.milliseconds, samples)
    }

    func recordDraw(_ d: Duration, endedAt end: ContinuousClock.Instant) {
        guard enabled else { return }
        push(&draw, d.milliseconds)
        if let lastDraw { push(&interval, (end - lastDraw).milliseconds) }
        lastDraw = end
    }

    var summary: String {
        func p(_ xs: [Double], _ q: Double) -> String {
            guard !xs.isEmpty else { return "–" }
            let s = xs.sorted()
            return String(format: "%.2f", s[min(s.count - 1, Int(Double(s.count) * q))])
        }
        return "frames \(interval.count + 1) · interval p50 \(p(interval, 0.5)) p95 \(p(interval, 0.95)) ms"
            + " · draw p50 \(p(draw, 0.5)) p95 \(p(draw, 0.95)) ms · prepare p50 \(p(prepare, 0.5)) p95 \(p(prepare, 0.95)) ms" + model
    }

    private func push(_ xs: inout [Double], _ x: Double) {
        xs.append(x)
        if xs.count > 600 { xs.removeFirst(xs.count - 600) }
    }
}

private extension Duration {
    var milliseconds: Double {
        let (s, atto) = components
        return Double(s) * 1000 + Double(atto) / 1e15
    }
}
