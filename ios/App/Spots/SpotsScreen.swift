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
                    EmptyState(
                        symbol: "mappin.and.ellipse", title: "No saved spots",
                        message: "Save the places you shoot from to see their week, attach a skyline and set alerts.",
                        actionTitle: "Add a spot", actionID: "add-first-spot") { adding = true }
                        .frame(maxHeight: .infinity)
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .screenChrome("Spots") {
                if !spots.isEmpty {
                    Button { Task { await checkAll() } } label: { Label("Re-check all", systemImage: "arrow.clockwise") }
                        .disabled(checkingAll)
                        .accessibilityIdentifier("recheck-all")
                }
                Button { adding = true } label: { Label("Add spot", systemImage: "plus") }
                    .accessibilityIdentifier("add-spot")
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
                Text(checkingAll ? "Checking every spot's week…" : "Each week shows when it was checked. ↻ re-checks every spot.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
            }
            .paletteRow(palette)
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
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            HStack(spacing: DS.Space.s) {
                Text(spot.name).font(.dsHeadline).foregroundStyle(palette.primary)
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
                HStack(spacing: DS.Space.s) {
                    MiniWeekStrip(week: week)
                    Spacer(minLength: 0)
                    AgeText(date: week.checkedAt).font(.dsData).foregroundStyle(palette.tertiary)
                }
            } else {
                Text("Week not checked yet").font(.dsFootnote).foregroundStyle(palette.secondary)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }
}
