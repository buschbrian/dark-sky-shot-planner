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
    }

    private func item(_ value: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            VStack(spacing: DS.Space.xxs) {
                Image(systemName: symbol).font(.system(size: 20, weight: on ? .semibold : .regular))
                Text(title).font(.caption2.weight(on ? .semibold : .regular))
            }
            .foregroundStyle(on ? palette.accent : palette.tertiary)
            .frame(maxWidth: .infinity, minHeight: DS.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("fieldDock.\(title.lowercased())")
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
                        .background(on ? palette.accent : .clear, in: Capsule())
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
    /// Hides the system tab bar in field mode and puts the palette dock in its place.
    func fieldDock(_ on: Bool, tab: Binding<AppTab>) -> some View {
        toolbarVisibility(on ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if on { FieldDock(tab: tab) }
            }
    }
}
