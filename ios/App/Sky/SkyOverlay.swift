import SkyCore
import SwiftUI

/// Everything one overlay frame needs, in view points.
struct SkyOverlayInput {
    let projector: SkyProjector
    let scene: NightSkyScene
    let track: GCTrack
    let horizon: HorizonProfile?
    let style: OverlayStyle
    let timeZone: TimeZone
    var crosshair = false
    /// Stars, figures, trails, radiants and the find target (nil: none drawn).
    var realism: SkyRealismFrame?
    /// The simulated sky is drawn behind (not the camera): the Milky Way
    /// comes from the backdrop, so the overlay skips its band stroke.
    var planetarium = false
    var showsMilkyWayBand = true
}

/// A labelled target the overlay places on screen or points to at the edge.
struct OverlayTarget {
    let object: SkyObject
    let position: HorizontalPosition
    let projection: SkyProjection

    var shortName: String {
        switch object {
        case .galacticCenter: "GC"
        default: object.rawValue.capitalized
        }
    }

    var spokenName: String {
        object == .galacticCenter ? "Galactic Center" : object.rawValue.capitalized
    }

    /// Worth drawing or pointing to: above the mathematical horizon (the GC
    /// and Moon a little below too, since terrain and refraction are close calls).
    var isUp: Bool {
        switch object {
        case .moon, .galacticCenter: position.altitudeDeg > -2
        default: position.altitudeDeg > 0
        }
    }

    var isOnScreen: Bool {
        if case .inFrame = projection { true } else { false }
    }
}

extension SkyOverlayInput {
    var targets: [OverlayTarget] {
        scene.bodies.map { OverlayTarget(object: $0.object, position: $0.position, projection: projector.project($0.position)) }
            .filter(\.isUp)
    }

    /// Radius in points of an angular uncertainty at the principal point.
    func radius(degrees: Double) -> Double {
        projector.intrinsics.fx * tan(min(degrees, 40) * .pi / 180)
    }

    /// The VoiceOver summary: which way the phone faces, how trustworthy
    /// the overlay is, and every target on and off screen.
    var accessibilitySummary: String {
        let bore = projector.boresight
        var parts = ["Facing \(CompassPoint.name(forAzimuth: bore.azimuthDeg)), \(Int(bore.altitudeDeg.rounded()))° up, at \(Self.time(scene.date, timeZone))."]
        switch style {
        case .confident: break
        case .approximate(let u?): parts.append("Positions approximate, compass accuracy ±\(Int(u.rounded()))°.")
        case .approximate(nil): parts.append("Positions approximate, no valid compass heading.")
        }
        let all = targets
        let on = all.filter(\.isOnScreen)
        let off = all.filter { !$0.isOnScreen }
        parts.append(on.isEmpty ? "On screen: no targets." : "On screen: " + on.map(describe).joined(separator: "; ") + ".")
        if !off.isEmpty {
            parts.append("Off screen: " + off.map { "\($0.spokenName) \(turnHint($0))" }.joined(separator: "; ") + ".")
        }
        if milkyWayOnScreen { parts.append("Milky Way band on screen.") }
        if horizon != nil { parts.append("Terrain horizon shown.") }
        if let realism { parts += realismSummary(realism) }
        return parts.joined(separator: " ")
    }

    private var milkyWayOnScreen: Bool {
        scene.milkyWay.contains { point in
            guard point.altitudeDeg > 0, case .inFrame = projector.project(point) else { return false }
            return true
        }
    }

    private func realismSummary(_ r: SkyRealismFrame) -> [String] {
        var parts: [String] = []
        if let find = r.find { parts.insert("Finding \(find.name): \(find.guidance.spoken).", at: 0) }
        if !r.constellationsOnScreen.isEmpty {
            parts.append("Constellations on screen: " + r.constellationsOnScreen.prefix(6).joined(separator: ", ") + ".")
        }
        if !r.namedStarsOnScreen.isEmpty {
            parts.append("Bright stars on screen: " + r.namedStarsOnScreen.prefix(6).joined(separator: ", ") + ".")
        }
        if let t = r.trails { parts.append(Self.trailSummary(t)) }
        for radiant in r.radiants {
            var s = "\(radiant.name) radiant \(Int(radiant.position.altitudeDeg.rounded()))° up in the \(CompassPoint.name(forAzimuth: radiant.position.azimuthDeg))"
            if let rate = radiant.hourlyRate { s += rate > 0 ? ", about \(Int(rate.rounded())) meteors an hour" : ", below the horizon" }
            parts.append(s + ".")
        }
        return parts
    }

    static func trailSummary(_ t: SkyRealismFrame.Trails) -> String {
        let minutes = Int((t.sequence.duration / 60).rounded())
        var s = String(format: "Star trails over %d h %02d min: arcs of %.0f°", minutes / 60, minutes % 60, t.sequence.arcDeg)
        switch t.framing {
        case .inFrame(let x, let y):
            s += String(format: ", celestial pole in frame %d%% across, %d%% down", Int((x * 100).rounded()), Int((y * 100).rounded()))
        case .outsideFrame(let dir), .behindCamera(let dir?):
            s += ", celestial pole off screen to the " + direction(dir)
        case .behindCamera(nil):
            s += ", celestial pole behind you"
        }
        if let d = t.polarisOffsetDeg { s += String(format: "; Polaris %.2f° from the pole", d) }
        return s + "."
    }

    static func direction(_ dir: Double) -> String {
        let (dx, dy) = (cos(dir), sin(dir))
        var words: [String] = []
        if dx > 0.38 { words.append("right") } else if dx < -0.38 { words.append("left") }
        if dy > 0.38 { words.append("bottom") } else if dy < -0.38 { words.append("top") }
        return words.joined(separator: " and ")
    }

    private func describe(_ t: OverlayTarget) -> String {
        var s = "\(t.spokenName) \(Int(t.position.altitudeDeg.rounded()))° up in the \(CompassPoint.name(forAzimuth: t.position.azimuthDeg))"
        if t.object == .moon { s += ", \(Int((scene.moonIllumination * 100).rounded()))% lit" }
        return s
    }

    private func turnHint(_ t: OverlayTarget) -> String {
        guard let dir = projector.screenDirection(toward: t.position) else { return "behind you" }
        let (dx, dy) = (cos(dir), sin(dir))
        var words: [String] = []
        if dx > 0.38 { words.append("right") } else if dx < -0.38 { words.append("left") }
        if dy > 0.38 { words.append("down") } else if dy < -0.38 { words.append("up") }
        let way = words.joined(separator: " and ")
        return t.projection == .behindCamera ? "behind you, turn \(way)" : "to the \(way)"
    }

    static func time(_ date: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return date.formatted(style)
    }

    static func hour(_ date: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = tz
        return date.formatted(style)
    }
}

/// The Night AR drawing: Milky Way band, GC path with hour ticks, targets,
/// cardinal points, the mathematical and terrain horizons, and edge arrows.
struct SkyOverlayView: View {
    let input: SkyOverlayInput
    /// `input.accessibilitySummary`, possibly throttled by the caller.
    let summary: String
    var meter: FrameMeter?
    @Environment(\.palette) var palette

    var isFieldMode: Bool { palette == .field }

    var body: some View {
        Canvas { context, size in
            let start = ContinuousClock.now
            draw(in: &context, size: size)
            let end = ContinuousClock.now
            meter?.recordDraw(end - start, endedAt: end)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Sky overlay")
        .accessibilityValue(summary)
        .accessibilityIdentifier("sky.overlay")
    }

    private var dash: [CGFloat] { input.style.isConfident ? [] : [7, 6] }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let p = input.projector
        if !input.planetarium && input.showsMilkyWayBand { drawMilkyWay(&context, p) }
        if let realism = input.realism { drawRealism(&context, realism, size: size) }
        drawHorizons(&context, p)
        drawCardinals(&context, p)
        drawTrack(&context, p)
        let targets = input.targets
        for t in targets where t.isOnScreen { drawTarget(&context, t) }
        for t in targets where !t.isOnScreen { drawEdgeArrow(&context, t, size: size) }
        if let find = input.realism?.find { drawFind(&context, find, size: size) }
        if input.crosshair { drawCrosshair(&context, p) }
    }

    private func path(_ runs: [[PixelPoint]]) -> Path {
        var path = Path()
        for run in runs {
            path.addLines(run.map { CGPoint(x: $0.u, y: $0.v) })
        }
        return path
    }

    private func drawMilkyWay(_ c: inout GraphicsContext, _ p: SkyProjector) {
        let band = path(p.projectPath(input.scene.milkyWay, closed: true))
        // About 12° wide at the centre of the view; the real band varies from ~10° to 30°.
        let width = input.radius(degrees: 6) * 2
        c.stroke(band, with: .color(palette.primary.opacity(0.10)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        c.stroke(band, with: .color(palette.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
    }

    private func drawHorizons(_ c: inout GraphicsContext, _ p: SkyProjector) {
        let flat = stride(from: 0.0, to: 360, by: 2).map { HorizontalPosition(altitudeDeg: 0, azimuthDeg: $0) }
        c.stroke(path(p.projectPath(flat, closed: true)), with: .color(palette.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: dash))
        if let horizon = input.horizon {
            let skyline = stride(from: 0.0, to: 360, by: 1).map {
                HorizontalPosition(altitudeDeg: horizon.altitudeDeg(atAzimuth: $0), azimuthDeg: $0)
            }
            c.stroke(path(p.projectPath(skyline, closed: true)), with: .color(palette.good), style: StrokeStyle(lineWidth: 2, dash: dash))
        }
    }

    private func drawCardinals(_ c: inout GraphicsContext, _ p: SkyProjector) {
        for az in stride(from: 0.0, to: 360, by: 45) {
            let ground = max(0, input.horizon?.altitudeDeg(atAzimuth: az) ?? 0)
            guard case .inFrame(let base) = p.project(HorizontalPosition(altitudeDeg: ground, azimuthDeg: az)) else { continue }
            let major = az.truncatingRemainder(dividingBy: 90) == 0
            let point = CGPoint(x: base.u, y: base.v)
            var tick = Path()
            tick.move(to: point)
            tick.addLine(to: CGPoint(x: point.x, y: point.y - (major ? 14 : 8)))
            c.stroke(tick, with: .color(palette.secondary), lineWidth: 1.5)
            let text = Text(CompassPoint.abbreviation(forAzimuth: az))
                .font(major ? .headline : .caption).foregroundStyle(palette.secondary)
            c.draw(text, at: CGPoint(x: point.x, y: point.y - (major ? 16 : 10)), anchor: .bottom)
        }
    }

    private func drawTrack(_ c: inout GraphicsContext, _ p: SkyProjector) {
        let color = palette.marginal
        var runs: [(up: Bool, positions: [HorizontalPosition])] = []
        for s in input.track.samples {
            let up = s.position.altitudeDeg >= 0
            if runs.last?.up == up {
                runs[runs.count - 1].positions.append(s.position)
            } else {
                // Share the boundary sample so the solid and faint parts meet.
                let joint = runs.last?.positions.last.map { [$0] } ?? []
                runs.append((up, joint + [s.position]))
            }
        }
        for run in runs {
            let stroke = run.up
                ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash)
                : StrokeStyle(lineWidth: 1, dash: [2, 5])
            c.stroke(path(p.projectPath(run.positions)), with: .color(color.opacity(run.up ? 0.9 : 0.4)), style: stroke)
        }
        let gc = input.scene.position(of: .galacticCenter).flatMap { p.project($0).pixel }
        for tick in input.track.hourTicks where tick.position.altitudeDeg > -2 {
            guard case .inFrame(let px) = p.project(tick.position) else { continue }
            let point = CGPoint(x: px.u, y: px.v)
            c.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
            // The GC marker already says where it is at this hour.
            if let gc, hypot(gc.u - px.u, gc.v - px.v) < 24 { continue }
            c.draw(Text(SkyOverlayInput.hour(tick.date, input.timeZone)).font(.caption2).foregroundStyle(color),
                   at: CGPoint(x: point.x, y: point.y + 6), anchor: .top)
        }
    }

    private func color(for object: SkyObject) -> Color {
        switch object {
        case .galacticCenter: palette.marginal
        case .moon: palette.primary
        default: palette.accent
        }
    }

    private func drawTarget(_ c: inout GraphicsContext, _ t: OverlayTarget) {
        guard let px = t.projection.pixel else { return }
        let center = CGPoint(x: px.u, y: px.v)
        let color = color(for: t.object)
        let r: CGFloat
        switch t.object {
        case .moon:
            r = 11
            c.fill(Path(ellipseIn: rect(center, r)), with: .color(color.opacity(0.15 + 0.5 * input.scene.moonIllumination)))
            c.stroke(Path(ellipseIn: rect(center, r)), with: .color(color), style: StrokeStyle(lineWidth: 2, dash: dash))
        case .galacticCenter:
            r = 10
            c.stroke(Path(ellipseIn: rect(center, r)), with: .color(color), style: StrokeStyle(lineWidth: 2.5, dash: dash))
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - r - 6, y: center.y))
            cross.addLine(to: CGPoint(x: center.x - r + 3, y: center.y))
            cross.move(to: CGPoint(x: center.x + r - 3, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + r + 6, y: center.y))
            c.stroke(cross, with: .color(color), lineWidth: 2)
        default:
            r = 5
            c.fill(Path(ellipseIn: rect(center, 4)), with: .color(color))
            c.stroke(Path(ellipseIn: rect(center, r + 2)), with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: dash))
        }
        if case .approximate(let u?) = input.style {
            let ring = input.radius(degrees: u)
            if ring > r + 4 {
                c.stroke(Path(ellipseIn: rect(center, ring)), with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            }
        }
        var label = "\(t.shortName) \(Int(t.position.altitudeDeg.rounded()))°"
        if t.object == .moon { label += " · \(Int((input.scene.moonIllumination * 100).rounded()))%" }
        if !input.style.isConfident { label += " ≈" }
        c.draw(Text(label).font(.caption.weight(.semibold)).foregroundStyle(color),
               at: CGPoint(x: center.x + r + 6, y: center.y - r - 2), anchor: .bottomLeading)
    }

    private func drawEdgeArrow(_ c: inout GraphicsContext, _ t: OverlayTarget, size: CGSize) {
        let p = input.projector
        guard let dir = p.screenDirection(toward: t.position) else { return }
        let origin = PixelPoint(u: p.intrinsics.cx, v: p.intrinsics.cy)
        let edge = EdgeMarker.point(from: origin, direction: dir, width: size.width, height: size.height, inset: 26)
        let tip = CGPoint(x: edge.u, y: edge.v)
        let color = color(for: t.object)
        // A stemmed arrow reads as a direction at any angle; a bare narrow triangle does not.
        let back = CGPoint(x: tip.x - 22 * cos(dir), y: tip.y - 22 * sin(dir))
        var arrow = Path()
        arrow.move(to: back)
        arrow.addLine(to: tip)
        for side in [-0.6, 0.6] {
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - 11 * cos(dir + side), y: tip.y - 11 * sin(dir + side)))
        }
        c.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        // Label on the inward side of the arrow.
        let inward = CGPoint(x: tip.x - 30 * cos(dir), y: tip.y - 30 * sin(dir) + (abs(cos(dir)) > 0.3 ? 0 : -14 * sin(dir)))
        let anchor: UnitPoint = cos(dir) > 0.3 ? .trailing : cos(dir) < -0.3 ? .leading : .center
        c.draw(Text(t.shortName).font(.caption.weight(.semibold)).foregroundStyle(color), at: inward, anchor: anchor)
    }

    private func drawCrosshair(_ c: inout GraphicsContext, _ p: SkyProjector) {
        let center = CGPoint(x: p.intrinsics.cx, y: p.intrinsics.cy)
        var cross = Path()
        for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
            cross.move(to: CGPoint(x: center.x + dx * 8, y: center.y + dy * 8))
            cross.addLine(to: CGPoint(x: center.x + dx * 30, y: center.y + dy * 30))
        }
        c.stroke(cross, with: .color(palette.primary), lineWidth: 2)
        c.stroke(Path(ellipseIn: rect(center, 4)), with: .color(palette.primary), lineWidth: 1.5)
    }

    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }
}
