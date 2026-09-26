import SwiftData
import SwiftUI

/// Create or edit a spot: name, coordinates, time zone, notes. Coordinates
/// are typed or copied from the current place; nothing is looked up online,
/// so a precise pin never leaves the phone.
struct SpotEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state

    let spot: Spot?

    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var notes = ""
    @State private var pickingZone = false

    static let commonZones = ["America/Denver", "America/Phoenix", "America/Boise", "America/Los_Angeles", "America/Chicago"]

    var parsed: (lat: Double, lon: Double)? {
        guard let lat = Self.number(latitude), let lon = Self.number(longitude),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsed != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: prompt("Name"))
                        .accessibilityIdentifier("spot-name")
                    TextField("Latitude", text: $latitude, prompt: prompt("Latitude, e.g. 38.374031"))
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("spot-latitude")
                    TextField("Longitude", text: $longitude, prompt: prompt("Longitude, e.g. -109.965416"))
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("spot-longitude")
                    if !latitude.isEmpty || !longitude.isEmpty, parsed == nil {
                        Text("Latitude −90…90 and longitude −180…180, decimal degrees.")
                            .font(.footnote).foregroundStyle(palette.poor)
                    }
                    if let place = state.place, spot == nil {
                        Button("Fill from current place (\(place.name))") {
                            if name.isEmpty { name = place.name }
                            latitude = String(format: "%.6f", place.latitude)
                            longitude = String(format: "%.6f", place.longitude)
                            timeZoneID = place.timeZoneID
                        }
                    }
                } footer: {
                    Text("Coordinates stay on this phone. Conditions requests send only a cell rounded to 0.05°.")
                        .foregroundStyle(palette.secondary)
                }
                .paletteRow(palette)

                Section {
                    Button { pickingZone = true } label: {
                        Disclosure {
                            Text("Time zone")
                            Spacer()
                            Text(timeZoneID).foregroundStyle(palette.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spot-timezone")
                } footer: {
                    Text("Nights are planned from 21:00 in this zone.").foregroundStyle(palette.secondary)
                }
                .paletteRow(palette)

                Section {
                    TextField("Notes", text: $notes, prompt: prompt("Access, parking, where to set up"), axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("spot-notes")
                }
                .paletteRow(palette)
            }
            .paletteList()
            .paletteTitle(spot == nil ? "New spot" : "Edit spot", palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                        .foregroundStyle(canSave ? palette.accent : palette.secondary)
                        .accessibilityIdentifier("spot-save")
                }
                .sharedBackgroundVisibility(palette.toolbarGlass)
            }
            .navigationDestination(isPresented: $pickingZone) {
                ZonePicker(selection: $timeZoneID, zones: zones)
            }
            .onAppear(perform: load)
        }
        .tint(palette.accent)
        .preferredColorScheme(palette.colorScheme)
        .presentationBackground(palette.background)
    }

    var zones: [String] {
        let america = TimeZone.knownTimeZoneIdentifiers.filter { $0.hasPrefix("America/") && !Self.commonZones.contains($0) }
        var out = Self.commonZones
        for z in [TimeZone.current.identifier, timeZoneID] where !out.contains(z) { out.insert(z, at: 0) }
        return out + america.filter { !out.contains($0) }
    }

    func prompt(_ text: String) -> Text { Text(text).foregroundStyle(palette.secondary) }

    func load() {
        guard let spot else { return }
        name = spot.name
        latitude = String(format: "%.6f", spot.latitude)
        longitude = String(format: "%.6f", spot.longitude)
        timeZoneID = spot.timeZoneID
        notes = spot.notes
    }

    func save() {
        guard let p = parsed else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let spot {
            let moved = spot.latitude != p.lat || spot.longitude != p.lon
            spot.name = trimmed
            spot.latitude = p.lat
            spot.longitude = p.lon
            spot.timeZoneID = timeZoneID
            spot.notes = notes
            if moved {
                // A skyline belongs to one point; a moved spot needs a new one.
                spot.horizonCSV = nil
                spot.horizonSource = nil
                spot.horizonUpdatedAt = nil
            }
            spot.weekData = nil
            if spot.isPinned { WidgetBridge.publish(spot) }
        } else {
            context.insert(Spot(name: trimmed, latitude: p.lat, longitude: p.lon, timeZoneID: timeZoneID, notes: notes))
        }
        try? context.save()
        dismiss()
    }

    /// Accepts "−" (U+2212) and a trailing hemisphere-free decimal.
    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{2212}", with: "-"))
    }
}

struct ZonePicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let zones: [String]

    var body: some View {
        List(zones, id: \.self) { zone in
            Button {
                selection = zone
                dismiss()
            } label: {
                HStack {
                    Text(zone)
                    Spacer()
                    if zone == selection { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paletteRow(palette)
        }
        .paletteList()
        .paletteTitle("Time zone", palette)
        .paletteBackButton(palette, dismiss: dismiss)
    }
}
