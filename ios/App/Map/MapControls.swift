import SkyCore
import SwiftUI

/// The "at time T" scrubber across the night (PhotoPills-planner style): hour
/// ticks, the astronomical-darkness band, and a thumb. Drawn entirely from
/// the palette so field mode stays red.
struct NightScrubber: View {
    let window: TimeWindow
    let darkness: TimeWindow?
    let timeZone: TimeZone
    @Binding var time: Date

    @Environment(\.palette) private var palette
    static let step: TimeInterval = 5 * 60

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                PaletteButton(systemImage: "minus", label: "10 minutes earlier") { nudge(-600) }
                Spacer()
                Text(MapPlanner.clock(time, timeZone: timeZone))
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.primary)
                Text(timeZone.abbreviation(for: time) ?? "")
                    .font(.footnote)
                    .foregroundStyle(palette.secondary)
                Spacer()
                PaletteButton(systemImage: "plus", label: "10 minutes later") { nudge(600) }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5).fill(palette.surface).frame(height: 24)
                    if let d = darkness {
                        Rectangle().fill(palette.accent.opacity(0.35))
                            .frame(width: max(0, x(d.end, w) - x(d.start, w)), height: 24)
                            .offset(x: x(d.start, w))
                    }
                    ForEach(hourTicks, id: \.self) { t in
                        Rectangle().fill(palette.secondary).frame(width: 1, height: 10).offset(x: x(t, w), y: 14)
                        if hour(t) % 2 == 0 {
                            Text(String(format: "%02d", hour(t)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.secondary)
                                .fixedSize()
                                .offset(x: x(t, w) - 7, y: 27)
                        }
                    }
                    Capsule().fill(palette.accent).frame(width: 6, height: 34).offset(x: x(time, w) - 3, y: -5)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = min(1, max(0, v.location.x / max(1, w)))
                    set(window.start.addingTimeInterval(f * window.duration))
                })
            }
            .frame(height: 42)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Planner time")
            .accessibilityValue(MapPlanner.clock(time, timeZone: timeZone))
            .accessibilityAdjustableAction { direction in
                nudge(direction == .increment ? 600 : -600)
            }
            .accessibilityIdentifier("map.scrubber")
        }
    }

    private var hourTicks: [Date] {
        Array(TimeScrubber.times(across: window, step: 3600).dropFirst().dropLast())
    }

    private func hour(_ t: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.hour, from: t)
    }

    private func x(_ t: Date, _ w: CGFloat) -> CGFloat {
        CGFloat(TimeScrubber.clamp(t, to: window).timeIntervalSince(window.start) / max(1, window.duration)) * w
    }

    private func nudge(_ dt: TimeInterval) { set(time.addingTimeInterval(dt)) }

    private func set(_ t: Date) {
        time = TimeScrubber.snap(t, across: window, step: Self.step)
    }
}

extension Palette {
    /// A data color (legend swatch) as field mode may show it: its luminance on the red channel.
    func swatch(_ hex: String, field: Bool) -> Color {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
        if field { return Color(red: 0.2126 * r + 0.7152 * g + 0.0722 * b, green: 0, blue: 0) }
        return Color(red: r, green: g, blue: b)
    }
}
