import SwiftUI

/// Field mode (ios/AGENTS.md invariant 5): pure red for everything the app
/// draws. The shell multiplies the window by red and hides the status bar and
/// home indicator; sheets and full-screen covers are separate presentations,
/// so each applies `fieldSafe` itself.
extension View {
    /// Multiplies by pure red (any stray white becomes red, any blue black)
    /// and hides the status bar and home indicator while field mode is on.
    func fieldSafe(_ on: Bool) -> some View {
        colorMultiply(on ? Color.red(1) : .white)
            .statusBarHidden(on)
            .persistentSystemOverlays(on ? .hidden : .automatic)
    }
}

extension Palette {
    /// Toolbar glass is grey, so field mode hides it.
    var toolbarGlass: Visibility { isField ? .hidden : .automatic }
}

/// The field-mode switch. It lives in one place on every screen: the last
/// item on the trailing side of the navigation bar (`screenChrome`).
struct FieldModeToggle: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            state.fieldMode.toggle()
        } label: {
            Image(systemName: state.fieldMode ? "moon.stars.fill" : "moon.stars")
                .foregroundStyle(state.fieldMode ? palette.accent : palette.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Field mode")
        .accessibilityValue(state.fieldMode ? "On" : "Off")
        .accessibilityHint("Switches the whole app to dim red")
    }
}
