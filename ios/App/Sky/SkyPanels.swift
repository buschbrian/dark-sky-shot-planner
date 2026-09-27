import SkyCore
import SwiftUI

/// The bottom panel the Sky view shows above its time scrubber.
enum SkyPanel: Equatable {
    case find, trails, layers
}

/// What the latest drawn frame says, read by the controls a few times a
/// second (not observed, so drawing never invalidates the controls).
final class SkyFrameReadout {
    var find: (name: String, guidance: SkyGuidance)?
    var trails: SkyRealismFrame.Trails?
    var limitingMagnitude: Double?
    private var announced: (String, Int)?

    /// VoiceOver hears when a find target comes into view or is centred.
    func announceFindProgress() {
        guard let find else {
            announced = nil
            return
        }
        let stage = find.guidance.separationDeg <= SkyGuidance.centredDeg ? 2 : find.guidance.isOnScreen ? 1 : 0
        if let announced, announced.0 == find.name, announced.1 == stage { return }
        let first = announced?.0 != find.name
        announced = (find.name, stage)
        guard stage > 0 || first else { return }
        let text = switch stage {
        case 2: "\(find.name) centred"
        case 1: "\(find.name) in view"
        default: "Finding \(find.name): \(find.guidance.spoken)"
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// One findable thing with where it is now.
struct SkyFindItem: Identifiable {
    let target: SkyFindTarget
    let name: String
    let altitudeDeg: Double

    var id: String {
        switch target {
        case .constellation(let a): "c.\(a)"
        case .star(let hr): "s.\(hr)"
        case .body(let o): "b.\(o.rawValue)"
        case .radiant(let id): "r.\(id)"
        }
    }
}

struct SkyFindPanel: View {
    enum Kind: String, CaseIterable, Identifiable {
        case constellations = "Constellations", stars = "Stars", planets = "Moon & planets", showers = "Showers"
        var id: String { rawValue }
    }

    let items: (Kind) -> [SkyFindItem]
    @Binding var target: SkyFindTarget?
    let canPoint: Bool
    let onPoint: () -> Void
    let onClose: () -> Void

    @State private var kind = Kind.constellations
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Find").font(.headline).foregroundStyle(palette.primary)
                Spacer()
                if target != nil {
                    Button("Stop") { target = nil }.buttonStyle(SkyButtonStyle()).accessibilityIdentifier("sky.find.stop")
                }
                if canPoint, target != nil {
                    Button("Point there", action: onPoint).buttonStyle(SkyButtonStyle(prominent: true))
                        .accessibilityIdentifier("sky.find.point")
                        .accessibilityHint("Turns the simulated view to the target")
                }
                Button("Close", action: onClose).buttonStyle(SkyButtonStyle()).accessibilityIdentifier("sky.panel.close")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Kind.allCases) { k in
                        Button(k.rawValue) { kind = k }
                            .buttonStyle(SkyButtonStyle(prominent: kind == k))
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                    }
                }
            }
            let list = items(kind)
            if list.isEmpty {
                Text(kind == .showers ? "No meteor shower is active tonight, or none has been supplied." : "Nothing to find.")
                    .font(.caption).foregroundStyle(palette.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(list) { item in
                            Button {
                                target = item.target
                            } label: {
                                Text("\(item.name) \(Int(item.altitudeDeg.rounded()))°")
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SkyButtonStyle(prominent: target == item.target))
                            .opacity(item.altitudeDeg > 0 ? 1 : 0.55)
                            .accessibilityLabel(item.name)
                            .accessibilityValue(item.altitudeDeg > 0 ? "\(Int(item.altitudeDeg.rounded())) degrees up" : "below the horizon")
                            .accessibilityAddTraits(target == item.target ? .isSelected : [])
                            .accessibilityIdentifier("sky.find.item.\(item.name)")
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }
}

/// Star-trail designer: start at the scrubber's time, a length or a
/// frame count × interval, and where the pole falls in the frame.
struct SkyTrailPanel: View {
    @Binding var sequence: StarTrailSequence?
    let start: Date
    let timeZone: TimeZone
    let readout: SkyFrameReadout
    let canPoint: Bool
    let onPointAtPole: () -> Void
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    static let durations: [Int] = [30, 60, 120, 180, 240]
    static let intervals: [Int] = [15, 30, 60]

    private var minutes: Int {
        sequence.map { Int(($0.duration / 60).rounded()) } ?? 60
    }

    private var interval: Int { sequence.map { Int($0.interval) } ?? 30 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Star trails").font(.headline).foregroundStyle(palette.primary)
                Spacer()
                if canPoint {
                    Button("Point at pole", action: onPointAtPole).buttonStyle(SkyButtonStyle())
                        .accessibilityIdentifier("sky.trails.pointPole")
                }
                Button(sequence == nil ? "Close" : "Hide trails") {
                    sequence = nil
                    onClose()
                }
                .buttonStyle(SkyButtonStyle()).accessibilityIdentifier("sky.panel.close")
            }
            Text("Starts \(SkyOverlayInput.time(start, timeZone)) (move the time bar to change)")
                .font(.caption).foregroundStyle(palette.secondary)
            chips(title: "Length", values: Self.durations, selected: minutes, label: { $0 < 60 ? "\($0) min" : "\($0 / 60) h" },
                  id: "sky.trails.duration") { set(minutes: $0, interval: interval) }
            chips(title: "Every", values: Self.intervals, selected: interval, label: { "\($0) s" },
                  id: "sky.trails.interval") { set(minutes: minutes, interval: $0) }
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(summary)
                    .font(.caption.monospacedDigit()).foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sky.trails.readout")
            }
        }
        .onAppear { if sequence == nil { set(minutes: 60, interval: 30) } }
        .onChange(of: start) { set(minutes: minutes, interval: interval) }
    }

    private var summary: String {
        guard let s = sequence else { return "" }
        var text = String(format: "Arcs %.1f° · %d × %d s (%d s exposures, %d s gaps)", s.arcDeg, s.frames, Int(s.interval), Int(s.exposure), Int(s.interval - s.exposure))
        if let t = readout.trails, t.sequence == s {
            switch t.framing {
            case .inFrame(let x, let y): text += String(format: "\nPole in frame: %d%% across, %d%% down", Int((x * 100).rounded()), Int((y * 100).rounded()))
            case .outsideFrame(let d), .behindCamera(let d?): text += "\nPole off screen to the " + SkyOverlayInput.direction(d)
            case .behindCamera(nil): text += "\nPole behind you"
            }
            if let p = t.polarisOffsetDeg { text += String(format: " · Polaris %.2f° from the true pole", p) }
        }
        return text
    }

    private func set(minutes: Int, interval: Int) {
        // One second between frames for the camera to write (Timelapse's default buffer).
        let exposure = Double(interval) - Timelapse.defaultBufferSeconds
        let next = try? StarTrailSequence(start: start, duration: Double(minutes * 60), exposure: exposure, interval: Double(interval))
        sequence = next
        if let next { SkyTrailDesign(sequence: next, poleInFrame: nil).save() }
    }

    private func chips(title: String, values: [Int], selected: Int, label: @escaping (Int) -> String, id: String, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(palette.secondary).frame(width: 44, alignment: .leading)
            ForEach(values, id: \.self) { v in
                Button(label(v)) { set(v) }
                    .buttonStyle(SkyButtonStyle(prominent: v == selected))
                    .accessibilityAddTraits(v == selected ? .isSelected : [])
                    .accessibilityIdentifier("\(id).\(v)")
            }
        }
    }
}

struct SkyLayersPanel: View {
    @Binding var layers: SkyLayers
    let isLive: Bool
    let limitingMagnitude: Double?
    let onClose: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Show").font(.headline).foregroundStyle(palette.primary)
                Spacer()
                Button("Close", action: onClose).buttonStyle(SkyButtonStyle()).accessibilityIdentifier("sky.panel.close")
            }
            HStack(spacing: 6) {
                toggle("Stars", $layers.stars)
                toggle("Lines", $layers.constellationLines)
                toggle("Names", $layers.names)
                toggle("Milky Way", $layers.milkyWay)
            }
            if isLive {
                toggle("Simulated sky instead of camera", $layers.planetarium)
            }
            if let limitingMagnitude {
                Text(String(format: "Stars drawn to magnitude %.1f: the naked-eye limit this sky model gives for the Sun, Moon and a dark site (approximate; light pollution not included).", limitingMagnitude))
                    .font(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Button(title) { value.wrappedValue.toggle() }
            .buttonStyle(SkyButtonStyle(prominent: value.wrappedValue))
            .accessibilityAddTraits(value.wrappedValue ? .isSelected : [])
            .accessibilityValue(value.wrappedValue ? "on" : "off")
            .accessibilityIdentifier("sky.layer.\(title)")
    }
}
