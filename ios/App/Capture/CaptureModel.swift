import AVFoundation
import CoreMotion
import Foundation
import Observation
import SkyCore
import UIKit

/// The capture screen's state and the sequence runner (ADR-0011): locked
/// manual exposure and focus, a self-timer that waits for the tripod to
/// settle, frames requested back to back, thermal throttling, every frame
/// kept with a JSON log, then a stack built on the phone.
@Observable
final class CaptureModel {
    enum Mode: String, CaseIterable, Identifiable {
        case stack, trails
        var id: String { rawValue }
        var title: String { self == .stack ? "Stack" : "Star trails" }
    }

    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case settling
        case capturing(frame: Int, of: Int)
        case coolingDown(TimeInterval)
        case stacking(Double, String)
        case finished(String)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .countdown, .settling, .capturing, .coolingDown, .stacking: true
            default: false
            }
        }
    }

    // Settings (persisted by the view with @AppStorage mirrors where useful).
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
    private(set) var log: [String] = []
    var errorMessage: String?

    @ObservationIgnored let engine = CaptureEngine()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private let started = Date()

    // MARK: Derived plan

    var frameCount: Int {
        switch mode {
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

    // MARK: Lifecycle

    func appear() async {
        access = AVCaptureDevice.authorizationStatus(for: .video)
        if access == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
        startSensors()
        guard access == .authorized else { return }
        await configure()
        engine.start()
    }

    func disappear() {
        guard !phase.isRunning else { return }
        engine.stop()
        stopSensors()
    }

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
        UIDevice.current.isBatteryMonitoringEnabled = true
        sampleEnvironment()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleEnvironment() }
        }
        timers.append(t)
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 50
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let r = data?.rotationRate else { return }
                MainActor.assumeIsolated { self?.stability.add(SIMD3(r.x, r.y, r.z)) }
            }
        }
    }

    private func stopSensors() {
        motion.stopDeviceMotionUpdates()
        timers.forEach { $0.invalidate() }
        timers.removeAll()
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
        let url = URL.documentsDirectory
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: Sequence

    func start() {
        guard !phase.isRunning, let plan, let dims = frameDimensions else { return }
        guard plan.fits(freeBytes: freeBytes) else {
            errorMessage = "Not enough free space: the sequence needs \(Self.bytes(plan.peakBytes)) plus a 1 GB reserve."
            return
        }
        runTask = Task { await run(plan: plan, dims: dims) }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func run(plan: CapturePlan, dims: CMVideoDimensions) async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        log.removeAll()
        let folder = URL.documentsDirectory.appending(path: "Captures/\(Self.folderName.string(from: Date()))")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await applyManual()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        lastFolder = folder
        let request = FrameRequest(format: rawAvailable ? fileFormat : .heic, dimensions: dims)
        engine.prepare(request)

        // Self-timer, then wait (up to 15 s) for the tripod to stop moving.
        for s in stride(from: timerSeconds, to: 0, by: -1) {
            phase = .countdown(s)
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { phase = .idle; return }
        }
        phase = .settling
        stability.reset()
        let settleStart = Date()
        while stability.isStable != true, Date().timeIntervalSince(settleStart) < 15 {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { phase = .idle; return }
        }
        if stability.isStable != true { note("The phone did not settle within 15 s; shooting anyway (frames that moved are flagged).") }

        var entries: [SequenceLog.Frame] = []
        var pending: [Task<CapturedFrame, any Error>] = []
        var failures = 0
        let startTime = Date()
        frameLoop: for i in 0..<plan.frames {
            if Task.isCancelled { note("Stopped by you after \(i) frames."); break }
            thermal = ProcessInfo.processInfo.thermalState
            switch ThermalPolicy.action(for: thermal, subExposure: subExposure) {
            case .proceed: break
            case .coolDown(let pause):
                phase = .coolingDown(pause)
                note("Frame \(i + 1): thermal state \(CameraProbe.thermalName(thermal)), pausing \(Int(pause)) s.")
                try? await Task.sleep(for: .seconds(pause))
            case .stop:
                note("Stopped at frame \(i + 1): the phone is critically hot. Frames so far are kept.")
                break frameLoop
            }
            phase = .capturing(frame: i + 1, of: plan.frames)
            let base = folder.appending(path: String(format: "frame-%04d", i + 1))
            // Request the next frame as soon as this one's exposure ends; keep
            // at most two frames being written behind it.
            let exposed = AsyncStream<Void>.makeStream()
            let engine = engine
            let task = Task.detached { try await engine.capture(request, to: base) { exposed.continuation.finish() } }
            pending.append(task)
            let watcher = Task { _ = try? await task.value; exposed.continuation.finish() }
            for await _ in exposed.stream {}
            watcher.cancel()
            let rate = stability.meanRate ?? 0
            if pending.count >= 2 {
                let first = pending.removeFirst()
                if let frame = await record(first, entries: &entries) { measuredFrameBytes = frame.bytes } else { failures += 1 }
            }
            if failures >= 3 { note("Stopped: three frames failed."); break }
            lastRates[i] = rate
            if gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
        }
        for task in pending {
            if let frame = await record(task, entries: &entries) { measuredFrameBytes = frame.bytes }
        }
        let elapsed = Date().timeIntervalSince(startTime)
        for i in entries.indices {
            let rate = lastRates[entries[i].index - 1] ?? 0
            entries[i].meanRotationRate = rate
            entries[i].moved = rate > stability.maxMeanRate * 3
        }
        lastRates.removeAll()
        note(String(format: "%d frames in %.1f s (%.2f s per frame).", entries.count, elapsed,
                    elapsed / Double(max(entries.count, 1))))
        let sequence = SequenceLog(
            created: Date(), lens: lens.rawValue, mode: mode.rawValue, subExposure: subExposure, iso: Double(iso),
            aperture: aperture.map(Double.init), focusLensPosition: Double(focusPosition),
            format: request.format.rawValue, width: Int(dims.width), height: Int(dims.height),
            thermalAtEnd: CameraProbe.thermalName(ProcessInfo.processInfo.thermalState),
            batteryAtEnd: Double(UIDevice.current.batteryLevel), frames: entries, notes: log, stack: nil)
        sequence.write(to: folder)
        guard !entries.isEmpty else { phase = .failed("No frame was captured."); return }
        await stack(entries: entries, folder: folder, sequence: sequence)
    }

    @ObservationIgnored private var lastRates: [Int: Double] = [:]

    private func record(_ task: Task<CapturedFrame, any Error>, entries: inout [SequenceLog.Frame]) async -> CapturedFrame? {
        do {
            let frame = try await task.value
            let index = Int(frame.url.deletingPathExtension().lastPathComponent.dropFirst("frame-".count)) ?? entries.count + 1
            entries.append(SequenceLog.Frame(
                index: index, file: frame.url.lastPathComponent, bytes: frame.bytes, exposure: frame.exposure,
                iso: frame.iso, fNumber: frame.fNumber, meanRotationRate: 0, moved: false))
            if phoneGear == nil, let f = frame.focalLength, let f35 = frame.focalLength35, let n = frame.fNumber {
                phoneGear = try? PhoneGear.profiles(name: "iPhone \(lens.title)", focalLengthMM: f,
                                                    focalLength35mmEquivalent: f35, fNumber: n,
                                                    widthPx: frame.width, heightPx: frame.height)
            }
            return frame
        } catch {
            note("A frame failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func stack(entries: [SequenceLog.Frame], folder: URL, sequence: SequenceLog) async {
        let usable = entries.filter { !$0.moved }
        if usable.count < entries.count { note("\(entries.count - usable.count) frame(s) moved and are left out of the stack (still saved).") }
        let frames = usable.map { StackBuilder.Frame(url: folder.appending(path: $0.file), exposure: $0.exposure, iso: $0.iso) }
        let stackMode: StackMode = mode == .trails ? .maximum : .sigmaClippedMean
        let output = folder.appending(path: mode == .trails ? "star-trails.tif" : "stack.tif")
        let builder = StackBuilder(frames: frames, mode: stackMode, output: output,
                                   workDirectory: URL.cachesDirectory.appending(path: "stack-work/\(folder.lastPathComponent)"))
        phase = .stacking(0, "Starting")
        let report: @Sendable (Double, String) -> Void = { [weak self] fraction, message in
            Task { @MainActor in self?.phase = .stacking(fraction, message) }
        }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try builder.run(progress: report) }
        }.value
        var finished = sequence
        switch result {
        case .success(let report):
            finished.stack = report.description
            finished.notes = log
            finished.write(to: folder)
            lastStack = output
            phase = .finished("\(report.used) frames \(mode == .trails ? "combined" : "stacked"). Saved in Files › Dark Sky › Captures.")
        case .failure(let error):
            finished.stack = "failed: \(error.localizedDescription)"
            finished.write(to: folder)
            phase = .failed("\(error.localizedDescription) The \(entries.count) frames are kept.")
        }
        freeBytes = Self.freeSpace()
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
