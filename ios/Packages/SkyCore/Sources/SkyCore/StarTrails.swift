public import Foundation
import CAstronomy

/// A star-trail capture: `frames` exposures of `exposure` seconds, one
/// every `interval` seconds (shutter-release to shutter-release, as in
/// `Timelapse`). The Sky view previews it; the capture flow runs it.
public struct StarTrailSequence: Sendable, Hashable, Codable {
    public let start: Date
    public let exposure: TimeInterval
    public let interval: TimeInterval
    public let frames: Int

    public init(start: Date, exposure: TimeInterval, interval: TimeInterval, frames: Int) throws(ExposureError) {
        let t = try requirePositive(.exposure, exposure)
        let i = try requirePositive(.interval, interval)
        guard i >= t else { throw .intervalTooShort(intervalSeconds: i, minimumSeconds: t) }
        guard frames >= 1 else { throw .invalid(.frames, Double(frames)) }
        self.start = start
        self.exposure = t
        self.interval = i
        self.frames = frames
    }

    /// As many frames as fit in `duration` (from the first shutter opening to the last closing).
    public init(start: Date, duration: TimeInterval, exposure: TimeInterval, interval: TimeInterval) throws(ExposureError) {
        let d = try requirePositive(.eventDuration, duration)
        let t = try requirePositive(.exposure, exposure)
        guard d >= t else { throw .invalid(.eventDuration, d) }
        try self.init(start: start, exposure: t, interval: interval, frames: Int(floorTolerant((d - t) / interval)) + 1)
    }

    /// From an M10 timelapse plan: its exposure, interval and frame count.
    public init(start: Date, timelapse plan: TimelapsePlan) throws(ExposureError) {
        try self.init(start: start, exposure: plan.exposure, interval: plan.interval, frames: plan.frames)
    }

    /// First shutter opening to last shutter closing.
    public var duration: TimeInterval { Double(frames - 1) * interval + exposure }
    public var end: Date { start.addingTimeInterval(duration) }
    /// Share of each interval with the shutter closed: the gaps a stacked
    /// trail shows. 0 is continuous.
    public var gapFraction: Double { 1 - exposure / interval }
    /// How far every star turns about the pole over the sequence, degrees.
    public var arcDeg: Double { StarTrails.siderealDegreesPerSecond * duration }
}

/// Where the celestial pole falls in the frame, for a circular composition.
public enum PoleFraming: Sendable, Hashable {
    /// Fractions of the view's width and height from its top-left corner.
    case inFrame(x: Double, y: Double)
    /// In front of the camera but outside the view; the edge-arrow direction
    /// (radians, 0 = right, π/2 = down) from the view's centre.
    case outsideFrame(direction: Double)
    case behindCamera(direction: Double?)
}

public enum StarTrails {
    /// Earth's rotation relative to the stars: 360° per sidereal day
    /// (86164.0905 s; IERS Conventions 2010), 15.041″ a second.
    public static let siderealDegreesPerSecond = 360 / 86164.0905

    /// The celestial pole of date above this observer's horizon (the north
    /// pole unless the observer is south of the equator), as a
    /// reference-frame vector, refracted like the stars around it.
    public static func poleReferenceVector(at date: Date, observer: Observer) -> SIMD3<Double> {
        var time = AstroTime.from(date)
        let eqdToRef = RotationMatrix(Astronomy_Rotation_EQD_HOR(&time, observer.c))
        let pole = SIMD3<Double>(0, 0, observer.latitude >= 0 ? 1 : -1)
        return SkyRotation.refracted(eqdToRef * pole)
    }

    public static func pole(at date: Date, observer: Observer) -> HorizontalPosition {
        HorizontalPosition(reference: poleReferenceVector(at: date, observer: observer))
    }

    /// Angle between a star's apparent place and the true celestial pole of
    /// date, degrees: 90° − |apparent declination|. Polaris: about 0.63° in 2026.
    public static func distanceFromPoleDeg(ofStarAt index: Int, in field: StarField, at date: Date) -> Double {
        90 - abs(field.equatorOfDate(ofStarAt: index, at: date).decDeg)
    }

    /// Where the pole sits for this projector (`SkyProjector.project`).
    public static func framing(of pole: HorizontalPosition, projector: SkyProjector) -> PoleFraming {
        let k = projector.intrinsics
        switch projector.project(pole) {
        case .inFrame(let p):
            return .inFrame(x: p.u / k.width, y: p.v / k.height)
        case .outsideFrame:
            return .outsideFrame(direction: projector.screenDirection(toward: pole) ?? 0)
        case .behindCamera:
            return .behindCamera(direction: projector.screenDirection(toward: pole))
        }
    }
}

/// Precomputed trail arcs for one sequence: each chosen star's apparent,
/// refracted reference-frame direction at evenly spaced times across it.
/// They depend on the place and times only, so a frame just projects them.
public struct StarTrailPreview: Sendable {
    public let sequence: StarTrailSequence
    public let pole: HorizontalPosition
    /// Catalogue index and the arc's reference-frame vectors, start to end.
    public let arcs: [(index: Int, points: [SIMD3<Double>])]

    /// Arcs for stars brighter than `magnitudeLimit` that are above the
    /// horizon at some point in the sequence, one point per `stepDeg` of turn.
    public init(sequence: StarTrailSequence, field: StarField, observer: Observer, magnitudeLimit: Double, stepDeg: Double = 1.5) {
        self.sequence = sequence
        pole = StarTrails.pole(at: sequence.start, observer: observer)
        let steps = max(2, min(240, Int((sequence.arcDeg / stepDeg).rounded(.up)) + 1))
        let rotations = (0..<steps).map { i in
            SkyRotation.eqjToReference(
                at: sequence.start.addingTimeInterval(sequence.duration * Double(i) / Double(steps - 1)), observer: observer)
        }
        var arcs: [(Int, [SIMD3<Double>])] = []
        for i in field.byBrightness {
            if field.catalog.stars[i].vmag > magnitudeLimit { break }
            let points = rotations.map { SkyRotation.refracted($0 * field.apparentEQJ[i]) }
            if points.contains(where: { $0.z > 0 }) { arcs.append((i, points)) }
        }
        self.arcs = arcs
    }
}
