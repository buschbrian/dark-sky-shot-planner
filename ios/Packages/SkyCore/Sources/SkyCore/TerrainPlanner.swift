public import Foundation
import CAstronomy

/// What the terrain changes about a night (M9). Mirrors `TerrainReport` in
/// `app/src/astronomy/planner.ts`.
public struct TerrainReport: Sendable, Hashable, Codable {
    /// The GC above the skyline, clipped to astronomical darkness.
    public let gcAboveSkyline: [TimeWindow]
    /// First moment in darkness the GC climbs over the skyline; nil when it is
    /// already clear at dusk or never clears.
    public let gcClearsSkyline: Date?
    /// First moment in darkness the GC drops behind the skyline.
    public let gcDropsBehindSkyline: Date?
    /// Moon-free darkness with the GC above the skyline.
    public let gcWindows: [MoonFreeWindow]
    /// Longest of `gcWindows`, in minutes (the same rule as `moonFreeMinutes`).
    public let gcMinutes: Int

    static let none = TerrainReport(
        gcAboveSkyline: [], gcClearsSkyline: nil, gcDropsBehindSkyline: nil, gcWindows: [], gcMinutes: 0)
}

extension Planner {
    /// Terrain crossings are found by sampling every 2 minutes, then bisecting
    /// to 0.1 s. A skyline notch the moon or GC crosses in under 2 minutes can
    /// be missed; both platforms miss it identically.
    static let terrainScanMs = 2.0 * 60_000
    static let terrainBisectMs = 100.0

    /// Degrees the moon's top limb stands above the skyline. The limb test and
    /// standard refraction follow `SearchRiseSet` (ADR-0002 amendment), with
    /// refraction evaluated at the moon's altitude instead of the fixed 34′ a
    /// flat horizon uses, because the skyline is usually degrees up.
    static func moonClearanceDeg(_ observer: Observer, horizon: HorizonProfile, at date: Date) throws(AstronomyError) -> Double {
        var time = AstroTime.from(date)
        let eq = Astronomy_Equator(BODY_MOON, &time, observer.c, EQUATOR_OF_DATE, ABERRATION)
        try check(eq.status, "Equator(moon)")
        let hor = Astronomy_Horizon(&time, observer.c, eq.ra, eq.dec, REFRACTION_NORMAL)
        let topLimb = hor.altitude + RAD2DEG * (MOON_EQUATORIAL_RADIUS_KM / KM_PER_AU / eq.dist)
        return topLimb - horizon.altitudeDeg(atAzimuth: hor.azimuth)
    }

    /// Degrees the GC stands above the skyline, geometric like every other GC
    /// number (ADR-0002 amendment).
    static func gcClearanceDeg(_ observer: Observer, horizon: HorizonProfile, at date: Date) -> Double {
        let p = gcPosition(observer, at: date)
        return p.altitudeDeg - horizon.altitudeDeg(atAzimuth: p.azimuthDeg)
    }

    struct Crossings {
        var above: [TimeWindow] = []
        var rises: [Date] = []
        var sets: [Date] = []
    }

    /// Intervals in [from, to] where `clearance` > 0, with the crossing times.
    static func scanCrossings<E: Error>(
        from: Date, to: Date, _ clearance: (Date) throws(E) -> Double
    ) throws(E) -> Crossings {
        let fromMs = (from.timeIntervalSince1970 * 1000).rounded()
        let toMs = (to.timeIntervalSince1970 * 1000).rounded()
        func date(_ ms: Double) -> Date {
            ms == fromMs ? from : ms == toMs ? to : Date(timeIntervalSince1970: ms / 1000)
        }
        func isUp(_ ms: Double) throws(E) -> Bool { try clearance(date(ms)) > 0 }

        var out = Crossings()
        var t0 = fromMs
        var up0 = try isUp(t0)
        var openedAt: Double? = up0 ? t0 : nil
        while t0 < toMs {
            let t1 = min(t0 + terrainScanMs, toMs)
            let up1 = try isUp(t1)
            if up1 != up0 {
                var lo = t0, hi = t1
                while hi - lo > terrainBisectMs {
                    let mid = ((lo + hi) / 2).rounded(.down)
                    if try isUp(mid) == up1 { hi = mid } else { lo = mid }
                }
                if up1 {
                    openedAt = hi
                    out.rises.append(date(hi))
                } else {
                    out.above.append(TimeWindow(start: date(openedAt ?? fromMs), end: date(hi)))
                    openedAt = nil
                    out.sets.append(date(hi))
                }
            }
            t0 = t1
            up0 = up1
        }
        if let openedAt { out.above.append(TimeWindow(start: date(openedAt), end: to)) }
        return out
    }

    /// Moon above the terrain skyline within [from, to].
    public static func moonUpIntervals(
        _ observer: Observer, horizon: HorizonProfile, from: Date, to: Date
    ) throws(AstronomyError) -> [TimeWindow] {
        try scanCrossings(from: from, to: to) { (d: Date) throws(AstronomyError) in
            try moonClearanceDeg(observer, horizon: horizon, at: d)
        }.above
    }

    /// Moon-free windows cut to the times the GC is above the skyline.
    static func intersect(_ windows: [MoonFreeWindow], _ intervals: [TimeWindow]) -> [MoonFreeWindow] {
        var out: [MoonFreeWindow] = []
        for w in windows {
            for iv in intervals where iv.end > w.start && iv.start < w.end {
                pushWindow(&out, max(w.start, iv.start), min(w.end, iv.end))
            }
        }
        return out
    }

    /// `gcVisibility`, counting only samples where the GC clears the skyline.
    public static func gcVisibility(
        _ observer: Observer, moonFree: [MoonFreeWindow], horizon: HorizonProfile
    ) -> GCVisibility {
        var best: (alt: Double, at: Date)?
        for window in moonFree {
            let startMs = (window.start.timeIntervalSince1970 * 1000).rounded()
            let endMs = (window.end.timeIntervalSince1970 * 1000).rounded()
            var t = startMs
            while true {
                let when = Date(timeIntervalSince1970: min(t, endMs) / 1000)
                let p = gcPosition(observer, at: when)
                if p.altitudeDeg > horizon.altitudeDeg(atAzimuth: p.azimuthDeg),
                   best.map({ p.altitudeDeg > $0.alt }) ?? true {
                    best = (p.altitudeDeg, when)
                }
                if t >= endMs { break }
                t += gcSampleSeconds * 1000
            }
        }
        return GCVisibility(
            maxAltitudeDeg: best.map { jsRound($0.alt * 10) / 10 },
            maxAltitudeAt: best?.at,
            risesDuringDarkness: best != nil)
    }

    /// `planNight` against a terrain skyline. With `horizon == nil` this is
    /// exactly `planNight(_:evening:)`. Otherwise moonrise/moonset are when the
    /// moon's top limb crosses the skyline, the moon-free windows are darkness
    /// with the moon behind terrain or below it, and the GC only counts while
    /// it is above the skyline.
    public static func planNight(
        _ observer: Observer, evening: Date, horizon: HorizonProfile?
    ) throws(AstronomyError) -> NightReport {
        guard let horizon else { return try planNight(observer, evening: evening) }
        let (darkness, noDarkness) = try darknessWindow(observer, evening: evening)
        let midDark = darkness.map {
            AstroTime.jsDate(ms: (($0.start.timeIntervalSince1970 + $0.end.timeIntervalSince1970) * 1000).rounded() / 2)
        } ?? evening

        var moonFree: [MoonFreeWindow] = []
        var moonrise: Date?
        var moonset: Date?
        var terrain = TerrainReport.none
        if let darkness {
            let moon = try scanCrossings(from: darkness.start, to: darkness.end) { (d: Date) throws(AstronomyError) in
                try moonClearanceDeg(observer, horizon: horizon, at: d)
            }
            moonFree = moonFreeWindows(darkness: darkness, moonUp: moon.above)
            moonrise = moon.rises.first
            moonset = moon.sets.first
            let gc = scanCrossings(from: darkness.start, to: darkness.end) { gcClearanceDeg(observer, horizon: horizon, at: $0) }
            let gcWindows = intersect(moonFree, gc.above)
            terrain = TerrainReport(
                gcAboveSkyline: gc.above,
                gcClearsSkyline: gc.rises.first,
                gcDropsBehindSkyline: gc.sets.first,
                gcWindows: gcWindows,
                gcMinutes: max(0, gcWindows.map(\.minutes).max() ?? 0))
        }
        return NightReport(
            darkness: darkness,
            noAstronomicalDarkness: noDarkness,
            moonIllumFraction: jsRound(try moonIllumination(at: midDark) * 1000) / 1000,
            moonset: moonset,
            moonrise: moonrise,
            moonFreeWindows: moonFree,
            moonFreeMinutes: max(0, moonFree.map(\.minutes).max() ?? 0),
            gc: gcVisibility(observer, moonFree: moonFree, horizon: horizon),
            terrain: terrain)
    }
}
