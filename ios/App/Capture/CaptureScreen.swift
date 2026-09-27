import AVFoundation
import SkyCore
import SwiftUI

/// M12: tripod capture with the iPhone's own camera (ADR-0011).
struct CaptureScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CaptureModel()
    @State private var onScreen = false
    @State private var wentToBackground = false
    @State private var showMagnifier = true
    @State private var savedMessage: String?
    @AppStorage("capture.iso") private var storedISO = 3200.0
    @AppStorage("capture.focus") private var storedFocus = 1.0
    @AppStorage("capture.timer") private var storedTimer = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                preview
                if model.access == .denied || model.access == .restricted {
                    Card {
                        Text("Camera access is off").font(.headline).foregroundStyle(palette.primary)
                        Text("Turn it on in Settings › Dark Sky › Camera to shoot from here.")
                            .font(.subheadline).foregroundStyle(palette.secondary)
                    }
                } else if model.camera == nil {
                    Card {
                        Text(model.access == .authorized ? "Starting the camera…" : "Waiting for camera permission.")
                            .font(.subheadline).foregroundStyle(palette.secondary)
                    }
                } else {
                    status
                    cameraCard
                    focusCard
                    sequenceCard
                    estimateCard
                    controls
                    savedCard
                    resultCard
                }
                #if DEBUG
                CaptureDebugState(model: model)
                CaptureProbeSection()
                #endif
            }
            .padding()
        }
        .background(palette.background)
        .paletteChrome("Capture", pushed: true)
        .toolbar(.hidden, for: .tabBar)
        .task {
            onScreen = true
            model.iso = Float(storedISO)
            model.focusPosition = Float(storedFocus)
            model.timerSeconds = storedTimer
            await model.appear()
        }
        // One lifetime (CaptureModel): leaving the screen, the background or
        // a lock ends the run with its frames kept and releases the camera.
        .onDisappear {
            onScreen = false
            model.leave(.leftScreen)
        }
        .onChange(of: scenePhase) { _, phase in
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
        .alert("Capture", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Preview and focus assist

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            CapturePreview(session: model.engine.session)
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Camera preview")
            if showMagnifier, let crop = model.focusCrop, let image = FocusImage.make(crop) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 140, height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.accent, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .accessibilityLabel("Magnified centre of the frame, for focusing")
            }
        }
    }

    private var status: some View {
        Group {
            switch model.phase {
            case .idle: EmptyView()
            case .waitingForPreviousRun: statusLine("Finishing the previous sequence…")
            case .countdown(let s): statusLine("Self-timer: \(s)")
            case .settling: statusLine("Waiting for the tripod to settle…")
            case .capturing(let i, let n): statusLine("Frame \(i) of \(n)")
            case .coolingDown(let s): statusLine("Hot: pausing \(Int(s)) s between frames")
            case .draining: statusLine("Saving the last frames…")
            case .stopped(let text): statusLine(text)
            case .stacking(let f, let what): statusLine("\(what) (\(Int(f * 100)) %)")
            case .finished(let text): statusLine(text)
            case .failed(let text): statusLine(text)
            }
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(palette.accent)
            .accessibilityIdentifier("capture.status")
    }

    // MARK: Cards

    private var cameraCard: some View {
        Card {
            Text("Camera").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            Picker("Lens", selection: $model.lens) {
                ForEach(CaptureCameraInfo.Lens.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isBusy)
            .onChange(of: model.lens) { Task { await model.configure() } }
            if let camera = model.camera {
                row("Exposure", String(format: "%.2g s (longest this camera allows)", model.subExposure))
                Slider(value: $model.subExposure, in: 0.1...camera.maxExposure, step: 0.1) {
                    Text("Exposure")
                } onEditingChanged: { editing in
                    if !editing { Task { try? await model.applyManual() } }
                }
                .disabled(model.phase.isBusy)
                row("ISO", "\(Int(model.iso))")
                Slider(value: Binding(get: { Double(model.iso) }, set: { model.iso = Float($0.rounded()) }),
                       in: Double(camera.minISO)...Double(camera.maxISO)) {
                    Text("ISO")
                } onEditingChanged: { editing in
                    if !editing {
                        storedISO = Double(model.iso)
                        Task { try? await model.applyManual() }
                    }
                }
                .disabled(model.phase.isBusy)
                if camera.apertureControl {
                    Picker("Aperture", selection: Binding(get: { model.aperture ?? camera.apertures[0] },
                                                          set: { model.aperture = $0; Task { try? await model.applyManual() } })) {
                        ForEach(camera.apertures, id: \.self) { Text(String(format: "f/%.2g", $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.phase.isBusy)
                } else if let a = camera.apertures.first {
                    row("Aperture", String(format: "f/%.2g (fixed)", a))
                }
                if let npf = model.npfSeconds {
                    Text(String(format: "NPF for this lens: %.1f s before stars trail; the %.2g s limit is the camera's.", npf, camera.maxExposure))
                        .font(.caption).foregroundStyle(palette.secondary)
                }
            }
        }
    }

    private var focusCard: some View {
        Card {
            Text("Focus").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            Text("Aim at a bright star or a distant light. Move the slider until the stars in the magnifier are smallest; the half-flux radius (HFR) is lowest there.")
                .font(.caption).foregroundStyle(palette.secondary)
            row("Lens position", String(format: "%.3f", model.focusPosition))
            Slider(value: Binding(get: { Double(model.focusPosition) }, set: { model.focusPosition = Float($0) }), in: 0...1) {
                Text("Lens position")
            } onEditingChanged: { editing in
                if !editing {
                    storedFocus = Double(model.focusPosition)
                    Task { try? await model.applyManual() }
                }
            }
            .disabled(model.phase.isBusy)
            HStack {
                ForEach([-0.01, -0.002, 0.002, 0.01], id: \.self) { step in
                    Button(String(format: "%+.3f", step)) {
                        model.focusPosition = min(1, max(0, model.focusPosition + Float(step)))
                        storedFocus = Double(model.focusPosition)
                        Task { try? await model.applyManual() }
                    }
                    .buttonStyle(PressDimStyle())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(model.phase.isBusy)
            HStack {
                Button("Autofocus once") { Task { await model.autofocus(); storedFocus = Double(model.focusPosition) } }
                    .buttonStyle(PressDimStyle()).foregroundStyle(palette.accent)
                Spacer()
                Toggle("Magnifier", isOn: $showMagnifier).toggleStyle(.button).foregroundStyle(palette.accent)
            }
            .font(.subheadline)
            row("Stars in centre", model.focusHFR.map { String(format: "%d, HFR %.2f px", model.focusStars, $0) } ?? "none found")
        }
    }

    private var sequenceCard: some View {
        Card {
            Text("Sequence").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            Picker("Mode", selection: $model.mode) {
                ForEach(CaptureModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isBusy)
            switch model.mode {
            case .stack:
                row("Noise reduction", String(format: "%.1f× better SNR", model.snrGain))
                Slider(value: $model.snrGain, in: 2...8, step: 0.5) { Text("SNR gain") }
                    .disabled(model.phase.isBusy)
                Text("\(model.frameCount) frames (√N rule, the Tools stacking calculator), aligned on stars and averaged with outliers such as satellites rejected.")
                    .font(.caption).foregroundStyle(palette.secondary)
            case .trails:
                row("Duration", "\(Int(model.trailMinutes)) min")
                Slider(value: $model.trailMinutes, in: 1...120, step: 1) { Text("Duration") }
                    .disabled(model.phase.isBusy)
                row("Interval", String(format: "%.1f s", model.trailInterval))
                Slider(value: $model.trailInterval, in: max(model.subExposure, 0.1)...30, step: 0.5) { Text("Interval") }
                    .disabled(model.phase.isBusy)
                Text("\(model.frameCount) frames, combined by the brightest value per pixel. A gap between frames leaves gaps in the trails.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            Picker("Files", selection: $model.fileFormat) {
                Text(model.rawAvailable ? "RAW (DNG)" : "RAW unavailable").tag(FrameRequest.FileFormat.raw)
                Text("HEIC").tag(FrameRequest.FileFormat.heic)
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isBusy || !model.rawAvailable)
            Toggle("12 MP frames (48 MP when off)", isOn: $model.twelveMegapixels)
                .font(.subheadline).foregroundStyle(palette.primary).tint(palette.accent)
                .disabled(model.phase.isBusy)
            Picker("Self-timer", selection: $model.timerSeconds) {
                ForEach([0, 2, 5, 10], id: \.self) { Text($0 == 0 ? "No timer" : "\($0) s").tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.timerSeconds) { storedTimer = model.timerSeconds }
            .disabled(model.phase.isBusy)
        }
    }

    private var estimateCard: some View {
        Card {
            Text("Before you start").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            if let plan = model.plan {
                row("Time", Duration.seconds(plan.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                row("Storage", "\(CaptureModel.bytes(plan.storedBytes)) kept, \(CaptureModel.bytes(plan.peakBytes)) at peak")
                row("Free", CaptureModel.bytes(model.freeBytes) + (plan.fits(freeBytes: model.freeBytes) ? "" : " (not enough)"))
                if model.measuredFrameBytes == nil {
                    Text("Frame size is an estimate until the first frame is saved.")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
            }
            row("Battery", batteryText)
            row("Temperature", CameraProbe.thermalName(model.thermal))
            row("Tripod", stabilityText)
        }
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

    /// What each button does is in its label: "Stop and stack" keeps going
    /// to a stack of what was shot; "Cancel" and "Stop stacking" stop all
    /// work. Frames already shot are always kept.
    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .countdown, .settling, .capturing, .coolingDown:
            HStack(spacing: 12) {
                bigButton("Stop and stack", symbol: "stop.circle", id: "capture.stopAndStack") { model.stopAndStack() }
                bigButton("Cancel", symbol: "xmark.circle", id: "capture.cancel") { model.cancel() }
            }
            Text("Stop and stack: end the sequence now and stack the frames shot. Cancel: end it and stack nothing. Either way every frame is kept.")
                .font(.caption).foregroundStyle(palette.secondary)
        case .draining:
            bigButton("Saving the last frames…", symbol: "hourglass", id: "capture.draining") {}.disabled(true)
        case .stacking:
            bigButton("Stop stacking", symbol: "xmark.circle", id: "capture.stopStacking") { model.cancel() }
            Text("Stops the stack within about a second. The frames are kept and can be stacked again here.")
                .font(.caption).foregroundStyle(palette.secondary)
        case .waitingForPreviousRun:
            bigButton("Finishing the previous sequence…", symbol: "hourglass", id: "capture.waiting") {}.disabled(true)
        case .idle, .finished, .stopped, .failed:
            bigButton("Start \(model.frameCount) frames", symbol: "camera.aperture", id: "capture.start") { model.start() }
                .disabled(model.plan == nil)
            Text("The sequence runs while this screen is open and the phone is unlocked. Leaving the screen, locking the phone or another app taking the camera ends it; the frames shot so far are kept.")
                .font(.caption).foregroundStyle(palette.secondary)
        }
    }

    private func bigButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressDimStyle())
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var savedCard: some View {
        if let saved = model.savedSequence, !model.phase.isBusy {
            Card {
                Text("Saved sequence, not stacked").font(.headline).foregroundStyle(palette.primary)
                Text("\(saved.folder.lastPathComponent): \(saved.log.frames.count) frames\(saved.log.ended.map { "; ended because \($0)" } ?? "").")
                    .font(.caption).foregroundStyle(palette.secondary)
                Button("Stack these frames") { model.stackSaved(saved) }
                    .buttonStyle(PressDimStyle()).foregroundStyle(palette.accent).font(.subheadline)
                    .accessibilityIdentifier("capture.stackSaved")
            }
        }
    }

    @ViewBuilder private var resultCard: some View {
        if model.lastFolder != nil || !model.log.isEmpty {
            Card {
                Text("Last sequence").font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
                ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).foregroundStyle(palette.secondary)
                }
                if let folder = model.lastFolder {
                    Text("Frames, sequence.json and the stack are in Files › On My iPhone › Dark Sky › Captures › \(folder.lastPathComponent).")
                        .font(.caption).foregroundStyle(palette.secondary)
                    Button("Save frames and stack to Photos") { Task { await saveToPhotos(folder) } }
                        .buttonStyle(PressDimStyle()).foregroundStyle(palette.accent).font(.subheadline)
                        .disabled(model.phase.isBusy)
                }
                if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(palette.secondary) }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(palette.secondary)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(palette.primary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func saveToPhotos(_ folder: URL) async {
        do {
            let ids = try await model.saveToPhotos(folder)
            savedMessage = "Saved \(ids.count) files to Photos. The originals also stay in the Dark Sky folder."
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
