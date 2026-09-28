import AVFoundation
import SkyCore
import SwiftUI

/// M12: tripod capture with the iPhone's own camera (ADR-0011).
///
/// Layout (review 2026-09-27 §6, §7): the preview and settings scroll; Start,
/// Stop and progress sit in a fixed bar at the bottom. Before a run the
/// order is the recommended start, guided focus, this sequence's numbers,
/// then the manual controls. During a run the settings are replaced by a
/// read-only summary. "How to shoot" opens the two-path guide, which also
/// shows the first time the screen opens.
struct CaptureScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CaptureModel()
    @State private var onScreen = false
    @State private var wentToBackground = false
    @State private var showMagnifier = true
    @State private var savedMessage: String?
    @State private var showGuide = false
    @State private var showResult = false
    @State private var trailDesign: SkyTrailDesign?
    @State private var trailPlan: PhoneTrailPlan?
    @AppStorage("capture.iso") private var storedISO = 3200.0
    @AppStorage("capture.focus") private var storedFocus = 1.0
    @AppStorage("capture.timer") private var storedTimer = 5
    @AppStorage("capture.guideSeen") private var guideSeen = false
    /// The field dock's tab label (caption2) grows with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var dockLabelLine: CGFloat = 13.5

    /// FieldDock: 8 top padding + 32 brightness + 8 spacing + a tab row of
    /// max(44, 20 pt icon + 2 + caption2 line).
    private var fieldDockClearance: CGFloat { 48 + max(DS.minTarget, 26 + dockLabelLine) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                preview
                if model.access == .denied || model.access == .restricted {
                    SectionCard("Camera") {
                        Text("Camera access is off").font(.dsHeadline).foregroundStyle(palette.primary)
                        Text("Turn it on in Settings › Dark Sky › Camera to shoot from here. Apple Camera's Night mode is another way: see How to shoot.")
                            .font(.dsCallout).foregroundStyle(palette.secondary)
                    }
                } else if model.camera == nil {
                    SectionCard {
                        Text(model.access == .authorized ? "Starting the camera…" : "Waiting for camera permission.")
                            .font(.dsCallout).foregroundStyle(palette.secondary)
                    }
                } else if model.phase.isBusy {
                    runCard
                } else {
                    savedCard
                    resultCard
                    presetCard
                    focusCard
                    planCard
                    Text("Manual settings").eyebrow(palette).padding(.top, DS.Space.s)
                    cameraCard
                    sequenceCard
                }
                #if DEBUG
                CaptureDebugState(model: model)
                if !model.demoing { CaptureProbeSection() }
                #endif
            }
            .padding(DS.Space.screen)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.camera != nil {
                CaptureControlBar(model: model) { showResult = true }
                    // Field mode's dock is a safe-area inset on the Tools
                    // stack that does not reach this pushed screen, so the
                    // bar clears it itself (measured: 92 pt at default size).
                    .padding(.bottom, palette.isField ? fieldDockClearance : 0)
                    .background(palette.background)
            }
        }
        .background(palette.background)
        .screenChrome("Capture", pushed: true) {
            Button { showGuide = true } label: {
                Label("How to shoot", systemImage: "questionmark.circle")
            }
            .foregroundStyle(palette.primary)
            .accessibilityIdentifier("capture.howTo")
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showGuide) {
            CaptureGuideSheet(model: model) { usePreset() }
        }
        .sheet(isPresented: $showResult) {
            CaptureResultView(model: model)
        }
        .task {
            onScreen = true
            #if DEBUG
            if let demo = CaptureModel.launchDemo {
                model.loadDemo(demo)
                trailDesignChanged()
                if !guideSeen { guideSeen = true; showGuide = true }
                return
            }
            #endif
            model.iso = Float(storedISO)
            model.focusPosition = Float(storedFocus)
            model.timerSeconds = storedTimer
            if !guideSeen { guideSeen = true; showGuide = true }
            await model.appear()
        }
        // One lifetime (CaptureModel): leaving the screen, the background or
        // a lock ends the run with its frames kept and releases the camera.
        .onDisappear {
            onScreen = false
            if !model.demoing { model.leave(.leftScreen) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !model.demoing else { return }
            switch phase {
            case .background:
                guard onScreen else { return }
                wentToBackground = true
                model.leave(.background)
            case .active:
                guard onScreen, wentToBackground else { return }
                wentToBackground = false
                Task { await model.appear() }
            default:
                break
            }
        }
        .onChange(of: model.resultReady) { _, ready in
            guard ready else { return }
            model.resultReady = false
            if onScreen, !showGuide { showResult = true }
        }
        .onChange(of: model.mode) { _, _ in trailDesignChanged() }
        .alert("Capture", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func usePreset() {
        Task {
            await model.applyPreset()
            storedISO = Double(model.iso)
            storedTimer = model.timerSeconds
        }
    }

    /// Star trails read the Sky view's saved design when there is one.
    private func trailDesignChanged() {
        guard model.mode == .trails else { return }
        trailDesign = SkyTrailDesign.saved
        if let trailDesign, trailPlan == nil { trailPlan = model.applyTrailDesign(trailDesign.sequence) }
    }

    // MARK: Preview and focus assist

    private var preview: some View {
        previewPicture
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxHeight: 440)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .accessibilityLabel("Camera preview")
            .overlay(alignment: .topTrailing) { magnifier }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var magnifier: some View {
        if showMagnifier, let crop = model.focusCrop, let image = FocusImage.make(crop) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 128, height: 128)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).stroke(palette.accent, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .padding(DS.Space.s)
                .accessibilityLabel("Magnified centre of the frame, for focusing")
        }
    }

    @ViewBuilder private var previewPicture: some View {
        #if DEBUG
        if model.demoing {
            if let image = model.demoPreview {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        } else {
            CapturePreview(session: model.engine.session)
        }
        #else
        CapturePreview(session: model.engine.session)
        #endif
    }

    // MARK: During a run

    private var runCard: some View {
        SectionCard("This run") {
            CaptureRow("Settings (locked)", lockedSummary, id: "capture.run.settings")
            CaptureRow("Frames saved", "\(model.savedFrames)", id: "capture.run.saved")
            CaptureRow("Battery", batteryText)
            CaptureRow("Heat", CameraProbe.thermalName(model.thermal))
            CaptureRow("Tripod", stabilityText)
            Text("Stop or cancel from the bar below. Leaving this screen or locking the phone also ends the run; the frames shot so far are kept.")
                .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockedSummary: String {
        var parts = [model.lens.title, CaptureWording.duration(model.subExposure), "ISO \(Int(model.iso))"]
        if let a = model.aperture { parts.append(CaptureGuideSheet.fNumber(a)) }
        if let r = model.selectedResolution { parts.append(r.title) }
        parts.append(model.formatTitle)
        return parts.joined(separator: " · ")
    }

    // MARK: Before a run

    private var presetCard: some View {
        SectionCard("Start here") {
            Text("Recommended start: main camera wide open, this phone's longest frame, ISO \(Int(model.preset?.iso ?? CapturePreset.startingISO)) to begin, a 9-frame test at 12 MP. Then focus on a star below.")
                .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s) { presetButtons }
                VStack(alignment: .leading, spacing: DS.Space.s) { presetButtons }
            }
        }
    }

    @ViewBuilder private var presetButtons: some View {
        Button { usePreset() } label: { Text("Use recommended settings") }
            .buttonStyle(ActionButtonStyle(.secondary))
            .accessibilityIdentifier("capture.usePreset")
        Button { showGuide = true } label: { Text("How to shoot") }
            .buttonStyle(ActionButtonStyle(.quiet))
            .accessibilityIdentifier("capture.howToInline")
    }

    private var focusCard: some View {
        SectionCard("Focus") {
            Text("Make the star as small and sharp as possible.").font(.dsHeadline).foregroundStyle(palette.primary)
            Text("Aim at a bright star or a distant light, then step the focus until the star in the magnifier is the smallest point you can get.")
                .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            CaptureRow("Star size (smaller is sharper)",
                       model.focusHFR.map { String(format: "%.2f px · %d star%@", $0, model.focusStars, model.focusStars == 1 ? "" : "s") } ?? "no star in the centre yet",
                       id: "capture.focus.hfr")
            Grid(horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.s) {
                GridRow {
                    focusButton("Nearer", symbol: "chevron.left.2", spoken: "Focus nearer", step: -0.01, id: "capture.focus.nearer")
                    focusButton("Farther", symbol: "chevron.right.2", spoken: "Focus farther", step: 0.01, id: "capture.focus.farther")
                }
                GridRow {
                    focusButton("A little nearer", symbol: "chevron.left", spoken: "Focus slightly nearer", step: -0.002, id: "capture.focus.slightlyNearer")
                    focusButton("A little farther", symbol: "chevron.right", spoken: "Focus slightly farther", step: 0.002, id: "capture.focus.slightlyFarther")
                }
            }
            CaptureRow("Lens position", String(format: "%.3f of 1 (1 is the far end, not infinity)", model.focusPosition), id: "capture.focus.position")
            Slider(value: Binding(get: { Double(model.focusPosition) }, set: { model.focusPosition = Float($0) }), in: 0...1) {
                Text("Lens position")
            } onEditingChanged: { editing in
                if !editing {
                    storedFocus = Double(model.focusPosition)
                    if !model.demoing { Task { try? await model.applyManual() } }
                }
            }
            .frame(minHeight: DS.minTarget)
            .accessibilityValue(String(format: "%.3f", model.focusPosition))
            HStack(spacing: DS.Space.s) {
                Button("Autofocus once") { Task { await model.autofocus(); storedFocus = Double(model.focusPosition) } }
                    .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                    .accessibilityIdentifier("capture.focus.autofocus")
                Spacer(minLength: 0)
                Toggle("Magnifier", isOn: $showMagnifier)
                    .toggleStyle(PaletteToggleStyle())
                    .fixedSize()
                    .accessibilityIdentifier("capture.focus.magnifier")
            }
            MoreInfo(title: "About the star size readout") {
                Text("The half-flux radius (HFR): the radius, in preview pixels, that holds half of each star's light, as a median over the stars in the centre. In focus it is at its lowest.")
            }
        }
    }

    private func focusButton(_ title: String, symbol: String, spoken: String, step: Float, id: String) -> some View {
        Button {
            model.nudgeFocus(step)
            storedFocus = Double(model.focusPosition)
        } label: {
            Label(title, systemImage: symbol)
                .font(.dsCallout)
                .frame(maxWidth: .infinity, minHeight: DS.minTarget)
        }
        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
        .accessibilityLabel(spoken)
        .accessibilityHint(String(format: "Moves the lens %.3f of its travel", abs(step)))
        .accessibilityIdentifier(id)
    }

    private var planCard: some View {
        SectionCard("This sequence") {
            if let d = model.durations {
                CaptureRow("Exposure per frame", CaptureWording.duration(d.perFrame), id: "capture.plan.perFrame")
                CaptureRow("Frames", "\(d.frames)")
                CaptureRow("Total exposure", CaptureWording.duration(d.integration), id: "capture.plan.integration")
                CaptureRow("Sequence time", "about " + CaptureWording.duration(d.sequence), id: "capture.plan.sequence")
                CaptureRow("Star-trailing limit (NPF)", d.starTrailLimit.map { CaptureWording.duration($0) } ?? "after the first frame", id: "capture.plan.npf")
            }
            if let plan = model.plan {
                CaptureRow("Storage", "\(CaptureModel.bytes(plan.storedBytes)) kept, \(CaptureModel.bytes(plan.peakBytes)) at peak")
                CaptureRow("Free", CaptureModel.bytes(model.freeBytes) + (plan.fits(freeBytes: model.freeBytes) ? "" : " (not enough)"))
                if !model.frameBytesMeasured {
                    Text("Frame size is an estimate until the first frame is saved.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                }
            }
            CaptureRow("Battery", batteryText)
            CaptureRow("Heat", CameraProbe.thermalName(model.thermal))
            CaptureRow("Tripod", stabilityText)
        }
    }

    private var cameraCard: some View {
        SectionCard("Camera") {
            CaptureChoiceRow(label: "Lens", options: CaptureCameraInfo.Lens.allCases.map { .init(value: $0, title: $0.title) },
                             selection: Binding(get: { model.lens }, set: { lens in
                                 model.lens = lens
                                 if !model.demoing { Task { await model.configure() } }
                             }), id: "capture.lens")
            if let camera = model.camera {
                CaptureRow("Exposure per frame", CaptureWording.exposurePerFrame(chosen: model.subExposure, maximum: camera.maxExposure),
                           id: "capture.exposure")
                Slider(value: $model.subExposure, in: 0.1...max(camera.maxExposure, 0.2), step: 0.1) {
                    Text("Exposure per frame")
                } onEditingChanged: { editing in
                    if !editing, !model.demoing { Task { try? await model.applyManual() } }
                }
                .frame(minHeight: DS.minTarget)
                .accessibilityIdentifier("capture.exposureSlider")
                Text("The maximum is what this phone's camera reports on \(CaptureGuideSheet.system), not a limit of every iPhone.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                CaptureRow("ISO", "\(Int(model.iso))", id: "capture.iso")
                Slider(value: Binding(get: { Double(model.iso) }, set: { model.iso = Float($0.rounded()) }),
                       in: Double(camera.minISO)...Double(camera.maxISO)) {
                    Text("ISO")
                } onEditingChanged: { editing in
                    if !editing {
                        storedISO = Double(model.iso)
                        if !model.demoing { Task { try? await model.applyManual() } }
                    }
                }
                .frame(minHeight: DS.minTarget)
                if camera.apertureControl {
                    CaptureChoiceRow(label: "Aperture", options: camera.apertures.map { .init(value: $0, title: CaptureGuideSheet.fNumber($0)) },
                                     selection: Binding(get: { model.aperture ?? camera.apertures[0] }, set: {
                                         model.aperture = $0
                                         if !model.demoing { Task { try? await model.applyManual() } }
                                     }), id: "capture.aperture")
                } else if let a = camera.apertures.first {
                    CaptureRow("Aperture", "\(CaptureGuideSheet.fNumber(a)) (fixed)")
                }
                if let npf = model.npfSeconds {
                    Text(CaptureWording.starTrailLimit(npf: npf, cameraMaximum: camera.maxExposure))
                        .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture.npf")
                }
            }
        }
    }

    private var sequenceCard: some View {
        SectionCard("Sequence") {
            CaptureChoiceRow(label: "Mode", options: CaptureModel.Mode.allCases.map { .init(value: $0, title: $0.title) },
                             selection: $model.mode, id: "capture.mode")
            switch model.mode {
            case .stack:
                CaptureRow("Noise reduction", String(format: "%.1f× better signal-to-noise", model.snrGain))
                Slider(value: $model.snrGain, in: 2...8, step: 0.5) { Text("Noise reduction") }
                    .frame(minHeight: DS.minTarget)
                Text("\(model.frameCount) frames (√N rule, as in the Tools stacking calculator), aligned on stars and averaged with outliers such as satellites rejected.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            case .trails:
                trailDesignNote
                CaptureRow("Duration", "\(Int(model.trailMinutes)) min", id: "capture.trails.duration")
                Slider(value: $model.trailMinutes, in: 1...120, step: 1) { Text("Duration") }
                    .frame(minHeight: DS.minTarget)
                CaptureRow("Interval", CaptureWording.duration(model.trailInterval), id: "capture.trails.interval")
                Slider(value: $model.trailInterval, in: max(model.subExposure, 0.1)...30, step: 0.5) { Text("Interval") }
                    .frame(minHeight: DS.minTarget)
                Text("\(model.frameCount) frames, combined by the brightest value per pixel. A gap between frames leaves gaps in the trails.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let choices = model.resolutionChoices
            if choices.count > 1 {
                CaptureChoiceRow(label: "Resolution", options: choices.map { r in
                    .init(value: r, title: r.title, detail: storageDetail(r))
                }, selection: Binding(get: { model.selectedResolution ?? choices[0] }, set: { model.resolution = $0 }), id: "capture.resolution")
            } else if let r = choices.first {
                CaptureRow("Resolution", "\(r.title) · \(storageDetail(r))")
            }
            if model.rawAvailable {
                CaptureChoiceRow(label: "Frames saved as", options: [
                    .init(value: FrameRequest.FileFormat.raw, title: model.rawTitle),
                    .init(value: FrameRequest.FileFormat.heic, title: "HEIC"),
                ], selection: $model.fileFormat, id: "capture.format")
            } else {
                CaptureRow("Frames saved as", "HEIC (this camera offers no RAW)")
            }
            CaptureChoiceRow(label: "Self-timer", options: [0, 2, 5, 10].map { .init(value: $0, title: $0 == 0 ? "No timer" : "\($0) s") },
                             selection: Binding(get: { model.timerSeconds }, set: { model.timerSeconds = $0; storedTimer = $0 }),
                             id: "capture.timer")
        }
    }

    /// "25 MB a frame · 224 MB for 9"
    private func storageDetail(_ r: CaptureResolution) -> String {
        let one = model.frameBytes(r)
        return "\(CaptureModel.bytes(one)) a frame\n\(CaptureModel.bytes(one * Int64(model.frameCount))) for \(model.frameCount)"
    }

    @ViewBuilder private var trailDesignNote: some View {
        if let design = trailDesign {
            let s = design.sequence
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("From your Sky trail design").font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                Text(trailDesignText(s, design.poleInFrame))
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Use the Sky design again") { trailPlan = model.applyTrailDesign(s) }
                    .buttonStyle(ActionButtonStyle(.quiet))
                    .accessibilityIdentifier("capture.trailDesign.apply")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture.trailDesign")
        } else {
            Text("Design a star trail in the Sky view (Trails) and it will appear here.")
                .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trailDesignText(_ s: StarTrailSequence, _ pole: CGPoint?) -> String {
        let plan = trailPlan ?? PhoneTrailPlan(design: s, maxExposure: model.camera?.maxExposure ?? 1)
        var text = "Sky: \(Int((s.duration / 60).rounded())) min, \(s.frames) × \(CaptureWording.duration(s.exposure)) every \(CaptureWording.duration(s.interval)) (a dedicated camera's frames). Here: \(Int(plan.minutes)) min of back-to-back \(CaptureWording.duration(plan.interval)) frames, so the trails have no gaps."
        if plan.clamped { text += " The design's \(Int(plan.designMinutes.rounded())) min is longer than this screen's 120 min limit." }
        if s.start > .now { text += " Planned start: \(s.start.formatted(date: .omitted, time: .shortened))." }
        if let pole {
            text += " The celestial pole sat \(Int((pole.x * 100).rounded())) % across and \(Int((pole.y * 100).rounded())) % down in the Sky preview: frame the same way for circles."
        }
        return text
    }

    private var batteryText: String {
        guard model.batteryLevel >= 0 else { return "unknown" }
        let level = "\(Int(model.batteryLevel * 100)) %"
        if let plan = model.plan, let use = model.battery.estimatedUse(duration: plan.duration) {
            return "\(level), about \(Int((use * 100).rounded(.up))) % for this sequence (measured here)"
        }
        return "\(level); drain not measured yet (needs 5 min and a 2 % drop)"
    }

    private var stabilityText: String {
        switch model.stability.isStable {
        case .some(true): "steady"
        case .some(false): String(format: "moving (%.3f rad/s)", model.stability.meanRate ?? 0)
        case .none: "measuring…"
        }
    }

    @ViewBuilder private var savedCard: some View {
        if let saved = model.savedSequence, !model.phase.isBusy {
            SectionCard("Saved sequence, not stacked") {
                Text("\(saved.folder.lastPathComponent): \(saved.log.frames.count) frames\(saved.log.ended.map { "; ended because \($0)" } ?? "").")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Stack these frames") { model.stackSaved(saved) }
                    .buttonStyle(ActionButtonStyle(.secondary))
                    .accessibilityIdentifier("capture.stackSaved")
            }
        }
    }

    @ViewBuilder private var resultCard: some View {
        if model.lastFolder != nil || !model.log.isEmpty {
            SectionCard("Last sequence") {
                if model.outcome != nil, model.lastStack != nil {
                    Button("View the result") { showResult = true }
                        .buttonStyle(ActionButtonStyle(.secondary))
                        .accessibilityIdentifier("capture.viewResult")
                }
                MoreInfo(title: "Sequence log", id: "capture.log") {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in Text(line) }
                }
                if let folder = model.lastFolder {
                    Text("Frames, sequence.json and the stack are in Files › On My iPhone › Dark Sky › Captures › \(folder.lastPathComponent).")
                        .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.outcome == nil {
                        Button("Save these frames to Photos") { Task { await saveToPhotos(folder) } }
                            .buttonStyle(ActionButtonStyle(.quiet))
                            .disabled(model.phase.isBusy)
                    }
                }
                if let savedMessage { Text(savedMessage).font(.dsFootnote).foregroundStyle(palette.secondary) }
            }
        }
    }

    private func saveToPhotos(_ folder: URL) async {
        do {
            let n = try await model.saveOriginals(folder)
            savedMessage = "Saved \(n) frames to Photos. The originals also stay in the Dark Sky folder."
        } catch {
            savedMessage = "Not saved to Photos (\(error.localizedDescription)); the files stay in the Dark Sky folder."
        }
    }
}

/// The Tools list's entry to Capture.
struct CaptureToolsRow: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationLink {
            CaptureScreen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.aperture").foregroundStyle(palette.accent).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tripod capture").font(.headline).foregroundStyle(palette.primary)
                    Text("Shoot and stack the night sky with this iPhone").font(.caption).foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(palette.secondary).accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressDimStyle())
        .accessibilityIdentifier("tools.capture")
    }
}

/// The session's preview, portrait.
struct CapturePreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90), c.videoRotationAngle != 90 {
                c.videoRotationAngle = 90
            }
        }
    }
}

/// The magnifier: the centre crop stretched between its 1st and 99.8th
/// percentiles so faint stars show. Display only; nothing saved is stretched.
enum FocusImage {
    static func make(_ plane: ImagePlane) -> CGImage? {
        var sorted = plane.pixels
        sorted.sort()
        let lo = sorted[sorted.count / 100], hi = max(sorted[Int(Double(sorted.count - 1) * 0.998)], lo + 1e-3)
        var bytes = [UInt8](repeating: 0, count: plane.pixels.count)
        for i in bytes.indices {
            bytes[i] = UInt8(max(0, min(255, (plane.pixels[i] - lo) / (hi - lo) * 255)))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: plane.width, height: plane.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: plane.width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

#if DEBUG
/// Debug only: what the lifecycle UI test asserts (one run, camera, idle timer).
struct CaptureDebugState: View {
    let model: CaptureModel
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let text = "run:\(CaptureModel.runExists ? "active" : "none") camera:\(model.engine.isRunning ? "on" : "off") idle:\(UIApplication.shared.isIdleTimerDisabled ? "disabled" : "enabled")"
            Text(text)
                .font(.caption2.monospaced()).foregroundStyle(palette.secondary)
                .accessibilityIdentifier("capture.debug")
                .accessibilityLabel(text)
        }
    }
}

/// Debug only: the capability probe on screen, the same JSON as `-CameraProbe YES`.
struct CaptureProbeSection: View {
    @Environment(\.palette) private var palette
    @State private var json: String?

    var body: some View {
        Card {
            Text("Camera probe (debug)").font(.headline).foregroundStyle(palette.primary)
            Button(json == nil ? "Read camera formats" : "Read again") {
                Task.detached {
                    let text = CameraProbe.json(CameraProbe.run())
                    await MainActor.run { json = text }
                }
            }
            .buttonStyle(PressDimStyle()).foregroundStyle(palette.accent)
            if let json {
                ShareLink(item: json).foregroundStyle(palette.accent)
                Text(json.prefix(4_000) + (json.count > 4_000 ? "\n…" : ""))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
#endif
