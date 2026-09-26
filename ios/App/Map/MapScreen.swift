import SwiftUI

/// Stub; built in M6.
struct MapScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Map", systemImage: "hammer", description: Text("Coming in M6."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Map")
                .toolbar { FieldModeToggle() }
        }
    }
}
