import SkyCore
import SwiftUI

/// The figure-8 compass calibration guide, drawn in the palette (red in
/// field mode) instead of iOS's white system prompt, which the Sky view
/// turns off. Shown while the magnetometer is uncalibrated or low, or the
/// heading accuracy is invalid or worse than the confident threshold.
struct FigureEightGuide: View {
    let quality: SensorQuality
    let onHide: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tick in
                Canvas { c, size in
                    draw(&c, size: size, t: reduceMotion ? 0.3 : tick.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: 96, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Calibrate the compass").font(.subheadline.weight(.semibold)).foregroundStyle(palette.primary)
                Text("Wave the phone in a slow figure 8, turning it as you go, away from the car and tripod.")
                    .font(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(quality.summary).font(.caption.monospacedDigit()).foregroundStyle(palette.marginal)
            }
            Spacer(minLength: 0)
            Button("Hide", action: onHide).buttonStyle(SkyButtonStyle())
                .accessibilityIdentifier("sky.figure8.hide")
        }
        .padding(10)
        .background(palette.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.marginal.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calibrate the compass: wave the phone in a slow figure 8. \(quality.summary)")
        .accessibilityIdentifier("sky.figure8")
    }

    /// A lemniscate of Gerono with a phone travelling round it.
    private func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width / 2 - 8, h = size.height / 2 - 6
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func point(_ s: Double) -> CGPoint { CGPoint(x: centre.x + w * sin(s), y: centre.y + h * sin(s) * cos(s) * 2) }
        var path = Path()
        path.move(to: point(0))
        for i in 1...64 { path.addLine(to: point(Double(i) / 64 * 2 * .pi)) }
        c.stroke(path, with: .color(palette.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        let s = t * 1.6
        let p = point(s), q = point(s + 0.05)
        let angle = atan2(q.y - p.y, q.x - p.x)
        var phone = Path(roundedRect: CGRect(x: -5, y: -8, width: 10, height: 16), cornerRadius: 2)
        phone = phone.applying(CGAffineTransform(rotationAngle: angle + .pi / 2).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
        c.fill(phone, with: .color(palette.accent))
    }
}

/// Debug builds only: `-SkySensorDiagnostics YES` shows this panel and
/// prints one `SKYDIAG` line a second to stdout (read it from the phone
/// with `xcrun devicectl device process launch --console`).
struct SensorDiagnosticsLine: Equatable {
    var headingDeg: Double?
    var smoothingDeg: Double
    var headingAccuracyDeg: Double
    var magnetic: MagneticFieldAccuracy
    var rateDegPerSecond: Double
    var disturbance: HeadingDisturbanceMonitor.State
    var correction: AttitudeCorrection
    var pending: Int

    var text: String {
        let heading = headingDeg.map { String(format: "%.1f", $0) } ?? "-"
        let dist: String = switch disturbance {
        case .steady: "steady"
        case .disturbed(let d): String(format: "disturbed(%.1f)", d)
        case .drifted(let d): String(format: "drifted(%.1f)", d)
        }
        var s = String(format: "heading=%@ smoothing=%+.2f headingAcc=%.1f magAcc=%@ rate=%.2f dist=%@",
                       heading, smoothingDeg, headingAccuracyDeg, magnetic.label, rateDegPerSecond, dist)
        if correction.isIdentity {
            s += " cal=none"
        } else {
            let tilt = correction.tiltDeg(facingAzimuth: headingDeg ?? 0)
            s += String(format: " cal=%@ yaw=%+.2f pitch=%+.2f roll=%+.2f residual=%.2f",
                        correction.targets.joined(separator: "+"), correction.yawDeg, tilt.pitch, tilt.roll, correction.residualDeg)
        }
        return s + " pending=\(pending)"
    }
}

struct SensorDiagnosticsPanel: View {
    let line: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sensor diagnostics (logged each second as SKYDIAG)").font(.caption2.weight(.bold)).foregroundStyle(palette.secondary)
            Text(line).font(.caption2.monospaced()).foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(palette.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sky.diagnostics")
    }
}
