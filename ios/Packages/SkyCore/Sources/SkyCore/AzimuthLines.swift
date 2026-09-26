public import Foundation

/// One map planner line: from the pin along the object's azimuth.
public struct AzimuthLine: Sendable, Hashable, Codable {
    public enum Event: String, Sendable, Hashable, Codable, CaseIterable {
        case rise, transit, set
        /// The scrubber's chosen time.
        case atTime
    }

    public let object: SkyObject
    public let event: Event
    public let date: Date
    /// Where the object is at `date`. Its azimuth is the line's bearing, and
    /// a negative altitude on an `atTime` line means below the horizon.
    public let position: HorizontalPosition
    public let start: GeoCoordinate
    /// `lengthMeters` along the WGS84 geodesic.
    public let end: GeoCoordinate
    public let lengthMeters: Double

    /// Degrees clockwise from true north: the initial azimuth of the geodesic at `start`.
    public var bearingDeg: Double { position.azimuthDeg }
}

public enum AzimuthLines {
    /// What the map draws lines for (PLAN.md §M6).
    public static let mapObjects: [SkyObject] = [.sun, .moon, .galacticCenter]

    public static func line(
        object: SkyObject, event: AzimuthLine.Event, date: Date, position: HorizontalPosition,
        from pin: GeoCoordinate, lengthMeters: Double
    ) -> AzimuthLine {
        let end = Geodesy.direct(from: pin, azimuthDeg: position.azimuthDeg, distanceMeters: lengthMeters).end
        return AzimuthLine(
            object: object, event: event, date: date, position: position,
            start: pin, end: end, lengthMeters: lengthMeters)
    }

    /// Rise, transit and set lines, for the events that exist.
    public static func lines(
        object: SkyObject, events: RiseSetTransit, from pin: GeoCoordinate, lengthMeters: Double
    ) -> [AzimuthLine] {
        let pairs: [(AzimuthLine.Event, HorizonEvent?)] = [(.rise, events.rise), (.transit, events.transit), (.set, events.set)]
        return pairs.compactMap { kind, event in
            event.map { line(object: object, event: kind, date: $0.date, position: $0.position, from: pin, lengthMeters: lengthMeters) }
        }
    }

    /// An `atTime` line from a precomputed alt/az series (the scrubber's
    /// path); nil when `date` is outside the series.
    public static func line(
        object: SkyObject, series: [SkySample], at date: Date, from pin: GeoCoordinate, lengthMeters: Double
    ) -> AzimuthLine? {
        SkyPositions.interpolated(series, at: date).map {
            line(object: object, event: .atTime, date: date, position: $0, from: pin, lengthMeters: lengthMeters)
        }
    }

    /// Every map line for a pin: rise/transit/set within `limitDays` of
    /// `eventsFrom`, plus an exact `atTime` line per object when `time` is
    /// given. Positions are apparent (standard refraction), as seen in the field.
    public static func plan(
        pin: Observer, objects: [SkyObject] = mapObjects, eventsFrom start: Date, limitDays: Double = 1,
        at time: Date?, lengthMeters: Double
    ) throws(AstronomyError) -> [AzimuthLine] {
        var out: [AzimuthLine] = []
        for object in objects {
            let events = try SkyPositions.riseSetTransit(of: object, observer: pin, from: start, limitDays: limitDays)
            out += lines(object: object, events: events, from: pin.coordinate, lengthMeters: lengthMeters)
            if let time {
                let position = try SkyPositions.position(of: object, at: time, observer: pin, refraction: .normal)
                out.append(line(object: object, event: .atTime, date: time, position: position, from: pin.coordinate, lengthMeters: lengthMeters))
            }
        }
        return out
    }
}
