import Foundation
import Testing
@testable import SkyCore

@Suite("Hyperfocal distance and depth of field")
struct DepthOfFieldTests {
    // Wikipedia, "Hyperfocal distance", Example: 50 mm at f/8, CoC 0.03 mm -> H = 10467 mm
    // (definition 1); definition 2 (H − f) gives 10417 mm.
    @Test func hyperfocal_WikipediaExample() throws {
        let h = try DepthOfField.hyperfocalMeters(focalLengthMM: 50, fNumber: 8, circleOfConfusionMM: 0.03)
        #expect(approx(h * 1000, 10467, 0.5))
        #expect(approx(h * 1000 - 50, 10417, 0.5))
    }

    // Wikipedia, "Hyperfocal distance", Example figure: 50 mm f/16 -> 5258 mm; 25 mm f/8 -> 2629 mm (CoC 0.03 mm).
    @Test("hyperfocal matches Wikipedia's example figure", arguments: [(50.0, 16.0, 5258.0), (25.0, 8.0, 2629.0)])
    func hyperfocal_WikipediaFigure(focal: Double, fNumber: Double, expectedMM: Double) throws {
        let h = try DepthOfField.hyperfocalMeters(focalLengthMM: focal, fNumber: fNumber, circleOfConfusionMM: 0.03)
        #expect(approx(h * 1000, expectedMM, 0.5))
    }

    // Wikipedia, "Hyperfocal distance", Example: focused at 10.5 m, everything from
    // 5.2 m to infinity is acceptably sharp.
    @Test func limits_WikipediaFocusAt10_5m() throws {
        let dof = try DepthOfField.limits(focalLengthMM: 50, fNumber: 8, circleOfConfusionMM: 0.03, focusDistanceMeters: 10.5)
        #expect(approx(dof.nearMeters, 5.2, 0.05))
        #expect(dof.far == .infinity)
        #expect(dof.depthMeters == nil)
    }

    @Test func focusAtHyperfocalGivesHalfToInfinity() throws {
        for f in GearGrid.focalLengths {
            for n in GearGrid.fNumbers {
                let h = try DepthOfField.hyperfocalMeters(focalLengthMM: f, fNumber: n, circleOfConfusionMM: 0.029)
                let dof = try DepthOfField.limits(focalLengthMM: f, fNumber: n, circleOfConfusionMM: 0.029, focusDistanceMeters: h)
                #expect(approxRel(dof.nearMeters, h / 2, 1e-9))
                #expect(dof.far == .infinity)
            }
        }
    }

    @Test func finiteFarLimitBracketsTheFocusDistance() throws {
        // 85 mm f/1.8 on full frame, focused at 3 m: a shallow, finite zone around the subject.
        let dof = try DepthOfField.limits(focalLengthMM: 85, fNumber: 1.8, circleOfConfusionMM: 0.029, focusDistanceMeters: 3)
        let far = try #require(dof.far.meters)
        #expect(dof.nearMeters < 3 && far > 3)
        #expect(far - 3 > 3 - dof.nearMeters) // more depth behind the subject than in front
        #expect(approx(try #require(dof.depthMeters), far - dof.nearMeters, 1e-12))
        // Greenleaf/DOFMaster by hand: H = 85²/(1.8·0.029) + 85 mm.
        let h = 85.0 * 85 / (1.8 * 0.029) + 85
        #expect(approxRel(dof.nearMeters * 1000, 3000 * (h - 85) / (h + 3000 - 170), 1e-12))
        #expect(approxRel(far * 1000, 3000 * (h - 85) / (h - 3000), 1e-12))
    }

    @Test func depthGrowsWhenStoppingDownAndShrinksWithFocalLength() throws {
        var previous = 0.0
        for n in GearGrid.fNumbers {
            let dof = try DepthOfField.limits(focalLengthMM: 85, fNumber: n, circleOfConfusionMM: 0.029, focusDistanceMeters: 2)
            let depth = try #require(dof.depthMeters)
            #expect(depth > previous)
            previous = depth
        }
        var previousH = 0.0
        for f in GearGrid.focalLengths {
            let h = try DepthOfField.hyperfocalMeters(focalLengthMM: f, fNumber: 2.8, circleOfConfusionMM: 0.029)
            #expect(h > previousH)
            previousH = h
        }
    }

    @Test func nearLimitRisesAndFarLimitRecedesWithFocusDistance() throws {
        var previousNear = 0.0
        var previousFar = 0.0
        for s in [0.5, 1, 2, 3, 5, 8] { // all inside H ≈ 10.5 m
            let dof = try DepthOfField.limits(focalLengthMM: 50, fNumber: 8, circleOfConfusionMM: 0.03, focusDistanceMeters: s)
            let far = try #require(dof.far.meters)
            #expect(dof.nearMeters > previousNear && far > previousFar)
            previousNear = dof.nearMeters
            previousFar = far
        }
    }

    @Test func savedGearUsesDiagonalOver1500() throws {
        let camera = try fullFrame()
        let lens = try LensProfile(name: "14/2.8", focalLengthMM: 14, maxFNumber: 2.8)
        let h = try DepthOfField.hyperfocalMeters(camera: camera, lens: lens)
        let c = (36.0 * 36 + 24 * 24).squareRoot() / 1500
        #expect(approxRel(h, (14 * 14 / (2.8 * c) + 14) / 1000, 1e-12))
        let dof = try DepthOfField.limits(camera: camera, lens: lens, fNumber: 4, focusDistanceMeters: 1)
        #expect(dof.hyperfocalMeters < h) // f/4 has a nearer hyperfocal than f/2.8
    }

    @Test func rejectsBadInput() {
        #expect(throws: ExposureError.invalid(.focalLength, 0)) {
            try DepthOfField.hyperfocalMeters(focalLengthMM: 0, fNumber: 2.8, circleOfConfusionMM: 0.029)
        }
        #expect(throws: ExposureError.invalid(.fNumber, 0.6)) {
            try DepthOfField.hyperfocalMeters(focalLengthMM: 24, fNumber: 0.6, circleOfConfusionMM: 0.029)
        }
        #expect(throws: ExposureError.invalid(.circleOfConfusion, 0)) {
            try DepthOfField.hyperfocalMeters(focalLengthMM: 24, fNumber: 2.8, circleOfConfusionMM: 0)
        }
        #expect(throws: ExposureError.invalid(.focusDistance, 0.02)) { // inside the focal length
            try DepthOfField.limits(focalLengthMM: 24, fNumber: 2.8, circleOfConfusionMM: 0.029, focusDistanceMeters: 0.02)
        }
        #expect(throws: ExposureError.self) {
            try DepthOfField.limits(focalLengthMM: 24, fNumber: 2.8, circleOfConfusionMM: 0.029, focusDistanceMeters: .nan)
        }
        #expect(throws: ExposureError.invalid(.cocDivisor, 0)) { try DepthOfField.circleOfConfusionMM(sensorDiagonalMM: 43.3, divisor: 0) }
        #expect(throws: ExposureError.invalid(.sensorDiagonal, -1)) { try DepthOfField.circleOfConfusionMM(sensorDiagonalMM: -1) }
    }

    @Test func infiniteFocusDistanceIsRejectedNotNaN() {
        // ∞ − ∞ would be NaN; the far limit for "focus at infinity" is modelled as s ≥ H instead.
        #expect(throws: ExposureError.invalid(.focusDistance, .infinity)) {
            try DepthOfField.limits(focalLengthMM: 24, fNumber: 2.8, circleOfConfusionMM: 0.029, focusDistanceMeters: .infinity)
        }
    }
}
