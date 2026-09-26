#if DEBUG
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import SkyCore
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

/// `-CaptureSelfTest YES`: a real three-frame sequence on the main camera at
/// the longest exposure. Prints each frame's EXIF (exposure, ISO, aperture,
/// size) and timing, stacks them, prints the report, then deletes every file
/// it wrote. No image leaves the phone. Needs camera permission and an
/// unlocked phone.
@_cdecl("ds_capture_selftest_install")
nonisolated func captureSelfTestInstall() {
    guard UserDefaults.standard.bool(forKey: "CaptureSelfTest") else { return }
    DispatchQueue.main.async {
        Task {
            await CaptureDebug.selfTest()
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
        let rasters = (0..<n).map { i in
            SyntheticStarField.render(stars, width: w, height: h, channels: 3, frameFromReference: truth(i), seed: UInt64(i + 1))
        }
        say(String(format: "render (not timed as part of stacking): %.2f s", Date().timeIntervalSince(t)))
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
        let result = FrameStacker().sigmaClipped(rasters, transforms: transforms)
        let combine = Date().timeIntervalSince(t)
        say(String(format: "sigma-clipped combine of %d frames: %.2f s (%d uncovered samples)", n, combine, result.uncovered))
        t = Date()
        var acc = StackAccumulator(mode: .maximum, width: w, height: h, channels: 3)
        for r in rasters { acc.add(r) }
        _ = acc.result
        say(String(format: "maximum (trails) of %d frames: %.2f s", n, Date().timeIntervalSince(t)))
        say("bench done")
    }

    @MainActor
    static func selfTest() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            say("selftest: camera permission is not granted; open Tools > Tripod capture once and tap Allow")
            return
        }
        let engine = CaptureEngine()
        let folder = URL.temporaryDirectory.appending(path: "capture-selftest")
        try? FileManager.default.removeItem(at: folder)
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "stack-work/selftest"))
            say("selftest: deleted \(folder.lastPathComponent) and its work files")
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info = try await engine.configure(lens: .main)
            say("selftest: main camera max exposure \(info.maxExposure) s, ISO \(info.minISO)-\(info.maxISO), apertures \(info.apertures), RAW \(info.proRaw.map(CameraProbe.fourCC) ?? "none"), shutter-sound suppression \(info.shutterSoundSuppression)")
            say("selftest: photo sizes \(info.photoDimensions.map { "\($0.width)x\($0.height)" })")
            engine.start()
            try await Task.sleep(for: .seconds(2))
            let raw = engine.runningRawFormats
            say("selftest: running session RAW: bayer \(raw.bayer), proRAW \(raw.proRaw)")
            let iso = Float(UserDefaults.standard.double(forKey: "CaptureSelfTestISO").nonZeroDouble ?? 400)
            try await engine.lockExposure(seconds: info.maxExposure, iso: iso, aperture: info.apertures.first)
            let position = engine.lensPosition
            try await engine.lockFocus(position: position)
            try await Task.sleep(for: .seconds(2.5))
            let dims = info.photoDimensions.sorted { $0.width * $0.height < $1.width * $1.height }
                .first { Int($0.width) * Int($0.height) >= 12_000_000 } ?? info.photoDimensions[0]
            let formats: [FrameRequest.FileFormat] = info.proRaw != nil ? [.raw, .raw, .raw, .heic] : [.heic, .heic, .heic]
            var frames: [CapturedFrame] = []
            var exposedAt: [Date] = []
            let start = Date()
            for (i, format) in formats.enumerated() {
                let request = FrameRequest(format: format, dimensions: dims)
                if i == 0 { engine.prepare(request) }
                let frame = try await engine.capture(request, to: folder.appending(path: String(format: "frame-%04d", i + 1))) {}
                exposedAt.append(Date())
                frames.append(frame)
                say(String(format: "frame %d %@: exposure %@ s, ISO %@, f/%@, focal %@ mm (%@ mm eq), %dx%d, %.1f MB, request->exposed %.2f s",
                           i + 1, frame.url.pathExtension, frame.exposure.map { String(format: "%.4f", $0) } ?? "?",
                           frame.iso.map { String(format: "%.0f", $0) } ?? "?", frame.fNumber.map { String(format: "%.2f", $0) } ?? "?",
                           frame.focalLength.map { String(format: "%.2f", $0) } ?? "?", frame.focalLength35.map { String(format: "%.0f", $0) } ?? "?",
                           frame.width, frame.height, Double(frame.bytes) / 1e6, frame.requestToCaptured))
            }
            let total = Date().timeIntervalSince(start)
            say(String(format: "selftest: %d frames of %.2f s in %.2f s (sequential, each awaited)", frames.count, info.maxExposure, total))
            if let f = frames.first, let fl = f.focalLength, let f35 = f.focalLength35, let n = f.fNumber,
               let gear = try? PhoneGear.profiles(name: "main", focalLengthMM: fl, focalLength35mmEquivalent: f35, fNumber: n, widthPx: f.width, heightPx: f.height) {
                let npf = (try? StarExposure.npf(camera: gear.camera, lens: gear.lens)) ?? .nan
                say(String(format: "selftest: phone gear pitch %.3f um, crop %.2f, NPF(k=1) %.2f s", gear.camera.pixelPitchUM, gear.camera.cropFactor, npf))
            }
            // Decode timing and stack attempt (indoors there may be no stars to align).
            let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
            var t = Date()
            if let first = frames.first {
                let raster = try StackBuilder.decode(first.url, context: context)
                say(String(format: "selftest: decode %@ to linear RGB16 %dx%d in %.2f s", first.url.pathExtension, raster.width, raster.height, Date().timeIntervalSince(t)))
            }
            let stackFrames = frames.filter { $0.url.pathExtension == frames[0].url.pathExtension }
            t = Date()
            let builder = StackBuilder(
                frames: stackFrames.map { .init(url: $0.url, exposure: $0.exposure, iso: $0.iso) }, mode: .maximum,
                output: folder.appending(path: "trails.tif"), workDirectory: URL.cachesDirectory.appending(path: "stack-work/selftest"))
            let report = try builder.run { _, _ in }
            say(String(format: "selftest: maximum stack of %d in %.2f s", report.used, Date().timeIntervalSince(t)))
            if let out = report.output, let src = CGImageSourceCreateWithURL(out as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
                let bytes = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                say("selftest: TIFF depth \(props[kCGImagePropertyDepth as String] ?? "?"), \(props[kCGImagePropertyPixelWidth as String] ?? "?")x\(props[kCGImagePropertyPixelHeight as String] ?? "?"), profile \(props[kCGImagePropertyProfileName as String] ?? "?"), \(bytes / 1_000_000) MB")
            }
            t = Date()
            let sigma = StackBuilder(
                frames: stackFrames.map { .init(url: $0.url, exposure: $0.exposure, iso: $0.iso) }, mode: .sigmaClippedMean,
                output: folder.appending(path: "stack.tif"), workDirectory: URL.cachesDirectory.appending(path: "stack-work/selftest"))
            do {
                let r = try sigma.run { _, _ in }
                say(String(format: "selftest: sigma stack in %.2f s\n%@", Date().timeIntervalSince(t), r.description))
            } catch {
                say("selftest: sigma stack not built (\(error.localizedDescription)); expected indoors without stars")
            }
            _ = exposedAt
        } catch {
            say("selftest failed: \(error.localizedDescription)")
        }
    }
}

private extension Double {
    var nonZeroDouble: Double? { self == 0 ? nil : self }
}
#endif
