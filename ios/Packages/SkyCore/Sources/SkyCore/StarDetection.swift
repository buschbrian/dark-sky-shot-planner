public import Foundation

public struct DetectedStar: Sendable, Hashable, Codable {
    /// Intensity-weighted centroid, in pixels (pixel centres at integers).
    public let x: Double
    public let y: Double
    /// Background-subtracted flux summed over the measuring window.
    public let flux: Double
    public let peak: Float
    /// Pixels of the smoothed star above half its peak.
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
                // Every other pixel each way: a quarter of the sort, the same median.
                plane.pixels.withUnsafeBufferPointer { p in
                    for y in stride(from: y0, to: min(y0 + size, plane.height), by: 2) {
                        let row = y * plane.width
                        for x in stride(from: x0, to: min(x0 + size, plane.width), by: 2) { sample.append(p[row + x]) }
                    }
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

/// Finds stars. The frame is first smoothed with a Gaussian the size of a
/// star (a matched filter, as SExtractor does), which is the optimal linear
/// detector for a known PSF in white noise. Pixels of the smoothed frame more
/// than `sigma` of its own noise above its local background are grouped
/// 8-connected and kept when the group is star-sized (a lone hot pixel and a
/// lit foreground both fail). Each star is then measured on the unsmoothed
/// frame by an iterated weighted centroid. Deterministic; no learned model.
///
/// "SNR" here is a star's optimal (matched-filter) signal-to-noise ratio,
/// flux ÷ (pixel noise × √(4π) × PSF σ): what a perfect aperture achieves.
public struct StarDetector: Sendable {
    /// Threshold in noise levels of the smoothed frame. 3 with `minArea` 1
    /// finds ≥ 95 % of SNR-5 stars on synthetic fields, at the cost of faint
    /// false detections in pure noise (a few hundred per megapixel); those
    /// sort last by flux and registration only uses the brightest stars.
    public var sigma: Float = 3
    /// Gaussian σ of the matched filter in pixels; 0 turns the filter off.
    public var psfSigma = 1.3
    public var minArea = 1
    public var maxArea = 2_000
    public var maxStars = 200
    /// Stars whose window touches the edge are dropped (their centroid is biased).
    public var edgeMargin = 3
    public var tileSize = 64

    public init() {}

    public func detect(_ plane: ImagePlane) -> [DetectedStar] {
        let filtered = psfSigma > 0 ? Self.gaussianSmooth(plane, sigma: psfSigma) : plane
        return detect(plane, detection: filtered, background: BackgroundMap(filtered, tileSize: tileSize),
                      measureBackground: psfSigma > 0 ? BackgroundMap(plane, tileSize: tileSize) : nil)
    }

    /// Separable Gaussian, kernel radius 3σ, normalised to 1; edges clamp.
    public static func gaussianSmooth(_ plane: ImagePlane, sigma: Double) -> ImagePlane {
        let r = max(1, Int((3 * sigma).rounded(.up)))
        var kernel = (-r...r).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
        let sum = kernel.reduce(0, +)
        for i in kernel.indices { kernel[i] /= sum }
        let w = plane.width, h = plane.height
        var tmp = [Float](repeating: 0, count: w * h)
        var out = [Float](repeating: 0, count: w * h)
        kernel.withUnsafeBufferPointer { k in
            plane.pixels.withUnsafeBufferPointer { src in
                tmp.withUnsafeMutableBufferPointer { t in
                    for y in 0..<h {
                        let row = y * w
                        for x in 0..<w {
                            var acc: Float = 0
                            if x >= r, x < w - r {
                                let base = row + x - r
                                for i in 0...(2 * r) { acc += k[i] * src[base + i] }
                            } else {
                                for i in 0...(2 * r) { acc += k[i] * src[row + min(max(x + i - r, 0), w - 1)] }
                            }
                            t[row + x] = acc
                        }
                    }
                }
            }
            tmp.withUnsafeBufferPointer { t in
                out.withUnsafeMutableBufferPointer { o in
                    for y in 0..<h {
                        for i in 0...(2 * r) {
                            let sy = min(max(y + i - r, 0), h - 1) * w
                            let kv = k[i]
                            let dst = y * w
                            for x in 0..<w { o[dst + x] += kv * t[sy + x] }
                        }
                    }
                }
            }
        }
        return ImagePlane(width: w, height: h, pixels: out)
    }

    /// Thresholds `detection` (the smoothed frame) against `background`,
    /// measures on `plane` against `measureBackground` (or `background`).
    public func detect(_ plane: ImagePlane, detection: ImagePlane, background: BackgroundMap,
                       measureBackground: BackgroundMap? = nil) -> [DetectedStar] {
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
                guard detection.pixels[i] > threshold[background.tile(x: x, y: y)] else { continue }
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
                            if detection.pixels[k] > threshold[background.tile(x: nx, y: ny)] { stack.append(k) }
                        }
                    }
                }
                stack.removeAll(keepingCapacity: true)
                guard (minArea...maxArea).contains(component.count) else { continue }
                // Every local maximum of the smoothed frame is a star: two
                // stars whose wings touch share a component but not a peak.
                for j in component {
                    let jx = j % w, jy = j / w
                    guard jx > 0, jy > 0, jx < w - 1, jy < h - 1 else { continue }
                    let v = detection.pixels[j]
                    var isPeak = true
                    peak: for ny in (jy - 1)...(jy + 1) {
                        for nx in (jx - 1)...(jx + 1) where nx != jx || ny != jy {
                            let u = detection.pixels[ny * w + nx]
                            // Ties go to the earlier pixel so a flat top yields one peak.
                            if u > v || (u == v && ny * w + nx < j) { isPeak = false; break peak }
                        }
                    }
                    guard isPeak, let star = measure(plane, detection: detection, peakIndex: j,
                                                     background: measureBackground ?? background,
                                                     detectionBackground: background) else { continue }
                    stars.append(star)
                }
            }
        }
        stars.sort { $0.flux > $1.flux }
        // A noisy faint star can show two peaks a pixel apart: keep the brighter.
        var kept: [DetectedStar] = []
        var grid: [Int: [Int]] = [:]
        let cell = 4.0
        for star in stars {
            let gx = Int(star.x / cell), gy = Int(star.y / cell)
            var near = false
            search: for dy in -1...1 {
                for dx in -1...1 {
                    for k in grid[(gy + dy) * 100_000 + gx + dx] ?? [] where hypot(kept[k].x - star.x, kept[k].y - star.y) < 2 {
                        near = true
                        break search
                    }
                }
            }
            if near { continue }
            grid[gy * 100_000 + gx, default: []].append(kept.count)
            kept.append(star)
            if kept.count >= maxStars { break }
        }
        return kept
    }

    /// Bright stars: an iterated flux-weighted centroid on the unsmoothed
    /// frame (negative noise included, so there is no pull toward the pixel
    /// grid). Faint stars, whose window is mostly noise: the sub-pixel peak of
    /// the smoothed frame (a parabola through the peak and its neighbours).
    private func measure(_ plane: ImagePlane, detection: ImagePlane, peakIndex: Int,
                         background: BackgroundMap, detectionBackground: BackgroundMap) -> DetectedStar? {
        let w = plane.width, h = plane.height
        let px = peakIndex % w, py = peakIndex / w
        let tile = background.tile(x: px, y: py)
        let bg = background.level[tile], noise = Double(max(background.noise[tile], 1e-5))
        // Window radius 3σ of the star as the smoothed frame shows it,
        // σ from the area above half its peak (area = π·(1.1774σ)²).
        let dBg = detectionBackground.level[detectionBackground.tile(x: px, y: py)]
        let half = dBg + (detection.pixels[peakIndex] - dBg) / 2
        let reach = min(20, max(3, Int((4 * max(psfSigma, 1)).rounded(.up))))
        var halfArea = 0
        for y in max(py - reach, 0)...min(py + reach, h - 1) {
            for x in max(px - reach, 0)...min(px + reach, w - 1) where detection.pixels[y * w + x] >= half { halfArea += 1 }
        }
        let sigmaSeen = (Double(halfArea) / .pi).squareRoot() / 1.1774
        let radius = min(20, max(2.5, 3 * sigmaSeen))
        let r = Int(radius.rounded(.up))
        guard px - r >= edgeMargin, py - r >= edgeMargin, px + r < w - edgeMargin, py + r < h - edgeMargin else { return nil }

        // A hot pixel or cosmic-ray hit: one bright raw pixel whose four
        // neighbours sit near the background. Even an undersampled star
        // (PSF σ 0.5 px) puts 13 % of its peak in each neighbour.
        var hot = peakIndex
        for y in (py - 1)...(py + 1) {
            for x in (px - 1)...(px + 1) where plane.pixels[y * w + x] > plane.pixels[hot] { hot = y * w + x }
        }
        let hx = hot % w, hy = hot / w
        let hotExcess = Double(plane.pixels[hot] - bg)
        if hotExcess > 8 * noise {
            let neighbours = Double(plane[hx - 1, hy] + plane[hx + 1, hy] + plane[hx, hy - 1] + plane[hx, hy + 1]) / 4 - Double(bg)
            if neighbours < 0.08 * hotExcess { return nil }
        }

        func parabola(_ l: Float, _ c: Float, _ rt: Float) -> Double {
            let den = Double(l - 2 * c + rt)
            guard den < 0 else { return 0 }
            return min(0.5, max(-0.5, 0.5 * Double(l - rt) / den))
        }
        let qx = Double(px) + parabola(detection[px - 1, py], detection[px, py], detection[px + 1, py])
        let qy = Double(py) + parabola(detection[px, py - 1], detection[px, py], detection[px, py + 1])

        // Raw-frame window sums around a centre.
        func window(_ cx: Double, _ cy: Double) -> (sw: Double, sx: Double, sy: Double, n: Int) {
            var sw = 0.0, sx = 0.0, sy = 0.0, n = 0
            let ix = Int(cx.rounded()), iy = Int(cy.rounded())
            for y in (iy - r)...(iy + r) {
                for x in (ix - r)...(ix + r) {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    let v = Double(plane.pixels[y * w + x] - bg)
                    sw += v
                    sx += v * Double(x)
                    sy += v * Double(y)
                    n += 1
                }
            }
            return (sw, sx, sy, n)
        }

        var cx = qx, cy = qy
        var sums = window(qx, qy)
        let snr = sums.sw / (noise * Double(sums.n).squareRoot())
        if snr >= 20 {
            for _ in 0..<3 {
                guard sums.sw > 0 else { break }
                let nx = sums.sx / sums.sw, ny = sums.sy / sums.sw
                guard hypot(nx - qx, ny - qy) <= radius / 2,
                      Int(nx) - r >= 0, Int(ny) - r >= 0, Int(nx) + r < w - 1, Int(ny) + r < h - 1 else { break }
                cx = nx
                cy = ny
                sums = window(cx, cy)
            }
        }
        var flux = sums.sw
        if psfSigma > 0, snr < 20 {
            // Faint: the smoothed peak is the steadier flux estimate. A
            // Gaussian star of flux F smoothed by a unit Gaussian of the same
            // σ peaks at F / (4πσ²).
            let dt = detectionBackground.tile(x: px, y: py)
            flux = 4 * .pi * psfSigma * psfSigma * Double(detection[px, py] - detectionBackground.level[dt])
        }
        guard flux > 0 else { return nil }

        var sr = 0.0, sw = 0.0
        let ix = Int(cx.rounded()), iy = Int(cy.rounded())
        for y in (iy - r)...(iy + r) {
            for x in (ix - r)...(ix + r) {
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
                            area: halfArea, hfr: sw > 0 ? sr / sw : 0)
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
