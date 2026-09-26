import Foundation
import Testing
@testable import SkyCore

@Suite("NPF rule, 500 rule, star trails")
struct StarExposureTests {
    // MARK: NPF, published worked examples

    // Fstoppers, "Using the NPF Rule for Photographing Night Skies": 5D Mark IV (5.36 µm),
    // 16 mm f/2.8 -> (98 + 160.8) / 16 = 16.2 s.
    @Test func npfSimple_Fstoppers5DMarkIV() throws {
        let t = try StarExposure.npfSimple(fNumber: 2.8, focalLengthMM: 16, pixelPitchUM: 5.36)
        #expect(approx(t, 16.2, 0.05))
    }

    // Fstoppers (same article): Sony a7R IV, 3.75 µm, 16 mm f/2.8 -> 13.1 s (13.156 truncated).
    @Test func npfSimple_FstoppersA7RIV() throws {
        let t = try StarExposure.npfSimple(fNumber: 2.8, focalLengthMM: 16, pixelPitchUM: 3.75)
        #expect(t >= 13.1 && t < 13.2)
    }

    // Lightstalking, "What Is The NPF Rule": Nikon D750 + 24 mm f/2.8 -> 11.54 s; 500 rule 20.8 s.
    @Test func npfSimpleAndRule500_LightstalkingD750() throws {
        let camera = try CameraProfile(name: "D750", sensorWidthMM: 35.9, sensorHeightMM: 24.0,
                                       resolution: PixelResolution(widthPx: 6016, heightPx: 4016))
        let lens = try LensProfile(name: "24/2.8", focalLengthMM: 24, maxFNumber: 2.8)
        #expect(approx(try StarExposure.npfSimple(camera: camera, lens: lens), 11.54, 0.005))
        #expect(approx(try StarExposure.roughRule500(focalLengthMM: 24), 20.8, 0.05))
    }

    /// The complete rule from its physical model in "Les coulisses de la règle NPF" (SAH):
    /// t = (k/2)(4.47·λ·N + f·α + 2p) / (f·cos δ / 13713), λ = 550 nm, α = 3″, SI units.
    static func npfFromSAHModel(n: Double, fMM: Double, pUM: Double, decDeg: Double, k: Double) -> Double {
        let airy = 4.47 * 550e-9 * n
        let seeing = fMM * 1e-3 * 3 * .pi / (180 * 3600)
        let bayer = 2 * pUM * 1e-6
        let speed = fMM * 1e-3 * cos(decDeg * .pi / 180) / 13713
        return k / 2 * (airy + seeing + bayer) / speed
    }

    @Test("complete NPF equals the SAH physical model it was derived from")
    func npfMatchesSAHDerivation() throws {
        for n in GearGrid.fNumbers {
            for f in GearGrid.focalLengths {
                for p in GearGrid.pitches {
                    for dec in [0.0, 30, -60] {
                        for k in [1.0, 2, 3] {
                            let ours = try StarExposure.npf(fNumber: n, focalLengthMM: f, pixelPitchUM: p, declinationDeg: dec, k: k)
                            let model = Self.npfFromSAHModel(n: n, fMM: f, pUM: p, decDeg: dec, k: k)
                            #expect(approxRel(ours, model, 0.0005), "N \(n) f \(f) p \(p) δ \(dec) k \(k)")
                        }
                    }
                }
            }
        }
    }

    // La Règle NPF (SAH, 2020) prints the complete rule rounded: k(16.9N + 0.10f + 13.7p)/(f cos δ).
    @Test func npfAgreesWithSAHRoundedCoefficients() throws {
        for n in GearGrid.fNumbers {
            for f in GearGrid.focalLengths {
                for p in GearGrid.pitches {
                    let ours = try StarExposure.npf(fNumber: n, focalLengthMM: f, pixelPitchUM: p)
                    let printed = (16.9 * n + 0.10 * f + 13.7 * p) / f
                    #expect(approxRel(ours, printed, 0.005))
                }
            }
        }
    }

    // Les coulisses (SAH): the simplified rule is the complete one with k = 2, δ = 0 and
    // seeing dropped, rounded up (2·16.856 -> 35, 2·13.713 -> 30).
    @Test func simplifiedRuleIsTheRoundedK2Case() throws {
        for n in GearGrid.fNumbers {
            for f in GearGrid.focalLengths {
                for p in GearGrid.pitches {
                    let simple = try StarExposure.npfSimple(fNumber: n, focalLengthMM: f, pixelPitchUM: p)
                    let noSeeingK2 = 2 * (16.856 * n + 13.713 * p) / f
                    #expect(simple >= noSeeingK2 && simple <= 1.1 * noSeeingK2)
                }
            }
        }
    }

    // MARK: NPF, properties

    @Test func npfDeclinationScalesAsSecant() throws {
        let t0 = try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4.35)
        let t60 = try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4.35, declinationDeg: 60)
        let tSouth = try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4.35, declinationDeg: -60)
        #expect(approxRel(t60, 2 * t0, 1e-12))
        #expect(t60 == tSouth)
        #expect(try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4.35, declinationDeg: 90) == .infinity)
        #expect(try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4.35, declinationDeg: -90) == .infinity)
    }

    @Test func npfKIsLinear() throws {
        let t1 = try StarExposure.npf(fNumber: 1.8, focalLengthMM: 20, pixelPitchUM: 5.93, k: 1)
        let t2 = try StarExposure.npf(fNumber: 1.8, focalLengthMM: 20, pixelPitchUM: 5.93, k: 2)
        #expect(approxRel(t2, 2 * t1, 1e-12))
    }

    @Test func npfIsMonotonic() throws {
        for p in GearGrid.pitches {
            var previous = Double.infinity
            for f in GearGrid.focalLengths { // longer lens -> shorter exposure
                let t = try StarExposure.npf(fNumber: 2.8, focalLengthMM: f, pixelPitchUM: p)
                #expect(t < previous)
                previous = t
            }
            previous = 0
            for n in GearGrid.fNumbers { // stopping down enlarges the Airy disk -> longer
                let t = try StarExposure.npf(fNumber: n, focalLengthMM: 24, pixelPitchUM: p)
                #expect(t > previous)
                previous = t
            }
            previous = 0
            for dec in [0.0, 20, 40, 60, 80, 89] { // closer to the pole -> longer
                let t = try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: p, declinationDeg: dec)
                #expect(t > previous)
                previous = t
            }
        }
        var previous = 0.0
        for p in GearGrid.pitches { // bigger pixels -> longer
            let t = try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: p)
            #expect(t > previous)
            previous = t
        }
    }

    @Test func npfIsFarShorterThanThe500RuleOnModernSensors() throws {
        // The point of the NPF rule (SAH): the 500 rule trails on fine-pitch sensors.
        let npf = try StarExposure.npf(fNumber: 1.8, focalLengthMM: 14, pixelPitchUM: 3.76)
        let rough = try StarExposure.roughRule500(focalLengthMM: 14)
        #expect(npf < rough / 2)
    }

    @Test func npfRejectsBadInput() {
        #expect(throws: ExposureError.invalid(.focalLength, 0)) { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 0, pixelPitchUM: 4) }
        #expect(throws: ExposureError.invalid(.focalLength, -24)) { try StarExposure.npf(fNumber: 2.8, focalLengthMM: -24, pixelPitchUM: 4) }
        #expect(throws: ExposureError.invalid(.fNumber, 0.5)) { try StarExposure.npf(fNumber: 0.5, focalLengthMM: 24, pixelPitchUM: 4) }
        #expect(throws: ExposureError.invalid(.pixelPitch, 0)) { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 0) }
        #expect(throws: ExposureError.invalid(.declination, 91)) {
            try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4, declinationDeg: 91)
        }
        #expect(throws: ExposureError.invalid(.npfK, 0.5)) { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4, k: 0.5) }
        #expect(throws: ExposureError.invalid(.npfK, 4)) { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4, k: 4) }
        #expect(throws: ExposureError.invalid(.fNumber, 0.69)) { try StarExposure.npfSimple(fNumber: 0.69, focalLengthMM: 24, pixelPitchUM: 4) }
        #expect(throws: ExposureError.self) { try StarExposure.npf(fNumber: .nan, focalLengthMM: 24, pixelPitchUM: 4) }
        #expect(throws: ExposureError.self) { try StarExposure.npfSimple(fNumber: 2.8, focalLengthMM: .infinity, pixelPitchUM: 4) }
    }

    @Test("no finite input ever yields NaN", arguments: [-1.0, 0, 1e-300, 0.7, 2.8, 1e300, .nan, .infinity, -.infinity])
    func neverNaN(value: Double) {
        let calls: [() throws -> Double] = [
            { try StarExposure.npf(fNumber: value, focalLengthMM: 24, pixelPitchUM: 4) },
            { try StarExposure.npf(fNumber: 2.8, focalLengthMM: value, pixelPitchUM: 4) },
            { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: value) },
            { try StarExposure.npf(fNumber: 2.8, focalLengthMM: 24, pixelPitchUM: 4, declinationDeg: value) },
            { try StarExposure.npfSimple(fNumber: value, focalLengthMM: value, pixelPitchUM: value) },
            { try StarExposure.roughRule500(focalLengthMM: value, cropFactor: value) },
            { try StarExposure.starTrailLengthPixels(exposure: value, focalLengthMM: value, pixelPitchUM: value) },
        ]
        for call in calls {
            if let result = try? call() { #expect(!result.isNaN) }
        }
    }

    // MARK: 500 rule (rough)

    // Fstoppers: 16 mm on full frame, "Rule of 500 ... 31,2 seconds" (500/16 = 31.25, truncated).
    @Test func rule500_FstoppersFullFrame16mm() throws {
        let t = try StarExposure.roughRule500(focalLengthMM: 16)
        #expect(t == 31.25 && t >= 31.2 && t < 31.3)
    }

    // PhotoPills, Milky Way guide: a 14 mm lens on a 1.5× crop body is 21 mm equivalent.
    @Test func rule500_PhotoPillsCropExample() throws {
        #expect(approx(try StarExposure.roughRule500(focalLengthMM: 14, cropFactor: 1.5), 500.0 / 21, 1e-12))
        let apsc = try CameraProfile(name: "APS-C", sensorWidthMM: 23.7, sensorHeightMM: 15.6, pixelPitchUM: 3.9)
        let lens = try LensProfile(name: "14/2.8", focalLengthMM: 14, maxFNumber: 2.8)
        #expect(approxRel(try StarExposure.roughRule500(camera: apsc, lens: lens), 500 / (14 * apsc.cropFactor), 1e-12))
    }

    @Test func rule500RejectsBadInput() {
        #expect(throws: ExposureError.invalid(.focalLength, 0)) { try StarExposure.roughRule500(focalLengthMM: 0) }
        #expect(throws: ExposureError.invalid(.cropFactor, 0)) { try StarExposure.roughRule500(focalLengthMM: 14, cropFactor: 0) }
    }

    // MARK: Star trails

    @Test func trailUnits() throws {
        // One hour at δ = 0: 15.041″/s × 3600 s = 15.041°, and 50 mm × 15.041° in radians = 13.126 mm.
        let mm = try StarExposure.starTrailLengthMM(exposure: 3600, focalLengthMM: 50)
        #expect(approx(mm, 50 * 15.041 * .pi / 180, 1e-9))
        let px = try StarExposure.starTrailLengthPixels(exposure: 3600, focalLengthMM: 50, pixelPitchUM: 5)
        #expect(approx(px, mm * 1000 / 5, 1e-6))
    }

    // Les coulisses (SAH), "temps d'exposition le plus strict": t = 13713·p/(f·cos δ)
    // is the time for a star to cross exactly one pixel.
    @Test func strictestNPFTimeMovesOnePixel() throws {
        for f in GearGrid.focalLengths {
            for p in GearGrid.pitches {
                for dec in [0.0, 45, -70] {
                    let t = 13.713 * p / (f * cos(dec * .pi / 180))
                    let px = try StarExposure.starTrailLengthPixels(exposure: t, focalLengthMM: f, pixelPitchUM: p, declinationDeg: dec)
                    #expect(approx(px, 1, 0.001))
                }
            }
        }
    }

    // Les coulisses (SAH), 500-rule origin: a star stays in a 0.029 mm CoC for
    // 13713 × 0.029 / f ≈ 398/f s at δ = 0°, and 562/f s at δ = 45°.
    @Test func trailMatchesSAHDerivationOfThe500Rule() throws {
        for f in GearGrid.focalLengths {
            #expect(approx(try StarExposure.starTrailLengthMM(exposure: 398 / f, focalLengthMM: f), 0.029, 0.0001))
            #expect(approx(try StarExposure.starTrailLengthMM(exposure: 562 / f, focalLengthMM: f, declinationDeg: 45), 0.029, 0.0001))
        }
    }

    @Test func trailProperties() throws {
        let base = try StarExposure.starTrailLengthPixels(exposure: 20, focalLengthMM: 24, pixelPitchUM: 4)
        #expect(approxRel(try StarExposure.starTrailLengthPixels(exposure: 40, focalLengthMM: 24, pixelPitchUM: 4), 2 * base, 1e-12))
        #expect(approxRel(try StarExposure.starTrailLengthPixels(exposure: 20, focalLengthMM: 48, pixelPitchUM: 4), 2 * base, 1e-12))
        #expect(approxRel(try StarExposure.starTrailLengthPixels(exposure: 20, focalLengthMM: 24, pixelPitchUM: 8), base / 2, 1e-12))
        #expect(approxRel(try StarExposure.starTrailLengthPixels(exposure: 20, focalLengthMM: 24, pixelPitchUM: 4, declinationDeg: 60), base / 2, 1e-12))
        #expect(try StarExposure.starTrailLengthPixels(exposure: 20, focalLengthMM: 24, pixelPitchUM: 4, declinationDeg: 90) == 0)
        #expect(try StarExposure.starTrailLengthPixels(exposure: 0, focalLengthMM: 24, pixelPitchUM: 4) == 0)
    }

    // Les coulisses (SAH): at the k = 1 time a star moves exactly one radius of its
    // image, (4.47·λ·N + f·α + 2p) / 2; k = 2 is one diameter.
    @Test func npfTimeMovesTheStarOneRadius() throws {
        let camera = try fullFrame(widthPx: 9504, heightPx: 6336)
        let lens = try LensProfile(name: "20/1.8", focalLengthMM: 20, maxFNumber: 1.8)
        let p = camera.pixelPitchUM
        let radiusUM = (4.47 * 0.550 * 1.8 + 20_000 * 3 * .pi / (180 * 3600) + 2 * p) / 2
        let t1 = try StarExposure.npf(camera: camera, lens: lens, k: 1)
        let t2 = try StarExposure.npf(camera: camera, lens: lens, k: 2)
        let px1 = try StarExposure.starTrailLengthPixels(exposure: t1, camera: camera, lens: lens)
        let px2 = try StarExposure.starTrailLengthPixels(exposure: t2, camera: camera, lens: lens)
        #expect(approxRel(px1 * p, radiusUM, 0.001))
        #expect(approxRel(px2, 2 * px1, 1e-9))
    }

    @Test func trailRejectsBadInput() {
        #expect(throws: ExposureError.invalid(.exposure, -1)) { try StarExposure.starTrailLengthMM(exposure: -1, focalLengthMM: 24) }
        #expect(throws: ExposureError.invalid(.focalLength, 0)) { try StarExposure.starTrailLengthMM(exposure: 10, focalLengthMM: 0) }
        #expect(throws: ExposureError.invalid(.pixelPitch, -4)) {
            try StarExposure.starTrailLengthPixels(exposure: 10, focalLengthMM: 24, pixelPitchUM: -4)
        }
        #expect(throws: ExposureError.invalid(.declination, -90.5)) {
            try StarExposure.starTrailLengthMM(exposure: 10, focalLengthMM: 24, declinationDeg: -90.5)
        }
    }
}
