public import Foundation

/// Longest untracked exposure before stars trail, and how far they trail.
///
/// The NPF rule is Frédéric Michaud's (Société Astronomique du Havre, 2010).
/// Source: F. Michaud, "La Règle NPF", sahavre.fr, 2020-12-01, and its
/// derivation "Les coulisses de la règle NPF", sahavre.fr (2013-03-28, as read
/// 2026-09-26). The SAH asks that any implementation credit the author and the
/// SAH, and allows no commercial use without consent.
public enum StarExposure {
    /// NPF "k": 1 = the star moves one radius (round; PhotoPills "Accurate"),
    /// 2 = one diameter (barely perceptible; PhotoPills "Default"), 3 = perceptible.
    public static let npfKRange = 1.0...3.0

    // Coefficients of the complete rule, unrounded as derived in "Les coulisses
    // de la règle NPF" (Airy 4.47·λ·N at 550 nm, 3″ seeing, Bayer 2·p, 86164 s
    // sidereal day); the SAH page prints them rounded as 16.9, 0.10 and 13.7.
    static let npfApertureCoefficient = 16.856
    static let npfFocalCoefficient = 0.0997
    static let npfPitchCoefficient = 13.713

    /// Complete NPF rule: t = k·(16.856·N + 0.0997·f + 13.713·p) / (f·cos δ) (Michaud, SAH).
    /// `declinationDeg` is the smallest |δ| in the frame; 0 (the default) is the
    /// worst case and safe for any direction. At δ = ±90° stars do not move and
    /// the result is `.infinity`.
    public static func npf(
        fNumber: Double, focalLengthMM: Double, pixelPitchUM: Double,
        declinationDeg: Double = 0, k: Double = 1
    ) throws(ExposureError) -> TimeInterval {
        let n = try requireFNumber(fNumber)
        let f = try requirePositive(.focalLength, focalLengthMM)
        let p = try requirePositive(.pixelPitch, pixelPitchUM)
        let dec = try requireDeclination(declinationDeg)
        let k = try require(.npfK, k) { npfKRange.contains($0) }
        if abs(dec) == 90 { return .infinity }
        let spread = npfApertureCoefficient * n + npfFocalCoefficient * f + npfPitchCoefficient * p
        return k * spread / (f * cos(dec * .pi / 180))
    }

    /// Simplified NPF rule: t = (35·N + 30·p) / f (Michaud, SAH; k = 2, δ = 0, seeing ignored).
    public static func npfSimple(fNumber: Double, focalLengthMM: Double, pixelPitchUM: Double) throws(ExposureError) -> TimeInterval {
        let n = try requireFNumber(fNumber)
        let f = try requirePositive(.focalLength, focalLengthMM)
        let p = try requirePositive(.pixelPitch, pixelPitchUM)
        return (35 * n + 30 * p) / f
    }

    /// The rough 500 rule, kept only for comparison: t = 500 / (crop × f)
    /// (PhotoPills Milky Way guide; SAH traces it to a film-era 0.029 mm CoC).
    /// It ignores pixel pitch and aperture and trails badly on modern sensors.
    public static func roughRule500(focalLengthMM: Double, cropFactor: Double = 1) throws(ExposureError) -> TimeInterval {
        let f = try requirePositive(.focalLength, focalLengthMM)
        let crop = try requirePositive(.cropFactor, cropFactor)
        return 500 / (crop * f)
    }

    /// Apparent rate of a star on the celestial equator: Earth's rotation rate
    /// ω = 7.292115e-5 rad/s = 15.041″/s (IERS Conventions 2010, Table 1.1).
    public static let siderealRateArcsecPerSecond = 15.041

    /// Distance a star at `declinationDeg` moves on the sensor near the image
    /// centre: d = f·θ, θ = 15.041″/s × t × cos δ (small-angle; exact for short
    /// exposures, a chord approximation for long star-trail sessions).
    public static func starTrailLengthMM(
        exposure: TimeInterval, focalLengthMM: Double, declinationDeg: Double = 0
    ) throws(ExposureError) -> Double {
        let t = try require(.exposure, exposure) { $0 >= 0 }
        let f = try requirePositive(.focalLength, focalLengthMM)
        let dec = try requireDeclination(declinationDeg)
        if abs(dec) == 90 { return 0 }
        let thetaRad = siderealRateArcsecPerSecond * t * cos(dec * .pi / 180) / 3600 * .pi / 180
        return f * thetaRad
    }

    /// Star-trail length in pixels: the on-sensor distance ÷ pixel pitch.
    public static func starTrailLengthPixels(
        exposure: TimeInterval, focalLengthMM: Double, pixelPitchUM: Double, declinationDeg: Double = 0
    ) throws(ExposureError) -> Double {
        let p = try requirePositive(.pixelPitch, pixelPitchUM)
        return try starTrailLengthMM(exposure: exposure, focalLengthMM: focalLengthMM, declinationDeg: declinationDeg) * 1000 / p
    }
}

// MARK: - Saved gear

extension StarExposure {
    /// Complete NPF for a saved camera and lens; `fNumber` nil means wide open.
    public static func npf(
        camera: CameraProfile, lens: LensProfile, fNumber: Double? = nil,
        declinationDeg: Double = 0, k: Double = 1
    ) throws(ExposureError) -> TimeInterval {
        try npf(fNumber: lens.aperture(fNumber), focalLengthMM: lens.focalLengthMM,
                pixelPitchUM: camera.pixelPitchUM, declinationDeg: declinationDeg, k: k)
    }

    public static func npfSimple(camera: CameraProfile, lens: LensProfile, fNumber: Double? = nil) throws(ExposureError) -> TimeInterval {
        try npfSimple(fNumber: lens.aperture(fNumber), focalLengthMM: lens.focalLengthMM, pixelPitchUM: camera.pixelPitchUM)
    }

    public static func roughRule500(camera: CameraProfile, lens: LensProfile) throws(ExposureError) -> TimeInterval {
        try roughRule500(focalLengthMM: lens.focalLengthMM, cropFactor: camera.cropFactor)
    }

    public static func starTrailLengthPixels(
        exposure: TimeInterval, camera: CameraProfile, lens: LensProfile, declinationDeg: Double = 0
    ) throws(ExposureError) -> Double {
        try starTrailLengthPixels(exposure: exposure, focalLengthMM: lens.focalLengthMM,
                                  pixelPitchUM: camera.pixelPitchUM, declinationDeg: declinationDeg)
    }
}
