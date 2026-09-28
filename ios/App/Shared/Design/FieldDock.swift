import SwiftUI

/// Field mode's bottom bar, drawn from the palette: the system tab bar is
/// Liquid Glass, which the red multiply cannot reach, so field mode hides it
/// and shows this instead. The brightness control sits on top of the tabs,
/// in thumb reach on every screen (ios/AGENTS.md invariant 5).
struct FieldDock: View {
    @Binding var tab: AppTab
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: DS.Space.s) {
            BrightnessControl()
            HStack(spacing: 0) {
                item(.tonight, "Tonight", "moon.stars")
                item(.map, "Map", "map")
                item(.sky, "Sky", "camera.viewfinder")
                item(.spots, "Spots", "mappin.and.ellipse")
                item(.tools, "Tools", "camera.aperture")
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.s)
        .background(palette.background)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fieldDock")
    }

    private func item(_ value: AppTab, _ title: String, _ symbol: String) -> some View {
        FieldDockItem(tab: $tab, value: value, title: title, symbol: symbol)
    }
}

/// One tab. The label stays on one line at every text size: it shrinks to
/// fit its fifth of the width, and a long press shows it full size in the
/// Large Content Viewer, as the system tab bar does.
private struct FieldDockItem: View {
    @Binding var tab: AppTab
    let value: AppTab
    let title: String
    let symbol: String
    @Environment(\.palette) private var palette
    #if DEBUG
    @State private var labelHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    #endif

    var body: some View {
        let on = tab == value
        Button { tab = value } label: {
            VStack(spacing: DS.Space.xxs) {
                Image(systemName: symbol).font(.system(size: 20, weight: on ? .semibold : .regular))
                Text(title)
                    .font(.caption2.weight(on ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    #if DEBUG
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { labelHeight = $0 }
                    .background {
                        // One line of the same style, for FieldDockInsetTests.
                        Text("Tg").font(.caption2.weight(on ? .semibold : .regular)).fixedSize().hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
                    }
                    #endif
            }
            .foregroundStyle(on ? palette.accent : palette.tertiary)
            .frame(maxWidth: .infinity, minHeight: DS.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: symbol)
            Text(title)
        }
        .accessibilityIdentifier("fieldDock.\(title.lowercased())")
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            Color.clear.frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("fieldDock.\(title.lowercased()).label")
                .accessibilityValue(String(format: "%.1f %.1f", labelHeight, lineHeight))
        }
        #endif
    }
}

/// Screen brightness for field mode: a palette slider with dim and bright ends.
struct BrightnessControl: View {
    @Environment(FieldBrightness.self) private var brightness
    @Environment(\.palette) private var palette

    var body: some View {
        let value = brightness.displayed
        HStack(spacing: DS.Space.m) {
            Image(systemName: "sun.min").foregroundStyle(palette.secondary).accessibilityHidden(true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.raised)
                    Capsule().fill(palette.accent.opacity(0.55))
                        .frame(width: max(12, geo.size.width * value))
                    Circle().fill(palette.primary)
                        .frame(width: 22, height: 22)
                        .offset(x: max(0, min(geo.size.width - 22, geo.size.width * value - 11)))
                }
                .frame(height: 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    brightness.set(Double(g.location.x / max(1, geo.size.width)))
                })
            }
            .frame(height: 32)
            Image(systemName: "sun.max").foregroundStyle(palette.secondary).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screen brightness")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            brightness.set(value + (direction == .increment ? 0.1 : -0.1))
        }
        .accessibilityIdentifier("field.brightness")
    }
}

/// Tonight / Week in field mode: the system segmented control draws grey glass.
struct ScopeSwitch: View {
    @Binding var scope: NightTab.Scope
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(NightTab.Scope.allCases, id: \.self) { s in
                let on = s == scope
                Button { scope = s } label: {
                    Text(s.rawValue)
                        .font(.dsCallout.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? palette.onAccent : palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? palette.accentFill : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? palette.accentEdge : .clear, lineWidth: DS.Stroke.focus))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressDimStyle())
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("scope.\(s.rawValue.lowercased())")
            }
        }
        .padding(DS.Space.xxs)
        .background(palette.raised, in: Capsule())
        .frame(width: 200)
    }
}

extension View {
    /// Field mode: hides this tab's system tab bar (`fieldDock` draws the replacement).
    func fieldTabBarHidden(_ on: Bool) -> some View {
        toolbarVisibility(on ? .hidden : .automatic, for: .tabBar)
    }

    /// Field mode: the dock goes under the whole tab view, not over it.
    ///
    /// A `safeAreaInset` on each tab's root does not reach the pages of the
    /// tab's NavigationStack: each page is hosted in its own UIKit controller
    /// that takes its safe area from UIKit, which never saw the SwiftUI inset
    /// (the root and pushed screens scrolled their last rows under the dock).
    /// Stacking the dock below the tab view ends the tab view's frame at the
    /// dock's top, so every screen, pushed or not, lays out above the dock at
    /// whatever height the dock has, with no number to keep in sync.
    func fieldDock(_ on: Bool, tab: Binding<AppTab>) -> some View {
        VStack(spacing: 0) {
            self
            if on { FieldDock(tab: tab) }
        }
    }
}
