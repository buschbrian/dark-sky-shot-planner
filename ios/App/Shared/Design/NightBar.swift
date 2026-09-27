import SkyCore
import SwiftUI

/// The app's signature: one night as a strip. Twilight at both ends,
/// astronomical darkness in the middle, the moon-free part of it lit in the
/// moon-free color and the moonlit part left dim. The same strip heads
/// Tonight, every Week row and the Map scrubber, so the headline number
/// always has the same picture.
struct NightBar: View {
    let span: TimeWindow
    let darkness: TimeWindow?
    let moonFree: [TimeWindow]
    let timeZone: TimeZone
    var now: Date?
    /// Darkness start and end under the bar.
    var showsTimes = true
    var height: CGFloat = 12
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Canvas { ctx, size in
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: DS.Radius.bar)
                ctx.clip(to: track)
                ctx.fill(track, with: .color(palette.data.twilight))
                if let d = darkness {
                    ctx.fill(Path(rect(d, size)), with: .color(palette.data.moonlit))
                }
                for w in moonFree {
                    ctx.fill(Path(rect(w, size)), with: .color(palette.data.moonFree))
                }
                if let now, now > span.start, now < span.end {
                    let x = self.x(now, size.width)
                    ctx.fill(Path(CGRect(x: x - 2, y: 0, width: 4, height: size.height)), with: .color(palette.surface))
                    ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(palette.primary))
                }
            }
            .frame(height: height)
            if showsTimes, let d = darkness {
                HStack {
                    Text(Format.clock(d.start, timeZone))
                    Spacer()
                    Text(Format.clock(d.end, timeZone))
                }
                .font(.dsData)
                .foregroundStyle(palette.tertiary)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night")
        .accessibilityValue(summary)
    }

    private func x(_ t: Date, _ width: CGFloat) -> CGFloat {
        let f = t.timeIntervalSince(span.start) / max(1, span.end.timeIntervalSince(span.start))
        return CGFloat(min(max(f, 0), 1)) * width
    }

    private func rect(_ w: TimeWindow, _ size: CGSize) -> CGRect {
        let a = x(w.start, size.width), b = x(w.end, size.width)
        return CGRect(x: a, y: 0, width: max(0, b - a), height: size.height)
    }

    private var summary: String {
        guard let d = darkness else { return "No astronomical darkness" }
        var s = "Dark from \(Format.clock(d.start, timeZone)) to \(Format.clock(d.end, timeZone))"
        if moonFree.isEmpty {
            s += ", moon up throughout"
        } else {
            s += "; moon-free " + moonFree.map { "\(Format.clock($0.start, timeZone)) to \(Format.clock($0.end, timeZone))" }
                .joined(separator: " and ")
        }
        return s
    }
}

/// The night bar's key, for the one place it is explained (Tonight).
struct NightBarLegend: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: DS.Space.m) {
            item("Moon-free", palette.data.moonFree)
            item("Moonlit", palette.data.moonlit)
            item("Twilight", palette.data.twilight)
        }
        .font(.caption)
        .foregroundStyle(palette.secondary)
        .accessibilityHidden(true)
    }

    private func item(_ name: String, _ color: Color) -> some View {
        HStack(spacing: DS.Space.xs) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(name)
        }
    }
}
