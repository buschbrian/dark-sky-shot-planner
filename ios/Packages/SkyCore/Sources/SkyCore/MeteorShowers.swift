public import Foundation
import CAstronomy

/// Swift port of `app/src/astronomy/showers.ts`: what a meteor shower does at
/// this spot on this night. The curated row gives only the radiant, the peak
/// instant and the active range; radiant altitude, the Moon and the usable
/// hours are computed here (ADR-0008 §3). Change the TypeScript first.
public enum MeteorShowers {
    /// A radiant must clear this altitude during astronomical darkness to count.
    public static let radiantMinAltitudeDeg = 10.0
    static let sampleMinutes = 5.0
    static let neighbourNights = 3

    /// J2000 radiant.
    public struct Radiant: Sendable, Hashable, Codable {
        public let raHours: Double
        public let decDeg: Double

        public init(raHours: Double, decDeg: Double) {
            self.raHours = raHours
            self.decDeg = decDeg
        }
    }

    public struct Night: Sendable, Hashable {
        /// The 21:00 site-mean-time instant the night is keyed on.
        public let eveningUtc: Date
        public let darkness: TimeWindow?
        /// Peak radiant altitude during darkness (0.1°); −∞ with no darkness.
        public let maxAltitudeDeg: Double
        public let maxAltitudeAt: Date?
        public let radiantObservable: Bool
        /// Dark hours with the radiant above the cutoff.
        public let radiantWindow: TimeWindow?
        /// Moon illuminated fraction at the middle of the radiant window.
        public let moonIllumFraction: Double
        /// Moon-down parts of the radiant window; empty means the Moon is up throughout.
        public let usableWindows: [MoonFreeWindow]
        public let usableMinutes: Int
    }

    public struct Assessment: Sendable, Hashable {
        public let peakNight: Night
        /// A night in the active range with 30+ more moonless radiant minutes than the peak.
        public let betterNight: Night?
        /// False when the radiant never clears 10° in darkness on any assessed night.
        public let observableHere: Bool
    }

    /// Radiant altitude at the observer, precessed from J2000 to the date, refracted.
    public static func radiantAltitudeDeg(_ site: Observer, _ radiant: Radiant, at when: Date) -> Double {
        var time = AstroTime.from(when)
        let j2000 = Astronomy_VectorFromSphere(
            astro_spherical_t(status: ASTRO_SUCCESS, lat: radiant.decDeg, lon: radiant.raHours * 15, dist: 1), time)
        let ofDate = Astronomy_RotateVector(Astronomy_Rotation_EQJ_EQD(&time), j2000)
        let eq = Astronomy_EquatorFromVector(ofDate)
        return Astronomy_Horizon(&time, site.c, eq.ra, eq.dec, REFRACTION_NORMAL).altitude
    }

    /// The peak night and up to three nights either side inside the active range.
    public static func assess(
        _ site: Observer, _ radiant: Radiant, peak: Date, activeFrom: Date, activeTo: Date
    ) throws(AstronomyError) -> Assessment {
        let peakNight = try assessNight(site, radiant, evening: evening(for: peak, longitude: site.longitude))
        var better: Night?
        var observableHere = peakNight.radiantObservable
        for offset in -neighbourNights...neighbourNights where offset != 0 {
            let evening = JSTime.date(JSTime.ms(peakNight.eveningUtc) + Double(offset) * JSTime.day)
            if evening < activeFrom || evening > activeTo { continue }
            let night = try assessNight(site, radiant, evening: evening)
            observableHere = observableHere || night.radiantObservable
            if night.usableMinutes > peakNight.usableMinutes + 30,
               better.map({ night.usableMinutes > $0.usableMinutes }) ?? true {
                better = night
            }
        }
        return Assessment(peakNight: peakNight, betterNight: better, observableHere: observableHere)
    }

    /// One night. Darkness and moon-up use the planner's sea-level observer,
    /// the radiant the site's own, exactly as the web app does.
    public static func assessNight(_ site: Observer, _ radiant: Radiant, evening: Date) throws(AstronomyError) -> Night {
        let seaLevel = (try? Observer(latitude: site.latitude, longitude: site.longitude)) ?? site
        guard let darkness = try Planner.darknessWindow(seaLevel, evening: evening).window else {
            return Night(
                eveningUtc: evening, darkness: nil, maxAltitudeDeg: -.infinity, maxAltitudeAt: nil,
                radiantObservable: false, radiantWindow: nil,
                moonIllumFraction: try Planner.moonIllumination(at: evening),
                usableWindows: [], usableMinutes: 0)
        }
        let step = sampleMinutes * 60_000
        let startMs = JSTime.ms(darkness.start), endMs = JSTime.ms(darkness.end)
        var best: (alt: Double, at: Date)?
        var above: (start: Date, end: Date)?
        var t = startMs
        while t <= endMs {
            let when = JSTime.date(min(t, endMs))
            let alt = radiantAltitudeDeg(site, radiant, at: when)
            if best.map({ alt > $0.alt }) ?? true { best = (alt, when) }
            if alt >= radiantMinAltitudeDeg {
                if above == nil { above = (when, when) } else { above!.end = when }
            }
            t += step
        }
        let radiantWindow = above.map { TimeWindow(start: $0.start, end: $0.end) }
        let mid = radiantWindow ?? darkness
        let midpoint = JSTime.date((JSTime.ms(mid.start) + JSTime.ms(mid.end)) / 2)
        let usable = try radiantWindow.map { w throws(AstronomyError) in
            Planner.moonFreeWindows(darkness: w, moonUp: try Planner.moonUpIntervals(seaLevel, from: w.start, to: w.end))
        } ?? []
        return Night(
            eveningUtc: evening, darkness: darkness,
            maxAltitudeDeg: best.map { round1($0.alt) } ?? -.infinity,
            maxAltitudeAt: best?.at,
            radiantObservable: radiantWindow != nil,
            radiantWindow: radiantWindow,
            moonIllumFraction: round3(try Planner.moonIllumination(at: midpoint)),
            usableWindows: usable,
            usableMinutes: usable.reduce(0) { $0 + $1.minutes })
    }

    /// 21:00 site mean solar time of the night an instant belongs to; before
    /// local noon it is the night that began the evening before.
    public static func evening(for instant: Date, longitude: Double) -> Date {
        let offset = (longitude / 15) * JSTime.hour
        let local = (JSTime.ms(instant) + offset).rounded(.towardZero)
        var dayStart = (local / JSTime.day).rounded(.down) * JSTime.day
        let hour = ((local - dayStart) / JSTime.hour).rounded(.down)
        if hour < 12 { dayStart -= JSTime.day }
        return JSTime.date(dayStart + 21 * JSTime.hour - offset)
    }
}
