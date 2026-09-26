public import Foundation
import CAstronomy

/// Swift port of `app/src/astronomy/planner.ts`. The TypeScript planner is the
/// reference (ADR-0009 §3): every step calls the same astronomy-engine
/// function with the same arguments, so the two agree to the millisecond on
/// the golden vectors. Change the TypeScript first, then mirror it here.
public struct TimeWindow: Sendable, Hashable, Codable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct MoonFreeWindow: Sendable, Hashable, Codable {
    public let start: Date
    public let end: Date
    public let minutes: Int
}

public struct GCVisibility: Sendable, Hashable, Codable {
    /// Max GC altitude (deg, rounded to 0.1) across the moon-free dark window; nil if none.
    public let maxAltitudeDeg: Double?
    public let maxAltitudeAt: Date?
    /// True when the GC actually climbs above the horizon in the dark window.
    public let risesDuringDarkness: Bool

    /// Whether the peak clears the photographic threshold from `config/app-config.json`.
    public func isUsable(_ config: AppConfig) -> Bool {
        (maxAltitudeDeg ?? -90) >= config.gcMinUsefulAltitudeDeg
    }
}

public struct NightReport: Sendable, Hashable, Codable {
    public let darkness: TimeWindow?
    /// True when astronomical night does not occur on this date/location.
    public let noAstronomicalDarkness: Bool
    public let moonIllumFraction: Double
    public let moonset: Date?
    public let moonrise: Date?
    public let moonFreeWindows: [MoonFreeWindow]
    /// Minutes of moon-free astronomical darkness (headline number).
    public let moonFreeMinutes: Int
    public let gc: GCVisibility
    /// Present only when a horizon profile was given (M9); the fields above
    /// are then judged against the terrain, not the mathematical horizon.
    public let terrain: TerrainReport?
}

public enum Planner {
    /// Sgr A*: 17h 45m 40.04s, −29° 00′ 28.1″ (J2000). Precessed to the date
    /// (`gcEquatorOfDate`) before any horizon math, like the web app.
    public static let gcRAHours = 17.7611222
    public static let gcDecDeg = -29.0078056

    static let gcSampleSeconds: TimeInterval = 5 * 60

    /// Sun-below-`altitudeDeg` interval for the night containing/after `evening`.
    /// Searches start 12 h earlier so the first descending crossing belongs to
    /// this night, never the previous one.
    public static func darknessWindow(
        _ observer: Observer,
        evening: Date,
        altitudeDeg: Double = -18
    ) throws(AstronomyError) -> (window: TimeWindow?, noDarkness: Bool) {
        let searchStart = evening.addingTimeInterval(-12 * 3600)
        let dusk = try searchResult(
            Astronomy_SearchAltitude(BODY_SUN, observer.c, DIRECTION_SET, AstroTime.from(searchStart), 1.5, altitudeDeg),
            "SearchAltitude(dusk)")
        guard let dusk else { return (nil, true) }
        let dawn = try searchResult(
            Astronomy_SearchAltitude(BODY_SUN, observer.c, DIRECTION_RISE, AstroTime.from(dusk), 2, altitudeDeg),
            "SearchAltitude(dawn)")
        guard let dawn else { return (nil, true) }
        return (TimeWindow(start: dusk, end: dawn), false)
    }

    /// Up iff the most recent rise/set event was a rise: the same top-limb,
    /// refracted definition `SearchRiseSet` uses for the events that follow.
    static func isMoonUp(_ observer: Observer, at date: Date) throws(AstronomyError) -> Bool {
        let rise = try searchResult(
            Astronomy_SearchRiseSetEx(BODY_MOON, observer.c, DIRECTION_RISE, AstroTime.from(date), -2, 0),
            "SearchRiseSet(last moonrise)")
        let set = try searchResult(
            Astronomy_SearchRiseSetEx(BODY_MOON, observer.c, DIRECTION_SET, AstroTime.from(date), -2, 0),
            "SearchRiseSet(last moonset)")
        if let rise, let set { return rise > set }
        if rise != nil || set != nil { return rise != nil }
        // No event within 2 days (polar latitudes only).
        return try SkyPositions.bodyPosition(BODY_MOON, at: date, observer: observer, refraction: .normal).altitudeDeg > 0
    }

    /// Moon above-horizon intervals overlapping [from, to].
    public static func moonUpIntervals(_ observer: Observer, from: Date, to: Date) throws(AstronomyError) -> [TimeWindow] {
        var out: [TimeWindow] = []
        var cursor = from.addingTimeInterval(-12 * 3600)
        var up = try isMoonUp(observer, at: cursor)
        var guardCount = 0
        while guardCount < 60 && cursor < to {
            guardCount += 1
            let event = try searchResult(
                Astronomy_SearchRiseSetEx(BODY_MOON, observer.c, up ? DIRECTION_SET : DIRECTION_RISE, AstroTime.from(cursor), 10, 0),
                "SearchRiseSet(moon)")
            guard let t = event else { break }
            if up {
                out.append(TimeWindow(start: cursor, end: t))
                up = false
            } else {
                up = true
            }
            cursor = t
        }
        return out.filter { $0.end > from && $0.start < to }
    }

    /// Intersect a dark window with moon-down periods -> moon-free sub-windows.
    public static func moonFreeWindows(darkness: TimeWindow, moonUp: [TimeWindow]) -> [MoonFreeWindow] {
        var windows: [MoonFreeWindow] = []
        var cursor = darkness.start
        for up in moonUp.sorted(by: { $0.start < $1.start }) {
            if up.end <= darkness.start || up.start >= darkness.end { continue }
            if up.start > cursor { pushWindow(&windows, cursor, min(up.start, darkness.end)) }
            cursor = max(cursor, up.end)
            if cursor >= darkness.end { break }
        }
        if cursor < darkness.end { pushWindow(&windows, cursor, darkness.end) }
        return windows
    }

    static func pushWindow(_ out: inout [MoonFreeWindow], _ start: Date, _ end: Date) {
        let ms = (end.timeIntervalSince(start) * 1000).rounded()
        if ms > 60_000 {
            out.append(MoonFreeWindow(start: start, end: end, minutes: Int(jsRound(ms / 60_000))))
        }
    }

    public static func moonIllumination(at date: Date) throws(AstronomyError) -> Double {
        let illum = Astronomy_Illumination(BODY_MOON, AstroTime.from(date))
        try check(illum.status, "Illumination(moon)")
        return illum.phase_fraction
    }

    /// GC RA (hours) and Dec (deg) on the true equator of date, as the web
    /// app's `gcEquatorOfDate`: `Astronomy_Horizon` expects of-date coordinates.
    public static func gcEquatorOfDate(at date: Date) -> (raHours: Double, decDeg: Double) {
        var time = AstroTime.from(date)
        let rotation = Astronomy_Rotation_EQJ_EQD(&time)
        let eqj = Astronomy_VectorFromSphere(
            astro_spherical_t(status: ASTRO_SUCCESS, lat: gcDecDeg, lon: gcRAHours * 15, dist: 1), time)
        let eqd = Astronomy_EquatorFromVector(Astronomy_RotateVector(rotation, eqj))
        // Cannot fail for a non-null time and a unit vector.
        precondition(eqd.status == ASTRO_SUCCESS, "GC precession failed: \(eqd.status)")
        return (eqd.ra, eqd.dec)
    }

    /// GC altitude/azimuth exactly as the web app's `gcAltitude`/`gcAzimuth`
    /// (geometric; ADR-0002 2026-09-25 amendment).
    public static func gcPosition(_ observer: Observer, at date: Date) -> HorizontalPosition {
        gcPosition(observer, at: date, refraction: .none)
    }

    static func gcPosition(_ observer: Observer, at date: Date, refraction: Refraction) -> HorizontalPosition {
        let eqd = gcEquatorOfDate(at: date)
        return SkyPositions.fixedPosition(
            raHours: eqd.raHours, decDeg: eqd.decDeg, at: date, observer: observer, refraction: refraction)
    }

    public static func gcVisibility(_ observer: Observer, moonFree: [MoonFreeWindow]) -> GCVisibility {
        var best: (alt: Double, at: Date)?
        for window in moonFree {
            let startMs = (window.start.timeIntervalSince1970 * 1000).rounded()
            let endMs = (window.end.timeIntervalSince1970 * 1000).rounded()
            var t = startMs
            while true {
                let when = Date(timeIntervalSince1970: min(t, endMs) / 1000)
                let alt = gcPosition(observer, at: when).altitudeDeg
                if best.map({ alt > $0.alt }) ?? true { best = (alt, when) }
                if t >= endMs { break }
                t += gcSampleSeconds * 1000
            }
        }
        return GCVisibility(
            maxAltitudeDeg: best.map { jsRound($0.alt * 10) / 10 },
            maxAltitudeAt: best?.at,
            risesDuringDarkness: (best?.alt ?? 0) > 0)
    }

    static func findMoonEvent(
        _ observer: Observer, darkness: TimeWindow?, direction: astro_direction_t
    ) throws(AstronomyError) -> Date? {
        guard let darkness else { return nil }
        let event = try searchResult(
            Astronomy_SearchRiseSetEx(BODY_MOON, observer.c, direction, AstroTime.from(darkness.start), 2, 0),
            "SearchRiseSet(moon event)")
        guard let t = event, t >= darkness.start, t <= darkness.end else { return nil }
        return t
    }

    public static func planNight(_ observer: Observer, evening: Date) throws(AstronomyError) -> NightReport {
        let (darkness, noDarkness) = try darknessWindow(observer, evening: evening)
        let midDark = darkness.map {
            AstroTime.jsDate(ms: (($0.start.timeIntervalSince1970 + $0.end.timeIntervalSince1970) * 1000).rounded() / 2)
        } ?? evening
        let moonFree: [MoonFreeWindow]
        if let darkness {
            moonFree = moonFreeWindows(
                darkness: darkness,
                moonUp: try moonUpIntervals(observer, from: darkness.start, to: darkness.end))
        } else {
            moonFree = []
        }
        return NightReport(
            darkness: darkness,
            noAstronomicalDarkness: noDarkness,
            moonIllumFraction: jsRound(try moonIllumination(at: midDark) * 1000) / 1000,
            moonset: try findMoonEvent(observer, darkness: darkness, direction: DIRECTION_SET),
            moonrise: try findMoonEvent(observer, darkness: darkness, direction: DIRECTION_RISE),
            moonFreeWindows: moonFree,
            moonFreeMinutes: max(0, moonFree.map(\.minutes).max() ?? 0),
            gc: gcVisibility(observer, moonFree: moonFree),
            terrain: nil)
    }
}
