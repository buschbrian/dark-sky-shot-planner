public import Foundation

public enum StackMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Per-pixel mean after rejecting values more than κσ from the median:
    /// averages noise down by about √N and drops satellites, aircraft and
    /// hot-pixel hits (Siril, "Stacking: sigma clipping").
    case sigmaClippedMean
    /// Per-pixel maximum: the star-trail stack. Nothing is aligned.
    case maximum
    /// Plain per-pixel mean.
    case mean
}

public struct SigmaClip: Sendable, Hashable, Codable {
    public var kappa: Float
    public var iterations: Int

    public static let standard = SigmaClip(kappa: 2.5, iterations: 3)

    public init(kappa: Float, iterations: Int) {
        self.kappa = kappa
        self.iterations = iterations
    }

    /// Clipped mean of `values[0..<count]`; sorts them in place. NaN entries
    /// (a frame that does not cover this pixel after alignment) must already
    /// be excluded by the caller. With fewer than three values there is
    /// nothing to reject against, so it is the plain mean.
    public func combine(_ values: UnsafeMutableBufferPointer<Float>, count: Int) -> Float {
        guard count > 0 else { return .nan }
        if count < 3 {
            var s: Float = 0
            for i in 0..<count { s += values[i] }
            return s / Float(count)
        }
        Self.insertionSort(values, count: count)
        var lo = 0, hi = count
        for _ in 0..<max(iterations, 1) {
            let n = hi - lo
            guard n >= 3 else { break }
            let median = n % 2 == 1 ? values[lo + n / 2] : (values[lo + n / 2 - 1] + values[lo + n / 2]) / 2
            var mean: Float = 0
            for i in lo..<hi { mean += values[i] }
            mean /= Float(n)
            var variance: Float = 0
            for i in lo..<hi { variance += (values[i] - mean) * (values[i] - mean) }
            let sigma = (variance / Float(n - 1)).squareRoot()
            let low = median - kappa * sigma, high = median + kappa * sigma
            var newLo = lo, newHi = hi
            while newLo < newHi, values[newLo] < low { newLo += 1 }
            while newHi > newLo, values[newHi - 1] > high { newHi -= 1 }
            if newLo == lo, newHi == hi { break }
            lo = newLo
            hi = newHi
        }
        var s: Float = 0
        for i in lo..<hi { s += values[i] }
        return hi > lo ? s / Float(hi - lo) : values[count / 2]
    }

    public func combine(_ values: [Float]) -> Float {
        var copy = values.filter { !$0.isNaN }
        let n = copy.count
        return copy.withUnsafeMutableBufferPointer { combine($0, count: n) }
    }

    static func insertionSort(_ v: UnsafeMutableBufferPointer<Float>, count: Int) {
        guard count > 1 else { return }
        for i in 1..<count {
            let x = v[i]
            var j = i - 1
            while j >= 0, v[j] > x {
                v[j + 1] = v[j]
                j -= 1
            }
            v[j + 1] = x
        }
    }
}

/// Aligns and combines frames into one 16-bit image. Frames are sampled
/// through their registration (frame → reference) with bilinear
/// interpolation, band by band, so a sigma-clipped stack of N frames holds
/// only N bands in memory while the frames themselves stay memory-mapped.
/// Maximum and mean stream one frame at a time instead (`StackAccumulator`).
public struct FrameStacker: Sendable {
    public var clip: SigmaClip
    /// Memory for one band of samples across all frames, in bytes.
    public var bandBudgetBytes: Int

    public init(clip: SigmaClip = .standard, bandBudgetBytes: Int = 192 << 20) {
        self.clip = clip
        self.bandBudgetBytes = bandBudgetBytes
    }

    public struct Result: Sendable {
        public let raster: RasterU16
        /// Output pixels (per channel sample) covered by no frame, set to 0.
        public let uncovered: Int
    }

    /// Sigma-clipped mean of `frames`; `transforms[i]` maps frame i onto the reference.
    /// Checks for task cancellation every output row (well under a second of
    /// work on a phone) and throws `CancellationError` when cancelled.
    public func sigmaClipped(_ frames: [RasterU16], transforms: [RigidTransform]) throws(CancellationError) -> Result {
        precondition(!frames.isEmpty && frames.count == transforms.count, "one transform per frame")
        let w = frames[0].width, h = frames[0].height, ch = frames[0].channels
        precondition(frames.allSatisfy { $0.width == w && $0.height == h && $0.channels == ch }, "frame sizes")
        let n = frames.count
        let rowBytes = n * w * ch * MemoryLayout<Float>.size
        let bandRows = max(1, min(h, bandBudgetBytes / max(rowBytes, 1)))
        let inverses = transforms.map(\.inverse)
        var output = [UInt16](repeating: 0, count: w * h * ch)
        var uncovered = 0
        var samples = [Float](repeating: .nan, count: n * bandRows * w * ch)
        var gather = [Float](repeating: 0, count: n)
        var y0 = 0
        while y0 < h {
            let rows = min(bandRows, h - y0)
            let bandCount = rows * w * ch
            for f in 0..<n {
                for row in 0..<rows {
                    if Task.isCancelled { throw CancellationError() }
                    let rowCount = w * ch
                    samples.withUnsafeMutableBufferPointer { s in
                        let start = f * bandCount + row * rowCount
                        let dst = UnsafeMutableBufferPointer(rebasing: s[start..<(start + rowCount)])
                        Self.warp(frames[f], inverses[f], firstRow: y0 + row, rows: 1, into: dst)
                    }
                }
            }
            if Task.isCancelled { throw CancellationError() }
            let cancelled = samples.withUnsafeBufferPointer { s in
                gather.withUnsafeMutableBufferPointer { g in
                    for k in 0..<bandCount {
                        if k % (w * ch) == 0, Task.isCancelled { return true }
                        var m = 0
                        for f in 0..<n {
                            let v = s[f * bandCount + k]
                            if !v.isNaN { g[m] = v; m += 1 }
                        }
                        if m == 0 { uncovered += 1; continue }
                        output[y0 * w * ch + k] = Self.quantize(clip.combine(g, count: m))
                    }
                    return false
                }
            }
            if cancelled { throw CancellationError() }
            y0 += rows
        }
        return Result(raster: RasterU16(width: w, height: h, channels: ch, values: output), uncovered: uncovered)
    }

    /// Samples `rows` output rows starting at `firstRow` from `frame`, where
    /// `inverse` maps output (reference) coordinates into the frame. NaN where
    /// the frame does not cover the output pixel.
    static func warp(_ frame: RasterU16, _ inverse: RigidTransform, firstRow: Int, rows: Int,
                     into dst: UnsafeMutableBufferPointer<Float>) {
        let w = frame.width, h = frame.height, ch = frame.channels
        let c = cos(inverse.rotation), s = sin(inverse.rotation)
        let exact = inverse.rotation == 0 && inverse.tx == inverse.tx.rounded() && inverse.ty == inverse.ty.rounded()
        frame.data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for r in 0..<rows {
                let y = Double(firstRow + r)
                // Frame coordinates of output pixel (0, y), and the step per x.
                var fx = -s * y + inverse.tx, fy = c * y + inverse.ty
                let base = r * w * ch
                for x in 0..<w {
                    defer { fx += c; fy += s }
                    let o = base + x * ch
                    if exact {
                        let ix = Int(fx.rounded()), iy = Int(fy.rounded())
                        guard ix >= 0, iy >= 0, ix < w, iy < h else {
                            for k in 0..<ch { dst[o + k] = .nan }
                            continue
                        }
                        let src = (iy * w + ix) * ch
                        for k in 0..<ch { dst[o + k] = Float(p[src + k]) }
                        continue
                    }
                    guard fx >= 0, fy >= 0, fx <= Double(w - 1), fy <= Double(h - 1) else {
                        for k in 0..<ch { dst[o + k] = .nan }
                        continue
                    }
                    let x0 = min(Int(fx), max(w - 2, 0)), y0 = min(Int(fy), max(h - 2, 0))
                    let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
                    let ax = Float(fx - Double(x0)), ay = Float(fy - Double(y0))
                    let i00 = (y0 * w + x0) * ch, i10 = (y0 * w + x1) * ch
                    let i01 = (y1 * w + x0) * ch, i11 = (y1 * w + x1) * ch
                    for k in 0..<ch {
                        let top = Float(p[i00 + k]) * (1 - ax) + Float(p[i10 + k]) * ax
                        let bottom = Float(p[i01 + k]) * (1 - ax) + Float(p[i11 + k]) * ax
                        dst[o + k] = top * (1 - ay) + bottom * ay
                    }
                }
            }
        }
    }

    static func quantize(_ v: Float) -> UInt16 {
        guard v.isFinite else { return 0 }
        return UInt16(max(0, min(Float(UInt16.max), v.rounded())))
    }
}

/// Streaming maximum or mean: one frame at a time, so a star-trail session
/// of hundreds of frames needs no decoded frames kept on disk.
public struct StackAccumulator: Sendable {
    public let mode: StackMode
    public let width: Int
    public let height: Int
    public let channels: Int
    public private(set) var frames = 0
    private var value: [Float]
    private var count: [UInt16]

    public init(mode: StackMode, width: Int, height: Int, channels: Int) {
        precondition(mode != .sigmaClippedMean, "sigma clipping needs all frames: use FrameStacker")
        self.mode = mode
        self.width = width
        self.height = height
        self.channels = channels
        value = [Float](repeating: mode == .maximum ? -.infinity : 0, count: width * height * channels)
        count = [UInt16](repeating: 0, count: width * height * channels)
    }

    /// Adds a frame; `transform` maps it onto the reference (identity for
    /// trails). Throws `CancellationError`, leaving the stack without this
    /// frame's later rows, if the task is cancelled.
    public mutating func add(_ frame: RasterU16, transform: RigidTransform = .identity) throws(CancellationError) {
        precondition(frame.width == width && frame.height == height && frame.channels == channels, "frame size")
        var row = [Float](repeating: .nan, count: width * channels)
        let inverse = transform.inverse
        let isMax = mode == .maximum
        for y in 0..<height {
            if Task.isCancelled { throw CancellationError() }
            row.withUnsafeMutableBufferPointer { FrameStacker.warp(frame, inverse, firstRow: y, rows: 1, into: $0) }
            let base = y * width * channels
            for k in 0..<(width * channels) {
                let v = row[k]
                guard !v.isNaN else { continue }
                if isMax { value[base + k] = max(value[base + k], v) } else { value[base + k] += v }
                count[base + k] &+= 1
            }
        }
        frames += 1
    }

    public var result: RasterU16 {
        var out = [UInt16](repeating: 0, count: value.count)
        for i in value.indices where count[i] > 0 {
            out[i] = FrameStacker.quantize(mode == .maximum ? value[i] : value[i] / Float(count[i]))
        }
        return RasterU16(width: width, height: height, channels: channels, values: out)
    }
}
