import Foundation
import Testing
@testable import SkyCore

/// Deterministic Gaussian noise (SplitMix64 + Box–Muller) so replays repeat.
struct Noise {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func uniform() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return (Double(z >> 11) + 0.5) / Double(1 << 53)
    }

    mutating func gaussian(_ sigma: Double) -> Double {
        sigma * (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
    }
}

@Suite("Compass quality and the figure-8 guide")
struct SensorQualityTests {
    static let config = try! AppConfig.bundled().arOverlay

    @Test("the guide shows for an uncalibrated or low magnetometer, or a poor or invalid heading", arguments: [
        (MagneticFieldAccuracy.uncalibrated, 3.0, true), (.low, 3, true), (.medium, 3, false), (.high, 3, false),
        (.high, 25, true), (.high, -1, true), (.medium, 10, false), (.medium, 10.5, true),
    ])
    func guide(_ c: (MagneticFieldAccuracy, Double, Bool)) {
        #expect(SensorQuality(magnetic: c.0, headingAccuracyDeg: c.1).needsFigureEight(config: Self.config) == c.2)
    }

    @Test("summary names both sensors")
    func summary() {
        #expect(SensorQuality(magnetic: .low, headingAccuracyDeg: 24.6).summary == "Magnetometer low · compass ±25°")
        #expect(SensorQuality(magnetic: .high, headingAccuracyDeg: -1).summary == "Magnetometer high · compass invalid")
    }

    @Test("config carries the calibration thresholds")
    func config() {
        #expect(Self.config.calibrationResidualMaxDeg == 1.5)
        #expect(Self.config.headingJumpDisturbanceDeg == 4)
        #expect(Self.config.headingDriftMaxDeg == 3)
    }

    @Test("phone heading is the camera azimuth and stays put as the camera tilts to the zenith", arguments: [0.0, 30, 60, 85, 89.9])
    func heading(_ pitch: Double) {
        for az in [0.0, 30, 181, 359] {
            let a = DeviceAttitude.upright(facingAzimuth: az, pitchDeg: pitch)
            #expect(azimuthDelta(a.headingDeg, az) < 1e-6)
        }
    }

    @Test("gyroscope heading rate: turning right (clockwise) is positive")
    func rate() {
        let a = DeviceAttitude.upright(facingAzimuth: 120, pitchDeg: 25)
        // 20°/s clockwise from above is −20°/s about up (right-handed), written in device axes.
        let world = SIMD3<Double>(0, 0, -20 * .pi / 180)
        let device = a.referenceToDevice * world
        #expect(abs(a.headingRateDegPerSecond(deviceRotationRate: device) - 20) < 1e-9)
    }
}

@Suite("Heading smoothing filter")
struct HeadingFilterTests {
    static let dt = 1.0 / 60

    @Test("a 30° step settles to within 1° in HeadingFilter.settleSeconds (1.1 s)")
    func step() {
        var f = HeadingFilter()
        f.update(measuredDeg: 100, at: 0)
        var settled: Double?
        for i in 1...180 {
            let t = Double(i) * Self.dt
            let h = f.update(measuredDeg: 130, at: t)
            if abs(Geodesy.signedAngle(h - 130)) < 1 { settled = settled ?? t } else { settled = nil }
        }
        let t = try! #require(settled)
        #expect(t <= HeadingFilter.settleSeconds, "settled at \(t) s")
        #expect(t > 0.5, "too little smoothing: settled at \(t) s")
    }

    @Test("359° → 1° crossing moves 2° the short way, never spinning through 180°")
    func wrap() {
        var f = HeadingFilter()
        f.update(measuredDeg: 359, at: 0)
        for i in 1...120 {
            let h = f.update(measuredDeg: 1, at: Double(i) * Self.dt)
            #expect(abs(Geodesy.signedAngle(h)) <= 1.0001, "went to \(h)")
        }
        #expect(abs(Geodesy.signedAngle(f.headingDeg! - 1)) < 0.05)
        // And a steady turn across north with the gyroscope stays on the true path.
        var g = HeadingFilter()
        for i in 0...120 {
            let t = Double(i) * Self.dt
            let truth = 350 + 20 * t
            let h = g.update(measuredDeg: truth, at: t, rateDegPerSecond: 20)
            #expect(abs(Geodesy.signedAngle(h - truth)) < 0.01)
        }
    }

    @Test("σ = 3° compass noise is reduced at least 2× (still phone, across north)")
    func noise() {
        var f = HeadingFilter()
        var n = Noise(seed: 42)
        var rawSq = 0.0, filteredSq = 0.0, count = 0.0
        for i in 0..<3600 {
            let raw = Geodesy.normalizedAzimuth(n.gaussian(3))
            let h = f.update(measuredDeg: raw, at: Double(i) * Self.dt)
            guard i > 120 else { continue }
            rawSq += pow(Geodesy.signedAngle(raw), 2)
            filteredSq += pow(Geodesy.signedAngle(h), 2)
            count += 1
        }
        let rawSigma = (rawSq / count).squareRoot(), filteredSigma = (filteredSq / count).squareRoot()
        #expect(abs(rawSigma - 3) < 0.2)
        #expect(filteredSigma * 2 <= rawSigma, "σ \(rawSigma) → \(filteredSigma)")
    }

    @Test("a fast 90°/s turn follows the gyroscope with no lag (mean error < 0.2°) under 1° compass noise")
    func fastTurn() {
        var f = HeadingFilter()
        var n = Noise(seed: 7)
        var sum = 0.0, worst = 0.0
        for i in 0...90 {
            let t = Double(i) * Self.dt
            let truth = 10 + 90 * t
            let h = f.update(measuredDeg: truth + n.gaussian(1), at: t, rateDegPerSecond: 90)
            let e = Geodesy.signedAngle(h - truth)
            if i > 10 { sum += e; worst = max(worst, abs(e)) }
        }
        #expect(abs(sum / 80) < 0.2, "mean lag \(sum / 80)°")
        #expect(worst < 1, "worst \(worst)°")
        // Without the gyroscope the same turn would trail by about rate × τ = 27°.
    }

    @Test("a jump beyond snapDeg is taken at once; the correction is signed across north")
    func snapAndCorrection() {
        var f = HeadingFilter()
        f.update(measuredDeg: 10, at: 0)
        #expect(f.update(measuredDeg: 200, at: 0.02) == 200)
        var g = HeadingFilter()
        g.update(measuredDeg: 358, at: 0)
        #expect(abs(g.correctionDeg(forMeasuredDeg: 2) - -4) < 1e-9)
    }
}

@Suite("Multi-point attitude calibration")
struct AttitudeCorrectionTests {
    static let config = try! AppConfig.bundled().arOverlay

    /// Bright targets spread across the sky, as a user would pick them: the
    /// tilt axes need targets away from the forward direction (a target on
    /// an axis does not move when the sky turns about it).
    static let targets: [HorizontalPosition] = [
        .init(altitudeDeg: 15, azimuthDeg: 95), .init(altitudeDeg: 40, azimuthDeg: 130), .init(altitudeDeg: 65, azimuthDeg: 175),
        .init(altitudeDeg: 20, azimuthDeg: 185), .init(altitudeDeg: 45, azimuthDeg: 230), .init(altitudeDeg: 15, azimuthDeg: 265),
        .init(altitudeDeg: 75, azimuthDeg: 300), .init(altitudeDeg: 30, azimuthDeg: 20),
    ]

    /// Where the sensors would say each target is, with `sigma` degrees of
    /// alignment noise: the RMS angle between where the user held the
    /// crosshair and the target (σ/√2 in each of altitude and across).
    static func observations(_ truth: AttitudeCorrection, targets: [HorizontalPosition], noise total: Double, seed: UInt64) -> [CalibrationObservation] {
        var n = Noise(seed: seed)
        let sigma = total / 2.0.squareRoot()
        return targets.enumerated().map { i, t in
            let sensed = HorizontalPosition(reference: truth.rotation.transposed * t.referenceVector)
            let jittered = HorizontalPosition(
                altitudeDeg: sensed.altitudeDeg + n.gaussian(sigma),
                azimuthDeg: sensed.azimuthDeg + n.gaussian(sigma) / cos(sensed.altitudeDeg * .pi / 180))
            return CalibrationObservation(target: "T\(i)", trueDirection: t, sensedDirection: jittered)
        }
    }

    @Test("synthetic yaw 7°, pitch −1.5°, roll 2° with 0.3° noise are recovered within 0.2°")
    func recovers() throws {
        let truth = AttitudeCorrection.synthetic(yawDeg: 7, pitchDeg: -1.5, rollDeg: 2, facingAzimuth: 180)
        // The decomposition returns the synthesis to second order (0.02°).
        #expect(abs(truth.yawDeg - 7) < 0.03)
        let exact = truth.tiltDeg(facingAzimuth: 180)
        #expect(abs(exact.pitch - -1.5) < 0.01 && abs(exact.roll - 2) < 0.01)
        for seed: UInt64 in [1, 2, 3, 4, 5] {
            let fit = try #require(AttitudeCorrection.solve(Self.observations(truth, targets: Self.targets, noise: 0.3, seed: seed)))
            let tilt = fit.tiltDeg(facingAzimuth: 180)
            #expect(abs(fit.yawDeg - 7) < 0.2, "yaw \(fit.yawDeg)")
            #expect(abs(tilt.pitch - -1.5) < 0.2, "pitch \(tilt.pitch)")
            #expect(abs(tilt.roll - 2) < 0.2, "roll \(tilt.roll)")
            #expect(fit.residualDeg > 0.1 && fit.residualDeg < 0.6)
            #expect(fit.isAcceptable(config: Self.config))
        }
    }

    @Test("two noiseless targets fit exactly; one target fits the heading only")
    func fewPoints() throws {
        let truth = AttitudeCorrection.synthetic(yawDeg: -12, pitchDeg: 1, rollDeg: -0.8, facingAzimuth: 90)
        let two = try #require(AttitudeCorrection.solve(Self.observations(truth, targets: Array(Self.targets.prefix(2)), noise: 0, seed: 0)))
        #expect(two.residualDeg < 1e-6)
        #expect(abs(two.yawDeg - truth.yawDeg) < 1e-6)
        #expect(abs(two.tiltDeg(facingAzimuth: 90).roll - -0.8) < 0.01)
        let pure = AttitudeCorrection.synthetic(yawDeg: 9, pitchDeg: 0, rollDeg: 0, facingAzimuth: 0)
        let one = try #require(AttitudeCorrection.solve(Self.observations(pure, targets: [Self.targets[3]], noise: 0, seed: 0)))
        #expect(abs(one.yawDeg - 9) < 1e-6 && one.residualDeg < 1e-6)
        // A yaw-only correction is the old single-target heading calibration.
        let a = DeviceAttitude.upright(facingAzimuth: 200, pitchDeg: 30)
        let viaCorrection = a.applying(one).referenceToDevice
        let viaHeading = a.applying(HeadingCalibration(offsetDeg: 9)).referenceToDevice
        for (x, y) in zip([viaCorrection.m11, viaCorrection.m22, viaCorrection.m33, viaCorrection.m12, viaCorrection.m31],
                          [viaHeading.m11, viaHeading.m22, viaHeading.m33, viaHeading.m12, viaHeading.m31]) {
            #expect(abs(x - y) < 1e-9)
        }
    }

    @Test("the corrected attitude puts each target on the crosshair")
    func appliesToAttitude() throws {
        let truth = AttitudeCorrection.synthetic(yawDeg: 5, pitchDeg: 1, rollDeg: 1.5, facingAzimuth: 200)
        let fit = try #require(AttitudeCorrection.solve(Self.observations(truth, targets: Self.targets, noise: 0, seed: 0)))
        let camera = CameraIntrinsics(longSideFieldOfViewDeg: 68, width: 1000, height: 1800)
        for t in Self.targets {
            let sensed = HorizontalPosition(reference: truth.rotation.transposed * t.referenceVector)
            // The sensors' attitude when the user holds the target on the crosshair.
            let raw = DeviceAttitude.upright(facingAzimuth: sensed.azimuthDeg, pitchDeg: sensed.altitudeDeg)
            let bore = SkyProjector(attitude: raw.applying(fit), intrinsics: camera).boresight
            #expect(SkyBrightness.angularSeparationDeg(bore, t) < 1e-4)
        }
    }

    @Test("a misidentified target leaves a residual above the config bound, so it is rejected")
    func rejects() throws {
        let truth = AttitudeCorrection.synthetic(yawDeg: 3, pitchDeg: 0, rollDeg: 0, facingAzimuth: 180)
        var obs = Self.observations(truth, targets: Array(Self.targets.prefix(3)), noise: 0.1, seed: 9)
        // The user aligned on the wrong star, 6° away.
        let wrong = HorizontalPosition(altitudeDeg: Self.targets[3].altitudeDeg + 6, azimuthDeg: Self.targets[3].azimuthDeg)
        obs.append(CalibrationObservation(target: "wrong", trueDirection: wrong,
                                          sensedDirection: HorizontalPosition(reference: truth.rotation.transposed * Self.targets[3].referenceVector)))
        let fit = try #require(AttitudeCorrection.solve(obs))
        #expect(fit.residualDeg > Self.config.calibrationResidualMaxDeg)
        #expect(!fit.isAcceptable(config: Self.config))
    }
}

@Suite("Magnetic disturbance and drift (sensor replay)")
struct HeadingDisturbanceTests {
    static let config = try! AppConfig.bundled().arOverlay
    static let dt = 1.0 / 60

    /// A still phone near a car: the fused heading jumps 8° over 0.2 s while the gyro reads ~0.
    @Test("a heading jump with the gyroscope still is a magnetic disturbance")
    func jump() {
        var m = HeadingDisturbanceMonitor(config: Self.config)
        var n = Noise(seed: 3)
        var flaggedAt: Double?
        for i in 0..<600 {
            let t = Double(i) * Self.dt
            let jump = t < 5 ? 0 : min((t - 5) / 0.2, 1) * 8
            let state = m.update(headingDeg: 180 + jump + n.gaussian(0.05), rateDegPerSecond: n.gaussian(0.2), at: t)
            if state != .steady { flaggedAt = flaggedAt ?? t }
        }
        let t = try! #require(flaggedAt)
        #expect(t > 5 && t < 5.4, "flagged at \(t)")
        guard case .disturbed(let d) = m.state else { Issue.record("state \(m.state)"); return }
        #expect(d > 4)
        #expect(m.isApproximate)
        m.reset()
        #expect(m.state == .steady && !m.isApproximate)
    }

    @Test("fast turns the gyroscope explains never flag")
    func turning() {
        var m = HeadingDisturbanceMonitor(config: Self.config)
        var n = Noise(seed: 4)
        var heading = 90.0
        for i in 0..<1200 {
            let t = Double(i) * Self.dt
            let rate = 60 * sin(t)
            heading += rate * Self.dt
            m.update(headingDeg: Geodesy.normalizedAzimuth(heading + n.gaussian(0.05)), rateDegPerSecond: rate, at: t)
        }
        #expect(m.state == .steady, "\(m.state)")
    }

    @Test("slow unexplained change accumulates into drift, without a jump")
    func drift() {
        var m = HeadingDisturbanceMonitor(config: Self.config)
        var flagged: (Double, HeadingDisturbanceMonitor.State)?
        for i in 0..<(60 * 30) {
            let t = Double(i) * Self.dt
            let state = m.update(headingDeg: 45 + 0.2 * t, rateDegPerSecond: 0, at: t)
            if state != .steady, flagged == nil { flagged = (t, state) }
        }
        let (t, state) = try! #require(flagged)
        guard case .drifted(let d) = state else { Issue.record("\(state)"); return }
        #expect(d > 3 && t > 14 && t < 16.5, "drift \(d) at \(t)")
    }
}
