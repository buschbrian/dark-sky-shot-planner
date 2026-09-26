import SwiftUI

/// Stub; built in M10.
struct ToolsScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Tools", systemImage: "hammer", description: Text("Coming in M10."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Tools")
                .toolbar { FieldModeToggle() }
        }
    }
}
