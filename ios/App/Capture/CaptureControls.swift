import SkyCore
import SwiftUI

/// A row of choices for the capture screen: `ChoiceRow`'s look with a 44 pt
/// minimum (HIG) and an optional second line per option, which the
/// resolution choice uses for its storage estimate.
struct CaptureChoiceRow<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var detail: String?
    }

    let label: String
    let options: [Option]
    @Binding var selection: Value
    let id: String
    var disabled = false
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(label).font(.dsCallout).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
            let stacked = typeSize.isAccessibilitySize || options.count > 4
            let layout = stacked ? AnyLayout(VStackLayout(spacing: DS.Space.xs)) : AnyLayout(HStackLayout(spacing: DS.Space.xs))
            layout {
                ForEach(options, id: \.title) { option in
                    let on = option.value == selection
                    Button { selection = option.value } label: {
                        VStack(spacing: DS.Space.xxs) {
                            Text(option.title)
                                .font(.dsCallout.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? palette.onAccent : palette.primary)
                            if let detail = option.detail {
                                Text(detail).font(.caption.monospacedDigit())
                                    .foregroundStyle(on ? palette.onAccent : palette.secondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.vertical, DS.Space.xs)
                        .padding(.horizontal, DS.Space.xs)
                        .frame(maxWidth: .infinity, minHeight: DS.minTarget)
                        .background(on ? palette.accentFill : palette.raised,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control - 2, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control - 2, style: .continuous)
                            .strokeBorder(on ? palette.accentEdge : .clear, lineWidth: DS.Stroke.focus))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityLabel("\(label): \(option.title)")
                    .accessibilityValue(option.detail ?? "")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(id).\(option.title)")
                }
            }
            .padding(DS.Space.xxs)
            .background(palette.background, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)
        }
    }
}

/// A labelled value row inside a capture card.
struct CaptureRow: View {
    let label: String
    let value: String
    var id: String?
    @Environment(\.palette) private var palette

    init(_ label: String, _ value: String, id: String? = nil) {
        self.label = label
        self.value = value
        self.id = id
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.dsCallout).foregroundStyle(palette.secondary)
                Spacer(minLength: DS.Space.s)
                Text(value).font(.dsCallout.monospacedDigit()).foregroundStyle(palette.primary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(label).font(.dsCallout).foregroundStyle(palette.secondary)
                Text(value).font(.dsCallout.monospacedDigit()).foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "")
    }
}

/// Start, Stop and progress, fixed at the bottom of the capture screen so
/// they are always in thumb reach while the preview and settings scroll
/// above (review 2026-09-27 §6). "Stop and stack" finishes and stacks what
/// was shot; "Cancel" ends the run and stacks nothing. Frames are always kept.
struct CaptureControlBar: View {
    let model: CaptureModel
    var onShowResult: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            switch model.phase {
            case .idle, .finished, .stopped, .failed:
                idle
            case .preparing, .countdown, .settling, .capturing, .coolingDown:
                running
            case .draining:
                progress(nil, "Saving the last frames…")
                wide(Button {} label: { Label("Saving the last frames…", systemImage: "hourglass") }, .secondary, id: "capture.draining")
                    .disabled(true)
            case .stacking(let fraction, let what):
                progress(fraction, "Stacking: \(what) (\(Int(fraction * 100)) %)")
                wide(Button { model.cancel() } label: { Label("Stop stacking", systemImage: "xmark.circle") }, .secondary, id: "capture.stopStacking")
                caption("Stops within about a second. The frames are kept and can be stacked again here.")
            case .waitingForPreviousRun:
                progress(nil, "Finishing the previous sequence…")
                wide(Button {} label: { Label("Finishing the previous sequence…", systemImage: "hourglass") }, .secondary, id: "capture.waiting")
                    .disabled(true)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.bar")
    }

    // MARK: States

    @ViewBuilder private var idle: some View {
        switch model.phase {
        case .finished(let text), .stopped(let text), .failed(let text):
            Text(text).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture.status")
        default:
            EmptyView()
        }
        if let d = model.durations {
            Text("\(d.frames) × \(CaptureWording.duration(d.perFrame)) · \(CaptureWording.duration(d.integration)) of light · about \(CaptureWording.duration(d.sequence))")
                .font(.dsFootnote.monospacedDigit()).foregroundStyle(palette.secondary)
                .accessibilityLabel("\(d.frames) frames of \(CaptureWording.duration(d.perFrame)), \(CaptureWording.duration(d.integration)) total exposure, about \(CaptureWording.duration(d.sequence)) from start to finish")
                .accessibilityIdentifier("capture.bar.summary")
        }
        buttons {
            if model.outcome != nil, case .finished = model.phase {
                Button(action: onShowResult) { Label("Result", systemImage: "photo") }
                    .buttonStyle(ActionButtonStyle(.secondary))
                    .accessibilityIdentifier("capture.showResult")
            }
            wide(Button { model.start() } label: {
                Label("Start \(model.frameCount) frames", systemImage: "camera.aperture")
            }, .primary, id: "capture.start")
            .disabled(model.plan == nil)
        }
    }

    @ViewBuilder private var running: some View {
        let (fraction, headline) = runningText
        progress(fraction, headline)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(detailLine(now: context.date))
                .font(.dsFootnote.monospacedDigit()).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture.bar.detail")
        }
        buttons {
            wide(Button { model.stopAndStack() } label: { Label("Stop and stack", systemImage: "stop.circle") }, .primary, id: "capture.stopAndStack")
            wide(Button { model.cancel() } label: { Label("Cancel", systemImage: "xmark.circle") }, .secondary, id: "capture.cancel")
        }
        caption("Stop and stack: finish now and stack the frames shot. Cancel: finish without stacking. Every frame is kept.")
    }

    private var runningText: (Double?, String) {
        switch model.phase {
        case .preparing: (nil, "Locking exposure and focus…")
        case .countdown(let s): (nil, "Self-timer: \(s)")
        case .settling: (nil, "Waiting for the tripod to settle…")
        case .capturing(let i, let n): (Double(i - 1) / Double(max(n, 1)), "Frame \(i) of \(n)")
        case .coolingDown(let s): (nil, "Hot: pausing \(Int(s)) s between frames")
        default: (nil, "")
        }
    }

    private func detailLine(now: Date) -> String {
        var parts: [String] = []
        if let start = model.runStarted { parts.append("\(Self.clock(now.timeIntervalSince(start))) elapsed") }
        if case .capturing(let i, let n) = model.phase {
            let left = Double(n - i + 1) * (model.subExposure + model.gap)
            parts.append("about \(Self.clock(left)) left")
        }
        parts.append("\(model.savedFrames) saved")
        parts.append("heat \(CameraProbe.thermalName(model.thermal))")
        return parts.joined(separator: " · ")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Pieces

    private func progress(_ fraction: Double?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(text).font(.dsHeadline.monospacedDigit()).foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture.status")
            if let fraction { PaletteProgress(value: fraction).accessibilityIdentifier("capture.progress") }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.dsFootnote).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: DS.Space.s) { content() }
        } else {
            HStack(spacing: DS.Space.s) { content() }
        }
    }

    private func wide(_ button: some View, _ kind: ActionButtonStyle.Kind, id: String) -> some View {
        button
            .labelStyle(WideLabelStyle())
            .buttonStyle(ActionButtonStyle(kind))
            .accessibilityIdentifier(id)
    }
}

/// Icon and title centred across the full width of a bar button.
private struct WideLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.xs) {
            configuration.icon
            configuration.title
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}
