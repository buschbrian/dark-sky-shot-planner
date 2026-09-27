import SkyCore
import SwiftUI

/// A compact badge for a Week row: the most significant sky event on that
/// night ("Orionids peak", "Total lunar eclipse"), plus "+1" when there is
/// more. Draws nothing when the night has no notable event. Self-contained:
/// every row shares one agenda through `SkyEventsStore`.
struct SkyEventBadge: View {
    let place: Place
    let night: NightDate

    @Environment(\.palette) private var palette
    private let store = SkyEventsStore.shared

    var body: some View {
        Group {
            if case .loaded(let result)? = store.entry(place: place, night: night),
               let site = try? place.observer() {
                let badges = SkyEventHighlights.badges(
                    SkyEventHighlights.highlights(result, first: night, nights: 1, timeZone: place.timeZone, site: site),
                    on: night)
                if let first = badges.first {
                    HStack(spacing: 5) {
                        Image(systemName: SkyEventsFormat.symbol(first.item)).accessibilityHidden(true)
                        Text(first.badge).lineLimit(1)
                        if badges.count > 1 { Text("+\(badges.count - 1)") }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(palette.accent.opacity(0.6), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Sky event: " + badges.map(\.badge).joined(separator: ", "))
                    .accessibilityIdentifier("skyEvents.badge")
                }
            }
        }
        .task(id: SkyEventsStore.key(place: place, night: night)) {
            await store.load(place: place, night: night)
        }
    }
}
