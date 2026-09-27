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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    if let working {
                        DataStatusLine(symbol: "clock", text: working)
                            .accessibilityIdentifier("location.working")
                    }
                    gpsSection
                    entrySection
                    spotsSection
                    Label("Precise coordinates stay on this phone. Weather requests and the time-zone lookup use a 0.05° cell (about 5 km).",
                          systemImage: "lock")
                        .font(.dsFootnote)
                        .foregroundStyle(palette.secondary)
                }
                .padding(DS.Space.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .sheetChrome("Location", cancel: SheetAction(title: "Cancel", id: "location.cancel") { dismiss() })
        }
        .presentationDragIndicator(.hidden)
        .sheetPresentation(palette)
    }

    private var gpsSection: some View {
        section("Where you are") {
            Button {
                Task { await useGPS() }
            } label: {
                Label("Use my location", systemImage: "location").frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(.secondary))
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
                    .foregroundStyle(text.isEmpty ? palette.tertiary : palette.primary)
                    .frame(maxWidth: .infinity, minHeight: DS.minTarget, alignment: .leading)
                    .padding(.horizontal, DS.Space.m)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
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
                    .font(.dsNumber)
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, DS.Space.m)
                    .frame(minHeight: DS.minTarget)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
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
                .tint(palette.raised)
                .foregroundStyle(palette.primary)
                Spacer()
                Button("Use", action: useText)
                    .buttonStyle(ActionButtonStyle(.primary))
                    .disabled(working != nil)
                    .accessibilityLabel("Use these coordinates")
                    .accessibilityIdentifier("location.use")
            }
            if let problem {
                Text(problem)
                    .font(.dsFootnote)
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
                        Disclosure {
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(spot.name).font(.dsBody).foregroundStyle(palette.primary)
                                Text(Format.coordinate(spot.latitude, spot.longitude))
                                    .font(.dsData)
                                    .foregroundStyle(palette.secondary)
                            }
                        }
                        .frame(minHeight: DS.minTarget)
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plans tonight for this spot")
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SectionCard(title) { content() }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.dsFootnote).foregroundStyle(palette.secondary)
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
        let choice = await PlaceChoice.coordinates(latitude: latitude, longitude: longitude, name: name, night: night)
        working = nil
        onChoose(choice)
        dismiss()
    }
}
