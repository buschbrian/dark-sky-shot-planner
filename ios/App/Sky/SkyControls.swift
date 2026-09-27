import SkyCore
import SwiftUI

/// Attitude calibration for this shooting session: one or more alignments
/// on known targets, fitted by `AttitudeCorrection.solve` (heading only for
/// one target, heading and tilt for two or more). Saved so it survives iOS
/// ending the app while the Camera app is in front, but restored only
/// nearby and the same night (`StoredCalibration`'s limits). The simulated
/// view never saves or restores.
@Observable
final class SkySession {
    private(set) var correction = AttitudeCorrection.identity
    /// Alignments collected for the next fit.
    private(set) var pending: [CalibrationObservation] = []
    private(set) var restored = false
    /// The last fit refused for its residual, shown until the next try.
    private(set) var rejected: AttitudeCorrection?

    private static let key = "sky.attitudeCorrection"

    var isCalibrated: Bool { !correction.isIdentity }
    var calibratedOn: String? { isCalibrated ? correction.targets.joined(separator: ", ") : nil }

    /// A fit of what is pending so far, for a live residual.
    var preview: AttitudeCorrection? { AttitudeCorrection.solve(pending) }

    func add(_ observation: CalibrationObservation) {
        pending.removeAll { $0.target == observation.target }
        pending.append(observation)
        rejected = nil
    }

    func clearPending() {
        pending = []
        rejected = nil
    }

    /// Fits the pending alignments; applies the fit only if its residual is
    /// within `ar_overlay.calibration_residual_max_deg`.
    @discardableResult
    func apply(config: AROverlayConfig?, at place: Place, persist: Bool) -> Bool {
        guard let fit = AttitudeCorrection.solve(pending) else { return false }
        if let config, !fit.isAcceptable(config: config) {
            rejected = fit
            return false
        }
        correction = fit
        pending = []
        rejected = nil
        restored = false
        guard persist else { return true }
        let stored = StoredCorrection(correction: fit, date: .now, latitude: place.latitude, longitude: place.longitude)
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: Self.key) }
        return true
    }

    func restore(at place: Place, now: Date = .now) {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(StoredCorrection.self, from: data),
              stored.isUsable(at: now, latitude: place.latitude, longitude: place.longitude) else { return }
        correction = stored.correction
        restored = true
    }

    func reset(persist: Bool) {
        correction = .identity
        pending = []
        rejected = nil
        restored = false
        if persist { UserDefaults.standard.removeObject(forKey: Self.key) }
    }
}

/// A saved correction, usable under `StoredCalibration`'s rules (same night, nearby).
struct StoredCorrection: Codable {
    let correction: AttitudeCorrection
    let date: Date
    let latitude: Double
    let longitude: Double

    func isUsable(at now: Date, latitude lat: Double, longitude lon: Double) -> Bool {
        StoredCalibration(calibration: .none, target: "", date: date, latitude: latitude, longitude: longitude)
            .isUsable(at: now, latitude: lat, longitude: lon)
    }
}

/// Something with a known direction to line the crosshair up on.
enum CalibrationTarget: Hashable, Identifiable {
    case body(SkyObject)
    /// A named bright star from the bundled catalogue.
    case star(hr: Int, name: String)
    /// A saved spot (a peak): azimuth only, from the geodesic.
    case landmark(name: String, latitude: Double, longitude: Double)

    var id: String {
        switch self {
        case .body(let o): o.rawValue
        case .star(let hr, _): "HR\(hr)"
        case .landmark(let name, let lat, let lon): "\(name)@\(lat),\(lon)"
        }
    }

    var name: String {
        switch self {
        case .body(let o): o == .galacticCenter ? "Galactic Center" : o.rawValue.capitalized
        case .star(_, let name): name
        case .landmark(let name, _, _): name
        }
    }

    /// True azimuth of the target seen from `place` at `date`.
    func azimuthDeg(from place: Place, at date: Date, stars: SkyStars?) -> Double? {
        direction(from: place, at: date, stars: stars, sensedAltitudeDeg: 0)?.azimuthDeg
    }

    /// The target's true apparent direction. A landmark has no altitude
    /// here, so it takes the sensed one and constrains the heading only.
    func direction(from place: Place, at date: Date, stars: SkyStars?, sensedAltitudeDeg: Double) -> HorizontalPosition? {
        switch self {
        case .body(let object):
            guard let observer = try? place.observer() else { return nil }
            return try? SkyPositions.position(of: object, at: date, observer: observer, refraction: .normal)
        case .star(let hr, _):
            guard let stars, let observer = try? place.observer(), let i = stars.catalog.index(ofHR: hr) else { return nil }
            return stars.field.position(ofStarAt: i, at: date, observer: observer)
        case .landmark(_, let lat, let lon):
            return Geodesy.inverse(
                from: GeoCoordinate(latitude: place.latitude, longitude: place.longitude),
                to: GeoCoordinate(latitude: lat, longitude: lon)).map {
                    HorizontalPosition(altitudeDeg: sensedAltitudeDeg, azimuthDeg: $0.initialAzimuthDeg)
                }
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

/// Line known targets up on the crosshair one at a time (Add), then Apply:
/// one target fixes the heading, two or more also fix tilt. The residual
/// shows how well the alignments agree; a fit above the config bound is refused.
struct CalibrationPanel: View {
    let targets: [CalibrationTarget]
    @Binding var choice: CalibrationTarget?
    let session: SkySession
    let residualLimitDeg: Double?
    let onAdd: (CalibrationTarget) -> Void
    let onApply: (CalibrationTarget?) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette

    private var added: Set<String> { Set(session.pending.map(\.target)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calibrate").font(.headline).foregroundStyle(palette.primary)
            if targets.isEmpty {
                Text("Nothing to align on: the Moon, planets and bright stars are down and no saved spot is nearby. Save a peak in Spots to use it here.")
                    .font(.caption).foregroundStyle(palette.secondary)
            } else {
                Text(choice.map { "Put \($0.name) in the crosshair, hold still, then tap Add. Two or more targets also correct tilt." }
                     ?? "Pick what you can see:")
                    .font(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(targets) { target in
                            Button(added.contains(target.name) ? "\(target.name) ✓" : target.name) { choice = target }
                                .buttonStyle(SkyButtonStyle(prominent: choice == target))
                                .accessibilityLabel(target.name)
                                .accessibilityValue(added.contains(target.name) ? "added" : "")
                                .accessibilityAddTraits(choice == target ? .isSelected : [])
                        }
                    }
                }
            }
            if let status {
                Text(status.text).font(.caption.monospacedDigit())
                    .foregroundStyle(status.bad ? palette.poor : palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(status.bad ? "sky.calibration.rejected" : "sky.calibration.status")
            }
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(SkyButtonStyle())
                if session.isCalibrated {
                    Button("Reset", action: onReset).buttonStyle(SkyButtonStyle())
                        .accessibilityIdentifier("sky.calibration.reset")
                }
                Spacer()
                Button("Add") { if let choice { onAdd(choice) } }
                    .buttonStyle(SkyButtonStyle())
                    .disabled(choice == nil)
                    .opacity(choice == nil ? 0.4 : 1)
                    .accessibilityIdentifier("sky.calibration.add")
                Button(session.pending.count > 1 ? "Apply \(session.pending.count)" : "Align") { onApply(choice) }
                    .buttonStyle(SkyButtonStyle(prominent: true))
                    .disabled(choice == nil && session.pending.isEmpty)
                    .opacity(choice == nil && session.pending.isEmpty ? 0.4 : 1)
                    .accessibilityIdentifier("sky.calibration.align")
            }
        }
    }

    private var status: (text: String, bad: Bool)? {
        if let r = session.rejected {
            let limit = residualLimitDeg.map { String(format: " (limit %.1f°)", $0) } ?? ""
            return (String(format: "Refused: the alignments disagree by %.1f° RMS%@. Check the target names, re-add the worst one, or Reset.", r.residualDeg, limit), true)
        }
        guard !session.pending.isEmpty else { return nil }
        let names = session.pending.map(\.target).joined(separator: ", ")
        guard let fit = session.preview else { return ("Added: \(names)", false) }
        if session.pending.count == 1 { return (String(format: "Added: %@ · heading %+.1f°", names, fit.yawDeg), false) }
        return (String(format: "Added: %@ · heading %+.1f°, residual %.2f°", names, fit.yawDeg, fit.residualDeg), false)
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
