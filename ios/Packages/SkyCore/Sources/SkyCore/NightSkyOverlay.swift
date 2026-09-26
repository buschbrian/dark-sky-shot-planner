public import Foundation

// Pure pieces of the Night AR overlay (M7): what to draw for a place and time,
// how confident to look, and where off-screen markers sit. Frames and the
// projection itself are in SkyFrames.swift and SkyProjection.swift.

extension DeviceAttitude {
    /// Portrait, held upright with no roll, the back camera facing
    /// `azimuthDeg` and tilted up by `pitchDeg`. The fixed attitude of the
    /// simulated view, and a readable way to write test attitudes.
    public static func upright(facingAzimuth azimuthDeg: Double, pitchDeg: Double) -> DeviceAttitude {
        DeviceAttitude(
            deviceX: HorizontalPosition(altitudeDeg: 0, azimuthDeg: azimuthDeg + 90),
            deviceY: HorizontalPosition(altitudeDeg: 90 - pitchDeg, azimuthDeg: azimuthDeg + 180),
            deviceZ: HorizontalPosition(altitudeDeg: -pitchDeg, azimuthDeg: azimuthDeg + 180))
    }
}

/// How the overlay draws itself for a heading confidence. A manual
/// calibration makes a poor compass trustworthy again; an invalid heading
/// (negative accuracy) never is, because the sensor fusion is drifting.
public enum OverlayStyle: Sendable, Hashable {
    case confident
    /// Dashed, with an uncertainty ring of this radius in degrees (nil: unknown).
    case approximate(uncertaintyDeg: Double?)

    public init(heading: HeadingConfidence, calibrated: Bool) {
        switch heading {
        case .confident: self = .confident
        case .poor(let accuracy): self = calibrated ? .confident : .approximate(uncertaintyDeg: accuracy)
        case .unavailable: self = .approximate(uncertaintyDeg: nil)
        }
    }

    public var isConfident: Bool { self == .confident }
}

public enum CompassPoint {
    static let abbreviations = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    static let names = [
        "north", "north-northeast", "northeast", "east-northeast", "east", "east-southeast", "southeast", "south-southeast",
        "south", "south-southwest", "southwest", "west-southwest", "west", "west-northwest", "northwest", "north-northwest",
    ]

    /// The 16-wind point nearest `azimuthDeg` ("SSW").
    public static func abbreviation(forAzimuth azimuthDeg: Double) -> String { abbreviations[index(azimuthDeg)] }

    /// Spelled out for VoiceOver ("south-southwest").
    public static func name(forAzimuth azimuthDeg: Double) -> String { names[index(azimuthDeg)] }

    static func index(_ azimuthDeg: Double) -> Int {
        Int((Geodesy.normalizedAzimuth(azimuthDeg) / 22.5).rounded()) % 16
    }
}

public enum EdgeMarker {
    /// Where the ray from `origin` at `direction` (radians, 0 = +u, π/2 = +v,
    /// as `SkyProjector.screenDirection` returns) leaves the rectangle
    /// inset by `inset` from a `width` × `height` view. The origin is clamped
    /// into that rectangle first.
    public static func point(
        from origin: PixelPoint, direction: Double, width: Double, height: Double, inset: Double
    ) -> PixelPoint {
        let minU = min(inset, width / 2), maxU = max(width - inset, width / 2)
        let minV = min(inset, height / 2), maxV = max(height - inset, height / 2)
        let u0 = min(max(origin.u, minU), maxU), v0 = min(max(origin.v, minV), maxV)
        let du = cos(direction), dv = sin(direction)
        var t = Double.infinity
        if du > 1e-12 { t = min(t, (maxU - u0) / du) }
        if du < -1e-12 { t = min(t, (minU - u0) / du) }
        if dv > 1e-12 { t = min(t, (maxV - v0) / dv) }
        if dv < -1e-12 { t = min(t, (minV - v0) / dv) }
        guard t.isFinite else { return PixelPoint(u: u0, v: v0) }
        return PixelPoint(u: min(max(u0 + du * t, minU), maxU), v: min(max(v0 + dv * t, minV), maxV))
    }
}

/// Apparent sky positions (standard refraction, where the camera sees them)
/// for one instant: the Moon, the planets and the GC, and the Milky Way's
/// mid-plane as a closed loop.
public struct NightSkyScene: Sendable, Hashable {
    public struct Body: Sendable, Hashable {
        public let object: SkyObject
        public let position: HorizontalPosition
    }

    public static let objects: [SkyObject] = [.moon, .galacticCenter] + SkyObject.planets

    public let date: Date
    /// In `objects` order.
    public let bodies: [Body]
    public let moonIllumination: Double
    public let milkyWay: [HorizontalPosition]

    public static func at(
        _ date: Date, observer: Observer, bandStepDeg: Double = 3
    ) throws(AstronomyError) -> NightSkyScene {
        var bodies: [Body] = []
        for object in objects {
            bodies.append(Body(object: object, position: try SkyPositions.position(of: object, at: date, observer: observer, refraction: .normal)))
        }
        let band = try SkyPositions.milkyWayBand(at: date, observer: observer, stepDeg: bandStepDeg, refraction: .normal)
        return NightSkyScene(
            date: date, bodies: bodies,
            moonIllumination: try Planner.moonIllumination(at: date),
            milkyWay: band.map(\.position))
    }

    public func position(of object: SkyObject) -> HorizontalPosition? {
        bodies.first { $0.object == object }?.position
    }
}

/// The GC's apparent path across a night, with ticks on the whole hours.
public struct GCTrack: Sendable, Hashable {
    public let window: TimeWindow
    public let samples: [SkySample]
    /// Whole hours strictly inside the window (`TimeScrubber` with a 1 h step).
    public let hourTicks: [SkySample]

    public static func across(
        _ window: TimeWindow, observer: Observer, step: TimeInterval = 600
    ) throws(AstronomyError) -> GCTrack {
        var samples = try SkyPositions.series(
            of: .galacticCenter, from: window.start, to: window.end, step: step, observer: observer, refraction: .normal)
        if let last = samples.last, last.date < window.end {
            samples.append(SkySample(date: window.end, position: try gcPosition(window.end, observer)))
        }
        var ticks: [SkySample] = []
        for t in TimeScrubber.times(across: window, step: 3600).dropFirst().dropLast() {
            ticks.append(SkySample(date: t, position: try gcPosition(t, observer)))
        }
        return GCTrack(window: window, samples: samples, hourTicks: ticks)
    }

    private static func gcPosition(_ date: Date, _ observer: Observer) throws(AstronomyError) -> HorizontalPosition {
        try SkyPositions.position(of: .galacticCenter, at: date, observer: observer, refraction: .normal)
    }
}

extension Planner {
    /// The span the Sky screen scrubs across for a night: astronomical
    /// darkness, or 21:00–06:00 local when the Sun never gets 18° down.
    public static func skyNightWindow(
        _ observer: Observer, night: NightDate, timeZone: TimeZone
    ) throws(AstronomyError) -> TimeWindow {
        let evening = night.evening(in: timeZone)
        if let dark = try darknessWindow(observer, evening: evening).window { return dark }
        return TimeWindow(start: evening, end: evening.addingTimeInterval(9 * 3600))
    }
}
