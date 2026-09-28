import ImageIO
import SkyCore
import SwiftUI

/// After a stack: the image, what went into it, and what to do with it
/// (review 2026-09-27 §7). "Save image" is the main action; every original
/// frame is a separate choice. No AI step: the stack is the noise
/// reduction, and nothing learned or generative touches the pixels.
struct CaptureResultView: View {
    let model: CaptureModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    picture
                    if let outcome = model.outcome {
                        if outcome.isUnaligned { unalignedNotice(outcome) }
                        counts(outcome)
                    }
                    actions
                    SectionCard("How it was made") {
                        Text(howMade).font(.dsFootnote).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("capture.result.method")
                    }
                }
                .padding(DS.Space.screen)
            }
            .background(palette.background)
            .sheetChrome("Result", confirm: SheetAction(title: "Done", id: "capture.result.done") { dismiss() }, fieldToggle: true)
        }
        .sheetPresentation(palette)
        .task(id: model.lastStack) {
            guard let url = model.lastStack else { return }
            image = await Task.detached { StretchedPreview.make(url: url, maxPixel: 1400) }.value
        }
    }

    private var picture: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(model.outcome?.kind == .trails ? "The star-trail image" : "The stacked image")
                    .accessibilityIdentifier("capture.result.image")
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(palette.surface)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay { UnavailableValue(reason: model.lastStack == nil ? "No finished image." : "Loading the image…") }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if image != nil {
                Text("Brightened for viewing; the saved file is unchanged")
                    .font(.caption2).foregroundStyle(palette.primary)
                    .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
                    .floatingSurface(palette, shape: Capsule())
                    .padding(DS.Space.s)
            }
        }
    }

    private func unalignedNotice(_ outcome: CaptureOutcome) -> some View {
        SectionCard {
            Label {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Not aligned on stars").font(.dsHeadline).foregroundStyle(palette.primary)
                    Text("\(outcome.unalignedReason ?? "") The frames were averaged as shot, so any drift or rotation between them blurs the stars. On a tripod over a short span this is usually fine.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.marginal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.result.unaligned")
        }
    }

    private func counts(_ o: CaptureOutcome) -> some View {
        SectionCard("Frames") {
            CaptureRow("Planned", "\(o.planned)")
            CaptureRow("Saved", "\(o.saved)", id: "capture.result.saved")
            switch o.kind {
            case .stack:
                CaptureRow(o.isUnaligned ? "Averaged unaligned" : "Aligned and stacked",
                           o.aligned.map(String.init) ?? "\(o.used)", id: "capture.result.aligned")
            case .trails:
                CaptureRow("Combined (brightest per pixel)", "\(o.used)", id: "capture.result.aligned")
            }
            CaptureRow("Left out (moved, repeated or not aligned)", "\(o.rejected)", id: "capture.result.rejected")
            CaptureRow("Total exposure", CaptureWording.duration(o.integration))
            CaptureRow("Frames saved as", model.formatTitle)
            CaptureRow("Image saved as", "16-bit linear TIFF")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Button {
                Task { await save(all: false) }
            } label: {
                Label("Save image to Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(.primary))
            .disabled(saving || model.lastStack == nil)
            .accessibilityIdentifier("capture.result.saveImage")
            Button {
                Task { await save(all: true) }
            } label: {
                Label("Also save every original frame (\(model.outcome?.saved ?? 0))", systemImage: "photo.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(.secondary))
            .disabled(saving || model.lastFolder == nil)
            .accessibilityIdentifier("capture.result.saveOriginals")
            if let message {
                Text(message).font(.dsFootnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture.result.message")
            }
            if let folder = model.lastFolder {
                Text("Everything also stays in Files › On My iPhone › Dark Sky › Captures › \(folder.lastPathComponent).")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var howMade: String {
        let trails = model.outcome?.kind == .trails
        return (trails
            ? "The brightest value of each pixel across every frame, nothing aligned, so the stars draw arcs."
            : "Frames aligned on their stars (shift and rotation), then averaged with outliers such as satellites and aircraft rejected (sigma clipping).")
            + " The noise reduction is the stacking itself: noise falls by about the square root of the number of frames. No AI denoise or other learned or generative processing was applied; the originals are kept unchanged."
    }

    private func save(all: Bool) async {
        saving = true
        defer { saving = false }
        do {
            if all {
                let n = try await model.saveOriginals()
                message = "Saved \(n) original frames to Photos."
            } else {
                _ = try await model.saveImage()
                message = "Saved the image to Photos."
            }
        } catch {
            message = "Not saved to Photos (\(error.localizedDescription)). The files stay in the Dark Sky folder."
        }
    }
}

/// A display copy of a linear stack: downsampled, then stretched between
/// the 1st and 99.8th luminance percentiles into 8-bit sRGB. Viewing only;
/// the TIFF on disk is never changed.
nonisolated enum StretchedPreview {
    static func make(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { return nil }
        let w = thumb.width, h = thumb.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lum = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { lum[i] = UInt8((UInt16(px[i * 4]) + UInt16(px[i * 4 + 1]) + UInt16(px[i * 4 + 2])) / 3) }
        lum.sort()
        let lo = Double(lum[lum.count / 100]), hi = max(Double(lum[Int(Double(lum.count - 1) * 0.998)]), lo + 1)
        for i in 0..<(w * h) {
            for c in 0..<3 {
                let v = (Double(px[i * 4 + c]) - lo) / (hi - lo)
                px[i * 4 + c] = UInt8(max(0, min(255, v * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
