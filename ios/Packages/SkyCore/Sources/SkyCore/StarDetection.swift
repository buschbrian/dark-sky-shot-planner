public import Foundation

public struct DetectedStar: Sendable, Hashable, Codable {
    /// Intensity-weighted centroid, in pixels (pixel centres at integers).
    public let x: Double
    public let y: Double
    /// Background-subtracted flux summed over the measuring window.
    public let flux: Double
    public let peak: Float
    /// Pixels above the detection threshold.
    public let area: Int
    /// Half-flux radius, the flux-weighted mean distance from the centroid
    /// (the focus measure N.I.N.A. and SGP report): smaller is sharper.
    public let hfr: Double

    public init(x: Double, y: Double, flux: Double, peak: Float, area: Int, hfr: Double) {
        self.x = x
        self.y = y
        self.flux = flux
        self.peak = peak
        self.area = area
        self.hfr = hfr
    }
}

/// Background and noise per tile: median and 1.4826 × MAD, which ignore the
/// stars themselves (a robust estimate; Siril and SExtractor use the same idea).
public struct BackgroundMap: Sendable {
    public let tileSize: Int
    public let columns: Int
    public let rows: Int
    public let level: [Float]
    public let noise: [Float]

    public init(_ plane: ImagePlane, tileSize: Int = 64) {
        let size = max(8, tileSize)
        let cols = (plane.width + size - 1) / size, rows = (plane.height + size - 1) / size
        var level = [Float](repeating: 0, count: cols * rows)
        var noise = [Float](repeating: 0, count: cols * rows)
        var sample: [Float] = []
        sample.reserveCapacity(size * size)
        for ty in 0..<rows {
            for tx in 0..<cols {
                sample.removeAll(keepingCapacity: true)
                let x0 = tx * size, y0 = ty * size
                for y in y0..<min(y0 + size, plane.height) {
                    let row = y * plane.width
                    for x in x0..<min(x0 + size, plane.width) { sample.append(plane.pixels[row + x]) }
                }
                let median = Self.median(&sample)
                for i in sample.indices { sample[i] = abs(sample[i] - median) }
                let mad = Self.median(&sample)
                level[ty * cols + tx] = median
                noise[ty * cols + tx] = 1.4826 * mad
            }
        }
        self.tileSize = size
        self.columns = cols
        self.rows = rows
        self.level = level
        self.noise = noise
    }

    public func tile(x: Int, y: Int) -> Int {
        min(y / tileSize, rows - 1) * columns + min(x / tileSize, columns - 1)
    }

    static func median(_ values: inout [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        values.sort()
        let n = values.count
        return n % 2 == 1 ? values[n / 2] : (values[n / 2 - 1] + values[n / 2]) / 2
    }
}

/// Finds stars: pixels more than `sigma` noise levels above the local
/// background, grouped 8-connected, kept when the group is star-sized (a lone
/// hot pixel and a lit foreground both fail), measured by an iterated
/// weighted centroid. Deterministic; no learned model.
public struct StarDetector: Sendable {
    public var sigma: Float = 5
    public var minArea = 3
    public var maxArea = 600
    public var maxStars = 200
    /// Stars whose window touches the edge are dropped (their centroid is biased).
    public var edgeMargin = 3
    public var tileSize = 64

    public init() {}

    public func detect(_ plane: ImagePlane) -> [DetectedStar] {
        detect(plane, background: BackgroundMap(plane, tileSize: tileSize))
    }

    public func detect(_ plane: ImagePlane, background: BackgroundMap) -> [DetectedStar] {
        let w = plane.width, h = plane.height
        // A floor keeps a noiseless (synthetic) frame from thresholding at zero.
        let floorNoise: Float = 1e-5
        var threshold = [Float](repeating: 0, count: background.level.count)
        for i in threshold.indices {
            threshold[i] = background.level[i] + sigma * max(background.noise[i], floorNoise)
        }
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        var component: [Int] = []
        var stars: [DetectedStar] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if visited[i] { continue }
                visited[i] = true
                guard plane.pixels[i] > threshold[background.tile(x: x, y: y)] else { continue }
                component.removeAll(keepingCapacity: true)
                stack.append(i)
                while let j = stack.popLast() {
                    component.append(j)
                    if component.count > maxArea * 4 { continue }
                    let jx = j % w, jy = j / w
                    for ny in max(jy - 1, 0)...min(jy + 1, h - 1) {
                        for nx in max(jx - 1, 0)...min(jx + 1, w - 1) {
                            let k = ny * w + nx
                            if visited[k] { continue }
                            visited[k] = true
                            if plane.pixels[k] > threshold[background.tile(x: nx, y: ny)] { stack.append(k) }
                        }
                    }
                }
                stack.removeAll(keepingCapacity: true)
                guard (minArea...maxArea).contains(component.count),
                      let star = measure(plane, component: component, background: background)
                else { continue }
                stars.append(star)
            }
        }
        stars.sort { $0.flux > $1.flux }
        return Array(stars.prefix(maxStars))
    }

    private func measure(_ plane: ImagePlane, component: [Int], background: BackgroundMap) -> DetectedStar? {
        let w = plane.width, h = plane.height
        var peakIndex = component[0]
        for j in component where plane.pixels[j] > plane.pixels[peakIndex] { peakIndex = j }
        let bg = background.level[background.tile(x: peakIndex % w, y: peakIndex / w)]
        var cx = Double(peakIndex % w), cy = Double(peakIndex / w)
        // Window radius from the footprint: about twice the radius of the
        // above-threshold disc, so the faint wings count too.
        let radius = max(2.5, 2 * (Double(component.count) / .pi).squareRoot() + 1)
        let r = Int(radius.rounded(.up))
        guard Int(cx) - r >= edgeMargin, Int(cy) - r >= edgeMargin,
              Int(cx) + r < w - edgeMargin, Int(cy) + r < h - edgeMargin else { return nil }
        var flux = 0.0
        for _ in 0..<3 {
            var sw = 0.0, sx = 0.0, sy = 0.0
            let ix = Int(cx.rounded()), iy = Int(cy.rounded())
            for y in max(iy - r, 0)...min(iy + r, h - 1) {
                for x in max(ix - r, 0)...min(ix + r, w - 1) {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    // Negative noise counts too: clipping it at zero pulls
                    // every centroid toward the window's pixel grid.
                    let v = Double(plane.pixels[y * w + x] - bg)
                    sw += v
                    sx += v * Double(x)
                    sy += v * Double(y)
                }
            }
            guard sw > 0 else { return nil }
            cx = sx / sw
            cy = sy / sw
            flux = sw
        }
        var sr = 0.0
        let ix = Int(cx.rounded()), iy = Int(cy.rounded())
        var sw = 0.0
        for y in max(iy - r, 0)...min(iy + r, h - 1) {
            for x in max(ix - r, 0)...min(ix + r, w - 1) {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let d = (dx * dx + dy * dy).squareRoot()
                guard d <= radius else { continue }
                let v = Double(plane.pixels[y * w + x] - bg)
                guard v > 0 else { continue }
                sw += v
                sr += v * d
            }
        }
        return DetectedStar(x: cx, y: cy, flux: flux, peak: plane.pixels[peakIndex] - bg,
                            area: component.count, hfr: sw > 0 ? sr / sw : 0)
    }
}

/// Focus: the median half-flux radius of the brightest stars. Smaller is
/// sharper; the focus assist shows it live while the lens position moves.
public enum FocusMeasure {
    public static func medianHFR(_ stars: [DetectedStar], brightest: Int = 20) -> Double? {
        var hfrs = stars.prefix(brightest).map(\.hfr).filter { $0 > 0 }
        guard !hfrs.isEmpty else { return nil }
        hfrs.sort()
        let n = hfrs.count
        return n % 2 == 1 ? hfrs[n / 2] : (hfrs[n / 2 - 1] + hfrs[n / 2]) / 2
    }
}
