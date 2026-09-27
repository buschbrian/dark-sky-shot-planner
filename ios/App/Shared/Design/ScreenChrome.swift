import SwiftUI

/// The one header pattern. Every tab screen:
///
///     [context action]      Title (or a scope picker)      [actions] · [field mode]
///
/// The title is drawn from the palette (the system title is white), the
/// field-mode toggle is always the last trailing item in its own glass group,
/// and in field mode the bar is solid black with no glass, scroll-edge blur
/// or scroll indicator.
struct ScreenChrome<Leading: View, Principal: View, Trailing: View>: ViewModifier {
    let title: String
    var pushed: Bool
    let leading: Leading
    let principal: Principal
    let trailing: Trailing
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The system back button is grey glass with a white chevron; field mode draws its own.
            .navigationBarBackButtonHidden(pushed && palette.isField)
            .toolbar {
                if pushed && palette.isField {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward").font(.headline).foregroundStyle(palette.accent)
                        }
                        .accessibilityLabel("Back")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if Leading.self != EmptyView.self {
                    ToolbarItem(placement: .topBarLeading) { leading }
                        .sharedBackgroundVisibility(palette.toolbarGlass)
                }
                ToolbarItem(placement: .principal) {
                    if Principal.self == EmptyView.self {
                        Text(title)
                            .font(.dsNavTitle)
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        principal
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                if Trailing.self != EmptyView.self {
                    ToolbarItemGroup(placement: .topBarTrailing) { trailing }
                        .sharedBackgroundVisibility(palette.toolbarGlass)
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { FieldModeToggle() }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
            }
            .tint(palette.accent)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(palette.isField ? .visible : .automatic, for: .navigationBar)
            .scrollEdgeEffectHidden(palette.isField, for: .all)
            .scrollIndicators(palette.isField ? .hidden : .automatic)
    }
}

extension View {
    /// A tab screen's header: title, optional context action on the left,
    /// optional actions on the right, then the field-mode toggle.
    func screenChrome<L: View, T: View>(
        _ title: String, pushed: Bool = false,
        @ViewBuilder leading: () -> L = { EmptyView() },
        @ViewBuilder trailing: () -> T = { EmptyView() }
    ) -> some View {
        modifier(ScreenChrome(title: title, pushed: pushed, leading: leading(), principal: EmptyView(), trailing: trailing()))
    }

    /// The same header with a control (the Tonight/Week picker) in place of the title.
    func screenChrome<L: View, P: View, T: View>(
        _ title: String,
        @ViewBuilder leading: () -> L,
        @ViewBuilder principal: () -> P,
        @ViewBuilder trailing: () -> T = { EmptyView() }
    ) -> some View {
        modifier(ScreenChrome(title: title, pushed: false, leading: leading(), principal: principal(), trailing: trailing()))
    }
}

/// A sheet toolbar button.
struct SheetAction {
    let title: String
    var id: String?
    var enabled = true
    let action: () -> Void
}

/// The sheet header: title in the palette, Cancel on the left, a confirming
/// action on the right, and field mode applied to the separate presentation.
struct SheetChrome: ViewModifier {
    let title: String
    let cancel: SheetAction?
    let confirm: SheetAction?
    /// A page pushed inside the sheet: field mode draws its own back chevron.
    var pushed = false
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(pushed && palette.isField)
            .toolbar {
                if pushed && palette.isField {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward").font(.headline).foregroundStyle(palette.accent)
                        }
                        .accessibilityLabel("Back")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .principal) {
                    Text(title).font(.dsNavTitle).foregroundStyle(palette.primary).accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                if let cancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancel.title, action: cancel.action)
                            .foregroundStyle(palette.accent)
                            .accessibilityIdentifier(cancel.id ?? "")
                    }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
                }
                if let confirm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirm.title, action: confirm.action)
                            .fontWeight(.semibold)
                            .foregroundStyle(confirm.enabled ? palette.accent : palette.tertiary)
                            .disabled(!confirm.enabled)
                            .accessibilityIdentifier(confirm.id ?? "")
                    }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
                }
            }
            .tint(palette.accent)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(palette.isField ? .visible : .automatic, for: .navigationBar)
            .scrollEdgeEffectHidden(palette.isField, for: .all)
            .scrollIndicators(palette.isField ? .hidden : .automatic)
    }
}

extension View {
    /// Apply inside the sheet's NavigationStack.
    func sheetChrome(_ title: String, cancel: SheetAction? = nil, confirm: SheetAction? = nil, pushed: Bool = false) -> some View {
        modifier(SheetChrome(title: title, cancel: cancel, confirm: confirm, pushed: pushed))
    }

    /// Apply to the sheet's root (outside its NavigationStack).
    func sheetPresentation(_ palette: Palette, detents: Set<PresentationDetent>? = nil) -> some View {
        presentationBackground(palette.background)
            .presentationDetents(detents ?? [.large])
            .fieldSafe(palette.isField)
    }
}

// MARK: - Lists

/// List and Form chrome from the palette (no system grey or blue).
struct PaletteList: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.primary)
            .tint(palette.accent)
            .listSectionSpacing(DS.Space.l)
            .scrollEdgeEffectHidden(palette.isField, for: .all)
            .scrollIndicators(palette.isField ? .hidden : .automatic)
    }
}

extension View {
    func paletteList() -> some View { modifier(PaletteList()) }

    func paletteRow(_ palette: Palette) -> some View {
        listRowBackground(palette.surface).listRowSeparatorTint(palette.hairline)
    }
}

/// A List section header in the eyebrow style.
struct SectionHeader: View {
    @Environment(\.palette) private var palette
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).eyebrow(palette)
    }
}
