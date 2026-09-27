import SkyCore
import SwiftUI

/// The "at time T" scrubber across the night (PhotoPills-planner style): hour
/// ticks, the astronomical-darkness band, and a thumb. Drawn entirely from
/// the palette so field mode stays red.
struct NightScrubber: View {
    let window: TimeWindow
    let darkness: TimeWindow?
    var moonFree: [TimeWindow] = []
    let timeZone: TimeZone
    @Binding var time: Date

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    static let step: TimeInterval = 5 * 60

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack(alignment: .center) {
                Button { nudge(-600) } label: { Image(systemName: "minus") }
                    .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                    .accessibilityLabel("10 minutes earlier")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(MapPlanner.clock(time, timeZone: timeZone))
                        .font(.system(.title, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.primary)
                    Text(timeZone.abbreviation(for: time) ?? "")
                        .font(.dsData)
                        .foregroundStyle(palette.secondary)
                }
                .accessibilityHidden(true)
                Spacer()
                Button { nudge(600) } label: { Image(systemName: "plus") }
                    .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                    .accessibilityLabel("10 minutes later")
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    NightBar(span: window, darkness: darkness, moonFree: moonFree, timeZone: timeZone,
                             showsTimes: false, height: 14)
                        .frame(width: w)
                    ForEach(hourTicks, id: \.self) { t in
                        Rectangle().fill(palette.tertiary).frame(width: 1, height: 5).offset(x: x(t, w), y: 17)
                        if hour(t) % (typeSize.isAccessibilitySize ? 4 : 2) == 0 {
                            Text(t.formatted(Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .narrow))))
                                .font(.dsData)
                                .foregroundStyle(palette.secondary)
                                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                                .fixedSize()
                                .frame(width: 40)
                                .offset(x: x(t, w) - 20, y: 23)
                        }
                    }
                    Capsule().fill(palette.primary)
                        .frame(width: 4, height: 26)
                        .overlay(Capsule().strokeBorder(palette.background, lineWidth: 1))
                        .offset(x: x(time, w) - 2, y: -6)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = min(1, max(0, v.location.x / max(1, w)))
                    set(window.start.addingTimeInterval(f * window.duration))
                })
            }
            .frame(height: 40)
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
