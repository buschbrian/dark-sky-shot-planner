import SkyCore
import SwiftUI

/// Heading calibration for this shooting session. Saved so it survives iOS
/// ending the app while the Camera app is in front, but restored only
/// nearby and the same night (`StoredCalibration`). The simulated view
/// never saves or restores.
@Observable
final class SkySession {
    private(set) var calibration = HeadingCalibration.none
    private(set) var calibratedOn: String?
    private(set) var restored = false

    private static let key = "sky.calibration"

    var isCalibrated: Bool { calibratedOn != nil }

    func calibrate(_ calibration: HeadingCalibration, on target: String, at place: Place, persist: Bool) {
        self.calibration = calibration
        calibratedOn = target
        restored = false
        guard persist else { return }
        let stored = StoredCalibration(
            calibration: calibration, target: target, date: .now, latitude: place.latitude, longitude: place.longitude)
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func restore(at place: Place, now: Date = .now) {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(StoredCalibration.self, from: data),
              stored.isUsable(at: now, latitude: place.latitude, longitude: place.longitude) else { return }
        calibration = stored.calibration
        calibratedOn = stored.target
        restored = true
    }

    func reset(persist: Bool) {
        calibration = .none
        calibratedOn = nil
        restored = false
        if persist { UserDefaults.standard.removeObject(forKey: Self.key) }
    }
}

/// Something with a known azimuth to line the crosshair up on.
enum CalibrationTarget: Hashable, Identifiable {
    case body(SkyObject)
    case landmark(name: String, latitude: Double, longitude: Double)

    var id: String {
        switch self {
        case .body(let o): o.rawValue
        case .landmark(let name, let lat, let lon): "\(name)@\(lat),\(lon)"
        }
    }

    var name: String {
        switch self {
        case .body(let o): o == .galacticCenter ? "Galactic Center" : o.rawValue.capitalized
        case .landmark(let name, _, _): name
        }
    }

    /// True azimuth of the target seen from `place` at `date`.
    func azimuthDeg(from place: Place, at date: Date) -> Double? {
        switch self {
        case .body(let object):
            guard let observer = try? place.observer() else { return nil }
            return try? SkyPositions.position(of: object, at: date, observer: observer, refraction: .normal).azimuthDeg
        case .landmark(_, let lat, let lon):
            return Geodesy.inverse(
                from: GeoCoordinate(latitude: place.latitude, longitude: place.longitude),
                to: GeoCoordinate(latitude: lat, longitude: lon))?.initialAzimuthDeg
        }
    }
}

struct SkyButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? palette.background : palette.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(prominent ? palette.accent : palette.surface, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SkyPill: View {
    let text: String
    let color: Color
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(palette.background.opacity(0.75), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
    }
}

/// Compass accuracy and calibration state, never hiding a poor heading.
struct HeadingBadge: View {
    let text: String
    let style: OverlayStyle
    @Environment(\.palette) private var palette

    var body: some View {
        SkyPill(text: text, color: style.isConfident ? palette.good : palette.marginal)
            .accessibilityIdentifier("sky.heading")
    }
}

/// The night's time, PhotoPills-planner style: drag across darkness with
/// hour marks, snapped to 5 minutes; "Now" returns to live time.
struct SkyScrubber: View {
    let window: TimeWindow
    let time: Date
    let timeZone: TimeZone
    let isLive: Bool
    let canGoLive: Bool
    let onScrub: (Date) -> Void
    let onLive: () -> Void

    @Environment(\.palette) private var palette
    private static let step: TimeInterval = 300

    private var fraction: Double {
        guard window.duration > 0 else { return 0 }
        return min(max(TimeScrubber.clamp(time, to: window).timeIntervalSince(window.start) / window.duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(isLive ? "Now" : "Preview").font(.caption.weight(.bold)).foregroundStyle(palette.accent)
                Text(SkyOverlayInput.time(time, timeZone)).font(.subheadline.monospacedDigit()).foregroundStyle(palette.primary)
                if time < window.start { Text("before dark").font(.caption).foregroundStyle(palette.secondary) }
                if time > window.end { Text("after dawn").font(.caption).foregroundStyle(palette.secondary) }
                Spacer()
                if canGoLive && !isLive {
                    Button("Now", action: onLive).buttonStyle(SkyButtonStyle())
                        .accessibilityIdentifier("sky.scrubber.now")
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surface).frame(height: 6)
                    Capsule().fill(palette.accent.opacity(0.7)).frame(width: max(6, w * fraction), height: 6)
                    ForEach(hourMarks, id: \.self) { f in
                        Rectangle().fill(palette.secondary).frame(width: 1, height: 12).offset(x: w * f)
                    }
                    Circle().fill(palette.primary).frame(width: 22, height: 22).offset(x: w * fraction - 11)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    scrub(toFraction: g.location.x / max(w, 1))
                })
            }
            .frame(height: 24)
            HStack {
                Text("Dark " + SkyOverlayInput.time(window.start, timeZone))
                Spacer()
                Text("Dawn " + SkyOverlayInput.time(window.end, timeZone))
            }
            .font(.caption2)
            .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time")
        .accessibilityValue("\(isLive ? "Now" : "Preview"), \(SkyOverlayInput.time(time, timeZone))")
        .accessibilityHint("Swipe up or down to move 15 minutes")
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? 900 : -900
            onScrub(TimeScrubber.snap(time.addingTimeInterval(delta), across: window, step: Self.step))
        }
        .accessibilityIdentifier("sky.scrubber")
    }

    private var hourMarks: [Double] {
        guard window.duration > 0 else { return [] }
        return TimeScrubber.times(across: window, step: 3600).dropFirst().dropLast()
            .map { $0.timeIntervalSince(window.start) / window.duration }
    }

    private func scrub(toFraction f: Double) {
        let date = window.start.addingTimeInterval(min(max(f, 0), 1) * window.duration)
        onScrub(TimeScrubber.snap(date, across: window, step: Self.step))
    }
}

/// Line a known target up on the crosshair, then tap Align.
struct CalibrationPanel: View {
    let targets: [CalibrationTarget]
    @Binding var choice: CalibrationTarget?
    let isCalibrated: Bool
    let onAlign: (CalibrationTarget) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calibrate heading").font(.headline).foregroundStyle(palette.primary)
            if targets.isEmpty {
                Text("Nothing to align on: the Moon and planets are down and no saved spot is nearby. Save a peak in Spots to use it here.")
                    .font(.caption).foregroundStyle(palette.secondary)
            } else {
                Text(choice.map { "Put \($0.name) in the crosshair, hold still, then tap Align." } ?? "Pick what you can see:")
                    .font(.caption).foregroundStyle(palette.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(targets) { target in
                            Button(target.name) { choice = target }
                                .buttonStyle(SkyButtonStyle(prominent: choice == target))
                                .accessibilityAddTraits(choice == target ? .isSelected : [])
                        }
                    }
                }
            }
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(SkyButtonStyle())
                if isCalibrated {
                    Button("Reset", action: onReset).buttonStyle(SkyButtonStyle())
                        .accessibilityIdentifier("sky.calibration.reset")
                }
                Spacer()
                Button("Align") { if let choice { onAlign(choice) } }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .disabled(choice == nil)
                    .opacity(choice == nil ? 0.4 : 1)
                    .accessibilityIdentifier("sky.calibration.align")
            }
        }
    }
}

/// An honest full-screen explanation instead of a blank view.
struct SkyExplanation<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let actions: Actions

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(palette.secondary)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(palette.primary).multilineTextAlignment(.center)
            Text(message).font(.callout).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            HStack { actions }.padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sky.explanation")
    }
}

struct OpenSettingsButton: View {
    var body: some View {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Link("Open Settings", destination: url).buttonStyle(SkyButtonStyle(prominent: true))
        }
    }
}
