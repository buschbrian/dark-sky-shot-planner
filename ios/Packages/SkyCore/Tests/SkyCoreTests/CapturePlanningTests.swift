import Foundation
import Testing
@testable import SkyCore

@Suite("Capture planning")
struct CapturePlanningTests {
    // A 12 MP iPhone main-camera frame: 6.86 mm lens, 24 mm equivalent.
    // Crop 24 / 6.86 = 3.4985; diagonal 43.267 / 3.4985 = 12.367 mm; 4:3
    // split 9.894 × 7.420 mm; pitch 9.894 mm / 4032 px = 2.454 µm.
    @Test func phoneGearFromExif() throws {
        let gear = try PhoneGear.profiles(name: "iPhone main", focalLengthMM: 6.86, focalLength35mmEquivalent: 24,
                                          fNumber: 1.48, widthPx: 4032, heightPx: 3024)
        #expect(approx(gear.camera.sensorWidthMM, 9.894, 0.002))
        #expect(approx(gear.camera.sensorHeightMM, 7.420, 0.002))
        #expect(approx(gear.camera.pixelPitchUM, 2.454, 0.001))
        #expect(approx(gear.camera.cropFactor, 24 / 6.86, 1e-9))
        #expect(gear.lens.maxFNumber == 1.48)
    }

    @Test func phoneGearTakesPortraitDimensions() throws {
        let a = try PhoneGear.profiles(name: "a", focalLengthMM: 6.86, focalLength35mmEquivalent: 24,
                                       fNumber: 1.48, widthPx: 3024, heightPx: 4032)
        #expect(a.camera.resolution?.widthPx == 4032)
    }

    @Test func npfForThePhoneMainCamera() throws {
        // NPF (k = 1, δ = 0): (16.856·1.48 + 0.0997·6.86 + 13.713·2.454) / 6.86 = 8.64 s.
        let gear = try PhoneGear.profiles(name: "m", focalLengthMM: 6.86, focalLength35mmEquivalent: 24,
                                          fNumber: 1.48, widthPx: 4032, heightPx: 3024)
        let t = try StarExposure.npf(camera: gear.camera, lens: gear.lens)
        #expect(approx(t, 8.64, 0.01))
    }

    @Test func planTotals() throws {
        // 16 frames of 1 s with 0.25 s gaps; 24.9 MB DNGs, 73 MB working copies.
        let raw = CapturePlan.estimatedRawBytes(width: 4032, height: 3024)
        let rgb = CapturePlan.rgb16Bytes(width: 4032, height: 3024)
        #expect(raw == 24_873_246)
        #expect(rgb == 73_156_608)
        let plan = try CapturePlan(frames: 16, subExposure: 1, gap: 0.25, bytesPerFrame: raw,
                                   workingBytesPerFrame: rgb, stackBytes: rgb)
        #expect(plan.duration == 20)
        #expect(plan.integration == 16)
        #expect(plan.storedBytes == 16 * raw + rgb)
        #expect(plan.peakBytes == 16 * (raw + rgb) + rgb)
        #expect(plan.fits(freeBytes: 3 << 30))
        #expect(!plan.fits(freeBytes: 2 << 30))
        #expect(plan.maxFrames(freeBytes: 3 << 30) == Int(((3 << 30) - (1 << 30) - rgb) / (raw + rgb)))
    }

    @Test func planRejectsNonsense() {
        #expect(throws: ExposureError.self) {
            try CapturePlan(frames: 0, subExposure: 1, gap: 0, bytesPerFrame: 1, workingBytesPerFrame: 0, stackBytes: 0)
        }
        #expect(throws: ExposureError.self) {
            try CapturePlan(frames: 1, subExposure: 0, gap: 0, bytesPerFrame: 1, workingBytesPerFrame: 0, stackBytes: 0)
        }
        #expect(throws: ExposureError.self) {
            try CapturePlan(frames: 1, subExposure: 1, gap: -1, bytesPerFrame: 1, workingBytesPerFrame: 0, stackBytes: 0)
        }
    }

    @Test func framesFromTheStackingCalculator() throws {
        // A 4× SNR gain needs 16 frames (M10 Stacking).
        let plan = try Stacking.plan(snrGain: 4, subExposure: 1)
        #expect(plan.frames == 16)
    }
}

@Suite("Battery trend")
struct BatteryTrendTests {
    @Test func unmeasuredUntilTheLevelMoves() {
        var t = BatteryTrend()
        t.add(.init(time: 0, level: 0.80))
        t.add(.init(time: 600, level: 0.80))
        #expect(t.drainPerHour == nil)
        #expect(t.estimatedUse(duration: 600) == nil)
    }

    @Test func fitsAStraightLine() throws {
        var t = BatteryTrend()
        // 1 % every 3 minutes = 20 %/h.
        for i in 0...10 { t.add(.init(time: Double(i) * 180, level: 0.9 - 0.01 * Double(i))) }
        #expect(approx(try #require(t.drainPerHour), 0.20, 1e-9))
        #expect(approx(try #require(t.estimatedUse(duration: 600)), 0.20 / 6, 1e-9))
    }

    @Test func chargingRestartsTheFit() {
        var t = BatteryTrend()
        t.add(.init(time: 0, level: 0.9))
        t.add(.init(time: 400, level: 0.85))
        t.add(.init(time: 500, level: 0.95))
        #expect(t.samples.count == 1)
    }
}

@Suite("Thermal policy")
struct ThermalPolicyTests {
    @Test func stepsUpWithHeat() {
        #expect(ThermalPolicy.action(for: .nominal, subExposure: 1) == .proceed)
        #expect(ThermalPolicy.action(for: .fair, subExposure: 1) == .proceed)
        #expect(ThermalPolicy.action(for: .serious, subExposure: 1) == .coolDown(2))
        #expect(ThermalPolicy.action(for: .serious, subExposure: 8) == .coolDown(8))
        #expect(ThermalPolicy.action(for: .critical, subExposure: 1) == .stop)
    }
}

@Suite("Tripod stability")
struct StabilityTests {
    @Test func stillOnATripod() {
        var m = StabilityMonitor(window: 50)
        var rng = SplitMix64(seed: 1)
        for _ in 0..<50 {
            m.add(SIMD3(0.001 * rng.gaussian(), 0.001 * rng.gaussian(), 0.001 * rng.gaussian()))
        }
        #expect(m.isStable == true)
    }

    @Test func notStillInTheHand() {
        var m = StabilityMonitor(window: 50)
        for i in 0..<50 {
            let t = Double(i) / 50
            m.add(SIMD3(0.05 * sin(2 * .pi * 3 * t), 0.03 * cos(2 * .pi * 2 * t), 0.02))
        }
        #expect(m.isStable == false)
    }

    @Test func aTapShowsUpAsVariance() {
        var m = StabilityMonitor(window: 50)
        for i in 0..<50 { m.add(i == 25 ? SIMD3(0.2, -0.1, 0) : .zero) }
        #expect(m.isStable == false)
        #expect(m.meanRate! < 0.01)
    }

    @Test func undecidedUntilTheWindowFills() {
        var m = StabilityMonitor(window: 50)
        for _ in 0..<49 { m.add(.zero) }
        #expect(m.isStable == nil)
        m.add(.zero)
        #expect(m.isStable == true)
        m.reset()
        #expect(m.isStable == nil)
    }
}
