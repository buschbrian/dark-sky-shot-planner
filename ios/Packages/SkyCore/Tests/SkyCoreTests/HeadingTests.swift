import Foundation
import Testing
@testable import SkyCore

@Suite("Heading confidence and calibration (M7)")
struct HeadingTests {
    @Test("confidence threshold comes from config/app-config.json")
    func confidenceFromConfig() throws {
        let config = try AppConfig.bundled().arOverlay
        let max = config.headingAccuracyConfidentMaxDeg
        #expect(try AppConfig.decode(Repo.data("config/app-config.json")).arOverlay == config)

        #expect(HeadingConfidence(headingAccuracyDeg: -1, config: config) == .unavailable)
        #expect(HeadingConfidence(headingAccuracyDeg: .nan, config: config) == .unavailable)
        #expect(HeadingConfidence(headingAccuracyDeg: .infinity, config: config) == .unavailable)
        #expect(HeadingConfidence(headingAccuracyDeg: 0, config: config) == .confident(accuracyDeg: 0))
        #expect(HeadingConfidence(headingAccuracyDeg: max, config: config).isConfident)
        #expect(HeadingConfidence(headingAccuracyDeg: max + 0.1, config: config) == .poor(accuracyDeg: max + 0.1))
        #expect(!HeadingConfidence(headingAccuracyDeg: 180, config: config).isConfident)
    }

    @Test(
        "calibration offset wraps across north",
        arguments: [(100.0, 90.0, 10.0), (5, 355, 10), (355, 5, -10), (0, 180, 180), (180, 0, 180), (359.5, 0.5, -1), (42, 42, 0)]
    )
    func offsetWraps(_ c: (computed: Double, aligned: Double, offset: Double)) {
        let cal = HeadingCalibration(computedAzimuthDeg: c.computed, alignedAzimuthDeg: c.aligned)
        #expect(abs(cal.offsetDeg - c.offset) < 1e-12)
        #expect(azimuthDelta(cal.correct(azimuthDeg: c.aligned), c.computed) < 1e-12)
    }

    @Test func correctionStaysInRange() {
        #expect(HeadingCalibration(offsetDeg: 10).correct(azimuthDeg: 355) == 5)
        #expect(HeadingCalibration(offsetDeg: -10).correct(azimuthDeg: 5) == 355)
        #expect(HeadingCalibration(offsetDeg: 370).offsetDeg == 10)
        #expect(HeadingCalibration.none.correct(azimuthDeg: 123) == 123)
    }

    @Test("aligning the Moon on the crosshair corrects a 10° compass error in the projection")
    func calibrationFixesProjection() {
        let camera = CameraIntrinsics(fx: 2900, fy: 2900, cx: 1512, cy: 2016, width: 3024, height: 4032)
        func facing(_ az: Double) -> DeviceAttitude {
            DeviceAttitude(
                deviceX: HorizontalPosition(altitudeDeg: 0, azimuthDeg: az + 90),
                deviceY: HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0),
                deviceZ: HorizontalPosition(altitudeDeg: 0, azimuthDeg: az + 180))
        }
        // The phone really faces 100°, the Moon (computed) sits there on the
        // crosshair, but the magnetometer reads 10° low.
        let moon = HorizontalPosition(altitudeDeg: 0, azimuthDeg: 100)
        let reported = SkyProjector(attitude: facing(90), intrinsics: camera)
        let moonPixel = reported.project(moon).pixel!
        #expect(abs(moonPixel.u - (1512 + 2900 * tan(10 * Double.pi / 180))) < 1e-6)

        let cal = HeadingCalibration(computedAzimuthDeg: moon.azimuthDeg, alignedAzimuthDeg: reported.boresight.azimuthDeg)
        #expect(abs(cal.offsetDeg - 10) < 1e-9)
        let fixed = SkyProjector(attitude: reported.attitude.applying(cal), intrinsics: camera)
        let p = fixed.project(moon).pixel!
        #expect(abs(p.u - 1512) < 1e-6 && abs(p.v - 2016) < 1e-6)
        #expect(azimuthDelta(fixed.boresight.azimuthDeg, 100) < 1e-9)
        // Altitudes are untouched by a heading correction.
        let high = HorizontalPosition(altitudeDeg: 30, azimuthDeg: 100)
        #expect(abs(fixed.unproject(fixed.project(high).pixel!).altitudeDeg - 30) < 1e-9)
        #expect(abs(fixed.project(high).pixel!.v - (2016 - 2900 * tan(30 * Double.pi / 180))) < 1e-6)
    }
}
