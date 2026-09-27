public import Foundation

/// One channel of an image as linear floats, row-major, pixel centres at
/// integer coordinates. Star detection and focus measures run on this.
public struct ImagePlane: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height, "plane size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: Float = 0) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    public subscript(x: Int, y: Int) -> Float {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Bilinear sample; nil outside the pixel-centre grid.
    public func bilinear(x: Double, y: Double) -> Float? {
        guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { return nil }
        let x0 = min(Int(x), max(width - 2, 0)), y0 = min(Int(y), max(height - 2, 0))
        let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let top = self[x0, y0] * (1 - fx) + self[x1, y0] * fx
        let bottom = self[x0, y1] * (1 - fx) + self[x1, y1] * fx
        return top * (1 - fy) + bottom * fy
    }

    /// Mean of the colour channels (the first three, or the only one) over
    /// `bin`×`bin` blocks, scaled to 0...1. Binning by 2 quarters the work of
    /// star detection on a 12 MP frame and halves the noise.
    public static func luminance(_ raster: RasterU16, bin: Int = 1) -> ImagePlane {
        precondition(bin >= 1, "bin")
        let w = raster.width / bin, h = raster.height / bin
        let colours = min(raster.channels, 3)
        let scale = 1 / (Float(UInt16.max) * Float(colours * bin * bin))
        var out = [Float](repeating: 0, count: w * h)
        raster.data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            let stride = raster.channels
            for y in 0..<h {
                for x in 0..<w {
                    var sum: UInt32 = 0
                    for dy in 0..<bin {
                        let row = (y * bin + dy) * raster.width
                        for dx in 0..<bin {
                            let base = (row + x * bin + dx) * stride
                            for c in 0..<colours { sum &+= UInt32(p[base + c]) }
                        }
                    }
                    out[y * w + x] = Float(sum) * scale
                }
            }
        }
        return ImagePlane(width: w, height: h, pixels: out)
    }
}

/// An interleaved 16-bit image (RGB or single channel), little-endian, as
/// decoded from a frame. `data` may be memory-mapped from a file, so a stack
/// of many frames need not all sit in RAM.
public struct RasterU16: Sendable {
    public let width: Int
    public let height: Int
    public let channels: Int
    public let data: Data

    public init(width: Int, height: Int, channels: Int, data: Data) {
        precondition(width > 0 && height > 0 && channels > 0, "raster size")
        precondition(data.count >= width * height * channels * 2, "raster data too short")
        self.width = width
        self.height = height
        self.channels = channels
        self.data = data
    }

    public init(width: Int, height: Int, channels: Int, values: [UInt16]) {
        self.init(width: width, height: height, channels: channels,
                  data: values.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    public var values: [UInt16] {
        data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self).prefix(width * height * channels)) }
    }
}
