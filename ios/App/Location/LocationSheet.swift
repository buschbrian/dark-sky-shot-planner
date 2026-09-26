import SkyCore
import SwiftData
import SwiftUI

struct LocationChoice {
    var place: Place
    var zoneIsDeviceGuess: Bool
    /// Set when a pasted web link names a night.
    var night: NightDate?
}

/// Where Tonight plans for: GPS, typed or pasted coordinates (or the web
/// app's share link), or a saved spot.
struct LocationSheet: View {
    let onChoose: (LocationChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Query(sort: \Spot.name) private var spots: [Spot]
    @State private var text = ""
    @State private var problem: String?
    @State private var working: String?
    @State private var gps = LocationProvider()

    private var lookupZones: Bool { !ProcessInfo.processInfo.arguments.contains("-DarkSkyUITest") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let working {
                        Text(working)
                            .foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("location.working")
                    }
                    gpsSection
                    entrySection
                    spotsSection
                    Text("Precise coordinates stay on this phone. Weather requests and the time-zone lookup use a 0.05° cell (about 5 km).")
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Location").font(.headline).foregroundStyle(palette.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("location.cancel")
                }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
            }
        }
        .presentationBackground(palette.background)
        .presentationDragIndicator(.hidden)
        .fieldSafe(state.fieldMode)
    }

    private var gpsSection: some View {
        section("Where you are") {
            Button {
                Task { await useGPS() }
            } label: {
                Label("Use my location", systemImage: "location")
            }
            .buttonStyle(PaletteButtonStyle(palette: palette))
            .disabled(gps.status == .locating || working != nil)
            .accessibilityIdentifier("location.gps")
            switch gps.status {
            case .idle: EmptyView()
            case .locating: note("Finding your location…")
            case .denied: note("Location access is off for Dark Sky. Allow it in Settings, or type coordinates below.")
            case .unavailable: note("No GPS fix yet. Try again under open sky, or type coordinates below.")
            }
        }
    }

    private var entrySection: some View {
        section("Coordinates or a web link") {
            if state.fieldMode {
                Text(text.isEmpty ? "38.35, -109.95" : text)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(text.isEmpty ? palette.secondary : palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Coordinates")
                    .accessibilityValue(text.isEmpty ? "empty" : text)
                    .accessibilityIdentifier("location.input")
                CoordinateKeypad(text: $text)
            } else {
                TextField("38.35, -109.95 or a share link", text: $text, axis: .vertical)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(useText)
                    .foregroundStyle(palette.primary)
                    .padding(10)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Coordinates or web link")
                    .accessibilityIdentifier("location.input")
            }
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        text = strings.first ?? ""
                        problem = nil
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.roundedRectangle)
                .tint(palette.surface)
                .foregroundStyle(palette.primary)
                Spacer()
                Button("Use", action: useText)
                    .buttonStyle(PaletteButtonStyle(palette: palette, prominent: true))
                    .disabled(working != nil)
                    .accessibilityLabel("Use these coordinates")
                    .accessibilityIdentifier("location.use")
            }
            if let problem {
                Text(problem)
                    .foregroundStyle(palette.poor)
                    .accessibilityIdentifier("location.problem")
            }
        }
    }

    private var spotsSection: some View {
        section("Saved spots") {
            if spots.isEmpty {
                note("No saved spots yet. Add them in Spots.")
            } else {
                ForEach(spots) { spot in
                    Button {
                        onChoose(LocationChoice(place: spot.place, zoneIsDeviceGuess: false, night: nil))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spot.name).foregroundStyle(palette.primary)
                            Text(Format.coordinate(spot.latitude, spot.longitude))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plans tonight for this spot")
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(palette.secondary)
    }

    private func useText() {
        guard let input = PlaceInput.parse(text) else {
            problem = "Couldn't read that. Type latitude, longitude (38.35, -109.95) or paste a Dark Sky web link."
            return
        }
        problem = nil
        Task {
            await choose(
                latitude: input.latitude, longitude: input.longitude,
                name: Format.coordinate(input.latitude, input.longitude), night: input.night)
        }
    }

    private func useGPS() async {
        guard let fix = await gps.currentLocation() else { return }
        await choose(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, name: "My location", night: nil)
    }

    private func choose(latitude: Double, longitude: Double, name: String, night: NightDate?) async {
        working = "Looking up the time zone…"
        let zone = lookupZones ? await TimeZoneLookup.zone(latitude: latitude, longitude: longitude) : nil
        working = nil
        let tz = zone ?? .current
        onChoose(LocationChoice(
            place: Place(name: name, latitude: latitude, longitude: longitude, timeZoneID: tz.identifier),
            zoneIsDeviceGuess: zone == nil, night: night))
        dismiss()
    }
}
