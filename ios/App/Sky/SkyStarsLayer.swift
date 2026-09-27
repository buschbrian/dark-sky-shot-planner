import SkyCore
import SwiftUI

/// Drawing for `SkyRealismFrame`: stars batched into a few paths by size and
/// colour (one fill each, not one per star), constellation figures, labels,
/// star trails around the pole, meteor radiants and the find highlight.
extension SkyOverlayView {
    func drawRealism(_ c: inout GraphicsContext, _ r: SkyRealismFrame, size: CGSize) {
        if let trails = r.trails { drawTrails(&c, trails, scale: r.starScale) }
        drawFigures(&c, r)
        drawStars(&c, r)
        drawLabels(&c, r)
        for radiant in r.radiants { drawRadiant(&c, radiant) }
        if let trails = r.trails { drawPole(&c, trails) }
    }

    /// Radius in points for an apparent magnitude: fixed by magnitude, so a
    /// brighter sky removes faint stars instead of shrinking every star.
    static func starRadius(_ m: Double, scale: Double) -> Double {
        min(max(0.55 + 0.42 * (6.5 - m), 0.55), 4.4) * scale
    }

    func starColor(_ bucket: UInt8) -> Color {
        if isFieldMode { return palette.accent }
        let (r, g, b) = SkyStarColors.rgb[Int(bucket)]
        return Color(red: r, green: g, blue: b)
    }

    private func drawStars(_ c: inout GraphicsContext, _ r: SkyRealismFrame) {
        guard !r.stars.isEmpty else { return }
        // 9 size steps × 7 colours at most; alpha fades stars near the limit.
        var paths: [Int: Path] = [:]
        var glow = Path()
        for s in r.stars {
            let step = min(max(Int(((s.magnitude + 1.5) * 1.0).rounded(.down)), 0), 8)
            let fade = min(max((r.limitingMagnitude - s.magnitude) / 1.5, 0.2), 1)
            let alphaStep = Int((fade * 3).rounded())
            let key = (step * 8 + Int(isFieldMode ? 0 : s.color)) * 4 + alphaStep
            let radius = Self.starRadius(s.magnitude, scale: r.starScale)
            paths[key, default: Path()].addEllipse(in: CGRect(x: s.point.x - radius, y: s.point.y - radius, width: 2 * radius, height: 2 * radius))
            if s.magnitude < 1.2 {
                let g = radius * 2.6
                glow.addEllipse(in: CGRect(x: s.point.x - g, y: s.point.y - g, width: 2 * g, height: 2 * g))
            }
        }
        c.fill(glow, with: .color((isFieldMode ? palette.accent : .white).opacity(0.12)))
        for (key, path) in paths {
            let alpha = Double(key % 4) / 3
            let bucket = UInt8((key / 4) % 8)
            c.fill(path, with: .color(starColor(bucket).opacity(max(alpha, 0.25) * (input.planetarium ? 1 : 0.8))))
        }
    }

    private func drawFigures(_ c: inout GraphicsContext, _ r: SkyRealismFrame) {
        var normal = Path()
        for figure in r.figures where !figure.highlighted {
            for run in figure.runs { normal.addLines(run) }
        }
        let lineColor = isFieldMode ? palette.secondary : Color(red: 0.55, green: 0.70, blue: 1.0)
        c.stroke(normal, with: .color(lineColor.opacity(input.planetarium ? 0.45 : 0.6)), lineWidth: 1)
        for figure in r.figures where figure.highlighted {
            var p = Path()
            for run in figure.runs { p.addLines(run) }
            c.stroke(p, with: .color(palette.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawLabels(_ c: inout GraphicsContext, _ r: SkyRealismFrame) {
        let constellation = isFieldMode ? palette.secondary : Color(red: 0.62, green: 0.74, blue: 1.0)
        for label in r.labels {
            let color = label.highlighted ? palette.accent : (label.isConstellation ? constellation.opacity(0.85) : palette.primary.opacity(0.85))
            let text = Text(label.text)
                .font(label.isConstellation ? .caption2.weight(.semibold) : .caption2)
                .tracking(label.isConstellation ? 1.5 : 0)
                .foregroundStyle(color)
            c.draw(text, at: label.point, anchor: label.isConstellation ? .center : .topLeading)
        }
    }

    private func drawTrails(_ c: inout GraphicsContext, _ t: SkyRealismFrame.Trails, scale: Double) {
        // A handful of strokes: group arcs by brightness and colour.
        var groups: [Int: Path] = [:]
        for arc in t.runs {
            let step = min(max(Int((arc.magnitude + 1.5).rounded(.down)), 0), 6)
            let key = step * 8 + Int(isFieldMode ? 0 : arc.color)
            for run in arc.runs { groups[key, default: Path()].addLines(run) }
        }
        for (key, path) in groups {
            let step = Double(key / 8)
            let width = max(0.8, (2.8 - 0.3 * step) * scale)
            c.stroke(path, with: .color(starColor(UInt8(key % 8)).opacity(max(0.45, 0.95 - 0.08 * step))),
                     style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: t.sequence.gapFraction > 0.15 ? [6, 2] : []))
        }
    }

    private func drawPole(_ c: inout GraphicsContext, _ t: SkyRealismFrame.Trails) {
        let color = palette.marginal
        if let pole = t.pole {
            var cross = Path()
            cross.move(to: CGPoint(x: pole.x - 9, y: pole.y))
            cross.addLine(to: CGPoint(x: pole.x + 9, y: pole.y))
            cross.move(to: CGPoint(x: pole.x, y: pole.y - 9))
            cross.addLine(to: CGPoint(x: pole.x, y: pole.y + 9))
            c.stroke(cross, with: .color(color), lineWidth: 1.5)
            c.stroke(Path(ellipseIn: CGRect(x: pole.x - 5, y: pole.y - 5, width: 10, height: 10)), with: .color(color), lineWidth: 1)
            c.draw(Text("Celestial pole").font(.caption2.weight(.semibold)).foregroundStyle(color),
                   at: CGPoint(x: pole.x - 10, y: pole.y + 8), anchor: .topTrailing)
        }
        if let polaris = t.polaris {
            c.stroke(Path(ellipseIn: CGRect(x: polaris.x - 7, y: polaris.y - 7, width: 14, height: 14)), with: .color(color), lineWidth: 1.5)
            let offset = t.polarisOffsetDeg.map { String(format: " · %.2f° from pole", $0) } ?? ""
            c.draw(Text("Polaris" + offset).font(.caption2).foregroundStyle(color),
                   at: CGPoint(x: polaris.x + 10, y: polaris.y - 8), anchor: .bottomLeading)
        }
    }

    private func drawRadiant(_ c: inout GraphicsContext, _ r: SkyRealismFrame.Radiant) {
        let color = palette.marginal
        var hints = Path()
        for run in r.hints { hints.addLines(run) }
        c.stroke(hints, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 5]))
        guard let p = r.point, r.position.altitudeDeg > -5 else { return }
        var burst = Path()
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            burst.move(to: CGPoint(x: p.x + 5 * cos(a), y: p.y + 5 * sin(a)))
            burst.addLine(to: CGPoint(x: p.x + 11 * cos(a), y: p.y + 11 * sin(a)))
        }
        c.stroke(burst, with: .color(color), lineWidth: 1.5)
        var label = "\(r.name) radiant \(Int(r.position.altitudeDeg.rounded()))°"
        if let rate = r.hourlyRate { label += rate > 0 ? " · ~\(Int(rate.rounded()))/h" : " · below horizon" }
        c.draw(Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color), at: CGPoint(x: p.x + 14, y: p.y), anchor: .leading)
    }

    func drawFind(_ c: inout GraphicsContext, _ f: SkyRealismFrame.Find, size: CGSize) {
        let p = input.projector
        let color = palette.accent
        // A reticle at the centre shows what "centred" means.
        let centre = CGPoint(x: p.intrinsics.cx, y: p.intrinsics.cy)
        c.stroke(Path(ellipseIn: CGRect(x: centre.x - 18, y: centre.y - 18, width: 36, height: 36)),
                 with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        if f.guidance.isOnScreen, let point = f.point {
            c.stroke(Path(ellipseIn: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)), with: .color(color), lineWidth: 2)
            return
        }
        guard let dir = f.guidance.arrowDirection else { return }
        let edge = EdgeMarker.point(from: PixelPoint(u: p.intrinsics.cx, v: p.intrinsics.cy), direction: dir,
                                    width: size.width, height: size.height, inset: 40)
        let tip = CGPoint(x: edge.u, y: edge.v)
        var arrow = Path()
        arrow.move(to: CGPoint(x: tip.x - 34 * cos(dir), y: tip.y - 34 * sin(dir)))
        arrow.addLine(to: tip)
        for side in [-0.55, 0.55] {
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - 15 * cos(dir + side), y: tip.y - 15 * sin(dir + side)))
        }
        c.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        let inward = CGPoint(x: tip.x - 46 * cos(dir), y: tip.y - 46 * sin(dir))
        c.draw(Text(f.name).font(.caption.weight(.bold)).foregroundStyle(color), at: inward,
               anchor: cos(dir) > 0.3 ? .trailing : cos(dir) < -0.3 ? .leading : .center)
    }
}
