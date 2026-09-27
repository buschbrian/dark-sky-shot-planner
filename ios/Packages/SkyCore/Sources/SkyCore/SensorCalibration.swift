public import Foundation

// Compass and gyroscope quality for the Night AR (owner field test,
// 2026-09-26: "the calibration of the compass and gyroscope need to be
// worked on"). Four pieces, all pure and replayable in tests:
//
// - SensorQuality: Core Motion's magnetometer calibration state and
//   CLHeading's accuracy together, and when to show the figure-8 guide.
// - HeadingFilter: circular smoothing of the heading that follows the
//   gyroscope during fast turns (a complementary filter).
// - AttitudeCorrection: a least-squares fit of the attitude error from one
//   or more alignments on known targets (yaw, plus tilt with two or more).
// - HeadingDisturbanceMonitor: heading changes the gyroscope does not
//   explain (a magnetic disturbance, or drift since calibration).

/// `CMDeviceMotion.magneticField.accuracy` (`CMMagneticFieldCalibrationAccuracy`).
public enum MagneticFieldAccuracy: Int, Sendable, Hashable, Codable, CaseIterable {
    case uncalibrated = -1, low = 0, medium = 1, high = 2

    public var label: String {
        switch self {
        case .uncalibrated: "uncalibrated"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

/// The compass as the Sky view reports it: both sensors' own verdicts.
public struct SensorQuality: Sendable, Hashable {
    public var magnetic: MagneticFieldAccuracy
    /// `CLHeading.headingAccuracy`, degrees; negative means invalid.
    public var headingAccuracyDeg: Double

    public init(magnetic: MagneticFieldAccuracy, headingAccuracyDeg: Double) {
        self.magnetic = magnetic
        self.headingAccuracyDeg = headingAccuracyDeg
    }

    /// Show the figure-8 guide: the magnetometer is uncalibrated or low, or
    /// the heading is invalid or worse than the confident threshold.
    public func needsFigureEight(config: AROverlayConfig) -> Bool {
        if magnetic == .uncalibrated || magnetic == .low { return true }
        return !headingAccuracyDeg.isFinite || headingAccuracyDeg < 0 || headingAccuracyDeg > config.headingAccuracyConfidentMaxDeg
    }

    /// "Magnetometer low · compass ±25°".
    public var summary: String {
        let heading = headingAccuracyDeg >= 0 && headingAccuracyDeg.isFinite
            ? "compass ±\(Int(headingAccuracyDeg.rounded()))°" : "compass invalid"
        return "Magnetometer \(magnetic.label) · \(heading)"
    }
}

extension DeviceAttitude {
    /// The phone's heading, degrees clockwise from true north: the azimuth
    /// of the horizontal part of (back-camera axis − top-edge axis). That
    /// is the camera's azimuth when held upright and stays defined (and
    /// continuous) as the camera tilts up to the zenith, where the camera
    /// axis alone has no azimuth.
    public var headingDeg: Double {
        let camera = referenceToDevice.row3 * -1 // device −Z in the reference frame
        let top = referenceToDevice.row2         // device +Y
        let v = camera - top
        return HorizontalPosition(reference: SIMD3(v.x, v.y, 0)).azimuthDeg
    }

    /// Heading rate (degrees per second, clockwise positive) for a
    /// `CMDeviceMotion.rotationRate` (radians per second, device axes):
    /// the rate about the vertical.
    public func headingRateDegPerSecond(deviceRotationRate w: SIMD3<Double>) -> Double {
        let world = referenceToDevice.transposed * w
        // Right-handed about up is counter-clockwise seen from above.
        return -world.z * 180 / .pi
    }
}

/// Smooths a heading that wraps at 360°. Each sample first advances the
/// estimate by the gyroscope's heading rate (so fast turns do not lag),
/// then pulls it toward the measured heading along the shorter way round
/// with time constant `timeConstant` (so compass noise averages out).
/// Differences go through `Geodesy.signedAngle`, never raw subtraction, so
/// 359° → 1° is a 2° step.
public struct HeadingFilter: Sendable, Hashable {
    /// Seconds; a still phone settles a step to 1/e in this time.
    public var timeConstant: TimeInterval
    /// A disagreement this large is a new heading (recalibration, restart), not noise.
    public var snapDeg: Double
    public private(set) var headingDeg: Double?
    private var lastTime: TimeInterval?

    /// A 30° step settles to within 1° in τ·ln 30 ≈ 1.02 s at τ = 0.3 s.
    public static let settleSeconds: TimeInterval = 1.1

    public init(timeConstant: TimeInterval = 0.3, snapDeg: Double = 45) {
        self.timeConstant = timeConstant
        self.snapDeg = snapDeg
    }

    /// Feed a measured heading at time `t` (seconds, any epoch) with the
    /// gyroscope's heading rate; returns the filtered heading in [0, 360).
    @discardableResult
    public mutating func update(measuredDeg: Double, at t: TimeInterval, rateDegPerSecond rate: Double = 0) -> Double {
        guard let previous = headingDeg, let last = lastTime, t > last else {
            headingDeg = Geodesy.normalizedAzimuth(measuredDeg)
            lastTime = t
            return headingDeg!
        }
        let dt = min(t - last, 0.5)
        let predicted = previous + rate * dt
        let innovation = Geodesy.signedAngle(measuredDeg - predicted)
        let next: Double
        if abs(innovation) > snapDeg {
            next = measuredDeg
        } else {
            let alpha = 1 - exp(-dt / timeConstant)
            next = predicted + alpha * innovation
        }
        headingDeg = Geodesy.normalizedAzimuth(next)
        lastTime = t
        return headingDeg!
    }

    public mutating func reset() {
        headingDeg = nil
        lastTime = nil
    }

    /// Signed degrees to add to the raw heading to get the filtered one.
    public func correctionDeg(forMeasuredDeg measured: Double) -> Double {
        headingDeg.map { Geodesy.signedAngle($0 - measured) } ?? 0
    }
}

/// One alignment: the target's true direction and where the uncorrected
/// sensors said the crosshair pointed when the user lined it up.
public struct CalibrationObservation: Sendable, Hashable, Codable {
    public let target: String
    /// Reference-frame (north, west, up) unit vectors.
    public let trueDirection: SIMD3<Double>
    public let sensedDirection: SIMD3<Double>

    public init(target: String, trueDirection: HorizontalPosition, sensedDirection: HorizontalPosition) {
        self.target = target
        self.trueDirection = trueDirection.referenceVector
        self.sensedDirection = sensedDirection.referenceVector
    }
}

/// A rotation of the sky that takes where the sensors say the phone points
/// to where it really points: true = rotation · sensed. With one alignment
/// it is a heading offset only; with two or more it also tilts the vertical
/// (the pitch and roll bias of the accelerometer and the camera mount).
public struct AttitudeCorrection: Sendable, Hashable, Codable {
    public let rotation: RotationMatrix
    /// RMS angle between each target and its corrected direction, degrees.
    public let residualDeg: Double
    public let targets: [String]

    public static let identity = AttitudeCorrection(rotation: .identity, residualDeg: 0, targets: [])

    public var isIdentity: Bool { targets.isEmpty }

    /// The heading part: degrees added to every azimuth (clockwise positive).
    public var yawDeg: Double {
        // Where true north's horizontal direction ends up, measured clockwise.
        let n = rotation * SIMD3(1, 0, 0)
        return Geodesy.signedAngle(HorizontalPosition(reference: SIMD3(n.x, n.y, 0)).azimuthDeg)
    }

    /// The tilt part, for someone facing `azimuthDeg`: pitch raises what is
    /// in front (degrees, up positive) and roll tilts the horizon in view
    /// (degrees, clockwise as seen by the viewer positive).
    public func tiltDeg(facingAzimuth azimuthDeg: Double) -> (pitch: Double, roll: Double) {
        let tilt = RotationMatrix.aboutZ(yawDeg) * rotation // remove yaw: yaw⁻¹ = aboutZ(+yaw)
        let up = tilt * SIMD3(0, 0, 1)
        let forward = HorizontalPosition(altitudeDeg: 0, azimuthDeg: azimuthDeg).referenceVector
        let right = HorizontalPosition(altitudeDeg: 0, azimuthDeg: azimuthDeg + 90).referenceVector
        // The vertical leans toward `forward` when things in front are raised (pitch up).
        let pitch = -asin(max(-1, min(1, (up * forward).sum()))) * 180 / .pi
        let roll = asin(max(-1, min(1, (up * right).sum()))) * 180 / .pi
        return (pitch, roll)
    }

    /// A correction from yaw, then pitch about the right-hand axis and roll
    /// about the forward axis of someone facing `azimuthDeg` (test synthesis).
    public static func synthetic(yawDeg: Double, pitchDeg: Double, rollDeg: Double, facingAzimuth az: Double) -> AttitudeCorrection {
        let forward = HorizontalPosition(altitudeDeg: 0, azimuthDeg: az).referenceVector
        let right = HorizontalPosition(altitudeDeg: 0, azimuthDeg: az + 90).referenceVector
        // Right-handed about the right-hand axis lifts what is in front; about
        // the forward axis it turns the view clockwise for the viewer.
        let r = RotationMatrix.aboutZ(-yawDeg) * .about(axis: right, deg: pitchDeg) * .about(axis: forward, deg: rollDeg)
        return AttitudeCorrection(rotation: r, residualDeg: 0, targets: ["synthetic"])
    }

    /// Least-squares fit (Gauss–Newton on the rotation vector, which
    /// converges in a few steps for the few-degree errors a compass makes).
    /// One observation fits the heading only; two or more fit all three axes.
    public static func solve(_ observations: [CalibrationObservation]) -> AttitudeCorrection? {
        guard !observations.isEmpty else { return nil }
        let yawOnly = observations.count == 1 || observations.allSatisfy {
            angle($0.sensedDirection, observations[0].sensedDirection) < 2
        }
        var r = RotationMatrix.identity
        for _ in 0..<8 {
            var m = [[Double]](repeating: [0, 0, 0], count: 3)
            var b = SIMD3<Double>.zero
            for o in observations {
                let p = r * o.sensedDirection
                let cross = SIMD3(p.y * o.trueDirection.z - p.z * o.trueDirection.y,
                                  p.z * o.trueDirection.x - p.x * o.trueDirection.z,
                                  p.x * o.trueDirection.y - p.y * o.trueDirection.x)
                b += cross
                let pp = [p.x, p.y, p.z]
                for i in 0..<3 { for j in 0..<3 { m[i][j] += (i == j ? 1 : 0) - pp[i] * pp[j] } }
            }
            let w: SIMD3<Double>
            if yawOnly {
                guard m[2][2] > 1e-9 else { return nil }
                w = SIMD3(0, 0, b.z / m[2][2])
            } else {
                guard let solved = solve3(m, b) else { return nil }
                w = solved
            }
            let angleRad = (w * w).sum().squareRoot()
            if angleRad < 1e-12 { break }
            r = .about(axis: w / angleRad, deg: angleRad * 180 / .pi) * r
            if angleRad < 1e-10 { break }
        }
        let residuals = observations.map { angle(r * $0.sensedDirection, $0.trueDirection) }
        let rms = (residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count)).squareRoot()
        return AttitudeCorrection(rotation: r, residualDeg: rms, targets: observations.map(\.target))
    }

    /// Accept only a fit whose residual is within the configured bound.
    public func isAcceptable(config: AROverlayConfig) -> Bool {
        residualDeg <= config.calibrationResidualMaxDeg
    }

    static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = (a * b).sum() / ((a * a).sum() * (b * b).sum()).squareRoot()
        return acos(max(-1, min(1, d))) * 180 / .pi
    }

    private static func solve3(_ m: [[Double]], _ b: SIMD3<Double>) -> SIMD3<Double>? {
        let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        guard abs(det) > 1e-9 else { return nil }
        func replaced(_ col: Int) -> Double {
            var c = m
            for i in 0..<3 { c[i][col] = b[i] }
            return c[0][0] * (c[1][1] * c[2][2] - c[1][2] * c[2][1])
                - c[0][1] * (c[1][0] * c[2][2] - c[1][2] * c[2][0])
                + c[0][2] * (c[1][0] * c[2][1] - c[1][1] * c[2][0])
        }
        return SIMD3(replaced(0), replaced(1), replaced(2)) / det
    }
}

extension RotationMatrix {
    /// Right-handed rotation by `deg` about a unit `axis` (Rodrigues).
    public static func about(axis k: SIMD3<Double>, deg: Double) -> RotationMatrix {
        let t = deg * .pi / 180, c = cos(t), s = sin(t), v = 1 - c
        return RotationMatrix(
            m11: c + k.x * k.x * v, m12: k.x * k.y * v - k.z * s, m13: k.x * k.z * v + k.y * s,
            m21: k.y * k.x * v + k.z * s, m22: c + k.y * k.y * v, m23: k.y * k.z * v - k.x * s,
            m31: k.z * k.x * v - k.y * s, m32: k.z * k.y * v + k.x * s, m33: c + k.z * k.z * v)
    }
}

extension DeviceAttitude {
    /// The sensors' attitude with a fitted correction applied: a device
    /// vector the sensors place at sky direction s really points at C·s,
    /// so reference→device becomes R·Cᵀ. A yaw-only correction equals
    /// `applying(HeadingCalibration(offsetDeg: yawDeg))`.
    public func applying(_ correction: AttitudeCorrection) -> DeviceAttitude {
        DeviceAttitude(coreMotionRotationMatrix: referenceToDevice * correction.rotation.transposed)
    }
}

/// Watches for heading changes the gyroscope cannot explain. The gyro
/// measures turning directly and does not care about magnets; the fused
/// heading follows the magnetometer, so a jump in heading while the gyro
/// says the phone is still is a magnetic disturbance (a car, a steel
/// tripod, a magnetised rock), and slow unexplained change since the last
/// calibration is drift. Either marks the overlay approximate until the
/// user recalibrates (`reset`).
public struct HeadingDisturbanceMonitor: Sendable {
    public enum State: Sendable, Hashable {
        case steady
        case disturbed(jumpDeg: Double)
        case drifted(driftDeg: Double)
    }

    public let jumpThresholdDeg: Double
    public let driftThresholdDeg: Double
    /// Below this turn rate (deg/s) the phone counts as nearly still.
    public let stillRateDegPerSecond: Double
    public private(set) var state = State.steady
    /// Unexplained heading change since the last reset, degrees (signed).
    public private(set) var accumulatedDeg = 0.0

    private var window: [(t: TimeInterval, unexplained: Double, still: Bool)] = []
    private var last: (t: TimeInterval, heading: Double)?

    public init(jumpThresholdDeg: Double, driftThresholdDeg: Double, stillRateDegPerSecond: Double = 5) {
        self.jumpThresholdDeg = jumpThresholdDeg
        self.driftThresholdDeg = driftThresholdDeg
        self.stillRateDegPerSecond = stillRateDegPerSecond
    }

    public init(config: AROverlayConfig) {
        self.init(jumpThresholdDeg: config.headingJumpDisturbanceDeg, driftThresholdDeg: config.headingDriftMaxDeg)
    }

    public var isApproximate: Bool { state != .steady }

    /// Feed the fused heading (degrees) and the gyroscope heading rate (deg/s) at time `t`.
    @discardableResult
    public mutating func update(headingDeg: Double, rateDegPerSecond rate: Double, at t: TimeInterval) -> State {
        defer { last = (t, headingDeg) }
        guard let last, t > last.t else { return state }
        let dt = min(t - last.t, 0.5)
        let unexplained = Geodesy.signedAngle(headingDeg - last.heading) - rate * dt
        accumulatedDeg += unexplained
        window.append((t, unexplained, abs(rate) < stillRateDegPerSecond))
        window.removeAll { t - $0.t > 1 }
        // A jump: within the last second, with the phone still throughout.
        if window.allSatisfy(\.still) {
            let jump = window.reduce(0) { $0 + $1.unexplained }
            if abs(jump) > jumpThresholdDeg, state == .steady || isDrift {
                state = .disturbed(jumpDeg: jump)
            }
        }
        if state == .steady, abs(accumulatedDeg) > driftThresholdDeg {
            state = .drifted(driftDeg: accumulatedDeg)
        }
        return state
    }

    private var isDrift: Bool {
        if case .drifted = state { true } else { false }
    }

    /// After a recalibration: trust the heading again.
    public mutating func reset() {
        state = .steady
        accumulatedDeg = 0
        window = []
    }
}
