public import Foundation

/// A deterministic, low-resolution model of the Milky Way's surface
/// brightness in galactic coordinates, for the Sky view's simulated
/// backdrop. Not survey data: a smooth disk that thickens and brightens
/// toward the Galactic Center, a list of star clouds added on top and a list
/// of dust clouds that dim it, each placed at the published galactic
/// coordinates of the named feature (SIMBAD / standard atlases, rounded to a
/// degree) and sized by eye. Nothing is copied from an image or survey, so
/// there is no data licence to track. The Metal backdrop receives
/// `shaderParameters` and evaluates the same sums per pixel.
public enum MilkyWayModel {
    /// One elliptical Gaussian in (l, b), degrees.
    public struct Feature: Sendable, Hashable {
        public let name: String
        public let l: Double
        public let b: Double
        public let sigmaL: Double
        public let sigmaB: Double
        /// Added brightness for a star cloud, optical depth for dust.
        public let amplitude: Double
    }

    public static let starClouds: [Feature] = [
        Feature(name: "Galactic bulge", l: 0, b: -3, sigmaL: 12, sigmaB: 8, amplitude: 0.40),
        Feature(name: "Large Sagittarius Star Cloud", l: 2.5, b: -5.5, sigmaL: 5, sigmaB: 3.5, amplitude: 0.45),
        Feature(name: "Small Sagittarius Star Cloud (M24)", l: 12, b: -1, sigmaL: 2, sigmaB: 1.5, amplitude: 0.30),
        Feature(name: "Scutum Star Cloud", l: 27, b: -3, sigmaL: 4, sigmaB: 2.5, amplitude: 0.40),
        Feature(name: "Aquila band", l: 40, b: -3, sigmaL: 8, sigmaB: 3, amplitude: 0.15),
        Feature(name: "Cygnus Star Cloud", l: 72, b: 2.5, sigmaL: 7, sigmaB: 3.5, amplitude: 0.30),
        Feature(name: "Cassiopeia–Perseus arm", l: 120, b: 0, sigmaL: 18, sigmaB: 3, amplitude: 0.06),
        Feature(name: "Carina", l: 287, b: -1, sigmaL: 6, sigmaB: 3, amplitude: 0.35),
        Feature(name: "Crux–Centaurus", l: 305, b: -1, sigmaL: 8, sigmaB: 3, amplitude: 0.25),
        Feature(name: "Norma Star Cloud", l: 330, b: -2, sigmaL: 8, sigmaB: 3, amplitude: 0.30),
        Feature(name: "Scorpius", l: 345, b: -3, sigmaL: 6, sigmaB: 4, amplitude: 0.20),
    ]

    /// The Great Rift is a chain of dust clouds from the Northern Coalsack
    /// near Deneb (l ≈ 85°) through Aquila to the Pipe Nebula in Ophiuchus,
    /// drifting north of the plane as it goes.
    public static let dustClouds: [Feature] = [
        Feature(name: "Northern Coalsack", l: 85, b: 0.5, sigmaL: 4, sigmaB: 2, amplitude: 1.1),
        Feature(name: "Cygnus Rift", l: 78, b: 0, sigmaL: 4, sigmaB: 1.8, amplitude: 0.8),
        Feature(name: "Cygnus Rift", l: 70, b: 0.5, sigmaL: 4, sigmaB: 1.8, amplitude: 0.7),
        Feature(name: "Great Rift (Vulpecula)", l: 62, b: 1, sigmaL: 4, sigmaB: 2, amplitude: 0.8),
        Feature(name: "Great Rift (Sagitta)", l: 54, b: 1, sigmaL: 4, sigmaB: 2, amplitude: 0.9),
        Feature(name: "Great Rift (Aquila)", l: 46, b: 1.5, sigmaL: 4, sigmaB: 2.2, amplitude: 1.0),
        Feature(name: "Aquila Rift", l: 38, b: 2, sigmaL: 4, sigmaB: 2.5, amplitude: 1.1),
        Feature(name: "Aquila Rift", l: 30, b: 2.5, sigmaL: 4, sigmaB: 2.5, amplitude: 1.1),
        Feature(name: "Serpens Cauda dust", l: 22, b: 3, sigmaL: 4, sigmaB: 3, amplitude: 1.0),
        Feature(name: "Ophiuchus dust", l: 14, b: 3.5, sigmaL: 4, sigmaB: 3, amplitude: 0.9),
        Feature(name: "Ophiuchus dust", l: 6, b: 4.5, sigmaL: 4, sigmaB: 3, amplitude: 0.9),
        Feature(name: "Pipe Nebula", l: 358, b: 5.5, sigmaL: 4, sigmaB: 2.5, amplitude: 0.9),
        Feature(name: "Rho Ophiuchi clouds", l: 353, b: 16, sigmaL: 4, sigmaB: 3, amplitude: 0.5),
        Feature(name: "Coalsack", l: 301.5, b: -1, sigmaL: 2.5, sigmaB: 2.5, amplitude: 1.3),
    ]

    /// Relative surface brightness above the dark sky, about 0 (far from the
    /// plane) to 1.1 (the Sagittarius Star Cloud).
    public static func brightness(l: Double, b: Double) -> Double {
        let lw = wrapped(l)
        let amp = 0.16 + 0.30 * exp(-(lw / 55) * (lw / 55))
        let sigma = 3.0 + 3.0 * exp(-(lw / 45) * (lw / 45))
        var light = amp * (0.75 * exp(-b * b / (2 * sigma * sigma)) + 0.25 * exp(-abs(b) / (3 * sigma)))
        for f in starClouds { light += f.amplitude * gaussian(f, l, b) }
        var tau = 0.5 * exp(-(lw / 70) * (lw / 70)) * exp(-b * b / 2)
        for f in dustClouds { tau += f.amplitude * gaussian(f, l, b) }
        return light * exp(-tau)
    }

    /// Galactic (l, b) of a unit vector in the galactic frame.
    public static func galactic(_ g: SIMD3<Double>) -> (l: Double, b: Double) {
        (Geodesy.normalizedAzimuth(atan2(g.y, g.x) * 180 / .pi), asin(max(-1, min(1, g.z))) * 180 / .pi)
    }

    /// For the Metal backdrop: star-cloud count, then (l, b, σl, σb, amplitude)
    /// for every star cloud followed by every dust cloud.
    public static var shaderParameters: [Float] {
        [Float(starClouds.count)] + (starClouds + dustClouds).flatMap {
            [Float($0.l), Float($0.b), Float($0.sigmaL), Float($0.sigmaB), Float($0.amplitude)]
        }
    }

    static func gaussian(_ f: Feature, _ l: Double, _ b: Double) -> Double {
        let dl = wrapped(l - f.l), db = b - f.b
        return exp(-(dl * dl / (2 * f.sigmaL * f.sigmaL) + db * db / (2 * f.sigmaB * f.sigmaB)))
    }

    /// Degrees into (−180, 180].
    static func wrapped(_ x: Double) -> Double {
        let r = (x + 180).truncatingRemainder(dividingBy: 360)
        return (r < 0 ? r + 360 : r) - 180
    }
}
