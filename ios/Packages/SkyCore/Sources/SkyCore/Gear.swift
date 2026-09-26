import Foundation

/// A camera body as the owner enters it (never scraped). Pixel pitch is taken
/// as stated when given, otherwise derived from sensor width and image width.
/// Plain value type: the app persists it; SkyCore only validates and computes.
public struct CameraProfile: Sendable, Hashable, Codable {
    public let name: String
    public let sensorWidthMM: Double
    public let sensorHeightMM: Double
    public let resolution: PixelResolution?
    /// The manufacturer's pixel pitch, when the owner has it.
    public let statedPixelPitchUM: Double?

    public init(
        name: String,
        sensorWidthMM: Double,
        sensorHeightMM: Double,
        resolution: PixelResolution? = nil,
        pixelPitchUM: Double? = nil
    ) throws(ExposureError) {
        self.name = name
        self.sensorWidthMM = try requirePositive(.sensorWidth, sensorWidthMM)
        self.sensorHeightMM = try requirePositive(.sensorHeight, sensorHeightMM)
        self.statedPixelPitchUM = try pixelPitchUM.map { v throws(ExposureError) in try requirePositive(.pixelPitch, v) }
        guard resolution != nil || pixelPitchUM != nil else { throw .missingPixelPitch }
        self.resolution = resolution
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: c.decode(String.self, forKey: .name),
            sensorWidthMM: c.decode(Double.self, forKey: .sensorWidthMM),
            sensorHeightMM: c.decode(Double.self, forKey: .sensorHeightMM),
            resolution: c.decodeIfPresent(PixelResolution.self, forKey: .resolution),
            pixelPitchUM: c.decodeIfPresent(Double.self, forKey: .statedPixelPitchUM))
    }

    /// Photosite width in µm: sensor width ÷ image width × 1000 (NPF rule, SAH 2020).
    public var pixelPitchUM: Double {
        if let statedPixelPitchUM { return statedPixelPitchUM }
        // Non-nil by construction: init requires resolution or a stated pitch.
        return sensorWidthMM / Double(resolution!.widthPx) * 1000
    }

    public var sensorDiagonalMM: Double { (sensorWidthMM * sensorWidthMM + sensorHeightMM * sensorHeightMM).squareRoot() }

    /// Diagonal of 36 × 24 mm ÷ this sensor's diagonal (Wikipedia, "Crop factor").
    public var cropFactor: Double { CameraProfile.fullFrameDiagonalMM / sensorDiagonalMM }

    /// Circle of confusion from the diagonal by the d/1500 convention (Wikipedia, "Circle of confusion").
    public var circleOfConfusionMM: Double { sensorDiagonalMM / DepthOfField.defaultCoCDivisor }

    public static let fullFrameDiagonalMM = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()
}

public struct PixelResolution: Sendable, Hashable, Codable {
    public let widthPx: Int
    public let heightPx: Int

    public init(widthPx: Int, heightPx: Int) throws(ExposureError) {
        guard widthPx > 0 else { throw .invalid(.imageWidth, Double(widthPx)) }
        guard heightPx > 0 else { throw .invalid(.imageHeight, Double(heightPx)) }
        self.widthPx = widthPx
        self.heightPx = heightPx
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(widthPx: c.decode(Int.self, forKey: .widthPx), heightPx: c.decode(Int.self, forKey: .heightPx))
    }
}

/// A prime lens, or a zoom saved at the focal length the owner shoots it at.
public struct LensProfile: Sendable, Hashable, Codable {
    public let name: String
    public let focalLengthMM: Double
    /// The widest aperture, e.g. 1.4 for an f/1.4 lens.
    public let maxFNumber: Double

    /// The fastest photographic lens made (Zeiss Planar 50 mm f/0.7); anything wider is a typo.
    public static let minimumFNumber = 0.7

    public init(name: String, focalLengthMM: Double, maxFNumber: Double) throws(ExposureError) {
        self.name = name
        self.focalLengthMM = try requirePositive(.focalLength, focalLengthMM)
        self.maxFNumber = try requireFNumber(maxFNumber)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: c.decode(String.self, forKey: .name),
            focalLengthMM: c.decode(Double.self, forKey: .focalLengthMM),
            maxFNumber: c.decode(Double.self, forKey: .maxFNumber))
    }

    /// The f-number to compute with: `fNumber`, or wide open when nil; rejected if wider than the lens opens.
    func aperture(_ fNumber: Double?) throws(ExposureError) -> Double {
        guard let fNumber else { return maxFNumber }
        let n = try requireFNumber(fNumber)
        guard n >= maxFNumber else { throw .fNumberWiderThanLens(fNumber: n, maxFNumber: maxFNumber) }
        return n
    }
}
