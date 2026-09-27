import AVFoundation
import CoreImage
import ImageIO
import SkyCore
import UIKit

/// Which back camera, and what the chosen format allows. Built from the
/// device at configure time; the limits are whatever the format reports
/// (docs/ios/CAPTURE-LIMITS.md has the measured values), never assumed.
nonisolated struct CaptureCameraInfo: Sendable, Equatable {
    enum Lens: String, CaseIterable, Sendable, Identifiable {
        case main, ultraWide, telephoto
        var id: String { rawValue }

        var deviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .main: .builtInWideAngleCamera
            case .ultraWide: .builtInUltraWideCamera
            case .telephoto: .builtInTelephotoCamera
            }
        }

        var title: String {
            switch self {
            case .main: "Main"
            case .ultraWide: "Ultra wide"
            case .telephoto: "Telephoto"
            }
        }
    }

    let lens: Lens
    let maxExposure: Double
    let minISO: Float
    let maxISO: Float
    /// Recommended stops (iOS 27), or the one fixed aperture.
    let apertures: [Float]
    let apertureControl: Bool
    let photoDimensions: [CMVideoDimensions]
    let proRaw: OSType?
    let shutterSoundSuppression: Bool
    let customLensPosition: Bool

    static func == (a: Self, b: Self) -> Bool {
        a.lens == b.lens && a.maxExposure == b.maxExposure && a.minISO == b.minISO && a.maxISO == b.maxISO
            && a.apertures == b.apertures && a.proRaw == b.proRaw
            && a.photoDimensions.map { [$0.width, $0.height] } == b.photoDimensions.map { [$0.width, $0.height] }
    }
}

/// One frame's request. Exposure, ISO, aperture and focus are locked before
/// the sequence; each frame only picks the file format and size.
nonisolated struct FrameRequest: Sendable {
    enum FileFormat: String, Sendable, CaseIterable, Identifiable {
        case raw, heic
        var id: String { rawValue }
    }

    let format: FileFormat
    let dimensions: CMVideoDimensions
}

/// A captured frame, already written to disk.
nonisolated struct CapturedFrame: Sendable {
    let url: URL
    let bytes: Int64
    let exposure: Double?
    let iso: Double?
    let fNumber: Double?
    let focalLength: Double?
    let focalLength35: Double?
    let width: Int
    let height: Int
    /// Seconds from the capture request to the sensor finishing the exposure.
    let requestToCaptured: Double
}

enum CaptureError: LocalizedError {
    case noCamera, cannotConfigure(String), captureFailed(String), notRunning

    var errorDescription: String? {
        switch self {
        case .noCamera: "This camera is not available."
        case .cannotConfigure(let why): "The camera could not be set up: \(why)"
        case .captureFailed(let why): "A frame failed: \(why)"
        case .notRunning: "The camera is not running."
        }
    }
}

/// Owns the capture session on its own queue: format choice, locked manual
/// exposure and focus, RAW or HEIC stills, and a small luminance feed for
/// the focus assist. No computational photography is asked for: quality
/// prioritization is `.speed`, which Apple documents as the setting under
/// which custom exposure values are used for stills instead of being
/// overridden for multi-image fusion.
nonisolated final class CaptureEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "capture.session")
    private let videoQueue = DispatchQueue(label: "capture.focus")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private(set) var device: AVCaptureDevice?
    private var inFlight: [Int64: PhotoWriter] = [:]
    private let lock = NSLock()
    /// Latest centre crop of the preview, for the focus assist.
    var onFocusCrop: (@Sendable (ImagePlane) -> Void)?
    /// The session was interrupted (phone locked, another app took the
    /// camera, a call) or hit a runtime error; the string says which.
    var onInterruption: (@Sendable (String) -> Void)?
    private var lastCrop = Date.distantPast
    private var observers: [any NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).flatMap(AVCaptureSession.InterruptionReason.init)
            self?.setInterrupted(true)
            self?.onInterruption?("camera interrupted (\(Self.describe(raw)))")
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.setInterrupted(false)
            CaptureLog.event("camera interruption ended")
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.onInterruption?("camera error (\(error?.localizedDescription ?? "unknown"))")
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    static func describe(_ reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground: "app in background or phone locked"
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient: "another app is using the camera"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: "multiple foreground apps"
        case .videoDeviceNotAvailableDueToSystemPressure: "system pressure (heat)"
        case .none: "unknown reason"
        default: "reason \(reason!.rawValue)"
        }
    }

    var isRunning: Bool { session.isRunning }

    private var interruptedFlag = false

    /// True between an interruption and its end (a running session can be interrupted).
    var isInterrupted: Bool { lock.withLock { interruptedFlag } }

    private func setInterrupted(_ value: Bool) { lock.withLock { interruptedFlag = value } }

    // MARK: Configuration

    /// Picks the format with the longest maximum exposure, then ProRAW
    /// availability, then the largest photo size, and attaches it.
    func configure(lens: CaptureCameraInfo.Lens) async throws -> CaptureCameraInfo {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try configureOnQueue(lens)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configureOnQueue(_ lens: CaptureCameraInfo.Lens) throws -> CaptureCameraInfo {
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) else { throw CaptureError.noCamera }
        let newInput: AVCaptureDeviceInput
        do { newInput = try AVCaptureDeviceInput(device: device) } catch {
            throw CaptureError.cannotConfigure(error.localizedDescription)
        }
        session.beginConfiguration()
        var committed = false
        defer { if !committed { session.commitConfiguration() } }
        if let input { session.removeInput(input) }
        session.sessionPreset = .photo
        guard session.canAddInput(newInput) else { throw CaptureError.cannotConfigure("input rejected") }
        session.addInput(newInput)
        input = newInput
        self.device = device
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw CaptureError.cannotConfigure("photo output rejected") }
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }

        let format = Self.bestFormat(device.formats)
        try device.lockForConfiguration()
        device.activeFormat = format
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = false }
        device.unlockForConfiguration()

        photoOutput.maxPhotoQualityPrioritization = .speed
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
        let dims = format.supportedMaxPhotoDimensions
        if let largest = dims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = largest
        }
        session.commitConfiguration()
        committed = true
        // The RAW list reflects the committed configuration.
        let proRaw = photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
            ?? photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }

        var apertures = [device.lensAperture]
        var apertureControl = false
        if #available(iOS 27.0, *) {
            let stops = format.recommendedLensApertureStops
            if !stops.isEmpty { apertures = stops }
            apertureControl = stops.count > 1
        }
        return CaptureCameraInfo(
            lens: lens, maxExposure: CMTimeGetSeconds(format.maxExposureDuration),
            minISO: format.minISO, maxISO: format.maxISO,
            apertures: apertures, apertureControl: apertureControl,
            photoDimensions: dims, proRaw: proRaw,
            shutterSoundSuppression: photoOutput.isShutterSoundSuppressionSupported,
            customLensPosition: device.isLockingFocusWithCustomLensPositionSupported)
    }

    /// Longest exposure first (they tie at 1 s on the iPhone 18 Pro Max), then
    /// a format offering RAW-sized stills (the 48 MP formats carry ProRAW),
    /// then the largest photo, then full range over video range.
    static func bestFormat(_ formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format {
        func photoPixels(_ f: AVCaptureDevice.Format) -> Int {
            f.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
        }
        func fullRange(_ f: AVCaptureDevice.Format) -> Bool {
            CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        return formats.max { a, b in
            let ea = CMTimeGetSeconds(a.maxExposureDuration), eb = CMTimeGetSeconds(b.maxExposureDuration)
            if ea != eb { return ea < eb }
            if photoPixels(a) != photoPixels(b) { return photoPixels(a) < photoPixels(b) }
            if a.maxISO != b.maxISO { return a.maxISO < b.maxISO }
            return !fullRange(a) && fullRange(b)
        } ?? formats[0]
    }

    func start() {
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
            if session.isRunning, !session.isInterrupted { setInterrupted(false) }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    /// Stops the session and returns once it has stopped (the camera
    /// indicator goes off).
    func stopAndWait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                c.resume()
            }
        }
    }

    // MARK: Manual controls

    /// Locks exposure. With iOS 27 aperture control and no parameter left on
    /// Auto, Apple documents that the duration is applied as given (the
    /// streaming cap `activeMaxExposureDuration` is ignored).
    func lockExposure(seconds: Double, iso: Float, aperture: Float?) async throws {
        try await onQueue { [self] in
            guard let device else { throw CaptureError.notRunning }
            let format = device.activeFormat
            let duration = CMTime(seconds: min(max(seconds, CMTimeGetSeconds(format.minExposureDuration)),
                                               CMTimeGetSeconds(format.maxExposureDuration)),
                                  preferredTimescale: 1_000_000)
            let iso = min(max(iso, format.minISO), format.maxISO)
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if #available(iOS 27.0, *), let aperture,
               format.supportsExposureModeCustom(lensAperture: aperture, duration: duration, iso: iso) {
                device.setExposureModeCustom(lensAperture: aperture, duration: duration, iso: iso, completionHandler: nil)
            } else {
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            }
        }
    }

    /// Locks focus at a lens position (0 near … 1 far; 1 is not infinity).
    func lockFocus(position: Float) async throws {
        try await onQueue { [self] in
            guard let device, device.isLockingFocusWithCustomLensPositionSupported else { throw CaptureError.notRunning }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setFocusModeLocked(lensPosition: min(max(position, 0), 1), completionHandler: nil)
        }
    }

    /// One autofocus pass at the centre (a bright star or a distant light),
    /// then locks wherever it settled; returns that lens position.
    func autofocusOnce() async throws -> Float {
        try await onQueue { [self] in
            guard let device, device.isFocusModeSupported(.autoFocus) else { throw CaptureError.notRunning }
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            device.focusMode = .autoFocus
            device.unlockForConfiguration()
        }
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            if device?.isAdjustingFocus == false { break }
        }
        let position = device?.lensPosition ?? 1
        try await lockFocus(position: position)
        return position
    }

    var lensPosition: Float { device?.lensPosition ?? 1 }

    private func onQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            queue.async {
                do { try work(); c.resume() } catch { c.resume(throwing: error) }
            }
        }
    }

    // MARK: Stills

    /// Prepares the pipeline for this request so the first frame starts without delay.
    func prepare(_ request: FrameRequest) {
        let settings = makeSettings(request)
        photoOutput.setPreparedPhotoSettingsArray([settings], completionHandler: nil)
    }

    private func makeSettings(_ request: FrameRequest) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        let raw = photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
            ?? photoOutput.availableRawPhotoPixelFormatTypes.first
        if request.format == .raw, let raw {
            settings = AVCapturePhotoSettings(rawPixelFormatType: raw, rawFileType: .dng, processedFormat: nil, processedFileType: nil)
        } else if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .speed
        settings.flashMode = .off
        settings.maxPhotoDimensions = request.dimensions
        if photoOutput.isShutterSoundSuppressionSupported { settings.isShutterSoundSuppressionEnabled = true }
        return settings
    }

    /// Captures one frame and writes it to `url` (extension chosen here).
    /// Returns when the file is written; `onExposed` fires as soon as the
    /// sensor has finished, so the next frame can be requested at once.
    func capture(_ request: FrameRequest, to base: URL, onExposed: (@Sendable () -> Void)? = nil) async throws -> CapturedFrame {
        guard session.isRunning else { throw CaptureError.notRunning }
        let settings = makeSettings(request)
        let isRaw = settings.rawPhotoPixelFormatType != 0
        let url = base.appendingPathExtension(isRaw ? "dng" : "heic")
        return try await withCheckedThrowingContinuation { continuation in
            let writer = PhotoWriter(url: url, requested: Date(), onExposed: onExposed) { [weak self] result in
                self?.lock.withLock { self?.inFlight[settings.uniqueID] = nil }
                continuation.resume(with: result)
            }
            lock.withLock { inFlight[settings.uniqueID] = writer }
            photoOutput.capturePhoto(with: settings, delegate: writer)
        }
    }

    /// What the running photo output offers (the probe lists an idle session's).
    var runningRawFormats: (bayer: [String], proRaw: [String]) {
        let types = photoOutput.availableRawPhotoPixelFormatTypes
        return (types.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }.map(CameraProbe.fourCC),
                types.filter { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }.map(CameraProbe.fourCC))
    }
}

nonisolated extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// A 256 × 256 luminance crop from the centre of the preview frame, at
    /// most four times a second: the focus assist's magnifier and HFR.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onFocusCrop, Date().timeIntervalSince(lastCrop) > 0.25,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastCrop = Date()
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferIsPlanar(pixels), let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0), h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let size = min(256, w, h)
        let x0 = (w - size) / 2, y0 = (h - size) / 2
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var out = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let row = bytes + (y0 + y) * rowBytes + x0
            for x in 0..<size { out[y * size + x] = Float(row[x]) / 255 }
        }
        onFocusCrop(ImagePlane(width: size, height: size, pixels: out))
    }
}

/// Receives one photo, writes its file, and reports the frame's metadata.
nonisolated private final class PhotoWriter: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let url: URL
    let requested: Date
    let onExposed: (@Sendable () -> Void)?
    let done: (Result<CapturedFrame, any Error>) -> Void
    private var captured: Date?
    private var frame: CapturedFrame?
    private var failure: (any Error)?

    init(url: URL, requested: Date, onExposed: (@Sendable () -> Void)?, done: @escaping (Result<CapturedFrame, any Error>) -> Void) {
        self.url = url
        self.requested = requested
        self.onExposed = onExposed
        self.done = done
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        captured = Date()
        onExposed?()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error { failure = error; return }
        guard let data = photo.fileDataRepresentation() else { failure = CaptureError.captureFailed("no file data"); return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            failure = error
            return
        }
        let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let dims = photo.resolvedSettings.photoDimensions
        let raw = photo.isRawPhoto
        frame = CapturedFrame(
            url: url, bytes: Int64(data.count),
            exposure: exif[kCGImagePropertyExifExposureTime as String] as? Double,
            iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Double])?.first,
            fNumber: exif[kCGImagePropertyExifFNumber as String] as? Double,
            focalLength: exif[kCGImagePropertyExifFocalLength as String] as? Double,
            focalLength35: exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double,
            width: Int(raw ? photo.resolvedSettings.rawPhotoDimensions.width : dims.width),
            height: Int(raw ? photo.resolvedSettings.rawPhotoDimensions.height : dims.height),
            requestToCaptured: (captured ?? Date()).timeIntervalSince(requested))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        if let error = error ?? failure {
            done(.failure(error))
        } else if let frame {
            done(.success(frame))
        } else {
            done(.failure(CaptureError.captureFailed("no photo delivered")))
        }
    }
}
