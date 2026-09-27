#if DEBUG
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import SkyCore
import Photos
import UIKit

/// `-CaptureBench YES`: times star detection, registration and stacking on
/// synthetic 12 MP RGB frames with known transforms, prints the timings and
/// the registration error, and exits. Nothing touches the camera or disk.
@_cdecl("ds_capture_bench_install")
nonisolated func captureBenchInstall() {
    guard UserDefaults.standard.bool(forKey: "CaptureBench") else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        CaptureDebug.bench(frames: UserDefaults.standard.integer(forKey: "CaptureBenchFrames").nonZero ?? 8)
        fflush(stdout)
        exit(0)
    }
}

/// `-CaptureSelfTest YES`: the real run path (CaptureModel) headless: a
/// 5-frame sequence on the main camera at the longest exposure, ISO fixed,
/// focus locked at the far end of the lens travel, RAW where offered; the
/// stack; then the frames and stack added to Photos (add-only access, which
/// needs the owner's tap the first time). Prints EXIF, timing and asset ids.
@_cdecl("ds_capture_selftest_install")
nonisolated func captureSelfTestInstall() {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: "CaptureDeleteCaptures") {
        // Test cleanup: every sequence in the app's Captures folder (not Photos).
        let root = URL.documentsDirectory.appending(path: "Captures")
        let count = (try? FileManager.default.contentsOfDirectory(atPath: root.path).count) ?? 0
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "stack-work"))
        CaptureDebug.say("deleted \(count) capture folder(s)")
        exit(0)
    }
    guard defaults.bool(forKey: "CaptureSelfTest") || defaults.bool(forKey: "CaptureLifecycleTest") else { return }
    DispatchQueue.main.async {
        Task { @MainActor in
            if defaults.bool(forKey: "CaptureSelfTest") { await CaptureDebug.selfTest() }
            if defaults.bool(forKey: "CaptureLifecycleTest") { await CaptureDebug.lifecycleTest() }
            fflush(stdout)
            exit(0)
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

nonisolated enum CaptureDebug {
    static func say(_ line: String) {
        print("CAPTURE| " + line)
        fflush(stdout)
    }

    static func bench(frames n: Int) {
        let w = 4032, h = 3024
        say("bench: \(n) synthetic frames \(w)x\(h) RGB16, 600 stars")
        let stars = SyntheticStarField.stars(count: 600, width: w, height: h, seed: 42)
        func truth(_ i: Int) -> RigidTransform {
            RigidTransform(rotationDegrees: 0.02 * Double(i), about: 2016, -9000, shiftX: 0.4 * Double(i), shiftY: -0.3 * Double(i))
        }
        var t = Date()
        // As StackBuilder does: each decoded frame goes to a file and is
        // memory-mapped, so 20 frames of 72 MB need not all sit in RAM.
        let dir = URL.temporaryDirectory.appending(path: "capture-bench")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var rasters: [RasterU16] = []
        for i in 0..<n {
            let url = dir.appending(path: "f\(i).rgb16")
            autoreleasepool {
                let r = SyntheticStarField.render(stars, width: w, height: h, channels: 3, frameFromReference: truth(i), seed: UInt64(i + 1))
                try? r.data.write(to: url)
            }
            guard let mapped = try? Data(contentsOf: url, options: .alwaysMapped) else { say("bench: could not map frame \(i)"); return }
            rasters.append(RasterU16(width: w, height: h, channels: 3, data: mapped))
        }
        say(String(format: "render + write (not part of stacking): %.2f s; footprint %d MB", Date().timeIntervalSince(t), Int(CaptureLog.footprint() / 1_000_000)))
        let detector = StarDetector()
        t = Date()
        var lists: [[DetectedStar]] = []
        for r in rasters {
            let found = detector.detect(ImagePlane.luminance(r, bin: 2))
            lists.append(found.map { DetectedStar(x: $0.x * 2 + 0.5, y: $0.y * 2 + 0.5, flux: $0.flux, peak: $0.peak, area: $0.area, hfr: $0.hfr) })
        }
        let detect = Date().timeIntervalSince(t)
        say(String(format: "luminance+detect: %.2f s total, %.3f s/frame, %d stars in frame 0", detect, detect / Double(n), lists[0].count))
        t = Date()
        var transforms: [RigidTransform] = []
        var worst = 0.0
        for i in 0..<n {
            do {
                let reg = try StarMatcher().register(reference: lists[0], frame: lists[i])
                transforms.append(reg.transform)
                for (x, y) in [(0.0, 0.0), (Double(w - 1), 0), (0, Double(h - 1)), (Double(w - 1), Double(h - 1))] {
                    let f = truth(i).apply(x, y)
                    let back = reg.transform.apply(f.x, f.y)
                    worst = max(worst, hypot(back.x - x, back.y - y))
                }
            } catch {
                say("frame \(i) not registered: \(error)")
                transforms.append(.identity)
            }
        }
        let register = Date().timeIntervalSince(t)
        say(String(format: "register: %.3f s total; worst corner error %.3f px", register, worst))
        t = Date()
        let before = CaptureLog.footprint()
        guard let result = try? FrameStacker().sigmaClipped(rasters, transforms: transforms) else { return }
        let combine = Date().timeIntervalSince(t)
        say(String(format: "sigma-clipped combine of %d frames: %.2f s (%d uncovered samples); footprint %d MB before, %d MB after",
                   n, combine, result.uncovered, Int(before / 1_000_000), Int(CaptureLog.footprint() / 1_000_000)))
        t = Date()
        var acc = StackAccumulator(mode: .maximum, width: w, height: h, channels: 3)
        for r in rasters { try? acc.add(r) }
        _ = acc.result
        say(String(format: "maximum (trails) of %d frames: %.2f s", n, Date().timeIntervalSince(t)))
        say("bench done")
    }

    @MainActor
    static func waitIdle(_ model: CaptureModel, timeout: TimeInterval) async {
        let end = Date().addingTimeInterval(timeout)
        try? await Task.sleep(for: .milliseconds(200))
        while model.phase.isBusy, Date() < end { try? await Task.sleep(for: .milliseconds(100)) }
    }

    @MainActor
    static func selfTest() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            say("selftest: camera permission is not granted; open Tools > Tripod capture once and tap Allow")
            return
        }
        let model = CaptureModel()
        model.frameOverride = 5
        model.timerSeconds = 0
        model.iso = Float(UserDefaults.standard.double(forKey: "CaptureSelfTestISO").nonZeroDouble ?? 800)
        model.focusPosition = 1 // far end of the lens travel; true infinity is set on stars with the focus assist
        await model.appear()
        guard let camera = model.camera else { say("selftest: camera did not configure: \(model.errorMessage ?? "?")"); return }
        say("selftest: main camera max exposure \(camera.maxExposure) s, ISO \(camera.minISO)-\(camera.maxISO), apertures \(camera.apertures), RAW \(camera.proRaw.map(CameraProbe.fourCC) ?? "none"), shutter-sound suppression \(camera.shutterSoundSuppression)")
        try? await Task.sleep(for: .seconds(2))
        let raw = model.engine.runningRawFormats
        say("selftest: running session RAW: bayer \(raw.bayer), proRAW \(raw.proRaw)")
        model.subExposure = camera.maxExposure
        model.fileFormat = .raw
        say("selftest: plan \(model.frameCount) frames x \(model.subExposure) s, ISO \(Int(model.iso)), f/\(model.aperture ?? 0), \(model.frameDimensions.map { "\($0.width)x\($0.height)" } ?? "?"), storage \(model.plan.map { CaptureModel.bytes($0.storedBytes) } ?? "?"), free \(CaptureModel.bytes(model.freeBytes)), battery \(model.batteryLevel), thermal \(CameraProbe.thermalName(model.thermal))")
        model.start()
        await waitIdle(model, timeout: 300)
        for line in model.log { say("selftest log: \(line)") }
        say("selftest: phase \(model.phase)")
        if let npf = model.npfSeconds, let gear = model.phoneGear {
            say(String(format: "selftest: phone gear focal %.2f mm, pitch %.3f um, crop %.2f, NPF(k=1) %.2f s",
                       gear.lens.focalLengthMM, gear.camera.pixelPitchUM, gear.camera.cropFactor, npf))
        }
        if let stack = model.lastStack, let src = CGImageSourceCreateWithURL(stack as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            let bytes = (try? stack.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            say("selftest: stack \(stack.lastPathComponent): depth \(props[kCGImagePropertyDepth as String] ?? "?"), \(props[kCGImagePropertyPixelWidth as String] ?? "?")x\(props[kCGImagePropertyPixelHeight as String] ?? "?"), profile \(props[kCGImagePropertyProfileName as String] ?? "?"), \(bytes / 1_000_000) MB")
        }
        if let folder = model.lastFolder {
            say("selftest: photos add-only status before request: \(PHPhotoLibrary.authorizationStatus(for: .addOnly).rawValue) (0 notDetermined, 2 denied, 3 authorized)")
            let save = Task { try await model.saveToPhotos(folder) }
            let timeout = Task { try await Task.sleep(for: .seconds(60)); save.cancel() }
            switch await save.result {
            case .success(let ids): say("selftest: Photos asset ids \(ids)")
            case .failure(let error): say("selftest: not saved to Photos (\(error.localizedDescription)); status \(PHPhotoLibrary.authorizationStatus(for: .addOnly).rawValue)")
            }
            timeout.cancel()
        }
        model.leave(.leftScreen)
        try? await Task.sleep(for: .seconds(1.5))
        say("selftest: after leave, camera running \(model.engine.isRunning), idle timer disabled \(UIApplication.shared.isIdleTimerDisabled)")
    }

    /// `-CaptureLifecycleTest YES`: leave during the countdown, during
    /// acquisition and during stacking, each followed by a new screen
    /// model (as navigating back and returning does); checks one run at a
    /// time, drained frames, camera off, idle timer restored.
    @MainActor
    static func lifecycleTest() async {
        func state(_ label: String, _ m: CaptureModel) {
            say("lifecycle \(label): phase \(m.phase), camera running \(m.engine.isRunning), idle timer disabled \(UIApplication.shared.isIdleTimerDisabled), footprint \(CaptureLog.footprint() / 1_000_000) MB")
        }
        func fresh() async -> CaptureModel {
            let m = CaptureModel()
            m.frameOverride = 8
            m.timerSeconds = 3
            m.iso = 800
            await m.appear()
            m.subExposure = m.camera?.maxExposure ?? 1
            return m
        }
        // 1. Leave during the countdown.
        var m = await fresh()
        m.start()
        try? await Task.sleep(for: .seconds(1.2))
        state("1 before leave (countdown)", m)
        m.leave(.leftScreen)
        await waitIdle(m, timeout: 30)
        try? await Task.sleep(for: .seconds(0.5))
        state("1 after leave", m)

        // 2. Leave during acquisition; a second model opened at once must wait.
        m = await fresh()
        m.start()
        while !{ if case .capturing(let f, _) = m.phase { f >= 3 } else { false } }() {
            try? await Task.sleep(for: .milliseconds(100))
            if !m.phase.isBusy { break }
        }
        state("2 before leave (acquiring)", m)
        let left = Date()
        m.leave(.leftScreen)
        let second = CaptureModel()
        let secondAppear = Task { await second.appear() }
        try? await Task.sleep(for: .milliseconds(300))
        say("lifecycle 2: new screen while draining shows phase \(second.phase)")
        await waitIdle(m, timeout: 30)
        say(String(format: "lifecycle 2: run ended %.2f s after leave; log: %@", Date().timeIntervalSince(left), m.log.joined(separator: " | ")))
        state("2 after leave", m)
        await secondAppear.value
        state("2 second model", second)
        let saved = second.savedSequence
        say("lifecycle 2: saved unstacked sequence \(saved?.folder.lastPathComponent ?? "none") with \(saved?.log.frames.count ?? 0) frames, ended \(saved?.log.ended ?? "-")")

        // 3. Stack the saved frames, then leave half a second in.
        if let saved {
            second.stackSaved(saved)
            try? await Task.sleep(for: .milliseconds(500))
            state("3 before leave (stacking)", second)
            let t = Date()
            second.leave(.leftScreen)
            await waitIdle(second, timeout: 30)
            say(String(format: "lifecycle 3: stacking stopped %.2f s after leave; %@", Date().timeIntervalSince(t), second.log.last ?? ""))
            state("3 after leave", second)
            // 4. Back again: the same sequence is offered and stacks to completion.
            let third = CaptureModel()
            await third.appear()
            if let again = third.savedSequence {
                let t4 = Date()
                third.stackSaved(again)
                await waitIdle(third, timeout: 300)
                say(String(format: "lifecycle 4: restack %@ in %.1f s: %@", "\(third.phase)", Date().timeIntervalSince(t4), third.log.last ?? ""))
            }
            third.leave(.leftScreen)
            try? await Task.sleep(for: .seconds(1.5))
            state("4 after leave", third)
            if !UserDefaults.standard.bool(forKey: "CaptureKeepTestFrames") {
                try? FileManager.default.removeItem(at: saved.folder)
                say("lifecycle: deleted test folder \(saved.folder.lastPathComponent)")
            }
        }
        // Folders from part 1 (no frames) are removed too.
        let root = URL.documentsDirectory.appending(path: "Captures")
        for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if !files.contains(where: { $0.hasSuffix(".dng") || $0.hasSuffix(".heic") }) { try? FileManager.default.removeItem(at: folder) }
        }
        say("lifecycle done")
    }
}

private extension Double {
    var nonZeroDouble: Double? { self == 0 ? nil : self }
}
#endif
