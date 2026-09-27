import AVFoundation
import Observation
import SkyCore
import SwiftUI
import simd

/// The back camera's pinhole model for the portrait image, and where it came from.
struct LensModel: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case intrinsicMatrix
        case fieldOfView
        /// No camera (simulated view, or camera access off): a typical iPhone main camera.
        case assumed
    }

    let intrinsics: CameraIntrinsics
    let source: Source

    /// iPhone main camera, 16:9 video, about 68° across the long side.
    static let assumed = LensModel(
        intrinsics: CameraIntrinsics(longSideFieldOfViewDeg: 68, width: 1080, height: 1920), source: .assumed)
}

/// Camera permission and the preview session for the Sky screen.
@Observable
final class SkyCamera {
    enum Access: Equatable { case notDetermined, denied, restricted, granted, noCamera }

    private(set) var access: Access = .notDetermined
    private(set) var lens: LensModel?
    @ObservationIgnored let controller = SkyCaptureController()
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// Where the preview layer actually draws the whole camera image, in its
    /// own points (aspect fill overflows the view). Nil until it has video.
    func displayedImageRect() -> CGRect? {
        guard let layer = previewLayer, layer.connection != nil else { return nil }
        layer.orientForPortraitOverlay()
        let rect = layer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rect.width > 1 && rect.height > 1 && rect.height > rect.width ? rect : nil
    }

    init() {
        refreshAccess()
    }

    func start() {
        refreshAccess()
        switch access {
        case .notDetermined:
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refreshAccess()
                if access == .granted { run() }
            }
        case .granted:
            run()
        case .denied, .restricted, .noCamera:
            break
        }
    }

    func stop() {
        controller.stop()
    }

    private func run() {
        controller.start { [weak self] lens in
            Task { @MainActor in
                guard let self else { return }
                // The measured matrix beats the field-of-view estimate; never downgrade.
                if self.lens?.source == .intrinsicMatrix, lens.source != .intrinsicMatrix { return }
                self.lens = lens
            }
        }
    }

    private func refreshAccess() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            access = .noCamera
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .authorized: access = .granted
        @unknown default: access = .denied
        }
    }
}

/// Owns the `AVCaptureSession` on its own queue. Frames are read only until
/// the first one carrying the camera intrinsic matrix arrives.
nonisolated final class SkyCaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sky.camera")
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var matrixSeen = false
    private var onLens: (@Sendable (LensModel) -> Void)?

    func start(onLens: @escaping @Sendable (LensModel) -> Void) {
        queue.async { [self] in
            self.onLens = onLens
            if !configured { configure() }
            if configured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        preferLowLatencyFormat(device)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        // The data output stays in the sensor's native landscape orientation:
        // SkyCore's `portrait(fromLandscapeBuffer:)` expects exactly that.
        if let connection = output.connection(with: .video), connection.isCameraIntrinsicMatrixDeliverySupported {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        session.commitConfiguration()
        configured = true

        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fov = device.isGeometricDistortionCorrectionEnabled
            ? format.geometricDistortionCorrectedVideoFieldOfView : format.videoFieldOfView
        if fov > 0, dims.width > 0, dims.height > 0 {
            let short = Double(min(dims.width, dims.height)), long = Double(max(dims.width, dims.height))
            onLens?(LensModel(
                intrinsics: CameraIntrinsics(longSideFieldOfViewDeg: Double(fov), width: short, height: long),
                source: .fieldOfView))
        }
    }

    /// 1080p at up to 60 fps where the camera offers it, and never slower
    /// than 30 fps, so the picture lags the overlay by at most a frame or two.
    /// The cost is a darker preview at night than auto-exposure would give.
    private func preferLowLatencyFormat(_ device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width == 1920 && d.height == 1080
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
        }
        guard let format = candidates.max(by: { $0.videoFieldOfView < $1.videoFieldOfView }),
              (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !matrixSeen,
              let data = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data,
              data.count >= MemoryLayout<matrix_float3x3>.size,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        matrixSeen = true
        let m = data.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
        let fx = Double(m.columns.0.x), fy = Double(m.columns.1.y)
        let cx = Double(m.columns.2.x), cy = Double(m.columns.2.y)
        let w = Double(CVPixelBufferGetWidth(pixels)), h = Double(CVPixelBufferGetHeight(pixels))
        guard fx > 0, fy > 0, w > 0, h > 0 else { return }
        let intrinsics = w >= h
            ? CameraIntrinsics.portrait(fromLandscapeBuffer: fx, fy: fy, cx: cx, cy: cy, width: w, height: h)
            : CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy, width: w, height: h)
        onLens?(LensModel(intrinsics: intrinsics, source: .intrinsicMatrix))
        // One matrix is enough at a fixed 1× zoom; stop paying for frames.
        self.output.setSampleBufferDelegate(nil, queue: nil)
    }
}

/// Aspect-fill preview, rotated to portrait to match the portrait-only UI.
struct CameraPreview: UIViewRepresentable {
    let camera: SkyCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = camera.controller.session
        camera.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.orientForPortraitOverlay()
        }
    }
}

extension AVCaptureVideoPreviewLayer {
    /// Portrait (the UI never rotates) and unstabilized: stabilization crops
    /// and shifts the picture frame to frame, which no fixed pinhole model follows.
    func orientForPortraitOverlay() {
        guard let connection else { return }
        if connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoStabilizationSupported, connection.preferredVideoStabilizationMode != .off {
            connection.preferredVideoStabilizationMode = .off
        }
    }
}
