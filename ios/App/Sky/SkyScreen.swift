import SwiftUI

/// Stub; built in M7 (night AR).
struct SkyScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Sky", systemImage: "hammer", description: Text("Coming in M7 (night AR)."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Sky")
                .toolbar { FieldModeToggle() }
        }
    }
}
