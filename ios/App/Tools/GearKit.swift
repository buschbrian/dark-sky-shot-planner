import Foundation
import SkyCore

/// A saved `Gear` decoded into SkyCore profiles. Decoding re-runs SkyCore's
/// validation, so a kit that decodes is one the calculators accept.
struct GearKit: Hashable {
    let name: String
    let camera: CameraProfile
    let lens: LensProfile

    init(_ gear: Gear) throws {
        name = gear.name
        camera = try JSONDecoder().decode(CameraProfile.self, from: gear.cameraJSON)
        lens = try JSONDecoder().decode(LensProfile.self, from: gear.lensJSON)
    }

    init(name: String, camera: CameraProfile, lens: LensProfile) {
        self.name = name
        self.camera = camera
        self.lens = lens
    }

    func store(in gear: Gear) throws {
        gear.name = name
        gear.cameraJSON = try JSONEncoder().encode(camera)
        gear.lensJSON = try JSONEncoder().encode(lens)
    }

    func makeGear() throws -> Gear {
        Gear(name: name, cameraJSON: try JSONEncoder().encode(camera), lensJSON: try JSONEncoder().encode(lens))
    }

    var lensSummary: String {
        "\(ToolsFormat.number(lens.focalLengthMM, digits: 1)) mm f/\(ToolsFormat.number(lens.maxFNumber, digits: 1))"
    }

    var cameraSummary: String {
        let sensor = "\(ToolsFormat.number(camera.sensorWidthMM, digits: 1)) × \(ToolsFormat.number(camera.sensorHeightMM, digits: 1)) mm"
        return "\(sensor), \(ToolsFormat.number(camera.pixelPitchUM)) µm pixels"
    }

    var derivedSummary: String {
        "Crop \(ToolsFormat.number(camera.cropFactor))× · circle of confusion \(ToolsFormat.number(camera.circleOfConfusionMM, digits: 3)) mm (diagonal ÷ \(ToolsFormat.number(DepthOfField.defaultCoCDivisor)))"
    }
}
