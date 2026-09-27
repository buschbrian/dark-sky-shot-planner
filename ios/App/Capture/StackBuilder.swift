import CoreImage
import Foundation
import ImageIO
import SkyCore
import UniformTypeIdentifiers

/// Turns saved frames into one image on the phone (ADR-0011 §2, §3): decode
/// each frame to linear 16-bit RGB, find its stars, register it on the
/// middle frame, then take the sigma-clipped mean (or, for star trails, the
/// unaligned maximum). The output is a 16-bit linear TIFF; the frames are
/// untouched. No learned model runs anywhere in this path.
nonisolated struct StackBuilder: Sendable {
    struct Frame: Sendable {
        let url: URL
        let exposure: Double?
        let iso: Double?
    }

    struct Report: Sendable, CustomStringConvertible {
        var mode: StackMode
        var frames = 0
        var used = 0
        var width = 0
        var height = 0
        var reference = 0
        /// Per frame: nil when it could not be registered (left out of the stack).
        var registrations: [Registration?] = []
        var decodeSeconds = 0.0
        var detectSeconds = 0.0
        var registerSeconds = 0.0
        var combineSeconds = 0.0
        var writeSeconds = 0.0
        var output: URL?
        /// Set when the reference frame had too few stars to align on.
        var unalignedReason: String?

        var description: String {
            let regs = registrations.enumerated().map { i, r in
                r.map { String(format: "#%d %.3f° (%.1f, %.1f) %d stars rms %.2f px", i, $0.transform.rotationDegrees,
                               $0.transform.tx, $0.transform.ty, $0.matchedStars, $0.rmsResidual) } ?? "#\(i) not registered"
            }
            return """
            mode \(mode.rawValue), \(used)/\(frames) frames used, \(width)×\(height), reference #\(reference)
            decode \(String(format: "%.2f", decodeSeconds)) s, detect \(String(format: "%.2f", detectSeconds)) s, \
            register \(String(format: "%.2f", registerSeconds)) s, combine \(String(format: "%.2f", combineSeconds)) s, \
            write \(String(format: "%.2f", writeSeconds)) s\(unalignedReason.map { "\n" + $0 } ?? "")
            \(regs.joined(separator: "\n"))
            """
        }
    }

    enum Failure: LocalizedError {
        case decode(URL), tooFewRegistered(Int), write

        var errorDescription: String? {
            switch self {
            case .decode(let url): "Could not read \(url.lastPathComponent)."
            case .tooFewRegistered(let n): "Only \(n) frame(s) could be aligned on stars; nothing was stacked."
            case .write: "The stacked image could not be written."
            }
        }
    }

    let frames: [Frame]
    let mode: StackMode
    let output: URL
    let workDirectory: URL
    var clip = SigmaClip.standard
    /// Frames with too few stars are left out of an aligned stack rather than
    /// averaged in misaligned; a stack needs at least this many aligned frames.
    var minimumAligned = 2

    /// Throws `CancellationError` promptly (between frames, and every row
    /// inside the stacker) when its task is cancelled; the frames are untouched.
    func run(progress: @escaping @Sendable (Double, String) -> Void) throws -> Report {
        var report = Report(mode: mode)
        report.frames = frames.count
        guard !frames.isEmpty else { throw Failure.tooFewRegistered(0) }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                          .cacheIntermediates: false])

        if mode == .maximum {
            // Star trails: stream the maximum, nothing aligned, nothing cached.
            var accumulator: StackAccumulator?
            for (i, frame) in frames.enumerated() {
                try Task.checkCancellation()
                progress(Double(i) / Double(frames.count), "Frame \(i + 1) of \(frames.count)")
                let t0 = Date()
                let raster = try autoreleasepool { try Self.decode(frame.url, context: context) }
                report.decodeSeconds += Date().timeIntervalSince(t0)
                let t1 = Date()
                if accumulator == nil {
                    accumulator = StackAccumulator(mode: .maximum, width: raster.width, height: raster.height, channels: raster.channels)
                    report.width = raster.width
                    report.height = raster.height
                }
                guard raster.width == accumulator?.width, raster.height == accumulator?.height else { continue }
                try accumulator?.add(raster)
                report.combineSeconds += Date().timeIntervalSince(t1)
                report.used += 1
                report.registrations.append(Registration(transform: .identity, matchedStars: 0, rmsResidual: 0))
            }
            guard let accumulator else { throw Failure.tooFewRegistered(0) }
            let t = Date()
            try write(accumulator.result, report: report)
            report.writeSeconds = Date().timeIntervalSince(t)
            report.output = output
            return report
        }

        // Aligned stack: decode every frame to a memory-mappable file.
        var rasters: [RasterU16] = []
        var stars: [[DetectedStar]] = []
        let detector = StarDetector()
        for (i, frame) in frames.enumerated() {
            try Task.checkCancellation()
            progress(0.6 * Double(i) / Double(frames.count), "Reading frame \(i + 1) of \(frames.count)")
            let t0 = Date()
            let raster = try autoreleasepool { try Self.decode(frame.url, context: context) }
            let file = workDirectory.appending(path: String(format: "f%04d.rgb16", i))
            try raster.data.write(to: file)
            let mapped = try Data(contentsOf: file, options: .alwaysMapped)
            rasters.append(RasterU16(width: raster.width, height: raster.height, channels: raster.channels, data: mapped))
            report.decodeSeconds += Date().timeIntervalSince(t0)
            let t1 = Date()
            // Stars on a 2 × 2 binned luminance: a quarter of the pixels, half the noise.
            let found = detector.detect(ImagePlane.luminance(raster, bin: 2))
            stars.append(found.map { DetectedStar(x: $0.x * 2 + 0.5, y: $0.y * 2 + 0.5, flux: $0.flux,
                                                  peak: $0.peak, area: $0.area, hfr: $0.hfr * 2) })
            report.detectSeconds += Date().timeIntervalSince(t1)
        }
        let size = (rasters[0].width, rasters[0].height)
        report.width = size.0
        report.height = size.1
        // The middle frame: the others turn away from it by at most half the span.
        let reference = frames.count / 2
        report.reference = reference
        let t2 = Date()
        progress(0.6, "Aligning on stars")
        var keptRasters: [RasterU16] = []
        var transforms: [RigidTransform] = []
        // No stars to align on (cloud, daylight, indoors): a tripod keeps the
        // frames aligned for a short sequence, so stack them unaligned and say so.
        let matcher = StarMatcher()
        let alignOnStars = stars[reference].count >= matcher.minMatches
        if !alignOnStars {
            report.unalignedReason = "Only \(stars[reference].count) stars in the reference frame: stacked unaligned (tripod assumed)."
        }
        for i in rasters.indices {
            try Task.checkCancellation()
            guard rasters[i].width == size.0, rasters[i].height == size.1 else {
                report.registrations.append(nil)
                continue
            }
            let registration: Registration?
            if i == reference || !alignOnStars {
                registration = Registration(transform: .identity, matchedStars: alignOnStars ? stars[i].count : 0, rmsResidual: 0)
            } else {
                registration = try? matcher.register(reference: stars[reference], frame: stars[i])
            }
            report.registrations.append(registration)
            if let registration {
                keptRasters.append(rasters[i])
                transforms.append(registration.transform)
            }
        }
        report.registerSeconds = Date().timeIntervalSince(t2)
        // Fewer than half the frames aligned: probably not a star field
        // (indoors, cloud, foreground lights). On a tripod the frames are
        // already aligned for a short span, so stack them as shot and say so.
        let sameSize = rasters.filter { $0.width == size.0 && $0.height == size.1 }
        if alignOnStars, keptRasters.count * 2 < sameSize.count, sameSize.count >= minimumAligned {
            report.unalignedReason = "Only \(keptRasters.count) of \(sameSize.count) frames aligned on stars (not a star field?): stacked unaligned (tripod assumed)."
            keptRasters = sameSize
            transforms = Array(repeating: .identity, count: sameSize.count)
        }
        guard keptRasters.count >= minimumAligned else { throw Failure.tooFewRegistered(keptRasters.count) }
        report.used = keptRasters.count
        progress(0.7, "Combining \(keptRasters.count) frames")
        let t3 = Date()
        let combined = try FrameStacker(clip: clip).sigmaClipped(keptRasters, transforms: transforms)
        report.combineSeconds = Date().timeIntervalSince(t3)
        progress(0.95, "Writing")
        let t4 = Date()
        try write(combined.raster, report: report)
        report.writeSeconds = Date().timeIntervalSince(t4)
        report.output = output
        return report
    }

    /// Linear, scene-referred RGB: RAW files through CIRAWFilter with the
    /// global tone curve off (`boostAmount = 0`) and its noise reduction,
    /// sharpening and local tone mapping off; HEIC through Core Image into the
    /// same linear space. 16 bits per channel, alpha dropped.
    static func decode(_ url: URL, context: CIContext) throws -> RasterU16 {
        let image: CIImage?
        if url.pathExtension.lowercased() == "dng", let raw = CIRAWFilter(imageURL: url) {
            raw.boostAmount = 0
            if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = 0 }
            if raw.isColorNoiseReductionSupported { raw.colorNoiseReductionAmount = 0 }
            if raw.isSharpnessSupported { raw.sharpnessAmount = 0 }
            if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            if raw.isDetailSupported { raw.detailAmount = 0 }
            image = raw.outputImage
        } else {
            image = CIImage(contentsOf: url, options: [.applyOrientationProperty: false])
        }
        guard let image else { throw Failure.decode(url) }
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0 else { throw Failure.decode(url) }
        var rgba = [UInt16](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
        rgba.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: w * 8, bounds: extent, format: .RGBA16, colorSpace: space)
        }
        var rgb = [UInt16](repeating: 0, count: w * h * 3)
        rgba.withUnsafeBufferPointer { src in
            rgb.withUnsafeMutableBufferPointer { dst in
                for i in 0..<(w * h) {
                    dst[i * 3] = src[i * 4]
                    dst[i * 3 + 1] = src[i * 4 + 1]
                    dst[i * 3 + 2] = src[i * 4 + 2]
                }
            }
        }
        return RasterU16(width: w, height: h, channels: 3, values: rgb)
    }

    /// 16-bit linear-sRGB TIFF with what was done in its metadata.
    func write(_ raster: RasterU16, report: Report) throws {
        guard let provider = CGDataProvider(data: raster.data as CFData),
              let image = CGImage(
                width: raster.width, height: raster.height, bitsPerComponent: 16, bitsPerPixel: 48,
                bytesPerRow: raster.width * 6, space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { throw Failure.write }
        let first = frames.first
        let totalExposure = frames.prefix(report.used).compactMap(\.exposure).reduce(0, +)
        let what = mode == .maximum
            ? "Star trails: per-pixel maximum of \(report.used) frames, unaligned."
            : "Stack: sigma-clipped mean (kappa \(clip.kappa), \(clip.iterations) iterations) of \(report.used) of \(report.frames) frames, "
                + (report.unalignedReason ?? "registered on stars (rotation + shift) to frame \(report.reference + 1).")
        var exif: [CFString: Any] = [
            kCGImagePropertyExifUserComment: "\(what) Linear light, no tone curve, no learned processing. Total exposure \(String(format: "%.1f", totalExposure)) s.",
            kCGImagePropertyExifDateTimeOriginal: Self.exifDate.string(from: Date()),
        ]
        if let e = first?.exposure { exif[kCGImagePropertyExifExposureTime] = e }
        if let iso = first?.iso { exif[kCGImagePropertyExifISOSpeedRatings] = [iso] }
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFSoftware: "Dark Sky (M12 capture)",
                kCGImagePropertyTIFFImageDescription: what,
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.write }
    }

    static let exifDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}
