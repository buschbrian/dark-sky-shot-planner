import CoreLocation
import CoreMotion
import Foundation
import Observation
import SkyCore

/// Location, compass accuracy and Core Motion attitude for the Sky screen.
/// Attitude is polled each frame (`attitude()`), not observed.
@Observable
final class SkySensors: NSObject, CLLocationManagerDelegate {
    enum LocationAccess: Equatable { case notDetermined, denied, restricted, granted }

    private(set) var locationAccess: LocationAccess = .notDetermined
    private(set) var reducedAccuracy = false
    private(set) var here: Place?
    /// `CLHeading.headingAccuracy` in degrees; negative means invalid.
    private(set) var headingAccuracyDeg: Double = -1
    private(set) var headingUpdatedAt: Date?
    private(set) var motionStartedAt: Date?

    /// `CMDeviceMotion.magneticField.accuracy`, sampled with the attitude.
    private(set) var magneticAccuracy = MagneticFieldAccuracy.uncalibrated
    /// Magnetic disturbance or drift since the last calibration (never observed per frame).
    private(set) var disturbance = HeadingDisturbanceMonitor.State.steady

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var filter = HeadingFilter()
    @ObservationIgnored private var monitor = HeadingDisturbanceMonitor(
        jumpThresholdDeg: SkyScreen.arConfig?.headingJumpDisturbanceDeg ?? 4,
        driftThresholdDeg: SkyScreen.arConfig?.headingDriftMaxDeg ?? 3)
    @ObservationIgnored private var lastSampleTime: TimeInterval?
    @ObservationIgnored private var lastAttitude: DeviceAttitude?
    /// Latest raw readings for the diagnostics log.
    @ObservationIgnored private(set) var rawHeadingDeg: Double?
    @ObservationIgnored private(set) var headingRateDegPerSecond = 0.0
    @ObservationIgnored private(set) var smoothingDeg = 0.0

    let headingHardware = CLLocationManager.headingAvailable()

    /// The Night AR needs fused attitude against true north: that is the
    /// motion sensors plus the magnetometer.
    var motionHardware: Bool {
        motion.isDeviceMotionAvailable
            && CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
        refreshAccess()
    }

    func start() {
        running = true
        refreshAccess()
        switch locationAccess {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .granted:
            startUpdates()
        case .denied, .restricted:
            break
        }
    }

    func stop() {
        running = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        motionStartedAt = nil
    }

    /// Latest attitude in `.xTrueNorthZVertical`, copied field for field as
    /// SkyFrames.swift documents, with its heading smoothed by
    /// `HeadingFilter` (gyro-predicted, so turns do not lag); nil until the
    /// first sample arrives. Each new Core Motion sample also feeds the
    /// disturbance monitor.
    func attitude() -> DeviceAttitude? {
        guard let dm = motion.deviceMotion else { return nil }
        let m = dm.attitude.rotationMatrix
        let raw = DeviceAttitude(coreMotionRotationMatrix: RotationMatrix(
            m11: m.m11, m12: m.m12, m13: m.m13,
            m21: m.m21, m22: m.m22, m23: m.m23,
            m31: m.m31, m32: m.m32, m33: m.m33))
        if dm.timestamp != lastSampleTime {
            lastSampleTime = dm.timestamp
            let r = dm.rotationRate
            let rate = raw.headingRateDegPerSecond(deviceRotationRate: SIMD3(r.x, r.y, r.z))
            let heading = raw.headingDeg
            filter.update(measuredDeg: heading, at: dm.timestamp, rateDegPerSecond: rate)
            let state = monitor.update(headingDeg: heading, rateDegPerSecond: rate, at: dm.timestamp)
            if state != disturbance { disturbance = state }
            let accuracy = MagneticFieldAccuracy(rawValue: Int(dm.magneticField.accuracy.rawValue)) ?? .uncalibrated
            if accuracy != magneticAccuracy { magneticAccuracy = accuracy }
            rawHeadingDeg = heading
            headingRateDegPerSecond = rate
            smoothingDeg = filter.correctionDeg(forMeasuredDeg: heading)
        }
        lastAttitude = raw
        return raw.applying(HeadingCalibration(offsetDeg: smoothingDeg))
    }

    /// After a calibration the heading is trusted again.
    func resetDisturbance() {
        monitor.reset()
        disturbance = .steady
    }

    private func startUpdates() {
        guard running else { return }
        locationManager.startUpdatingLocation()
        if headingHardware { locationManager.startUpdatingHeading() }
        if motionHardware, !motion.isDeviceMotionActive {
            // Polled once per displayed frame (Apple's pattern for render
            // loops); 100 Hz keeps the newest sample under 10 ms old at 120 Hz ProMotion.
            motion.deviceMotionUpdateInterval = 1.0 / 100
            // The Sky view draws its own palette-coloured figure-8 guide
            // instead of iOS's white calibration prompt.
            motion.showsDeviceMovementDisplay = false
            // True north needs location; Core Motion starts once it has a fix.
            motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical)
            motionStartedAt = .now
            filter.reset()
            lastSampleTime = nil
        }
    }

    private func refreshAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationAccess = .notDetermined
        case .denied: locationAccess = .denied
        case .restricted: locationAccess = .restricted
        case .authorizedAlways, .authorizedWhenInUse: locationAccess = .granted
        @unknown default: locationAccess = .denied
        }
        reducedAccuracy = locationManager.accuracyAuthorization == .reducedAccuracy
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            refreshAccess()
            if locationAccess == .granted { startUpdates() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat = last.coordinate.latitude, lon = last.coordinate.longitude
        MainActor.assumeIsolated {
            // Sky positions barely move over a few hundred metres; avoid recomputing the night on GPS jitter.
            if let here, abs(here.latitude - lat) < 0.005, abs(here.longitude - lon) < 0.005 { return }
            here = Place(name: "Your location", latitude: lat, longitude: lon, timeZoneID: TimeZone.current.identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let accuracy = newHeading.headingAccuracy
        MainActor.assumeIsolated {
            headingAccuracyDeg = accuracy
            headingUpdatedAt = .now
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    /// Never iOS's white prompt: the Sky view shows its own figure-8 guide.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
}
