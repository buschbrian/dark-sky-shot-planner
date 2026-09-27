public import Foundation

/// How to move the phone to bring a target to the middle of the view: the
/// "find" flow's arrow and its spoken words.
public struct SkyGuidance: Sendable, Hashable {
    /// Angle between where the camera points and the target, degrees.
    public let separationDeg: Double
    /// Azimuth change, degrees in (−180, 180]: positive means turn right (clockwise from above).
    public let turnDeg: Double
    /// Altitude change: positive means tilt up.
    public let tiltDeg: Double
    public let isOnScreen: Bool
    /// Screen direction of the edge arrow (radians, 0 = right, π/2 = down); nil straight ahead.
    public let arrowDirection: Double?

    /// Close enough to call "centred" (the target is near the crosshair).
    public static let centredDeg = 3.0

    public init(target: HorizontalPosition, projector: SkyProjector) {
        let bore = projector.boresight
        separationDeg = SkyBrightness.angularSeparationDeg(bore, target)
        turnDeg = Geodesy.signedAngle(target.azimuthDeg - bore.azimuthDeg)
        tiltDeg = target.altitudeDeg - bore.altitudeDeg
        if case .inFrame = projector.project(target) { isOnScreen = true } else { isOnScreen = false }
        arrowDirection = projector.screenDirection(toward: target)
    }

    /// "In view, centred", or "turn right 40°, tilt up 10°". Pointing near
    /// the zenith makes azimuth meaningless, so only the tilt is given there.
    public var spoken: String {
        if separationDeg <= Self.centredDeg { return "centred" }
        var parts: [String] = []
        let turn = Int(abs(turnDeg).rounded()), tilt = Int(abs(tiltDeg).rounded())
        if turn >= 2 && separationDeg > 5 { parts.append("turn \(turnDeg > 0 ? "right" : "left") \(turn)°") }
        if tilt >= 2 { parts.append("tilt \(tiltDeg > 0 ? "up" : "down") \(tilt)°") }
        let move = parts.isEmpty ? "nearly centred" : parts.joined(separator: ", ")
        return isOnScreen ? "in view, \(move)" : move
    }
}
