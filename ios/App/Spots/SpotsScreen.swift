import SwiftUI

/// Stub; built in M8.
struct SpotsScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Spots", systemImage: "hammer", description: Text("Coming in M8."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Spots")
                .toolbar { FieldModeToggle() }
        }
    }
}
