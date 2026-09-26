import SwiftUI

/// Navigation chrome drawn from the palette, so field mode has no system
/// white title, grey bar material or light scroll indicator.
struct PaletteChrome<Trailing: View>: ViewModifier {
    let title: String
    var pushed = false
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The system back button is grey glass with a white chevron; field mode draws its own.
            .navigationBarBackButtonHidden(pushed && state.fieldMode)
            .toolbar {
                if pushed && state.fieldMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward").font(.headline).foregroundStyle(palette.accent)
                        }
                        .accessibilityLabel("Back")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .principal) {
                    Text(title).font(.headline).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    trailing()
                    FieldModeToggle()
                }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
            }
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollIndicators(state.fieldMode ? .hidden : .automatic)
    }
}

extension View {
    func paletteChrome(_ title: String, pushed: Bool = false) -> some View {
        modifier(PaletteChrome(title: title, pushed: pushed) { EmptyView() })
    }

    func paletteChrome<T: View>(_ title: String, @ViewBuilder trailing: @escaping () -> T) -> some View {
        modifier(PaletteChrome(title: title, trailing: trailing))
    }
}

/// Dims on press instead of the system grey highlight.
struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A rounded palette surface for grouped content.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
