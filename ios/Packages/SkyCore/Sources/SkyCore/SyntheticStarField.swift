public import Foundation

/// Deterministic star fields with a known transform, for testing star
/// detection, registration and stacking (ADR-0011: registration is checked on
/// synthetic star fields) and for timing the stacker on a phone.
public enum SyntheticStarField {
    public struct Star: Sendable, Hashable {
        public let x: Double
        public let y: Double
        /// Total counts (0...65535 scale) spread over the PSF.
        public let flux: Double
    }

    /// `count` stars uniformly placed, fluxes from a steep power law (many faint, few bright).
    public static func stars(count: Int, width: Int, height: Int, seed: UInt64,
                             minFlux: Double = 3_000, maxFlux: Double = 400_000) -> [Star] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            let u = rng.unit()
            let flux = minFlux * pow(maxFlux / minFlux, u * u * u)
            return Star(x: rng.unit() * Double(width - 1), y: rng.unit() * Double(height - 1), flux: flux)
        }
    }

    /// A satellite or aircraft trail: a 3-pixel-wide line this far above the background.
    public struct Streak: Sendable, Hashable {
        public let x0: Double, y0: Double, x1: Double, y1: Double
        public let brightness: Double

        public init(x0: Double, y0: Double, x1: Double, y1: Double, brightness: Double) {
            self.x0 = x0
            self.y0 = y0
            self.x1 = x1
            self.y1 = y1
            self.brightness = brightness
        }
    }

    /// Renders `stars` moved by `frameFromReference` (reference → this frame)
    /// as Gaussian PSFs over a flat background with Gaussian read noise, into
    /// a 16-bit raster with `channels` identical colour channels.
    public static func render(
        _ stars: [Star], width: Int, height: Int, channels: Int = 1,
        frameFromReference: RigidTransform = .identity,
        psfSigma: Double = 1.3, background: Double = 2_000, noiseSigma: Double = 40,
        streak: Streak? = nil, hotPixels: [(x: Int, y: Int)] = [], seed: UInt64
    ) -> RasterU16 {
        var image = [Double](repeating: background, count: width * height)
        let reach = Int((4 * psfSigma).rounded(.up))
        let norm = 1 / (2 * .pi * psfSigma * psfSigma)
        for star in stars {
            let p = frameFromReference.apply(star.x, star.y)
            let cx = Int(p.x.rounded()), cy = Int(p.y.rounded())
            let x0 = max(cx - reach, 0), x1 = min(cx + reach, width - 1)
            let y0 = max(cy - reach, 0), y1 = min(cy + reach, height - 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let dx = Double(x) - p.x, dy = Double(y) - p.y
                    image[y * width + x] += star.flux * norm * exp(-(dx * dx + dy * dy) / (2 * psfSigma * psfSigma))
                }
            }
        }
        if let streak {
            let length = hypot(streak.x1 - streak.x0, streak.y1 - streak.y0)
            let steps = max(1, Int(length * 2))
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let x = Int((streak.x0 + t * (streak.x1 - streak.x0)).rounded())
                let y = Int((streak.y0 + t * (streak.y1 - streak.y0)).rounded())
                for oy in -1...1 {
                    let yy = y + oy
                    guard x >= 0, x < width, yy >= 0, yy < height else { continue }
                    image[yy * width + x] = max(image[yy * width + x], background + streak.brightness)
                }
            }
        }
        for hot in hotPixels where hot.x >= 0 && hot.x < width && hot.y >= 0 && hot.y < height {
            image[hot.y * width + hot.x] = 60_000
        }
        var rng = SplitMix64(seed: seed)
        var out = [UInt16](repeating: 0, count: width * height * channels)
        for i in 0..<(width * height) {
            let base = image[i]
            for c in 0..<channels {
                let v = base + noiseSigma * rng.gaussian()
                out[i * channels + c] = UInt16(max(0, min(65_535, v.rounded())))
            }
        }
        return RasterU16(width: width, height: height, channels: channels, values: out)
    }
}

/// SplitMix64 (Steele, Lea & Flood 2014): small, fast, reproducible across platforms.
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Standard normal (Box–Muller).
    public mutating func gaussian() -> Double {
        let u1 = max(unit(), .leastNonzeroMagnitude), u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
