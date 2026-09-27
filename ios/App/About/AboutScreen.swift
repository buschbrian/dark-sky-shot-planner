import SwiftUI

/// Settings that belong to no one tab, pushed from the bottom of Tools. It
/// holds the not-yet-built iCloud sync, so the Spots list does not show a
/// disabled switch on every visit.
struct AboutScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        List { SyncSection() }
            .paletteList()
            .screenChrome("About", pushed: true)
    }
}

/// The navigation value that pushes `AboutScreen`.
struct AboutRoute: Hashable {}

/// CloudKit sync is deliberately not built: it needs an iCloud container on
/// the owner's team and a decision about what syncs (PLAN M8, ADR-0009 §4).
struct SyncSection: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            Toggle("Sync spots with iCloud", isOn: .constant(false))
                .toggleStyle(PaletteToggleStyle())
                .disabled(true)
                .accessibilityIdentifier("icloud-sync")
        } header: {
            SectionHeader("Sync")
        } footer: {
            Text("Not set up yet: spots live on this phone. Syncing needs an iCloud container and a decision on what to sync; precise coordinates would only go to your private iCloud database.")
                .font(.dsFootnote).foregroundStyle(palette.secondary)
        }
        .paletteRow(palette)
    }
}
