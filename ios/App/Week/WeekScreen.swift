import SwiftUI

/// Stub; built in M5.
struct WeekScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Week", systemImage: "hammer", description: Text("Coming in M5."))
                .foregroundStyle(palette.secondary)
                .background(palette.background)
                .navigationTitle("Week")
                .toolbar { FieldModeToggle() }
        }
    }
}
