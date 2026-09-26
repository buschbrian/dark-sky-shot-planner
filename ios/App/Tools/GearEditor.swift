import SkyCore
import SwiftData
import SwiftUI

/// Create or edit one camera + lens profile. Values are the owner's own,
/// typed from the manual or spec sheet; nothing is looked up.
struct GearEditor: View {
    let gear: Gear?
    var onSaved: (Gear) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var name = ""
    @State private var cameraName = ""
    @State private var sensorWidth = ""
    @State private var sensorHeight = ""
    @State private var imageWidth = ""
    @State private var imageHeight = ""
    @State private var pixelPitch = ""
    @State private var lensName = ""
    @State private var focalLength = ""
    @State private var maxAperture = ""
    @State private var saveError: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Card {
                        section("Profile")
                        textRow("Name (optional)", $name, id: "gear.name")
                    }
                    Card {
                        section("Camera")
                        textRow("Camera name", $cameraName, id: "gear.cameraName")
                        FieldRow(label: "Sensor width", unit: "mm", text: $sensorWidth, placeholder: "35.9", id: "gear.sensorWidth")
                        FieldRow(label: "Sensor height", unit: "mm", text: $sensorHeight, placeholder: "23.9", id: "gear.sensorHeight")
                        FieldRow(label: "Image width", unit: "px", text: $imageWidth, placeholder: "6000", id: "gear.imageWidth")
                        FieldRow(label: "Image height", unit: "px", text: $imageHeight, placeholder: "4000", id: "gear.imageHeight")
                        FieldRow(label: "Pixel pitch (optional)", unit: "µm", text: $pixelPitch, placeholder: "from width", id: "gear.pixelPitch")
                        note("Give the image size in pixels, or the pixel pitch from the spec sheet. A stated pitch wins.")
                    }
                    Card {
                        section("Lens")
                        textRow("Lens name", $lensName, id: "gear.lensName")
                        FieldRow(label: "Focal length", unit: "mm", text: $focalLength, placeholder: "20", id: "gear.focalLength")
                        FieldRow(label: "Widest aperture", unit: "f/", text: $maxAperture, placeholder: "1.4", id: "gear.maxAperture")
                        note("For a zoom, save one profile per focal length you shoot.")
                    }
                    switch draft {
                    case .success: EmptyView()
                    case .failure(let error): ErrorLine(message: error.message)
                    }
                    if let saveError { ErrorLine(message: saveError) }
                    if gear != nil {
                        Button("Delete this gear", role: .destructive) { confirmDelete = true }
                            .foregroundStyle(palette.poor)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle(gear == nil ? "New gear" : "Edit gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled((try? draft.get()) == nil)
                        .accessibilityIdentifier("gear.save")
                }
            }
            .confirmationDialog("Delete this gear?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
        }
        .tint(palette.accent)
        .presentationBackground(palette.background)
        .onAppear(perform: load)
    }

    /// The profiles as typed, validated by SkyCore.
    private var draft: Result<GearKit, ExposureError> {
        Result { () throws(ExposureError) in
            let resolution: PixelResolution?
            if imageWidth.isEmpty && imageHeight.isEmpty {
                resolution = nil
            } else {
                resolution = try PixelResolution(widthPx: pixels(imageWidth, .imageWidth), heightPx: pixels(imageHeight, .imageHeight))
            }
            let camera = try CameraProfile(
                name: cameraName.trimmed.isEmpty ? "Camera" : cameraName.trimmed,
                sensorWidthMM: ToolsFormat.required(sensorWidth),
                sensorHeightMM: ToolsFormat.required(sensorHeight),
                resolution: resolution,
                pixelPitchUM: ToolsFormat.optional(pixelPitch))
            let focal = ToolsFormat.required(focalLength)
            let lens = try LensProfile(
                name: lensName.trimmed.isEmpty ? "\(ToolsFormat.number(focal, digits: 1)) mm" : lensName.trimmed,
                focalLengthMM: focal,
                maxFNumber: ToolsFormat.required(maxAperture))
            let kitName = name.trimmed.isEmpty ? "\(camera.name) + \(lens.name)" : name.trimmed
            return GearKit(name: kitName, camera: camera, lens: lens)
        }
    }

    private func pixels(_ text: String, _ parameter: ExposureParameter) throws(ExposureError) -> Int {
        guard let v = ToolsFormat.parse(text), v == v.rounded(), v >= 1, v < 1_000_000 else {
            throw .invalid(parameter, ToolsFormat.parse(text) ?? .nan)
        }
        return Int(v)
    }

    private func load() {
        guard let gear, let kit = try? GearKit(gear) else { return }
        name = kit.name
        cameraName = kit.camera.name
        sensorWidth = ToolsFormat.number(kit.camera.sensorWidthMM, digits: 3)
        sensorHeight = ToolsFormat.number(kit.camera.sensorHeightMM, digits: 3)
        imageWidth = kit.camera.resolution.map { String($0.widthPx) } ?? ""
        imageHeight = kit.camera.resolution.map { String($0.heightPx) } ?? ""
        pixelPitch = kit.camera.statedPixelPitchUM.map { ToolsFormat.number($0, digits: 3) } ?? ""
        lensName = kit.lens.name
        focalLength = ToolsFormat.number(kit.lens.focalLengthMM, digits: 2)
        maxAperture = ToolsFormat.number(kit.lens.maxFNumber, digits: 2)
    }

    private func save() {
        guard let kit = try? draft.get() else { return }
        do {
            if let gear {
                try kit.store(in: gear)
                onSaved(gear)
            } else {
                let new = try kit.makeGear()
                context.insert(new)
                onSaved(new)
            }
            try context.save()
            dismiss()
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }

    private func delete() {
        guard let gear else { return }
        context.delete(gear)
        try? context.save()
        dismiss()
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(palette.secondary)
    }

    private func textRow(_ label: String, _ text: Binding<String>, id: String) -> some View {
        TextField(label, text: text, prompt: Text(label).foregroundStyle(palette.secondary))
            .textFieldStyle(.plain)
            .foregroundStyle(palette.primary)
            .autocorrectionDisabled()
            .padding(.vertical, 8)
            .accessibilityIdentifier(id)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
