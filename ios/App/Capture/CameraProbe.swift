import AVFoundation
import Foundation
import UIKit

/// What the back cameras report about long exposure, ISO, aperture, RAW and
/// focus (ADR-0011 §1: measure before designing). Reading devices and formats
/// needs no capture session and no camera permission; RAW pixel formats are
/// only listed by a photo output attached to a session input, which needs
/// permission. The probe never calls `startRunning`, so no frame is captured.
nonisolated struct CameraProbeReport: Codable, Sendable {
    struct Environment: Codable, Sendable {
        let model: String
        let systemVersion: String
        let cameraAuthorization: String
        let thermalState: String
        let generatedAt: String
        let note: String
    }

    struct Camera: Codable, Sendable {
        let deviceType: String
        let localizedName: String
        let activeFormatIndex: Int?
        let currentLensAperture: Float
        let activeMaxExposureDurationS: Double
        let customExposureSupported: Bool
        let lockedFocusSupported: Bool
        let lockingFocusWithCustomLensPositionSupported: Bool
        /// 0 (closest) to 1 (furthest) by API definition; 1 is not infinity.
        let lensPositionRange: [Float]
        let currentLensPosition: Float
        let minimumFocusDistanceMM: Int
        let lowLightBoostSupported: Bool
        let formats: [Format]
        let raw: RawSupport?
    }

    struct Format: Codable, Sendable {
        let index: Int
        let pixelFormat: String
        let width: Int
        let height: Int
        let fieldOfViewDeg: Float
        let binned: Bool
        let minExposureS: Double
        let maxExposureS: Double
        let minISO: Float
        let maxISO: Float
        let frameRates: [[Double]]
        let maxPhotoDimensions: [[Int]]
        let highPhotoQualitySupported: Bool
        let lowLightVideoNoiseReduction: Bool?
        let aperture: Aperture?
    }

    /// iOS 27 aperture control. `manualAtLimits` asks the format whether a
    /// fully manual exposure (no Auto parameter) at its longest duration and
    /// highest ISO is accepted with each recommended stop.
    struct Aperture: Codable, Sendable {
        let min: Float
        let max: Float
        let defaultValue: Float
        let recommendedStops: [Float]
        let fullyManualSupported: Bool
        let manualAtLimitsStops: [Float]
        let shutterPrioritySupported: Bool
    }

    struct RawSupport: Codable, Sendable {
        /// Per format index: what the photo output lists once that format is active.
        let byFormat: [RawFormat]
        let note: String
    }

    struct RawFormat: Codable, Sendable {
        let formatIndex: Int
        let bayerRaw: [String]
        let appleProRaw: [String]
        let rawFileTypes: [String]
        let appleProRawSupported: Bool
        let shutterSoundSuppressionSupported: Bool
        let zeroShutterLagSupported: Bool
    }

    let environment: Environment
    let cameras: [Camera]
}

nonisolated enum CameraProbe {
    static let backCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]

    static var authorization: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    /// Runs on any thread. With `includeRaw` and camera permission, each
    /// camera is attached to an idle session (never started) to list RAW formats.
    static func run(includeRaw: Bool = true) -> CameraProbeReport {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: backCameraTypes, mediaType: .video, position: .back)
        let authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let cameras = discovery.devices.map { camera($0, raw: includeRaw && authorized) }
        let note = authorized
            ? "Formats read without a running session; RAW lists come from an idle session (startRunning never called)."
            : "Camera permission is \(authorization): formats and ranges are complete, RAW lists need permission (open Tools > Capture once and tap Allow)."
        let env = CameraProbeReport.Environment(
            model: modelIdentifier(), systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            cameraAuthorization: authorization, thermalState: thermalName(ProcessInfo.processInfo.thermalState),
            generatedAt: ISO8601DateFormatter().string(from: Date()), note: note)
        return CameraProbeReport(environment: env, cameras: cameras)
    }

    static func json(_ report: CameraProbeReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func camera(_ device: AVCaptureDevice, raw: Bool) -> CameraProbeReport.Camera {
        let formats = device.formats.enumerated().map { format($0.element, index: $0.offset) }
        return CameraProbeReport.Camera(
            deviceType: device.deviceType.rawValue.replacingOccurrences(of: "AVCaptureDeviceTypeBuiltIn", with: ""),
            localizedName: device.localizedName,
            activeFormatIndex: device.formats.firstIndex(of: device.activeFormat),
            currentLensAperture: device.lensAperture,
            activeMaxExposureDurationS: seconds(device.activeMaxExposureDuration),
            customExposureSupported: device.isExposureModeSupported(.custom),
            lockedFocusSupported: device.isFocusModeSupported(.locked),
            lockingFocusWithCustomLensPositionSupported: device.isLockingFocusWithCustomLensPositionSupported,
            lensPositionRange: [0, 1],
            currentLensPosition: device.lensPosition,
            minimumFocusDistanceMM: device.minimumFocusDistance,
            lowLightBoostSupported: device.isLowLightBoostSupported,
            formats: formats,
            raw: raw ? rawSupport(device) : nil)
    }

    private static func format(_ f: AVCaptureDevice.Format, index: Int) -> CameraProbeReport.Format {
        let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        var lowLight: Bool?
        var aperture: CameraProbeReport.Aperture?
        if #available(iOS 27.0, *) {
            lowLight = f.isLowLightVideoNoiseReductionSupported
            aperture = apertureSupport(f)
        }
        return CameraProbeReport.Format(
            index: index,
            pixelFormat: fourCC(CMFormatDescriptionGetMediaSubType(f.formatDescription)),
            width: Int(dims.width), height: Int(dims.height),
            fieldOfViewDeg: f.videoFieldOfView,
            binned: f.isVideoBinned,
            minExposureS: seconds(f.minExposureDuration),
            maxExposureS: seconds(f.maxExposureDuration),
            minISO: f.minISO, maxISO: f.maxISO,
            frameRates: f.videoSupportedFrameRateRanges.map { [$0.minFrameRate, $0.maxFrameRate] },
            maxPhotoDimensions: f.supportedMaxPhotoDimensions.map { [Int($0.width), Int($0.height)] },
            highPhotoQualitySupported: f.isHighPhotoQualitySupported,
            lowLightVideoNoiseReduction: lowLight,
            aperture: aperture)
    }

    @available(iOS 27.0, *)
    private static func apertureSupport(_ f: AVCaptureDevice.Format) -> CameraProbeReport.Aperture {
        let stops = f.recommendedLensApertureStops
        let manualAtLimits = stops.filter {
            f.supportsExposureModeCustom(lensAperture: $0, duration: f.maxExposureDuration, iso: f.maxISO)
        }
        return CameraProbeReport.Aperture(
            min: f.minLensAperture, max: f.maxLensAperture, defaultValue: f.defaultLensAperture,
            recommendedStops: stops,
            fullyManualSupported: f.supportsExposureModeCustom(
                lensAperture: AVCaptureDevice.currentLensAperture,
                duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO),
            manualAtLimitsStops: manualAtLimits,
            shutterPrioritySupported: f.supportsExposureModeCustom(
                lensAperture: AVCaptureDevice.autoLensAperture,
                duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.autoISO))
    }

    /// Attaches the camera to an idle session and lists RAW formats per active
    /// format. `startRunning` is never called, so nothing is captured.
    private static func rawSupport(_ device: AVCaptureDevice) -> CameraProbeReport.RawSupport? {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        var rows: [CameraProbeReport.RawFormat] = []
        for (index, format) in device.formats.enumerated() {
            guard (try? device.lockForConfiguration()) != nil else { continue }
            session.beginConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            output.isAppleProRAWEnabled = false
            session.commitConfiguration()
            // Bayer RAW is listed with ProRAW off, ProRAW once it is on.
            let bayer = output.availableRawPhotoPixelFormatTypes
            var proRaw: [OSType] = []
            if output.isAppleProRAWSupported {
                session.beginConfiguration()
                output.isAppleProRAWEnabled = true
                session.commitConfiguration()
                proRaw = output.availableRawPhotoPixelFormatTypes
            }
            rows.append(CameraProbeReport.RawFormat(
                formatIndex: index,
                bayerRaw: bayer.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }.map(fourCC),
                appleProRaw: proRaw.filter { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }.map(fourCC),
                rawFileTypes: output.availableRawPhotoFileTypes.map(\.rawValue),
                appleProRawSupported: output.isAppleProRAWSupported,
                shutterSoundSuppressionSupported: output.isShutterSoundSuppressionSupported,
                zeroShutterLagSupported: output.isZeroShutterLagSupported))
        }
        session.removeInput(input)
        session.removeOutput(output)
        return CameraProbeReport.RawSupport(
            byFormat: rows,
            note: "bayerRaw: listed with appleProRAWEnabled = false; appleProRaw: with it true (where supported). Split by isBayerRAWPixelFormat / isAppleProRAWPixelFormat.")
    }

    static func seconds(_ t: CMTime) -> Double {
        t.isNumeric ? CMTimeGetSeconds(t) : .nan
    }

    static func fourCC(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        if bytes.allSatisfy({ (0x20...0x7E).contains($0) }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(format: "0x%08X", code)
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

#if DEBUG
/// `-CameraProbe YES`: print the report to stdout between markers and exit,
/// for `xcrun devicectl device process launch --console`. Called from a C
/// constructor (CameraProbeLaunch.c) so the app's entry point stays untouched;
/// the work itself runs on the main queue once the app is up.
@_cdecl("ds_camera_probe_install")
nonisolated func cameraProbeInstall() {
    guard UserDefaults.standard.bool(forKey: "CameraProbe") else { return }
    DispatchQueue.main.async {
        let report = CameraProbe.run()
        print("CAMERA_PROBE_BEGIN")
        print(CameraProbe.json(report))
        print("CAMERA_PROBE_END")
        fflush(stdout)
        exit(0)
    }
}
#endif
