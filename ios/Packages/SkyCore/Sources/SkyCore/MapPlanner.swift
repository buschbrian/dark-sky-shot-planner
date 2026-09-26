public import Foundation

/// One planner line as the map draws it: the densified geodesic and its label.
public struct MapLineFeature: Sendable, Hashable {
    public let line: AzimuthLine
    /// Pin first, `line.end` last; each vertex lies on the geodesic at `line.bearingDeg`.
    public let coordinates: [GeoCoordinate]

    public var labelCoordinate: GeoCoordinate { coordinates[coordinates.count - 1] }
    /// An at-time line for an object below the horizon at that time.
    public var belowHorizon: Bool { line.event == .atTime && line.position.altitudeDeg < 0 }
}

/// Everything the map planner needs for one pin and one night, computed once;
/// lines are then rebuilt cheaply as the zoom or the scrubber time changes.
public struct MapPlan: Sendable, Hashable {
    public let pin: Observer
    /// The scrubber's range: sunset − 30 min to sunrise + 30 min.
    public let window: TimeWindow
    public let events: [SkyObject: RiseSetTransit]
    /// Apparent alt/az every `MapPlanner.seriesStep` across `window`.
    public let series: [SkyObject: [SkySample]]

    /// Rise/transit/set lines for every object, plus an at-time line per
    /// object when `time` falls inside the window.
    public func lines(at time: Date?, lengthMeters: Double) -> [AzimuthLine] {
        var out: [AzimuthLine] = []
        for object in AzimuthLines.mapObjects {
            if let e = events[object] {
                out += AzimuthLines.lines(object: object, events: e, from: pin.coordinate, lengthMeters: lengthMeters)
            }
            if let time, let s = series[object],
               let at = AzimuthLines.line(object: object, series: s, at: time, from: pin.coordinate, lengthMeters: lengthMeters) {
                out.append(at)
            }
        }
        return out
    }
}

public enum MapPlanner {
    /// MapLibre joins vertices with straight Web Mercator chords; 2 km keeps
    /// a chord within centimetres of the geodesic at Mountain West latitudes.
    public static let maxSegmentMeters = 2_000.0
    static let maxSegments = 256
    public static let seriesStep: TimeInterval = 5 * 60
    static let windowPadding: TimeInterval = 30 * 60

    /// The night of `night` at `pin`: rise/transit/set from local noon for a
    /// day, and alt/az series across sunset − 30 min … sunrise + 30 min.
    public static func plan(pin: Observer, night: NightDate, timeZone: TimeZone) throws(AstronomyError) -> MapPlan {
        let noon = night.evening(in: timeZone).addingTimeInterval(-9 * 3600)
        var events: [SkyObject: RiseSetTransit] = [:]
        for object in AzimuthLines.mapObjects {
            events[object] = try SkyPositions.riseSetTransit(of: object, observer: pin, from: noon, limitDays: 1)
        }
        var window = TimeWindow(start: noon.addingTimeInterval(6 * 3600), end: noon.addingTimeInterval(18 * 3600))
        if let sunset = events[.sun]?.set?.date,
           let sunrise = try SkyPositions.riseSetTransit(of: .sun, observer: pin, from: sunset, limitDays: 1).rise?.date {
            window = TimeWindow(start: sunset.addingTimeInterval(-windowPadding), end: sunrise.addingTimeInterval(windowPadding))
        }
        var series: [SkyObject: [SkySample]] = [:]
        for object in AzimuthLines.mapObjects {
            var s = try SkyPositions.series(
                of: object, from: window.start, to: window.end, step: seriesStep, observer: pin, refraction: .normal)
            if let last = s.last, last.date < window.end {
                s.append(SkySample(date: window.end, position: try SkyPositions.position(
                    of: object, at: window.end, observer: pin, refraction: .normal)))
            }
            series[object] = s
        }
        return MapPlan(pin: pin, window: window, events: events, series: series)
    }

    /// The line's geodesic as map vertices, at most `maxSegmentMeters` apart.
    public static func feature(_ line: AzimuthLine, maxSegmentMeters: Double = maxSegmentMeters) -> MapLineFeature {
        let n = min(maxSegments, max(1, Int((line.lengthMeters / maxSegmentMeters).rounded(.up))))
        let coords = Geodesy.path(from: line.start, azimuthDeg: line.bearingDeg, distanceMeters: line.lengthMeters, segments: n)
        return MapLineFeature(line: line, coordinates: coords)
    }

    public static func features(_ lines: [AzimuthLine]) -> [MapLineFeature] {
        lines.map { feature($0) }
    }

    /// Ground metres per screen point at a MapLibre zoom (512-point world).
    public static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        2 * .pi * Geodesy.wgs84SemiMajorAxisMeters * cos(latitude * .pi / 180) / (512 * pow(2, zoom))
    }

    /// A line that reaches `fraction` of the viewport's shorter side, so its
    /// end label stays on screen at any zoom. Clamped to 100 m … 600 km.
    public static func lineLengthMeters(
        zoom: Double, latitude: Double, viewportShortSidePoints: Double, fraction: Double = 0.42
    ) -> Double {
        let m = metersPerPoint(zoom: zoom, latitude: latitude) * viewportShortSidePoints * fraction
        return min(600_000, max(100, m))
    }

    /// "Sun set 19:24 · 293°", "Moon 23:40 · 118° · 12° up", "GC 04:10 · 205° · below horizon".
    public static func label(for line: AzimuthLine, timeZone: TimeZone) -> String {
        let az = "\(Int(Geodesy.normalizedAzimuth(line.bearingDeg.rounded())))°"
        let time = clock(line.date, timeZone: timeZone)
        switch line.event {
        case .rise, .set, .transit:
            return "\(name(line.object)) \(line.event.rawValue) \(time) · \(az)"
        case .atTime:
            let alt = line.position.altitudeDeg
            let where_ = alt < 0 ? "below horizon" : "\(Int(alt.rounded()))° up"
            return "\(name(line.object)) \(time) · \(az) · \(where_)"
        }
    }

    public static func name(_ object: SkyObject) -> String {
        switch object {
        case .sun: "Sun"
        case .moon: "Moon"
        case .galacticCenter: "GC"
        default: object.rawValue.capitalized
        }
    }

    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
