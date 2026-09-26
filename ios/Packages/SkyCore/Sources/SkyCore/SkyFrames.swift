import Foundation

// Coordinate frames for the map lines and the night AR overlay. All frames
// are right-handed and every vector is a unit direction (no translation: the
// sky is at infinity).
//
// 1. Horizontal (sky) coordinates: altitude h up from the mathematical
//    horizon, azimuth A clockwise from TRUE north toward east, degrees, as
//    SkyPositions returns them.
//
// 2. World ENU: x = east, y = north, z = up.
//    dir(h, A) = (sin A cos h, cos A cos h, sin h).
//
// 3. Core Motion reference frame `.xTrueNorthZVertical` ("reference" below):
//    X = true north, Z = up (vertical), so Y = Z × X = WEST. Apple:
//    "A reference frame where the Z axis is vertical and the X axis points to
//    the geographic north pole", and yaw is 0 "when the X axis is aligned
//    with true north"
//    (developer.apple.com/documentation/coremotion/cmattitudereferenceframe/xtruenorthzvertical).
//    ENU (e, n, u) is (n, −e, u) in this frame.
//
// 4. Device (Core Motion body axes, the axis figure in
//    developer.apple.com/documentation/coremotion/cmmotionmanager): +X toward
//    the right edge of the screen in portrait, +Y toward the top edge, +Z out
//    of the screen toward the viewer. The back camera looks along −Z.
//
// 5. Attitude: `CMAttitude.rotationMatrix` R (fields m11…m33, m_ij = row i,
//    column j) maps reference coordinates to device coordinates:
//    d = R · r. So row i of R is device axis i written in the reference
//    frame, and identity means device X = north, Y = west, Z = up (lying
//    flat, screen up, top edge pointing west). This is how Apple's pARk
//    sample (developer.apple.com/library/archive/samplecode/pARk) uses the
//    matrix: it multiplies R by the point (north, −east, up).
//
// 6. Camera (pinhole, OpenCV convention), back camera, image upright in
//    PORTRAIT: x right, y down, z forward along the optical axis.
//    c = (d.x, −d.y, −d.z), a 180° turn about device X.
//
// 7. Pixels: u = fx·x/z + cx, v = fy·y/z + cy. Origin at the top-left corner
//    of the portrait image, u right, v down, continuous coordinates (the
//    first pixel's centre is (0.5, 0.5)). A direction projects only if z > 0.

extension HorizontalPosition {
    /// Unit vector in world ENU (frame 2).
    public var enuVector: SIMD3<Double> {
        let h = altitudeDeg * .pi / 180, az = azimuthDeg * .pi / 180
        return SIMD3(sin(az) * cos(h), cos(az) * cos(h), sin(h))
    }

    /// Unit vector in the Core Motion `.xTrueNorthZVertical` frame (frame 3).
    public var referenceVector: SIMD3<Double> {
        let e = enuVector
        return SIMD3(e.y, -e.x, e.z)
    }

    /// Inverse of `enuVector`; any non-zero length. Azimuth is 0 at the zenith and nadir.
    public init(enu v: SIMD3<Double>) {
        let horizontal = (v.x * v.x + v.y * v.y).squareRoot()
        let alt = atan2(v.z, horizontal) * 180 / .pi
        let az = horizontal == 0 ? 0 : Geodesy.normalizedAzimuth(atan2(v.x, v.y) * 180 / .pi)
        self.init(altitudeDeg: alt, azimuthDeg: az)
    }

    /// Inverse of `referenceVector`.
    public init(reference v: SIMD3<Double>) {
        self.init(enu: SIMD3(-v.y, v.x, v.z))
    }
}

/// A 3×3 rotation with the same field names as Core Motion's
/// `CMRotationMatrix` (m_ij = row i, column j), so the app copies it field
/// by field.
public struct RotationMatrix: Sendable, Hashable, Codable {
    public var m11, m12, m13: Double
    public var m21, m22, m23: Double
    public var m31, m32, m33: Double

    public init(
        m11: Double, m12: Double, m13: Double,
        m21: Double, m22: Double, m23: Double,
        m31: Double, m32: Double, m33: Double
    ) {
        (self.m11, self.m12, self.m13) = (m11, m12, m13)
        (self.m21, self.m22, self.m23) = (m21, m22, m23)
        (self.m31, self.m32, self.m33) = (m31, m32, m33)
    }

    /// The matrix whose rows are `r1`, `r2`, `r3`.
    public init(rows r1: SIMD3<Double>, _ r2: SIMD3<Double>, _ r3: SIMD3<Double>) {
        self.init(m11: r1.x, m12: r1.y, m13: r1.z, m21: r2.x, m22: r2.y, m23: r2.z, m31: r3.x, m32: r3.y, m33: r3.z)
    }

    public static let identity = RotationMatrix(rows: SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1))

    /// Right-handed rotation by `deg` about +Z (counter-clockwise seen from +Z).
    public static func aboutZ(_ deg: Double) -> RotationMatrix {
        let t = deg * .pi / 180
        return RotationMatrix(rows: SIMD3(cos(t), -sin(t), 0), SIMD3(sin(t), cos(t), 0), SIMD3(0, 0, 1))
    }

    public var row1: SIMD3<Double> { SIMD3(m11, m12, m13) }
    public var row2: SIMD3<Double> { SIMD3(m21, m22, m23) }
    public var row3: SIMD3<Double> { SIMD3(m31, m32, m33) }

    public var transposed: RotationMatrix {
        RotationMatrix(m11: m11, m12: m21, m13: m31, m21: m12, m22: m22, m23: m32, m31: m13, m32: m23, m33: m33)
    }

    public static func * (m: RotationMatrix, v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3((m.row1 * v).sum(), (m.row2 * v).sum(), (m.row3 * v).sum())
    }

    public static func * (l: RotationMatrix, r: RotationMatrix) -> RotationMatrix {
        let t = r.transposed
        func row(_ a: SIMD3<Double>) -> SIMD3<Double> { SIMD3((a * t.row1).sum(), (a * t.row2).sum(), (a * t.row3).sum()) }
        return RotationMatrix(rows: row(l.row1), row(l.row2), row(l.row3))
    }
}

/// Device attitude in Core Motion's `.xTrueNorthZVertical` frame (frames 3–5).
public struct DeviceAttitude: Sendable, Hashable, Codable {
    /// d = referenceToDevice · r.
    public let referenceToDevice: RotationMatrix

    /// Pass `CMDeviceMotion.attitude.rotationMatrix`, field for field, from
    /// updates started with `.xTrueNorthZVertical`.
    public init(coreMotionRotationMatrix m: RotationMatrix) {
        referenceToDevice = m
    }

    /// The attitude with each device axis given as a direction in the sky.
    /// Mainly for tests and previews; the axes must be orthonormal and right-handed.
    public init(deviceX: HorizontalPosition, deviceY: HorizontalPosition, deviceZ: HorizontalPosition) {
        referenceToDevice = RotationMatrix(rows: deviceX.referenceVector, deviceY.referenceVector, deviceZ.referenceVector)
    }

    /// Device vector for a sky direction.
    public func device(_ position: HorizontalPosition) -> SIMD3<Double> {
        referenceToDevice * position.referenceVector
    }

    /// Sky direction of a device vector.
    public func position(ofDevice d: SIMD3<Double>) -> HorizontalPosition {
        HorizontalPosition(reference: referenceToDevice.transposed * d)
    }

    /// The same attitude with every azimuth shifted by `calibration.offsetDeg`:
    /// a direction the sensors placed at azimuth A is really at A + offset.
    public func applying(_ calibration: HeadingCalibration) -> DeviceAttitude {
        // A true direction at azimuth A must map where the sensors put A − offset.
        // Lowering azimuth by δ (north toward west) is a right-handed turn of +δ about Z.
        DeviceAttitude(coreMotionRotationMatrix: referenceToDevice * .aboutZ(calibration.offsetDeg))
    }
}
