import SwiftUI

/// Stub; built in M2 (astronomy) and M4 (conditions).
struct TonightScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Tonight", systemImage: "hammer", description: Text("Coming in M2 (astronomy) and M4 (conditions)."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Tonight")
                .toolbar { FieldModeToggle() }
        }
    }
}
