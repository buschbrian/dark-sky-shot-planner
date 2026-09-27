public import Foundation

/// Curated, cited camera and lens presets from `config/gear-presets.json`
/// (ADR-0012), bundled by `ios/scripts/sync-shared.sh`. Researched and
/// refreshed by hand, never fetched at runtime. A preset only seeds a
/// `CameraProfile` or `LensProfile`; the owner can still edit every value.
public struct GearPresets: Sendable, Hashable, Decodable {
    public enum Category: String, Sendable, Hashable, Codable, CaseIterable {
        case iphone, ipad, fullFrame = "full-frame", apsC = "aps-c", mft
    }

    /// Where a camera's sensor millimetres come from.
    public enum SensorSizeBasis: String, Sendable, Hashable, Codable {
        case manufacturer
        /// iPhone: stated or measured pitch × pixels (Apple publishes no sensor size).
        case statedPitchTimesPixels = "stated-pitch-x-pixels"
        /// Converted from an inch-type string such as 1/1.28"; approximate.
        case opticalFormatEstimate = "optical-format estimate"
    }

    public enum PixelPitchBasis: String, Sendable, Hashable, Codable {
        /// From a real frame's EXIF on the owner's phone (`docs/ios/CAPTURE-LIMITS.md`).
        case exifMeasured = "exif-measured"
        case stated
        /// Twice the stated 48 MP pitch: the 12 MP quad-Bayer binned output.
        case statedNativeTimesTwo = "stated-native-x2-binned"
        /// Sensor width ÷ image width, the formula `CameraProfile` uses itself.
        case sensorWidthOverPixels = "sensor-width/pixels"
    }

    public enum FocalLengthBasis: String, Sendable, Hashable, Codable {
        case manufacturer
        case exifMeasured = "exif-measured"
        /// 35 mm-equivalent ÷ the crop factor of the pitch-implied sensor.
        case derivedFromEquivalent = "derived-from-equivalent"
        /// Measured horizontal field of view and the pitch-implied sensor width.
        case derivedFromMeasuredFOV = "derived-from-measured-fov"
    }

    public struct Pixels: Sendable, Hashable, Codable {
        public let w: Int
        public let h: Int
    }

    public struct Camera: Sendable, Hashable, Decodable, Identifiable {
        public let id: String
        public let brand: String
        public let model: String
        /// iPhone camera module (main, ultra-wide, telephoto); nil for bodies.
        public let module: String?
        public let category: Category
        public let mount: String
        public let sensorWidthMM: Double
        public let sensorHeightMM: Double
        public let sensorSizeBasis: SensorSizeBasis
        public let resolution: Pixels
        public let pixelPitchUM: Double
        public let pixelPitchBasis: PixelPitchBasis
        /// Full-resolution readout of a 48 MP quad-Bayer iPhone sensor.
        public let nativeResolution: Pixels?
        public let nativePixelPitchUM: Double?
        /// Lens ids this camera is built with (iPhone modules); empty for interchangeable bodies.
        public let pairsWith: [String]
        public let sourceURL: String
        public let verifiedOn: String
        public let valueBasis: String
        public let notes: String

        enum CodingKeys: String, CodingKey {
            case id, brand, model, module, category, mount, notes
            case sensorWidthMM = "sensor_width_mm", sensorHeightMM = "sensor_height_mm"
            case sensorSizeBasis = "sensor_size_basis", resolution = "resolution_px"
            case pixelPitchUM = "pixel_pitch_um", pixelPitchBasis = "pixel_pitch_basis"
            case nativeResolution = "native_resolution_px", nativePixelPitchUM = "native_pixel_pitch_um"
            case pairsWith = "pairs_with", sourceURL = "source_url", verifiedOn = "verified_on"
            case valueBasis = "value_basis"
        }

        public var displayName: String {
            let base = "\(brand) \(model)"
            return module.map { "\(base) \($0)" } ?? base
        }

        /// Pitch implied by the sensor width and image width.
        public var derivedPixelPitchUM: Double { sensorWidthMM / Double(resolution.w) * 1000 }

        /// The editable profile this preset seeds. A stated or measured pitch is
        /// passed through (it wins over sensor ÷ pixels); a pitch that was only
        /// computed from the sensor is left for `CameraProfile` to derive.
        public func profile() throws(ExposureError) -> CameraProfile {
            try CameraProfile(
                name: displayName, sensorWidthMM: sensorWidthMM, sensorHeightMM: sensorHeightMM,
                resolution: PixelResolution(widthPx: resolution.w, heightPx: resolution.h),
                pixelPitchUM: pixelPitchBasis == .sensorWidthOverPixels ? nil : pixelPitchUM)
        }
    }

    public struct Lens: Sendable, Hashable, Decodable, Identifiable {
        public let id: String
        public let brand: String
        public let name: String
        /// The format the lens covers.
        public let category: Category
        public let mount: [String]
        /// Primes: the focal length. Zooms: the wide end (`focalRangeMM` has both).
        public let focalLengthMM: Double
        public let focalLengthBasis: FocalLengthBasis
        public let focalRangeMM: [Double]?
        public let equivalentFocalMM: Double?
        public let maxFNumber: Double
        /// Discrete stops, for the iPhone 18 Pro main camera's variable aperture.
        public let apertureStops: [Double]?
        public let fisheye: Bool?
        public let pairsWith: [String]
        public let sourceURL: String
        public let verifiedOn: String
        public let valueBasis: String
        public let notes: String

        enum CodingKeys: String, CodingKey {
            case id, brand, name, category, mount, fisheye, notes
            case focalLengthMM = "focal_length_mm", focalLengthBasis = "focal_length_basis"
            case focalRangeMM = "focal_range_mm", equivalentFocalMM = "equivalent_focal_mm"
            case maxFNumber = "max_f_number", apertureStops = "aperture_stops"
            case pairsWith = "pairs_with", sourceURL = "source_url", verifiedOn = "verified_on"
            case valueBasis = "value_basis"
        }

        public var displayName: String { name.hasPrefix(brand) || name.hasPrefix("iPhone") ? name : "\(brand) \(name)" }

        public func profile() throws(ExposureError) -> LensProfile {
            try LensProfile(name: displayName, focalLengthMM: focalLengthMM, maxFNumber: maxFNumber)
        }
    }

    /// A research row deliberately left out, with the reason.
    public struct Excluded: Sendable, Hashable, Decodable {
        public let id: String
        public let table: String
        public let reason: String
    }

    public struct Renamed: Sendable, Hashable, Decodable {
        public let from: String
        public let to: String
        public let reason: String
    }

    public let schemaVersion: Int
    public let verifiedOn: String
    public let cameras: [Camera]
    public let lenses: [Lens]
    public let excluded: [Excluded]
    public let renamed: [Renamed]

    enum CodingKeys: String, CodingKey {
        case cameras, lenses, excluded, renamed
        case schemaVersion = "schema_version", verifiedOn = "verified_on"
    }

    public static let fileName = "gear-presets.json"

    public static func decode(_ data: Data) throws -> GearPresets {
        try JSONDecoder().decode(GearPresets.self, from: data)
    }

    /// The bundled copy of `config/gear-presets.json`.
    public static func bundled() throws -> GearPresets {
        try decode(SharedResources.data(fileName))
    }

    public func camera(id: String) -> Camera? { cameras.first { $0.id == id } }
    public func lens(id: String) -> Lens? { lenses.first { $0.id == id } }

    public func cameras(in category: Category) -> [Camera] { cameras.filter { $0.category == category } }
    public func lenses(in category: Category) -> [Lens] { lenses.filter { $0.category == category } }

    /// A phone module's own lenses; for a body, every lens made for its mount.
    public func lenses(for camera: Camera) -> [Lens] {
        if !camera.pairsWith.isEmpty { return camera.pairsWith.compactMap { lens(id: $0) } }
        return lenses.filter { $0.mount.contains(camera.mount) }
    }

    /// The cameras a lens is built into or mounts on.
    public func cameras(for lens: Lens) -> [Camera] {
        if !lens.pairsWith.isEmpty { return lens.pairsWith.compactMap { camera(id: $0) } }
        return cameras.filter { $0.pairsWith.isEmpty && lens.mount.contains($0.mount) }
    }
}
