import SkyCore
import SwiftUI

/// Inputs shared by the calculators, kept while the Tools tab lives.
@Observable
final class ToolsInputs {
    /// Empty means wide open.
    var fNumber = ""
    var declination = ToolsFormat.gcDeclinationText
    var k = 2.0
    var trailExposure = "20"
    /// Empty means focus at the hyperfocal distance.
    var focusDistance = ""
    var snrGain = "3"
    var subExposure = "15"
    var timelapseMode = TimelapseMode.intervalAndClip
    var tlExposure = "15"
    var tlBuffer = ToolsFormat.number(Timelapse.defaultBufferSeconds)
    var tlFPS = "24"
    var tlInterval = "20"
    var tlClip = "10"
    var tlEventMinutes = "60"
}

enum TimelapseMode: String, Hashable, CaseIterable {
    case intervalAndClip = "Interval + clip"
    case intervalAndEvent = "Interval + event"
    case eventAndClip = "Event + clip"
}

enum Calculator: String, Hashable, CaseIterable, Identifiable {
    case starExposure, starTrails, depthOfField, stacking, timelapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starExposure: "Star exposure (NPF, 500 rule)"
        case .starTrails: "Star-trail length"
        case .depthOfField: "Hyperfocal and depth of field"
        case .stacking: "Stacking for SNR"
        case .timelapse: "Timelapse"
        }
    }

    var subtitle: String {
        switch self {
        case .starExposure: "Longest exposure before stars trail"
        case .starTrails: "How far stars move, in pixels"
        case .depthOfField: "Where to focus for foreground and stars"
        case .stacking: "Frames for a target noise reduction"
        case .timelapse: "Interval, frames, clip and event length"
        }
    }

    var symbol: String {
        switch self {
        case .starExposure: "timer"
        case .starTrails: "line.diagonal"
        case .depthOfField: "scope"
        case .stacking: "square.stack.3d.up"
        case .timelapse: "film"
        }
    }
}

struct CalculatorView: View {
    let calculator: Calculator
    let kit: GearKit
    @Bindable var inputs: ToolsInputs
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    Text(kit.name).font(.headline).foregroundStyle(palette.primary)
                    Text("\(kit.lensSummary) on \(kit.camera.name): \(kit.cameraSummary)")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
                switch calculator {
                case .starExposure: starExposure
                case .starTrails: starTrails
                case .depthOfField: depthOfField
                case .stacking: stacking
                case .timelapse: timelapse
                }
                Text("Computed on this phone from the gear profile you entered.")
                    .font(.footnote).foregroundStyle(palette.secondary)
            }
            .padding()
        }
        .background(palette.background)
        .scrollDismissesKeyboard(.interactively)
        .paletteChrome(calculator.title, pushed: true)
    }

    // MARK: Shared inputs

    private var apertureRow: some View {
        FieldRow(label: "Aperture (f-number)", unit: nil, text: $inputs.fNumber,
                 placeholder: "\(ToolsFormat.number(kit.lens.maxFNumber)) (wide open)", id: "tools.fNumber")
    }

    private var declinationRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldRow(label: "Declination", unit: "°", text: $inputs.declination, placeholder: ToolsFormat.gcDeclinationText,
                     allowsNegative: true, id: "tools.declination")
            HStack {
                Text("Default: the Galactic Center, \(ToolsFormat.gcDeclinationText)°. 0° (the celestial equator) is the worst case.")
                    .font(.caption).foregroundStyle(palette.secondary)
                Spacer(minLength: 4)
                if inputs.declination != ToolsFormat.gcDeclinationText {
                    Button("Use Galactic Center") { inputs.declination = ToolsFormat.gcDeclinationText }
                        .font(.caption.bold()).foregroundStyle(palette.accent)
                }
            }
        }
    }

    private var fNumber: Double? { ToolsFormat.optional(inputs.fNumber) }
    private var declination: Double { ToolsFormat.required(inputs.declination) }

    // MARK: Calculators

    @ViewBuilder private var starExposure: some View {
        Card {
            apertureRow
            declinationRows
            ChoiceRow(label: "NPF k", options: [(1.0, "1 strict"), (2.0, "2 default"), (3.0, "3 loose")],
                      selection: $inputs.k, id: "tools.k")
            Text("k = 1: a star moves one radius (strict). k = 2: one diameter, barely visible (PhotoPills' default). k = 3: visible trailing.")
                .font(.caption).foregroundStyle(palette.secondary)
        }
        Card {
            let npf = Result { () throws(ExposureError) in
                try StarExposure.npf(camera: kit.camera, lens: kit.lens, fNumber: fNumber, declinationDeg: declination, k: inputs.k)
            }
            let rough = Result { () throws(ExposureError) in try StarExposure.roughRule500(camera: kit.camera, lens: kit.lens) }
            outcome(npf) { t in
                ResultRow(label: "NPF rule, k = \(ToolsFormat.number(inputs.k))", value: ToolsFormat.duration(t),
                          note: t.isFinite ? nil : "Stars at the celestial pole do not move.", id: "tools.result.npf")
            }
            outcome(rough) { t in
                ResultRow(label: "500 rule (the rough one)", value: ToolsFormat.duration(t),
                          note: "Ignores pixel pitch and aperture, so stars trail on modern sensors. Shown only for comparison.",
                          id: "tools.result.500")
            }
        }
        credit("NPF rule by Frédéric Michaud, Société Astronomique du Havre (SAH, 2010): “La Règle NPF”, sahavre.fr. Credited as the SAH asks; non-commercial use only. 500 rule: PhotoPills Milky Way guide.")
    }

    @ViewBuilder private var starTrails: some View {
        Card {
            FieldRow(label: "Exposure", unit: "s", text: $inputs.trailExposure, placeholder: "20", id: "tools.trailExposure")
            declinationRows
        }
        Card {
            let px = Result { () throws(ExposureError) in
                try StarExposure.starTrailLengthPixels(
                    exposure: ToolsFormat.required(inputs.trailExposure), camera: kit.camera, lens: kit.lens,
                    declinationDeg: declination)
            }
            let mm = Result { () throws(ExposureError) in
                try StarExposure.starTrailLengthMM(
                    exposure: ToolsFormat.required(inputs.trailExposure), focalLengthMM: kit.lens.focalLengthMM,
                    declinationDeg: declination)
            }
            outcome(px) { v in
                ResultRow(label: "Trail length", value: "\(ToolsFormat.number(v, digits: 1)) px",
                          note: (try? mm.get()).map { "\(ToolsFormat.number($0 * 1000, digits: 1)) µm on the sensor, near the image centre" },
                          id: "tools.result.trail")
            }
        }
        credit("Sidereal rate 15.041″/s (IERS Conventions 2010) × cos δ, on a \(ToolsFormat.number(kit.camera.pixelPitchUM)) µm pixel.")
    }

    @ViewBuilder private var depthOfField: some View {
        Card {
            apertureRow
            FieldRow(label: "Focus distance", unit: "m", text: $inputs.focusDistance, placeholder: "hyperfocal", id: "tools.focus")
        }
        Card {
            let h = Result { () throws(ExposureError) in
                try DepthOfField.hyperfocalMeters(camera: kit.camera, lens: kit.lens, fNumber: fNumber)
            }
            outcome(h) { hyperfocal in
                ResultRow(label: "Hyperfocal distance", value: ToolsFormat.meters(hyperfocal),
                          note: "Focus here and everything from half this distance to infinity is acceptably sharp.",
                          id: "tools.result.hyperfocal")
                let focus = ToolsFormat.optional(inputs.focusDistance) ?? hyperfocal
                let limits = Result { () throws(ExposureError) in
                    try DepthOfField.limits(camera: kit.camera, lens: kit.lens, fNumber: fNumber, focusDistanceMeters: focus)
                }
                outcome(limits) { l in
                    ResultRow(label: "Near limit", value: ToolsFormat.meters(l.nearMeters), id: "tools.result.near")
                    ResultRow(label: "Far limit", value: ToolsFormat.limit(l.far), id: "tools.result.far")
                    ResultRow(label: "Depth of field", value: l.depthMeters.map(ToolsFormat.meters) ?? "∞ (infinity)",
                              note: "Focused at \(ToolsFormat.meters(l.focusDistanceMeters)).")
                }
            }
        }
        credit("Thin-lens equations (Greenleaf 1950, via DOFMaster). \(kit.derivedSummary).")
    }

    @ViewBuilder private var stacking: some View {
        Card {
            FieldRow(label: "Target SNR gain", unit: "×", text: $inputs.snrGain, placeholder: "3", id: "tools.snrGain")
            FieldRow(label: "Sub-exposure", unit: "s", text: $inputs.subExposure, placeholder: "15", id: "tools.subExposure")
        }
        Card {
            let plan = Result { () throws(ExposureError) in
                try Stacking.plan(snrGain: ToolsFormat.required(inputs.snrGain), subExposure: ToolsFormat.required(inputs.subExposure))
            }
            outcome(plan) { p in
                ResultRow(label: "Frames", value: "\(p.frames)", id: "tools.result.frames")
                ResultRow(label: "Total integration", value: ToolsFormat.duration(p.totalIntegration))
                ResultRow(label: "SNR gain achieved", value: "\(ToolsFormat.number(p.snrGain))×")
            }
        }
        credit("Averaging N frames improves SNR by √N for random noise (Siril, “Signal to noise ratio”). Fixed-pattern noise needs darks or dithering.")
    }

    @ViewBuilder private var timelapse: some View {
        Card {
            ChoiceRow(label: "Solve from", options: TimelapseMode.allCases.map { ($0, $0.rawValue) },
                      selection: $inputs.timelapseMode, id: "tools.tlMode")
            FieldRow(label: "Exposure", unit: "s", text: $inputs.tlExposure, placeholder: "15", id: "tools.tlExposure")
            FieldRow(label: "Buffer", unit: "s", text: $inputs.tlBuffer, placeholder: "1", id: "tools.tlBuffer")
            FieldRow(label: "Frame rate", unit: "fps", text: $inputs.tlFPS, placeholder: "24", id: "tools.tlFPS")
            if inputs.timelapseMode != .eventAndClip {
                FieldRow(label: "Interval", unit: "s", text: $inputs.tlInterval, placeholder: "20", id: "tools.tlInterval")
            }
            if inputs.timelapseMode != .intervalAndEvent {
                FieldRow(label: "Clip length", unit: "s", text: $inputs.tlClip, placeholder: "10", id: "tools.tlClip")
            }
            if inputs.timelapseMode != .intervalAndClip {
                FieldRow(label: "Event duration", unit: "min", text: $inputs.tlEventMinutes, placeholder: "60", id: "tools.tlEvent")
            }
        }
        Card {
            let exposure = ToolsFormat.required(inputs.tlExposure)
            let buffer = ToolsFormat.required(inputs.tlBuffer)
            let fps = ToolsFormat.required(inputs.tlFPS)
            let interval = ToolsFormat.required(inputs.tlInterval)
            let clip = ToolsFormat.required(inputs.tlClip)
            let event = ToolsFormat.required(inputs.tlEventMinutes) * 60
            let mode = inputs.timelapseMode
            let plan = Result { () throws(ExposureError) in
                switch mode {
                case .intervalAndClip:
                    try Timelapse.plan(exposure: exposure, interval: interval, fps: fps, clipSeconds: clip, buffer: buffer)
                case .intervalAndEvent:
                    try Timelapse.plan(exposure: exposure, interval: interval, fps: fps, eventDuration: event, buffer: buffer)
                case .eventAndClip:
                    try Timelapse.plan(exposure: exposure, fps: fps, clipSeconds: clip, eventDuration: event, buffer: buffer)
                }
            }
            outcome(plan) { p in
                ResultRow(label: "Interval", value: ToolsFormat.duration(p.interval), id: "tools.result.interval")
                ResultRow(label: "Frames", value: "\(p.frames)")
                ResultRow(label: "Clip length", value: "\(ToolsFormat.duration(p.clipSeconds)) at \(ToolsFormat.number(p.fps)) fps")
                ResultRow(label: "Event duration", value: ToolsFormat.duration(p.eventDuration))
            }
        }
        credit("frames = clip × fps, shooting time = frames × interval (Enlaps time-lapse calculator). The interval must cover the exposure plus the camera's buffer time.")
    }

    // MARK: Helpers

    @ViewBuilder
    private func outcome<T, V: View>(_ result: Result<T, ExposureError>, @ViewBuilder _ content: (T) -> V) -> some View {
        switch result {
        case .success(let value): content(value)
        case .failure(let error): ErrorLine(message: error.message)
        }
    }

    private func credit(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(palette.secondary)
    }
}
