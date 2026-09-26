public import Foundation
import CAstronomy

public struct HorizonEvent: Sendable, Hashable, Codable {
    public let date: Date
    public let position: HorizontalPosition
}

/// The first rise, upper transit and set of an object in a search window,
/// each with where it happens (for map azimuth lines and AR ticks).
public struct RiseSetTransit: Sendable, Hashable, Codable {
    public let rise: HorizonEvent?
    public let transit: HorizonEvent?
    public let set: HorizonEvent?
}

extension SkyPositions {
    /// Sun, Moon and planets use astronomy-engine's rise/set (top limb,
    /// standard refraction) and hour-angle searches; positions are apparent.
    /// The GC (a fixed point the library has no rise/set for) rises and sets
    /// when `Planner.gcPosition` crosses 0°, the web planner's convention.
    public static func riseSetTransit(
        of object: SkyObject, observer: Observer, from start: Date, limitDays: Double = 1
    ) throws(AstronomyError) -> RiseSetTransit {
        precondition(limitDays > 0, "limitDays must be positive")
        let end = start.addingTimeInterval(limitDays * 86_400)
        guard let body = object.body else {
            return gcRiseSetTransit(observer: observer, from: start, to: end)
        }

        func riseOrSet(_ direction: astro_direction_t) throws(AstronomyError) -> HorizonEvent? {
            let found = try searchResult(
                Astronomy_SearchRiseSetEx(body, observer.c, direction, AstroTime.from(start), limitDays, 0),
                "SearchRiseSet")
            guard let found else { return nil }
            return HorizonEvent(date: found, position: try bodyPosition(body, at: found, observer: observer, refraction: .normal))
        }

        let ha = Astronomy_SearchHourAngleEx(body, observer.c, 0, AstroTime.from(start), 1)
        try check(ha.status, "SearchHourAngle")
        let transitDate = AstroTime.date(ha.time)
        let transit = transitDate <= end
            ? HorizonEvent(date: transitDate, position: HorizontalPosition(altitudeDeg: ha.hor.altitude, azimuthDeg: ha.hor.azimuth))
            : nil

        return RiseSetTransit(rise: try riseOrSet(DIRECTION_RISE), transit: transit, set: try riseOrSet(DIRECTION_SET))
    }

    private static func gcRiseSetTransit(observer: Observer, from start: Date, to end: Date) -> RiseSetTransit {
        let altitude = { (d: Date) in Planner.gcPosition(observer, at: d).altitudeDeg }
        let hourAngle = { (d: Date) -> Double in
            var time = AstroTime.from(d)
            var h = Astronomy_SiderealTime(&time) + observer.longitude / 15 - Planner.gcEquatorOfDate(at: d).raHours
            h = h.truncatingRemainder(dividingBy: 24)
            if h > 12 { h -= 24 } else if h <= -12 { h += 24 }
            return h
        }
        func event(_ date: Date?) -> HorizonEvent? {
            date.map { HorizonEvent(date: $0, position: Planner.gcPosition(observer, at: $0)) }
        }
        return RiseSetTransit(
            rise: event(firstCrossing(of: altitude, rising: true, from: start, to: end)),
            transit: event(firstCrossing(of: hourAngle, rising: true, from: start, to: end)),
            set: event(firstCrossing(of: altitude, rising: false, from: start, to: end)))
    }

    /// First time `f` crosses zero in the given direction: 10-minute scan,
    /// then bisection to 0.1 s (the tolerance astronomy-engine searches use).
    static func firstCrossing(
        of f: (Date) -> Double, rising: Bool, from start: Date, to end: Date
    ) -> Date? {
        let step: TimeInterval = 600
        var t0 = start
        var f0 = f(t0)
        while t0 < end {
            let t1 = min(t0.addingTimeInterval(step), end)
            let f1 = f(t1)
            if rising ? (f0 < 0 && f1 >= 0) : (f0 >= 0 && f1 < 0) {
                var lo = t0, hi = t1
                while hi.timeIntervalSince(lo) > 0.1 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    if (f(mid) < 0) == rising { lo = mid } else { hi = mid }
                }
                return hi
            }
            t0 = t1
            f0 = f1
        }
        return nil
    }
}
