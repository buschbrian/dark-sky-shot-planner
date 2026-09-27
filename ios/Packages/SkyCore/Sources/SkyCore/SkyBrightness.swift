public import Foundation

// Sky brightness for the Sky view's simulated backdrop and star limit. These
// are published *models*, used to make the preview look like the night will
// look; they are not a photometric forecast and the UI never shows them as a
// measured number. `ios/App/Sky/SkyBackdrop.metal` evaluates the same
// formulas per pixel; keep the two in step (SkyBrightnessTests pins values).

public enum Airmass {
    /// Kasten & Young (1989), Applied Optics 28(22):4735, for apparent
    /// altitude h in degrees: X = 1 / (sin h + 0.50572 (h + 6.07995°)^−1.6364).
    /// 1 at the zenith, about 38 at the horizon. Clamped at 1° below it.
    public static func kastenYoung(altitudeDeg: Double) -> Double {
        let h = max(altitudeDeg, -1)
        return 1 / (sin(h * .pi / 180) + 0.50572 * pow(h + 6.07995, -1.6364))
    }

    /// Krisciunas & Schaefer (1991), PASP 103:1033, eq. 3, for scattered
    /// light at zenith distance Z: X = (1 − 0.96 sin²Z)^−½.
    public static func krisciunasSchaefer(zenithDistanceDeg z: Double) -> Double {
        let s = sin(min(max(z, 0), 90) * .pi / 180)
        return 1 / (1 - 0.96 * s * s).squareRoot()
    }
}

/// Atmospheric extinction: a star's light dims by k magnitudes per airmass.
public struct Extinction: Sendable, Hashable {
    /// V-band coefficient, mag per airmass. 0.2 is a typical clear, dry
    /// site (Krisciunas & Schaefer used 0.172 on Mauna Kea); haze raises it.
    public var k: Double

    public static let typical = Extinction(k: 0.2)

    public init(k: Double) { self.k = k }

    /// Dimming relative to the zenith, so a star's catalogue magnitude holds
    /// straight overhead: k (X − 1). 0 at the zenith, ~7 mag at the horizon.
    public func deltaMagnitude(altitudeDeg: Double) -> Double {
        k * (Airmass.kastenYoung(altitudeDeg: altitudeDeg) - Self.zenithAirmass)
    }

    /// Kasten–Young gives 0.9997 straight up, not exactly 1.
    static let zenithAirmass = Airmass.kastenYoung(altitudeDeg: 90)
}

/// What lights the sky at one instant.
public struct SkyLighting: Sendable, Hashable {
    public var sun: HorizontalPosition
    public var moon: HorizontalPosition
    /// Sun–Moon phase angle seen from Earth, degrees: 0 full, 180 new.
    public var moonPhaseAngleDeg: Double
    /// Moonless, sunless zenith brightness in nanolamberts. 60 nL is about
    /// 21.9 mag/arcsec², a dark rural site; no light-pollution data is used.
    public var darkZenithNanoLamberts: Double
    public var extinction: Extinction

    public init(
        sun: HorizontalPosition, moon: HorizontalPosition, moonPhaseAngleDeg: Double,
        darkZenithNanoLamberts: Double = 60, extinction: Extinction = .typical
    ) {
        self.sun = sun
        self.moon = moon
        self.moonPhaseAngleDeg = moonPhaseAngleDeg
        self.darkZenithNanoLamberts = darkZenithNanoLamberts
        self.extinction = extinction
    }

    /// Phase angle from the illuminated fraction: f = (1 + cos α) / 2.
    public static func phaseAngleDeg(illuminatedFraction f: Double) -> Double {
        acos(max(-1, min(1, 2 * f - 1))) * 180 / .pi
    }
}

public enum SkyBrightness {
    /// Total sky brightness toward `direction`, nanolamberts: the dark sky
    /// brightening toward the horizon, scattered moonlight and twilight.
    public static func nanoLamberts(toward direction: HorizontalPosition, lighting: SkyLighting) -> Double {
        dark(direction, lighting) + moonlight(toward: direction, lighting: lighting) + twilight(toward: direction, lighting: lighting)
    }

    /// Natural sky at zenith distance Z (Krisciunas & Schaefer eq. 2):
    /// B = B_zen · 10^(−0.4 k (X − 1)) · X.
    static func dark(_ direction: HorizontalPosition, _ l: SkyLighting) -> Double {
        let x = Airmass.krisciunasSchaefer(zenithDistanceDeg: 90 - direction.altitudeDeg)
        return l.darkZenithNanoLamberts * pow(10, -0.4 * l.extinction.k * (x - 1)) * x
    }

    /// Krisciunas & Schaefer (1991) moonlight model, eqs. 15–21: Moon
    /// brightness I* from the phase angle, the scattering function f(ρ) of
    /// the Moon–target separation, extinction of the moonlight on its way
    /// down and the fraction scattered toward the target. Faded out over the
    /// last degree as the Moon sets.
    public static func moonlight(toward direction: HorizontalPosition, lighting l: SkyLighting) -> Double {
        let moonAlt = l.moon.altitudeDeg
        guard moonAlt > -1, direction.altitudeDeg > -1 else { return 0 }
        let a = abs(l.moonPhaseAngleDeg)
        let istar = pow(10, -0.4 * (3.84 + 0.026 * a + 4e-9 * pow(a, 4)))
        let rho = max(angularSeparationDeg(direction, l.moon), 1)
        let cosRho = cos(rho * .pi / 180)
        let f = pow(10, 5.36) * (1.06 + cosRho * cosRho) + pow(10, 6.15 - rho / 40)
        let xMoon = Airmass.krisciunasSchaefer(zenithDistanceDeg: 90 - max(moonAlt, 0))
        let x = Airmass.krisciunasSchaefer(zenithDistanceDeg: 90 - max(direction.altitudeDeg, 0))
        let k = l.extinction.k
        let b = f * istar * pow(10, -0.4 * k * xMoon) * (1 - pow(10, -0.4 * k * x))
        return b * min(1, (moonAlt + 1) / 2)
    }

    /// Twilight: a hand-tuned exponential in the Sun's altitude, about
    /// 19.8 mag/arcsec² at the zenith with the Sun 12° down and brightening
    /// one magnitude per degree (so ~13.8 at the end of civil twilight and
    /// negligible past −18°), brighter toward the Sun and the horizon. Not
    /// from a paper: it only makes the dusk preview look right, and the star
    /// limit it implies is labelled approximate.
    public static func twilight(toward direction: HorizontalPosition, lighting l: SkyLighting) -> Double {
        let h = min(l.sun.altitudeDeg, 10)
        guard h > -20 else { return 0 }
        let zenith = 410 * pow(10, 0.4 * (h + 12))
        let rho = angularSeparationDeg(direction, l.sun)
        let towardSun = 1 + 4 * exp(-rho / 35)
        let low = 1 + 2 * exp(-max(direction.altitudeDeg, 0) / 12)
        return zenith * towardSun * low
    }

    /// Nanolamberts → V mag/arcsec² (Garstang 1986, as used by Krisciunas & Schaefer):
    /// V = (20.7233 − ln(B / 34.08)) / 0.92104.
    public static func magnitudePerArcsec2(nanoLamberts b: Double) -> Double {
        (20.7233 - log(max(b, 1e-6) / 34.08)) / 0.92104
    }

    /// Naked-eye limiting magnitude for a sky of `mpsas` mag/arcsec²:
    /// NELM = 7.93 − 5 log10(10^(4.316 − mpsas/5) + 1), the conversion
    /// published by Unihedron (after Schaefer 1990, PASP 102:212).
    public static func nakedEyeLimitingMagnitude(skyMagnitudePerArcsec2 mpsas: Double) -> Double {
        7.93 - 5 * log10(pow(10, 4.316 - mpsas / 5) + 1)
    }

    /// The faintest catalogue star worth drawing overhead for this lighting.
    public static func zenithLimitingMagnitude(_ l: SkyLighting) -> Double {
        let zenith = HorizontalPosition(altitudeDeg: 90, azimuthDeg: 0)
        return nakedEyeLimitingMagnitude(skyMagnitudePerArcsec2: magnitudePerArcsec2(nanoLamberts: nanoLamberts(toward: zenith, lighting: l)))
    }

    public static func angularSeparationDeg(_ a: HorizontalPosition, _ b: HorizontalPosition) -> Double {
        let d = (a.enuVector * b.enuVector).sum()
        return acos(max(-1, min(1, d))) * 180 / .pi
    }
}
