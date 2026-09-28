import SkyCore
import SwiftUI
import UIKit

/// "How to shoot": two paths, shown the first time Capture opens and from
/// its toolbar (review 2026-09-27 §7). Apple Camera's Night mode is Apple's
/// own pipeline, closed to apps; Dark Sky's path stacks frames whose length
/// is whatever this phone's camera reports, stated as this phone's number.
struct CaptureGuideSheet: View {
    enum Path: Hashable { case apple, darkSky }

    let model: CaptureModel
    var onUsePreset: () -> Void
    @State var path: Path = .apple
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    Text("Two ways to photograph the night sky with this iPhone. Both need the phone held still, ideally on a tripod.")
                        .font(.dsCallout).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CaptureChoiceRow(label: "Choose a way", options: [
                        .init(value: .apple, title: "Use Apple Camera"),
                        .init(value: .darkSky, title: "Capture and stack in Dark Sky"),
                    ], selection: $path, id: "capture.guide.path")
                    switch path {
                    case .apple: appleCamera
                    case .darkSky: darkSky
                    }
                }
                .padding(DS.Space.screen)
            }
            .background(palette.background)
            .sheetChrome("How to shoot", confirm: SheetAction(title: "Done", id: "capture.guide.done") { dismiss() }, fieldToggle: true)
        }
        .sheetPresentation(palette)
    }

    // MARK: Apple Camera

    private var appleCamera: some View {
        VStack(alignment: .leading, spacing: DS.Space.cardGap) {
            SectionCard("Use Apple Camera") {
                Text("The simplest route: Apple's Night mode combines many frames for you. It is only in the Camera app; no other app can use it.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                step(1, "Keep it still", "Put the phone on a tripod or a solid surface. Night mode offers longer captures when the phone is steady.")
                step(2, "Choose Max when it is offered", "Night mode turns on by itself in low light. Tap its button and slide to Max, which extends the capture time. How long depends on the phone, the light and how still it is; there is no fixed length.")
                step(3, "Flash and Live Photos off", "Turning on Live Photos or the flash turns Night mode off.")
                step(4, "ProRAW if you will edit", "On Pro models, Settings › Camera › Formats › Apple ProRAW keeps more editing room. Apple gives about 25 MB per photo at 12 MP and about 75 MB at 48 MP, 10 to 12 times a HEIF photo. Resolution options depend on the model.")
            }
            .accessibilityIdentifier("capture.guide.apple")
            SectionCard("Apple's guides") {
                link("Night mode on iPhone", "https://support.apple.com/en-us/102519", id: "capture.guide.nightModeLink")
                link("Apple ProRAW on iPhone", "https://support.apple.com/en-us/119916", id: "capture.guide.proRAWLink")
                if palette.isField {
                    Text("These open Safari, which field mode cannot turn red.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                }
            }
        }
    }

    // MARK: Dark Sky

    private var darkSky: some View {
        VStack(alignment: .leading, spacing: DS.Space.cardGap) {
            SectionCard("What this phone allows") {
                if let camera = model.camera {
                    Text(CaptureWording.ceiling(camera.maxExposure, device: "this iPhone", system: Self.system))
                        .font(.dsFootnote).foregroundStyle(palette.primary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture.guide.ceiling")
                    CaptureRow("Camera", camera.lens.title)
                    CaptureRow("ISO", "\(Int(camera.minISO).formatted())–\(Int(camera.maxISO).formatted())")
                    CaptureRow("Aperture", camera.apertures.map { Self.fNumber($0) }.joined(separator: ", "))
                    CaptureRow("RAW", model.rawAvailable ? model.rawTitle : "not offered")
                    Text("Read from the camera just now, not assumed. Apps cannot use Night mode, so longer light comes from stacking many frames.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    UnavailableValue(reason: "Detected when the camera starts on the Capture screen.")
                }
            }
            SectionCard("Four different times") {
                term("Exposure per frame", model.durations.map { CaptureWording.duration($0.perFrame) }, "How long the shutter stays open for one frame. It cannot pass this phone's maximum.")
                term("Total exposure", model.durations.map { CaptureWording.duration($0.integration) }, "Frames × exposure: the light the stack collects.")
                term("Sequence time", model.durations.map { "about " + CaptureWording.duration($0.sequence) }, "Clock time from Start to the last frame, with the self-timer. Settling and heat pauses can add to it.")
                term("Star-trailing limit (NPF)", model.npfSeconds.map { CaptureWording.duration($0) }, "How long stars stay points with this lens. A limit set by the stars, not a length the camera can expose. Known after the first frame, from its lens data.")
            }
            .accessibilityIdentifier("capture.guide.times")
            SectionCard("1. Start with the recommended settings") {
                Text(presetText).font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    onUsePreset()
                    dismiss()
                } label: {
                    Label("Use recommended settings", systemImage: "wand.and.stars.inverse").frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(.primary))
                .disabled(model.camera == nil || model.phase.isBusy)
                .accessibilityIdentifier("capture.guide.usePreset")
            }
            SectionCard("2. Focus on a star") {
                Text("Make the star as small and sharp as possible.").font(.dsHeadline).foregroundStyle(palette.primary)
                    .accessibilityIdentifier("capture.guide.focus")
                Text("Aim at a bright star or a distant light. Watch the magnifier and step the focus farther or nearer until the star is the smallest point you can get; the star size readout is lowest there. Focus stays locked for the whole sequence.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                MoreInfo(title: "About the star size readout") {
                    Text("It is the half-flux radius (HFR): the radius, in preview pixels, holding half of each star's light, as a median over the stars found in the centre. A sharper focus gives a smaller number. \"Autofocus once\" is a quick start; the far end of the lens travel is not infinity on an iPhone.")
                }
            }
            SectionCard("3. Adjust by hand if you need to") {
                Text("Manual controls sit below focus on the Capture screen: camera, exposure, ISO, aperture, the number of frames, resolution, file format and the self-timer. Tune ISO from a test frame: raise it if the sky is black and noisy, lower it if bright stars clip.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var presetText: String {
        guard let camera = model.camera, let p = model.preset else {
            return "Main camera, widest aperture, the longest frame the camera allows, a 9-frame test, 12 MP, ProRAW where offered and a 5 s self-timer."
        }
        let size = model.resolutionChoices.first?.title ?? "12 MP"
        return "Main camera at \(p.aperture.map(Self.fNumber) ?? "its aperture"), \(CaptureWording.duration(p.exposure)) frames (this phone's maximum), ISO \(Int(p.iso)) as a starting point, a 9-frame test, \(size), \(p.raw ? model.rawTitle : "HEIC") and a \(p.selfTimer) s self-timer. The camera now: \(camera.lens.title)."
    }

    // MARK: Pieces

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text("\(n)").font(.dsHeadline.monospacedDigit()).foregroundStyle(palette.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                Text(text).font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func term(_ name: String, _ value: String?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
                Spacer(minLength: DS.Space.s)
                Text(value ?? Voice.unavailable).font(.dsCallout.monospacedDigit())
                    .foregroundStyle(value == nil ? palette.tertiary : palette.primary)
            }
            Text(text).font(.dsFootnote).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func link(_ title: String, _ url: String, id: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title).font(.dsCallout)
                Spacer()
                Image(systemName: "arrow.up.right.square").accessibilityHidden(true)
            }
            .foregroundStyle(palette.accent)
            .frame(minHeight: DS.minTarget)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens Apple Support in Safari")
        .accessibilityIdentifier(id)
    }

    static func fNumber(_ f: Float) -> String { String(format: "f/%.3g", f) }

    static var system: String { "iOS \(UIDevice.current.systemVersion)" }
}
