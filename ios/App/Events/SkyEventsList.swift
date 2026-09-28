import SkyCore
import SwiftUI

/// Every computed and curated event within 30 days of `night`, from `place`:
/// the web app's sky-events list, word for word, one card per event with its
/// provenance. Curated rows show their source and `verified_on`; the link
/// opens Safari only outside field mode (Safari cannot be drawn red).
struct SkyEventsList: View {
    let place: Place
    let night: NightDate

    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    private let store = SkyEventsStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                switch store.entry(place: place, night: night) {
                case nil, .loading?:
                    Text("Working out what else is in the sky…").foregroundStyle(palette.secondary)
                case .failed(let message)?:
                    Text(message).foregroundStyle(palette.poor)
                case .loaded(let result)?:
                    header(result)
                    ForEach(result.items) { item in
                        SkyEventCard(item: item, timeZone: place.timeZone, linksEnabled: !state.fieldMode)
                    }
                    if !result.problems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Curated rows skipped").font(.subheadline.bold()).foregroundStyle(palette.poor)
                            ForEach(result.problems, id: \.self) {
                                Text($0).font(.caption).foregroundStyle(palette.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle("Sky events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: SkyEventsStore.key(place: place, night: night)) {
            await store.load(place: place, night: night)
        }
        .accessibilityIdentifier("skyEvents.list")
    }

    private func header(_ result: SkyEventsResult) -> some View {
        let tz = place.timeZone
        return Text(
            "\(result.items.count) events from \(place.name), "
                + "\(SkyEventsFormat.day(result.window.start, tz)) – \(SkyEventsFormat.day(result.window.end, tz)), "
                + "plus anything already running. Times are \(tz.abbreviation(for: result.window.start) ?? tz.identifier).")
            .font(.footnote)
            .foregroundStyle(palette.secondary)
    }
}

/// One event: when, category, title, the verdict line, and where it came from.
struct SkyEventCard: View {
    let item: SkyEventItem
    let timeZone: TimeZone
    let linksEnabled: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: SkyEventsFormat.symbol(item))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(whenText).font(.caption.weight(.semibold)).foregroundStyle(palette.secondary)
                Spacer(minLength: 4)
                Text(SkyEventsFormat.category(item.category))
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            Text(item.title).font(.dsHeadline).foregroundStyle(palette.primary)
            Text(item.verdict).font(.dsCallout).foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
            provenance
        }
        .padding(DS.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Ranges are dated, not timed: a range has no useful clock (as on the web).
    private var whenText: String {
        if let until = item.until {
            return "\(SkyEventsFormat.day(item.at, timeZone)) – \(SkyEventsFormat.day(until, timeZone))"
        }
        return "\(SkyEventsFormat.day(item.at, timeZone)), \(SkyEventsFormat.clock(item.at, timeZone))"
    }

    @ViewBuilder private var provenance: some View {
        switch item.provenance {
        case .computed:
            Label("Computed on this phone", systemImage: "cpu")
                .font(.caption).foregroundStyle(palette.secondary)
        case .curated(let url, let on):
            HStack(spacing: 4) {
                Image(systemName: on == nil ? "exclamationmark.triangle" : "checkmark.seal")
                    .accessibilityHidden(true)
                Text("Curated, " + (on.map { "verified \($0)" } ?? "unverified") + " ·")
                if linksEnabled, let link = URL(string: url) {
                    Link(SkyEventsFormat.host(url), destination: link).underline()
                } else {
                    Text(SkyEventsFormat.host(url))
                }
            }
            .font(.caption)
            .foregroundStyle(on == nil ? palette.marginal : palette.secondary)
            .tint(palette.accent)
        }
    }
}
