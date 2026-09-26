import SwiftData
import SwiftUI

@main
struct DarkSkyApp: App {
    @State private var state = AppState()
    private let conditions: any ConditionsProviding = ConditionsClient.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(\.conditions, conditions)
        }
        .modelContainer(for: [Spot.self, Gear.self])
    }
}

enum AppTab: Hashable {
    case tonight, map, sky, spots, tools
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var tab = AppTab.tonight

    var body: some View {
        let palette = state.fieldMode ? Palette.field : Palette.standard
        TabView(selection: $tab) {
            Tab("Tonight", systemImage: "moon.stars", value: AppTab.tonight) { NightTab() }
            Tab("Map", systemImage: "map", value: AppTab.map) { MapScreen() }
            Tab("Sky", systemImage: "camera.viewfinder", value: AppTab.sky) { SkyScreen() }
            Tab("Spots", systemImage: "mappin.and.ellipse", value: AppTab.spots) { SpotsScreen() }
            Tab("Tools", systemImage: "camera.aperture", value: AppTab.tools) { ToolsScreen() }
        }
        .tint(palette.accent)
        .environment(\.palette, palette)
        .preferredColorScheme(palette.colorScheme)
    }
}

/// Tonight and the 7-night outlook answer the same question for the same spot,
/// so they share a tab; the iPhone tab bar holds five before "More".
struct NightTab: View {
    enum Scope: String, CaseIterable { case tonight = "Tonight", week = "Week" }

    @Environment(\.palette) private var palette
    @State private var scope = Scope.tonight

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            switch scope {
            case .tonight: TonightScreen()
            case .week: WeekScreen()
            }
        }
        .background(palette.background)
    }
}
