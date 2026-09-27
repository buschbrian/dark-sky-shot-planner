import SwiftUI

// Names the five screens used before the design system, kept so branches
// written against them still build after a merge. Each forwards to the design
// system; the deprecation warning says what to use instead. Delete this file
// once no caller is left (`grep -rn "deprecated" ios/App`).

@available(*, deprecated, message: "Use SectionCard")
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SectionCard { VStack(alignment: .leading, spacing: DS.Space.s) { content } }
    }
}

@available(*, deprecated, message: "Use SectionCard(title)")
struct MapSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        SectionCard(title) { content }
    }
}

@available(*, deprecated, message: "Use Button with ActionButtonStyle")
struct PaletteButton: View {
    var title: String?
    var systemImage: String?
    var label: String?
    var action: () -> Void

    init(_ title: String? = nil, systemImage: String? = nil, label: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemImage { Image(systemName: systemImage) }
                if let title { Text(title) }
            }
        }
        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
        .accessibilityLabel(label ?? title ?? "")
    }
}

@available(*, deprecated, message: "Use ActionButtonStyle")
struct PaletteButtonStyle: ButtonStyle {
    let palette: Palette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonStyle(prominent ? .primary : .secondary).makeBody(configuration: configuration)
    }
}

@available(*, deprecated, message: "Use PaletteToggleStyle()")
typealias MapToggleStyle = PaletteToggleStyle


extension View {
    @available(*, deprecated, message: "Use SectionCard")
    func card(_ palette: Palette) -> some View {
        padding(DS.Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    @available(*, deprecated, message: "Use screenChrome")
    func paletteChrome(_ title: String, pushed: Bool = false) -> some View {
        screenChrome(title, pushed: pushed)
    }

    @available(*, deprecated, message: "Use screenChrome")
    func paletteChrome<T: View>(_ title: String, @ViewBuilder trailing: @escaping () -> T) -> some View {
        screenChrome(title, trailing: trailing)
    }

    @available(*, deprecated, message: "Use screenChrome")
    func paletteTitle(_ title: String, _ palette: Palette) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.dsNavTitle).foregroundStyle(palette.primary)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }

    @available(*, deprecated, message: "Use screenChrome(title, pushed: true)")
    func paletteBackButton(_ palette: Palette, dismiss: DismissAction) -> some View {
        navigationBarBackButtonHidden(palette.isField)
            .toolbar {
                if palette.isField {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel("Back")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}
