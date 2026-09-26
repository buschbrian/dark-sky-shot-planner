import SwiftUI

/// Field mode (ios/AGENTS.md invariant 5): in red mode no white or blue pixel
/// anywhere. Views take every color from the palette, never a literal.
struct Palette: Equatable {
    let background: Color
    let surface: Color
    let primary: Color
    let secondary: Color
    let accent: Color
    let good: Color
    let marginal: Color
    let poor: Color
    let colorScheme: ColorScheme

    static let standard = Palette(
        background: Color(.systemBackground), surface: Color(.secondarySystemBackground),
        primary: .primary, secondary: .secondary, accent: .indigo,
        good: .green, marginal: .orange, poor: .red, colorScheme: .dark)

    /// Pure red channel only, black background. Levels differ by brightness.
    static let field = Palette(
        background: .black, surface: Color(red: 0.10, green: 0, blue: 0),
        primary: Color(red: 0.85, green: 0, blue: 0), secondary: Color(red: 0.55, green: 0, blue: 0),
        accent: Color(red: 1.0, green: 0, blue: 0),
        good: Color(red: 0.85, green: 0, blue: 0), marginal: Color(red: 0.6, green: 0, blue: 0),
        poor: Color(red: 0.4, green: 0, blue: 0), colorScheme: .dark)
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.standard
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Toolbar toggle reachable from every screen.
struct FieldModeToggle: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Toggle(isOn: $state.fieldMode) {
            Label("Field mode", systemImage: "moon.stars")
        }
        .toggleStyle(.button)
        .accessibilityHint("Switches the whole app to dim red")
    }
}
