import AVFoundation
import CoreMotion
import Foundation
import Observation
import Photos
import SkyCore
import UIKit

/// The capture screen's state and the sequence runner (ADR-0011).
///
/// **Lifetime (one rule).** A sequence lives only while the Capture screen is
/// on screen and the app is active. Leaving the screen, sending the app to
/// the background, locking the phone or a camera interruption ends it: frames
/// already requested are drained to disk, every original is kept with its
/// `sequence.json`, stacking is not started (or is cancelled), and the
/// camera, motion updates, timers and the idle-timer override are released.
/// An unstacked sequence is offered again ("Stack saved frames") whenever the
/// screen opens. Only one run exists in the app at a time: a new screen waits
/// for the previous run's cleanup before it opens the camera.
///
/// **Stop.** "Stop and stack" ends acquisition and stacks what was shot;
/// "Cancel" ends everything and stacks nothing; "Stop stacking" cancels a
/// stack in progress (the stacker checks every row). Frames are never deleted.
@Observable
final class CaptureModel {
    enum Mode: String, CaseIterable, Identifiable {
        case stack, trails
        var id: String { rawValue }
        var title: String { self == .stack ? "Stack" : "Star trails" }
    }

    enum Phase: Equatable {
        case idle
        case waitingForPreviousRun
        case countdown(Int)
        case settling
        case capturing(frame: Int, of: Int)
        case coolingDown(TimeInterval)
        case draining
        case stacking(Double, String)
        case finished(String)
        case stopped(String)
        case failed(String)

        var isAcquiring: Bool {
            switch self {
            case .countdown, .settling, .capturing, .coolingDown, .draining: true
            default: false
            }
        }

        var isStacking: Bool { if case .stacking = self { true } else { false } }
        var isBusy: Bool { isAcquiring || isStacking || self == .waitingForPreviousRun }
    }

    /// Why acquisition ended early.
    enum EndReason: Equatable {
        case stopAndStack, cancelled, leftScreen, background, interrupted(String), tooHot, failures

        var stacks: Bool { self == .stopAndStack }

        var text: String {
            switch self {
            case .stopAndStack: "stopped by you; stacking what was shot"
            case .cancelled: "cancelled by you"
            case .leftScreen: "you left the Capture screen"
            case .background: "the app went to the background or the phone locked"
            case .interrupted(let why): why
            case .tooHot: "the phone is critically hot"
            case .failures: "three frames failed"
            }
        }
    }

    // Settings.
    var lens: CaptureCameraInfo.Lens = .main
    var mode: Mode = .stack
    var subExposure: Double = 1
    var iso: Float = 3200
    var aperture: Float?
    var focusPosition: Float = 1
    var snrGain: Double = 4
    var trailMinutes: Double = 20
    var trailInterval: Double = 1
    var timerSeconds = 5
    var fileFormat: FrameRequest.FileFormat = .raw
    var twelveMegapixels = true
    /// Debug self-test: an exact frame count instead of the SNR plan.
    var frameOverride: Int?

    // Live state.
    private(set) var camera: CaptureCameraInfo?
    private(set) var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var phase: Phase = .idle
    private(set) var stability = StabilityMonitor()
    private(set) var thermal = ProcessInfo.processInfo.thermalState
    private(set) var battery = BatteryTrend()
    private(set) var batteryLevel: Float = -1
    private(set) var freeBytes: Int64 = 0
    private(set) var measuredFrameBytes: Int64?
    private(set) var phoneGear: (camera: CameraProfile, lens: LensProfile)?
    private(set) var focusHFR: Double?
    private(set) var focusStars = 0
    private(set) var focusCrop: ImagePlane?
    private(set) var lastFolder: URL?
    private(set) var lastStack: URL?
    private(set) var savedSequence: SavedSequence?
    private(set) var log: [String] = []
    private(set) var lastAssetIdentifiers: [String] = []
    var errorMessage: String?

    @ObservationIgnored let engine = CaptureEngine()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var endRequest: EndReason?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private let started = Date()
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var sensorsOn = false
    @ObservationIgnored private var peakFootprint: Int64 = 0

    /// The one run in the app (acquisition, drain, stack and cleanup).
    private static var activeRun: Task<Void, Never>?
    static var runExists: Bool { activeRun != nil }

    // MARK: Derived plan

    var frameCount: Int {
        if let frameOverride { return frameOverride }
        return switch mode {
        case .stack: (try? Stacking.framesNeeded(snrGain: snrGain)) ?? 1
        case .trails: max(1, Int((trailMinutes * 60 / max(trailInterval, subExposure)).rounded(.down)))
        }
    }

    var gap: TimeInterval { mode == .trails ? max(0, trailInterval - subExposure) : 0 }

    var frameDimensions: CMVideoDimensions? {
        guard let dims = camera?.photoDimensions, !dims.isEmpty else { return nil }
        let sorted = dims.sorted { $0.width * $0.height < $1.width * $1.height }
        if twelveMegapixels, let twelve = sorted.first(where: { Int($0.width) * Int($0.height) >= 12_000_000 }) { return twelve }
        return sorted.last
    }

    var rawAvailable: Bool { camera?.proRaw != nil }

    var plan: CapturePlan? {
        guard let d = frameDimensions else { return nil }
        let w = Int(d.width), h = Int(d.height)
        let perFrame = measuredFrameBytes ?? (fileFormat == .raw && rawAvailable
            ? CapturePlan.estimatedRawBytes(width: w, height: h)
            : Int64(Double(w * h) * 0.35)) // HEIC estimate until the first frame is measured
        return try? CapturePlan(
            frames: frameCount, subExposure: subExposure, gap: gap, bytesPerFrame: perFrame,
            workingBytesPerFrame: mode == .stack ? CapturePlan.rgb16Bytes(width: w, height: h) : 0,
            stackBytes: CapturePlan.rgb16Bytes(width: w, height: h))
    }

    /// NPF (k = 1, the celestial equator, wide open) for this lens, once a
    /// frame's EXIF has given the real focal length (ADR-0011 §4).
    var npfSeconds: Double? {
        guard let phoneGear else { return nil }
        return try? StarExposure.npf(camera: phoneGear.camera, lens: phoneGear.lens)
    }

    // MARK: Screen lifetime

    /// The screen appeared or the app came back to the foreground.
    func appear() async {
        visible = true
        CaptureLog.event("screen visible")
        if let previous = Self.activeRun, runTask == nil {
            phase = .waitingForPreviousRun
            CaptureLog.event("waiting for the previous run to finish its cleanup")
            await previous.value
            if phase == .waitingForPreviousRun { phase = .idle }
        }
        guard visible else { return }
        savedSequence = SavedSequence.latestUnstacked()
        access = AVCaptureDevice.authorizationStatus(for: .video)
        if access == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard visible else { return }
        startSensors()
        guard access == .authorized else { return }
        if camera == nil { await configure() } else { try? await applyManual() }
        guard visible else { return }
        engine.onInterruption = { [weak self] why in
            Task { @MainActor in self?.interrupted(why) }
        }
        engine.start()
        CaptureLog.event("camera on")
    }

    /// The screen left, or the app went to the background: end any run
    /// (drained, frames kept) and release the camera and sensors.
    func leave(_ reason: EndReason) {
        visible = false
        CaptureLog.event("leave: \(reason.text); phase \(phase)")
        if let runTask {
            endRequest = endRequest ?? reason
            runTask.cancel() // stacking stops; acquisition drains its requested frames
        } else {
            Task { await releaseHardware() }
        }
    }

    private func interrupted(_ why: String) {
        CaptureLog.event("interruption: \(why)")
        guard runTask != nil, phase.isAcquiring else { return }
        endRequest = endRequest ?? .interrupted(why)
    }

    private func releaseHardware() async {
        UIApplication.shared.isIdleTimerDisabled = false
        stopSensors()
        engine.onInterruption = nil
        await engine.stopAndWait()
        CaptureLog.event("camera off, motion and timers stopped, idle timer restored")
    }

    // MARK: Configuration

    func configure() async {
        do {
            let info = try await engine.configure(lens: lens)
            camera = info
            subExposure = min(max(subExposure, 0.01), info.maxExposure)
            iso = min(max(iso, info.minISO), info.maxISO)
            aperture = info.apertures.first
            if !rawAvailable { fileFormat = .heic }
            measuredFrameBytes = nil
            phoneGear = nil
            engine.onFocusCrop = { [weak self] crop in
                let stars = StarDetector().detect(crop)
                let hfr = FocusMeasure.medianHFR(stars)
                Task { @MainActor in
                    self?.focusCrop = crop
                    self?.focusHFR = hfr
                    self?.focusStars = stars.count
                }
            }
            try await applyManual()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyManual() async throws {
        try await engine.lockExposure(seconds: subExposure, iso: iso, aperture: aperture)
        if camera?.customLensPosition == true { try await engine.lockFocus(position: focusPosition) }
    }

    func autofocus() async {
        do { focusPosition = try await engine.autofocusOnce() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Sensors

    private func startSensors() {
        guard !sensorsOn else { return }
        sensorsOn = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        sampleEnvironment()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleEnvironment() }
        }
        timers.append(t)
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 50
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let r = data?.rotationRate else { return }
                MainActor.assumeIsolated { self?.stability.add(SIMD3(r.x, r.y, r.z)) }
            }
        }
    }

    private func stopSensors() {
        sensorsOn = false
        motion.stopDeviceMotionUpdates()
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    func sampleEnvironment() {
        batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel >= 0 {
            battery.add(.init(time: Date().timeIntervalSince(started), level: Double(batteryLevel)))
        }
        thermal = ProcessInfo.processInfo.thermalState
        freeBytes = Self.freeSpace()
    }

    static func freeSpace() -> Int64 {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: Controls

    func start() {
        guard !phase.isBusy, runTask == nil, Self.activeRun == nil, let plan, let dims = frameDimensions else { return }
        sampleEnvironment()
        guard plan.fits(freeBytes: freeBytes) else {
            errorMessage = "Not enough free space: the sequence needs \(Self.bytes(plan.peakBytes)) plus a 1 GB reserve."
            return
        }
        endRequest = nil
        let task = Task { await run(plan: plan, dims: dims) }
        runTask = task
        Self.activeRun = task
    }

    /// End acquisition and stack what was shot.
    func stopAndStack() {
        guard phase.isAcquiring else { return }
        endRequest = endRequest ?? .stopAndStack
        CaptureLog.event("stop and stack requested")
    }

    /// End everything: no stack (frames kept), or stop a stack in progress.
    func cancel() {
        endRequest = endRequest ?? .cancelled
        runTask?.cancel()
        CaptureLog.event("cancel requested in phase \(phase)")
    }

    /// Stacks a saved sequence again (after a cancel, a leave or an interruption).
    func stackSaved(_ saved: SavedSequence) {
        guard !phase.isBusy, runTask == nil, Self.activeRun == nil else { return }
        endRequest = nil
        let task = Task {
            await stack(log: saved.log, folder: saved.folder)
            await finishRun()
        }
        runTask = task
        Self.activeRun = task
    }

    // MARK: The run

    private func shouldEnd() -> Bool { endRequest != nil || Task.isCancelled }

    /// Sleeps in short steps so Stop, Cancel and leaving act within 0.1 s.
    private func pause(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !shouldEnd() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func run(plan: CapturePlan, dims: CMVideoDimensions) async {
        UIApplication.shared.isIdleTimerDisabled = true
        log.removeAll()
        lastAssetIdentifiers = []
        peakFootprint = CaptureLog.footprint()
        let folder = URL.documentsDirectory.appending(path: "Captures/\(Self.folderName.string(from: Date()))")
        CaptureLog.event("run start: \(plan.frames) frames, \(subExposure) s, ISO \(Int(iso)), aperture \(aperture.map { "f/\($0)" } ?? "fixed"), lens position \(focusPosition), thermal \(CameraProbe.thermalName(ProcessInfo.processInfo.thermalState)), battery \(UIDevice.current.batteryLevel)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await applyManual()
        } catch {
            phase = .failed(error.localizedDescription)
            await finishRun()
            return
        }
        lastFolder = folder
        let request = FrameRequest(format: rawAvailable ? fileFormat : .heic, dimensions: dims)
        engine.prepare(request)

        // Self-timer, then wait (up to 15 s) for the tripod to stop moving.
        for s in stride(from: timerSeconds, to: 0, by: -1) where !shouldEnd() {
            phase = .countdown(s)
            await pause(1)
        }
        if !shouldEnd() {
            phase = .settling
            stability.reset()
            let settleStart = Date()
            while stability.isStable != true, Date().timeIntervalSince(settleStart) < 15, !shouldEnd() {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if stability.isStable != true, !shouldEnd() {
                note("The phone did not settle within 15 s; shooting anyway (frames that moved are flagged).")
            }
        }

        var entries: [SequenceLog.Frame] = []
        var pending: [(index: Int, rate: Double, exposedAt: Double, task: Task<CapturedFrame, any Error>)] = []
        var failures = 0
        let startTime = Date()
        let thermalAtStart = ProcessInfo.processInfo.thermalState
        var coolDowns = 0
        frameLoop: for i in 0..<plan.frames {
            if shouldEnd() { break }
            thermal = ProcessInfo.processInfo.thermalState
            switch ThermalPolicy.action(for: thermal, subExposure: subExposure) {
            case .proceed: break
            case .coolDown(let seconds):
                coolDowns += 1
                phase = .coolingDown(seconds)
                note("Frame \(i + 1): thermal state \(CameraProbe.thermalName(thermal)), pausing \(Int(seconds)) s.")
                await pause(seconds)
                if shouldEnd() { break frameLoop }
            case .stop:
                endRequest = endRequest ?? .tooHot
                break frameLoop
            }
            phase = .capturing(frame: i + 1, of: plan.frames)
            let base = folder.appending(path: String(format: "frame-%04d", i + 1))
            // Request the next frame as soon as this one's exposure ends; keep
            // at most two frames being written behind it.
            let exposed = AsyncStream<Void>.makeStream()
            let engine = engine
            let task = Task.detached { try await engine.capture(request, to: base) { exposed.continuation.finish() } }
            let watcher = Task.detached { _ = try? await task.value; exposed.continuation.finish() }
            for await _ in exposed.stream {}
            watcher.cancel()
            pending.append((i + 1, stability.meanRate ?? 0, Date().timeIntervalSince(startTime), task))
            peakFootprint = max(peakFootprint, CaptureLog.footprint())
            if pending.count >= 2 {
                let first = pending.removeFirst()
                if await record(first, into: &entries) == nil { failures += 1 }
            }
            if failures >= 3 {
                endRequest = endRequest ?? .failures
                break
            }
            if gap > 0 { await pause(gap) }
        }
        // Drain: every requested frame finishes writing, whatever ended the loop.
        phase = .draining
        for item in pending { _ = await record(item, into: &entries) }
        pending.removeAll()
        let elapsed = Date().timeIntervalSince(startTime)
        let intervals = zip(entries.dropFirst(), entries).map { $0.exposedAt - $1.exposedAt }
        let ended = endRequest
        note(String(format: "%d of %d frames in %.1f s; frame interval %@; peak memory %d MB; thermal %@ → %@%@.",
                    entries.count, plan.frames, elapsed,
                    intervals.isEmpty ? "n/a" : String(format: "mean %.2f s, max %.2f s", intervals.reduce(0, +) / Double(intervals.count), intervals.max()!),
                    Int(peakFootprint / 1_000_000), CameraProbe.thermalName(thermalAtStart),
                    CameraProbe.thermalName(ProcessInfo.processInfo.thermalState),
                    coolDowns > 0 ? ", \(coolDowns) cool-down pause(s)" : ""))
        if let ended { note("Acquisition ended early: \(ended.text).") }
        CaptureLog.event("acquisition done: \(log.last ?? "")")
        let sequence = SequenceLog(
            created: Date(), lens: lens.rawValue, mode: mode.rawValue, subExposure: subExposure, iso: Double(iso),
            aperture: aperture.map(Double.init), focusLensPosition: Double(focusPosition),
            format: request.format.rawValue, width: Int(dims.width), height: Int(dims.height),
            thermalAtEnd: CameraProbe.thermalName(ProcessInfo.processInfo.thermalState),
            batteryAtEnd: Double(UIDevice.current.batteryLevel), peakMemoryMB: Int(peakFootprint / 1_000_000),
            ended: ended?.text, frames: entries, notes: log, stack: nil)
        sequence.write(to: folder)
        if entries.isEmpty {
            phase = .stopped("No frame was captured\(ended.map { ": \($0.text)" } ?? ".")")
        } else if let ended, !ended.stacks {
            phase = .stopped("\(entries.count) frames kept, not stacked: \(ended.text). Stack them from this screen later.")
        } else if !Task.isCancelled {
            await stack(log: sequence, folder: folder)
        }
        await finishRun()
    }

    /// Releases what the run held: the idle-timer override always, and the
    /// camera and sensors too when the screen is gone or the app inactive.
    private func finishRun() async {
        UIApplication.shared.isIdleTimerDisabled = false
        if !visible { await releaseHardware() }
        savedSequence = SavedSequence.latestUnstacked()
        freeBytes = Self.freeSpace()
        runTask = nil
        Self.activeRun = nil
        CaptureLog.event("run finished: \(phase); idle timer restored; camera \(engine.isRunning ? "on (screen visible)" : "off")")
    }

    private func record(_ item: (index: Int, rate: Double, exposedAt: Double, task: Task<CapturedFrame, any Error>),
                        into entries: inout [SequenceLog.Frame]) async -> CapturedFrame? {
        do {
            // A frame whose capture was cut off (lock, interruption) may never
            // report back: wait at most 15 s so the drain always ends.
            guard let result = await Self.firstOf(item.task, seconds: 15) else {
                note("Frame \(item.index) did not finish writing within 15 s.")
                CaptureLog.event("frame \(item.index) timed out while draining")
                return nil
            }
            let frame = try result.get()
            measuredFrameBytes = frame.bytes
            let moved = item.rate > stability.maxMeanRate * 3
            entries.append(SequenceLog.Frame(
                index: item.index, file: frame.url.lastPathComponent, bytes: frame.bytes, exposure: frame.exposure,
                iso: frame.iso, fNumber: frame.fNumber, width: frame.width, height: frame.height,
                exposedAt: item.exposedAt, meanRotationRate: item.rate, moved: moved))
            CaptureLog.event(String(format: "frame %d saved %@ %dx%d, exposure %@ s, ISO %@, f/%@, %.1f MB, at %.2f s",
                                    item.index, frame.url.lastPathComponent, frame.width, frame.height,
                                    frame.exposure.map { String(format: "%.4f", $0) } ?? "?",
                                    frame.iso.map { String(format: "%.0f", $0) } ?? "?",
                                    frame.fNumber.map { String(format: "%.2f", $0) } ?? "?",
                                    Double(frame.bytes) / 1e6, item.exposedAt))
            if phoneGear == nil, let f = frame.focalLength, let f35 = frame.focalLength35, let n = frame.fNumber {
                phoneGear = try? PhoneGear.profiles(name: "iPhone \(lens.title)", focalLengthMM: f,
                                                    focalLength35mmEquivalent: f35, fNumber: n,
                                                    widthPx: frame.width, heightPx: frame.height)
            }
            return frame
        } catch {
            note("Frame \(item.index) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The task's result, or nil after `seconds`, whichever comes first.
    private static func firstOf(_ task: Task<CapturedFrame, any Error>, seconds: Double) async -> Result<CapturedFrame, any Error>? {
        await withCheckedContinuation { (c: CheckedContinuation<Result<CapturedFrame, any Error>?, Never>) in
            let once = ResumeOnce(c)
            Task.detached { once.resume(await task.result) }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(nil)
            }
        }
    }

    private func stack(log sequence: SequenceLog, folder: URL) async {
        let usable = sequence.frames.filter { !$0.moved }
        if usable.count < sequence.frames.count {
            note("\(sequence.frames.count - usable.count) frame(s) moved and are left out of the stack (still saved).")
        }
        let frames = usable.map { StackBuilder.Frame(url: folder.appending(path: $0.file), exposure: $0.exposure, iso: $0.iso) }
        let trails = sequence.mode == Mode.trails.rawValue
        let output = folder.appending(path: trails ? "star-trails.tif" : "stack.tif")
        let builder = StackBuilder(frames: frames, mode: trails ? .maximum : .sigmaClippedMean, output: output,
                                   workDirectory: URL.cachesDirectory.appending(path: "stack-work/\(folder.lastPathComponent)"))
        phase = .stacking(0, "Starting")
        let progress: @Sendable (Double, String) -> Void = { [weak self] fraction, message in
            Task { @MainActor in
                guard let self, self.phase.isStacking else { return }
                self.phase = .stacking(fraction, message)
            }
        }
        let start = Date()
        let work = Task.detached(priority: .userInitiated) { try builder.run(progress: progress) }
        // Cancelling the run (Cancel, leaving, background) cancels the stack.
        let result = await withTaskCancellationHandler {
            await work.result
        } onCancel: {
            work.cancel()
        }
        let seconds = Date().timeIntervalSince(start)
        var finished = sequence
        switch result {
        case .success(let report):
            finished.stack = report.description
            lastStack = output
            note(String(format: "Stacked %d of %d frames in %.1f s%@.", report.used, report.frames, seconds,
                        report.unalignedReason.map { " (\($0))" } ?? ""))
            phase = .finished("\(report.used) frames \(trails ? "combined" : "stacked"). Saved in Files › Dark Sky › Captures.")
        case .failure(let error as CancellationError):
            _ = error
            finished.stack = nil
            note(String(format: "Stacking stopped after %.1f s; the frames are kept.", seconds))
            phase = .stopped("Stacking stopped. The \(sequence.frames.count) frames are kept; stack them again from this screen.")
        case .failure(let error):
            finished.stack = "failed: \(error.localizedDescription)"
            phase = .failed("\(error.localizedDescription) The \(sequence.frames.count) frames are kept.")
        }
        CaptureLog.event("stack: \(log.last ?? "")")
        finished.notes = log
        finished.write(to: folder)
    }

    // MARK: Photos

    /// Adds the frames and the stack to the photo library (add-only access)
    /// and returns the new assets' local identifiers.
    func saveToPhotos(_ folder: URL) async throws -> [String] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        CaptureLog.event("photos add-only authorization: \(status.rawValue)")
        guard status == .authorized || status == .limited else { throw CaptureError.captureFailed("Photos access was not given") }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["dng", "heic", "tif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let box = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges {
            for url in files {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
                if let id = request.placeholderForCreatedAsset?.localIdentifier { box.ids.append(id) }
            }
        }
        lastAssetIdentifiers = box.ids
        CaptureLog.event("saved to Photos: \(box.ids.count) assets \(box.ids)")
        return box.ids
    }

    private func note(_ line: String) { log.append(line) }

    static let folderName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

nonisolated private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<Result<CapturedFrame, any Error>?, Never>?
    private let lock = NSLock()

    init(_ c: CheckedContinuation<Result<CapturedFrame, any Error>?, Never>) { continuation = c }

    func resume(_ value: Result<CapturedFrame, any Error>?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

nonisolated private final class IdentifierBox: @unchecked Sendable {
    var ids: [String] = []
}

/// `sequence.json` beside the frames: every setting and per-frame fact, so
/// a stack can be reproduced from the saved frames (ADR-0011 §3).
nonisolated struct SequenceLog: Codable, Sendable {
    struct Frame: Codable, Sendable {
        let index: Int
        let file: String
        let bytes: Int64
        let exposure: Double?
        let iso: Double?
        let fNumber: Double?
        let width: Int
        let height: Int
        /// Seconds from the first frame request to this frame's exposure end.
        let exposedAt: Double
        var meanRotationRate: Double
        var moved: Bool
    }

    let created: Date
    let lens: String
    let mode: String
    let subExposure: Double
    let iso: Double
    let aperture: Double?
    let focusLensPosition: Double
    let format: String
    let width: Int
    let height: Int
    let thermalAtEnd: String
    let batteryAtEnd: Double
    let peakMemoryMB: Int
    let ended: String?
    var frames: [Frame]
    var notes: [String]
    var stack: String?

    func write(to folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: folder.appending(path: "sequence.json"), options: .atomic)
    }
}

/// The newest saved sequence with no stack yet, offered for stacking.
nonisolated struct SavedSequence: Sendable, Equatable {
    let folder: URL
    let log: SequenceLog

    static func == (a: Self, b: Self) -> Bool { a.folder == b.folder }

    static func latestUnstacked() -> SavedSequence? {
        let root = URL.documentsDirectory.appending(path: "Captures")
        let folders = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for folder in folders.prefix(10) {
            guard let data = try? Data(contentsOf: folder.appending(path: "sequence.json")),
                  let log = try? decoder.decode(SequenceLog.self, from: data) else { continue }
            if log.stack == nil, !log.frames.isEmpty { return SavedSequence(folder: folder, log: log) }
            return nil // the newest sequence is stacked: nothing pending
        }
        return nil
    }
}
