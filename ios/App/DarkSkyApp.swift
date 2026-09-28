import SkyCore
import SwiftData
import SwiftUI

@main
struct DarkSkyApp: App {
    @State private var state = AppState()
    /// The one conditions client, for the views (`\.conditions`) and the background refresh.
    private let conditions: any ConditionsProviding = DebugConditions.override ?? ConditionsClient.live()
    @Environment(\.scenePhase) private var scenePhase
    /// One container for the scene and the background refresh (same default store as before).
    private let container: ModelContainer = {
        do { return try ModelContainer(for: Spot.self, Gear.self) } catch { fatalError("SwiftData store: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(\.conditions, conditions)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(SpotRefresh.taskIdentifier)) {
            await SpotRefresh.runInBackground(container, conditions: conditions)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { SpotRefresh.schedule(container) }
        }
    }
}

enum AppTab: Hashable {
    case tonight, map, sky, spots, tools
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var brightness = FieldBrightness()

    var body: some View {
        @Bindable var state = state
        let palette = state.fieldMode ? Palette.field : Palette.standard
        TabView(selection: $state.tab) {
            Tab("Tonight", systemImage: "moon.stars", value: AppTab.tonight) { NightTab().fieldTabBarHidden(state.fieldMode) }
            Tab("Map", systemImage: "map", value: AppTab.map) { MapScreen().fieldTabBarHidden(state.fieldMode) }
            Tab("Sky", systemImage: "camera.viewfinder", value: AppTab.sky) { SkyScreen().environment(\.skyRadiants, CuratedRadiants.provider).fieldTabBarHidden(state.fieldMode) }
            Tab("Spots", systemImage: "mappin.and.ellipse", value: AppTab.spots) { SpotsScreen().fieldTabBarHidden(state.fieldMode) }
            Tab("Tools", systemImage: "camera.aperture", value: AppTab.tools) { ToolsScreen().fieldTabBarHidden(state.fieldMode) }
        }
        .fieldDock(state.fieldMode, tab: $state.tab)
        .environment(brightness)
        .tint(palette.accent)
        .environment(\.palette, palette)
        .preferredColorScheme(palette.colorScheme)
        // Field mode's guarantee: whatever a view or system control draws,
        // multiplying by pure red leaves no green or blue light.
        .colorMultiply(state.fieldMode ? Color.red(1) : .white)
        // The status bar and home indicator are drawn outside the window, so
        // the multiply can't reach them: hide them instead.
        .statusBarHidden(state.fieldMode)
        .persistentSystemOverlays(state.fieldMode ? .hidden : .automatic)
        .background(palette.background.ignoresSafeArea())
        // Brightness the app changed goes back when field mode ends, the app
        // leaves the foreground or quits (a quit passes through background).
        .onAppear { brightness.sync(fieldMode: state.fieldMode, active: scenePhase == .active) }
        .onChange(of: state.fieldMode) { _, on in brightness.sync(fieldMode: on, active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in brightness.sync(fieldMode: state.fieldMode, active: phase == .active) }
        #if DEBUG
        .onAppear { DebugLaunch.apply(to: state) }
        .overlay {
            if DebugLaunch.showsGallery {
                DesignGallery()
                    .environment(\.palette, palette)
                    .colorMultiply(state.fieldMode ? Color.red(1) : .white)
            }
        }
        #endif
    }
}

#if DEBUG
/// Screenshot hooks (Debug only): `-DSTab week|map|sky|spots|tools|gallery`
/// opens that tab (or the design gallery), and `DS_PLACE` (see `WeekDebug`)
/// sets the place for every tab.
enum DebugLaunch {
    static let showsGallery = UserDefaults.standard.string(forKey: "DSTab") == "gallery"

    static func apply(to state: AppState) {
        WeekDebug.applyLaunchPlace(to: state)
        state.prefetchSkyEvents()
        switch UserDefaults.standard.string(forKey: "DSTab") {
        case "week": state.nightScope = .week
        case "map": state.tab = .map
        case "sky": state.tab = .sky
        case "spots": state.tab = .spots
        case "tools": state.tab = .tools
        default: break
        }
    }
}
#endif

/// Tonight and the 7-night outlook answer the same question for the same
/// place, so they share a tab (the iPhone tab bar holds five before "More"),
/// one header and one location sheet. The scope picker takes the title slot.
struct NightTab: View {
    enum Scope: String, CaseIterable { case tonight = "Tonight", week = "Week" }

    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @State private var showLocation = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Group {
                switch state.nightScope {
                case .tonight: TonightScreen(chooseLocation: { showLocation = true })
                case .week: WeekScreen(chooseLocation: { showLocation = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .screenChrome(state.nightScope.rawValue) {
                Button { showLocation = true } label: {
                    Label("Location", systemImage: "mappin.and.ellipse")
                }
                .foregroundStyle(palette.primary)
                .accessibilityIdentifier("tonight.location")
            } principal: {
                if palette.isField {
                    ScopeSwitch(scope: $state.nightScope)
                } else {
                    Picker("Scope", selection: $state.nightScope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet(onChoose: choose)
        }
        .onAppear(perform: restore)
    }

    private func choose(_ choice: LocationChoice) {
        state.choose(choice)
        state.prefetchSkyEvents()
    }

    /// A relaunch opens where the owner left off; UI tests always start empty.
    private func restore() {
        if !RememberedPlace.persists() { UserDefaults.standard.removeObject(forKey: ShotPlan.storageKey) }
        state.restoreRememberedPlace()
        state.prefetchSkyEvents()
    }
}
