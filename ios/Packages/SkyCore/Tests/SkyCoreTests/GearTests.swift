import Foundation
import Testing
@testable import SkyCore

@Suite("Gear profiles")
struct GearTests {
    // Fstoppers, "Using the NPF Rule for Photographing Night Skies": Canon 5D Mark IV,
    // 36 mm / 6720 px × 1000 = 5.36 µm.
    @Test func pitchDerivedFromSensorWidth_Fstoppers5DMarkIV() throws {
        let camera = try CameraProfile(name: "5D Mark IV", sensorWidthMM: 36, sensorHeightMM: 24,
                                       resolution: PixelResolution(widthPx: 6720, heightPx: 4480))
        #expect(approx(camera.pixelPitchUM, 5.36, 0.005))
    }

    // Lightstalking, "What Is The NPF Rule": Nikon D750, 35.9 mm / 6016 px = 5.967 µm.
    @Test func pitchDerivedFromSensorWidth_LightstalkingD750() throws {
        let camera = try CameraProfile(name: "D750", sensorWidthMM: 35.9, sensorHeightMM: 24.0,
                                       resolution: PixelResolution(widthPx: 6016, heightPx: 4016))
        #expect(approx(camera.pixelPitchUM, 5.967, 0.0005))
    }

    @Test func statedPitchWinsOverDerived() throws {
        let camera = try CameraProfile(name: "stated", sensorWidthMM: 35.6, sensorHeightMM: 23.8,
                                       resolution: PixelResolution(widthPx: 6000, heightPx: 4000), pixelPitchUM: 5.9)
        #expect(camera.pixelPitchUM == 5.9)
        let pitchOnly = try CameraProfile(name: "pitch only", sensorWidthMM: 35.6, sensorHeightMM: 23.8, pixelPitchUM: 5.9)
        #expect(pitchOnly.pixelPitchUM == 5.9)
    }

    // Wikipedia, "Crop factor", table of sensor formats (diagonal ratio to 43.3 mm).
    @Test("crop factor matches Wikipedia's format table", arguments: [
        (22.2, 14.8, 1.6, 0.05), // Canon APS-C
        (23.7, 15.6, 1.5, 0.05), // general APS-C
        (17.3, 13.0, 2.0, 0.05), // Four Thirds
        (43.8, 32.9, 0.79, 0.005), // Fujifilm GFX
        (36.0, 24.0, 1.0, 1e-12),
    ])
    func cropFactor(width: Double, height: Double, expected: Double, tolerance: Double) throws {
        let camera = try CameraProfile(name: "", sensorWidthMM: width, sensorHeightMM: height, pixelPitchUM: 4)
        #expect(approx(camera.cropFactor, expected, tolerance))
    }

    // Wikipedia, "Circle of confusion", table "CoC diameter based on d/1500".
    @Test("circle of confusion matches Wikipedia's d/1500 table", arguments: [
        (13.2, 8.8, 0.011), // 1" sensor
        (18.0, 13.5, 0.015), // Four Thirds
        (22.2, 14.8, 0.018), // APS-C Canon
        (23.6, 15.7, 0.019), // APS-C Nikon/Pentax/Sony
        (36.0, 24.0, 0.029), // 35 mm
    ])
    func circleOfConfusion(width: Double, height: Double, expected: Double) throws {
        let camera = try CameraProfile(name: "", sensorWidthMM: width, sensorHeightMM: height, pixelPitchUM: 4)
        #expect(approx(camera.circleOfConfusionMM, expected, 0.0005))
        #expect(try DepthOfField.circleOfConfusionMM(sensorDiagonalMM: camera.sensorDiagonalMM) == camera.circleOfConfusionMM)
    }

    @Test func cameraRejectsBadInput() throws {
        #expect(throws: ExposureError.missingPixelPitch) {
            try CameraProfile(name: "", sensorWidthMM: 36, sensorHeightMM: 24)
        }
        #expect(throws: ExposureError.invalid(.sensorWidth, 0)) {
            try CameraProfile(name: "", sensorWidthMM: 0, sensorHeightMM: 24, pixelPitchUM: 4)
        }
        #expect(throws: ExposureError.invalid(.sensorHeight, -24)) {
            try CameraProfile(name: "", sensorWidthMM: 36, sensorHeightMM: -24, pixelPitchUM: 4)
        }
        #expect(throws: ExposureError.invalid(.pixelPitch, 0)) {
            try CameraProfile(name: "", sensorWidthMM: 36, sensorHeightMM: 24, pixelPitchUM: 0)
        }
        #expect(throws: ExposureError.invalid(.imageWidth, 0)) { try PixelResolution(widthPx: 0, heightPx: 4000) }
        #expect(throws: ExposureError.invalid(.imageHeight, -1)) { try PixelResolution(widthPx: 6000, heightPx: -1) }
        #expect(throws: ExposureError.self) {
            try CameraProfile(name: "", sensorWidthMM: .nan, sensorHeightMM: 24, pixelPitchUM: 4)
        }
        #expect(throws: ExposureError.self) {
            try CameraProfile(name: "", sensorWidthMM: .infinity, sensorHeightMM: 24, pixelPitchUM: 4)
        }
    }

    @Test func lensRejectsBadInput() {
        #expect(throws: ExposureError.invalid(.focalLength, 0)) { try LensProfile(name: "", focalLengthMM: 0, maxFNumber: 2.8) }
        #expect(throws: ExposureError.invalid(.focalLength, -14)) { try LensProfile(name: "", focalLengthMM: -14, maxFNumber: 2.8) }
        #expect(throws: ExposureError.invalid(.fNumber, 0.69)) { try LensProfile(name: "", focalLengthMM: 50, maxFNumber: 0.69) }
        #expect(throws: Never.self) { try LensProfile(name: "Planar 50/0.7", focalLengthMM: 50, maxFNumber: 0.7) }
    }

    @Test func apertureWiderThanTheLensIsRejected() throws {
        let camera = try fullFrame()
        let lens = try LensProfile(name: "14/2.8", focalLengthMM: 14, maxFNumber: 2.8)
        #expect(throws: ExposureError.fNumberWiderThanLens(fNumber: 1.4, maxFNumber: 2.8)) {
            try StarExposure.npf(camera: camera, lens: lens, fNumber: 1.4)
        }
        let wideOpen = try StarExposure.npf(camera: camera, lens: lens)
        let stated = try StarExposure.npf(camera: camera, lens: lens, fNumber: 2.8)
        #expect(wideOpen == stated)
    }

    @Test func profilesRoundTripThroughJSON() throws {
        let camera = try fullFrame("A7 III", widthPx: 6000, heightPx: 4000)
        let lens = try LensProfile(name: "24 GM", focalLengthMM: 24, maxFNumber: 1.4)
        let decodedCamera = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(camera))
        let decodedLens = try JSONDecoder().decode(LensProfile.self, from: JSONEncoder().encode(lens))
        #expect(decodedCamera == camera)
        #expect(decodedLens == lens)
    }

    @Test func decodingValidatesLikeTheInitializer() {
        let badLens = Data(#"{"name":"x","focalLengthMM":-5,"maxFNumber":2}"#.utf8)
        #expect(throws: ExposureError.invalid(.focalLength, -5)) { try JSONDecoder().decode(LensProfile.self, from: badLens) }
        let noPitch = Data(#"{"name":"x","sensorWidthMM":36,"sensorHeightMM":24}"#.utf8)
        #expect(throws: ExposureError.missingPixelPitch) { try JSONDecoder().decode(CameraProfile.self, from: noPitch) }
    }
}
