import SwiftData
import SwiftUI

/// Saved spots (M8): each with its skyline, notes, a 7-night strip and an
/// optional Go alert. One spot can be pinned to the widget.
struct SpotsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var conditions
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var state
    @Query(sort: \Spot.name) private var spots: [Spot]

    @State private var adding = false
    @State private var path: [Spot] = []
    @State private var checkingAll = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView {
                        Label("No saved spots", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Save the places you shoot from to see their week, attach a skyline and set alerts.")
                    } actions: {
                        Button("Add a spot") { adding = true }.accessibilityIdentifier("add-first-spot")
                    }
                    .foregroundStyle(palette.secondary)
                } else {
                    list
                }
            }
            .background(palette.background)
            .paletteTitle("Spots", palette)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { FieldModeToggle() }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
                if !spots.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await checkAll() } } label: { Label("Re-check all", systemImage: "arrow.clockwise") }
                            .disabled(checkingAll)
                            .accessibilityIdentifier("recheck-all")
                    }
                    .sharedBackgroundVisibility(palette.toolbarGlass)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add spot", systemImage: "plus") }
                        .accessibilityIdentifier("add-spot")
                }
                .sharedBackgroundVisibility(palette.toolbarGlass)
            }
            .navigationDestination(for: Spot.self) { SpotDetail(spot: $0) }
            .sheet(isPresented: $adding) { SpotEditor(spot: nil) }
        }
        .background(palette.background)
        .tint(palette.accent)
        #if DEBUG
        .onAppear(perform: resetForUITests)
        #endif
    }

    #if DEBUG
    /// UI tests launch with `-resetSpots` to start from an empty list.
    func resetForUITests() {
        guard ProcessInfo.processInfo.arguments.contains("-resetSpots"), !Self.didReset else { return }
        Self.didReset = true
        for spot in spots { context.delete(spot) }
        try? context.save()
        WidgetBridge.publish(nil)
    }

    static var didReset = false
    #endif

    var list: some View {
        List {
            Section {
                ForEach(spots) { spot in
                    Button { path.append(spot) } label: {
                        Disclosure { SpotRow(spot: spot, inUse: state.place == spot.place) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spot-row-\(spot.name)")
                }
                .onDelete { offsets in
                    for i in offsets {
                        if spots[i].isPinned { WidgetBridge.publish(nil) }
                        context.delete(spots[i])
                    }
                    try? context.save()
                }
            } footer: {
                Text(checkingAll ? "Checking every spot's week…" : "Verdicts are shown with when they were checked. ↻ re-checks every spot.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            .paletteRow(palette)

            SyncSection()
        }
        .paletteList()
    }

    func checkAll() async {
        checkingAll = true
        await SpotRefresh.run(spots, conditions: conditions, background: false)
        try? context.save()
        checkingAll = false
    }
}

struct SpotRow: View {
    @Environment(\.palette) private var palette
    let spot: Spot
    let inUse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(spot.name).font(.body.weight(.semibold)).foregroundStyle(palette.primary)
                if inUse {
                    Image(systemName: "location.fill").accessibilityLabel("In use")
                }
                if spot.isPinned {
                    Image(systemName: "pin.fill").accessibilityLabel("Pinned to widget")
                }
                if spot.horizonCSV != nil {
                    Image(systemName: "mountain.2.fill").accessibilityLabel("Has a horizon profile")
                }
                if spot.alertGoThisWeek {
                    Image(systemName: "bell.fill").accessibilityLabel("Go alert on")
                }
            }
            .font(.caption)
            .foregroundStyle(palette.secondary)
            if let week = spot.week {
                HStack(spacing: 8) {
                    MiniWeekStrip(week: week)
                    AgeText(date: week.checkedAt).font(.caption2).foregroundStyle(palette.secondary)
                }
            } else {
                Text("Week not checked yet").font(.caption).foregroundStyle(palette.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// CloudKit sync is deliberately not built: it needs an iCloud container on
/// the owner's team and a decision about what syncs (PLAN M8, ADR-0009 §4).
struct SyncSection: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            Toggle("Sync spots with iCloud", isOn: .constant(false))
                .toggleStyle(PaletteToggleStyle(palette: palette))
                .disabled(true)
                .accessibilityIdentifier("icloud-sync")
        } header: {
            SectionHeader("Sync")
        } footer: {
            Text("Not available yet. Syncing needs an iCloud container on the developer team and a decision on what to sync (spots with precise coordinates would go to your private iCloud database only). Until then spots live on this phone.")
                .font(.caption).foregroundStyle(palette.secondary)
        }
        .paletteRow(palette)
    }
}
