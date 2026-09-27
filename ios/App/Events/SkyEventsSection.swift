import SkyCore
import SwiftUI

/// "In the sky tonight & this week" for the Tonight screen: the most
/// significant events over the seven nights from `night`, each with why it
/// matters, the best time and the Moon, then what is coming after that.
/// Self-contained: give it the place and night; it loads the shared agenda.
/// Must sit inside a NavigationStack (the "All sky events" link pushes).
struct SkyEventsSection: View {
    let place: Place
    let night: NightDate
    /// How many highlights to show before "All sky events".
    var limit = 4

    @Environment(\.palette) private var palette
    private let store = SkyEventsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In the sky tonight & this week")
                .font(.headline)
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .task(id: SkyEventsStore.RunKey(key: SkyEventsStore.key(place: place, night: night), first: night)) {
            await store.load(place: place, night: night)
        }
        .onAppear { store.viewAppeared("section") }
        .accessibilityIdentifier("skyEvents.section")
    }

    @ViewBuilder private var content: some View {
        if case .failed(let message)? = store.entry(place: place, night: night) {
            Text(message).font(.subheadline).foregroundStyle(palette.poor)
        } else if let all = store.highlights(place: place, first: night) {
            VStack(alignment: .leading, spacing: 12) { rows(all) }
                .onAppear { store.contentShown(place: place, night: night, by: "section") }
        } else {
            Text("Working out what else is in the sky…")
                .font(.subheadline).foregroundStyle(palette.secondary)
        }
    }

    /// Highlights arrive precomputed (off the main actor); this only filters.
    @ViewBuilder private func rows(_ all: [SkyEventHighlight]) -> some View {
        let week = all.filter { $0.night <= night.adding(days: 6) && $0.significance >= SkyEventHighlights.sectionThreshold }
        let later = all.filter { $0.night > night.adding(days: 6) && $0.significance >= SkyEventHighlights.sectionThreshold }
        let tonight = NightDate.containing(.now, in: place.timeZone)

        if week.isEmpty {
            Text("Nothing notable in the sky this week beyond the Moon and the Milky Way.")
                .font(.subheadline).foregroundStyle(palette.secondary)
        }
        ForEach(week.prefix(limit)) { h in
            SkyEventHighlightRow(highlight: h, timeZone: place.timeZone, tonight: tonight)
        }
        if week.count < 2, let next = later.sorted(by: { $0.night < $1.night }).first {
            Text("Coming up").font(.subheadline.bold()).foregroundStyle(palette.secondary)
            SkyEventHighlightRow(highlight: next, timeZone: place.timeZone, tonight: tonight)
        }
        NavigationLink {
            SkyEventsList(place: place, night: night)
        } label: {
            HStack {
                Text("All sky events, ±30 days")
                Spacer()
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("skyEvents.all")
    }
}

/// One highlight: symbol, title and night, then why, best time, Moon and source.
struct SkyEventHighlightRow: View {
    let highlight: SkyEventHighlight
    let timeZone: TimeZone
    let tonight: NightDate
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: SkyEventsFormat.symbol(highlight.item))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 6)
                        when
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        when
                    }
                }
                Text(highlight.whyItMatters)
                    .font(.subheadline).foregroundStyle(palette.primary)
                if let best = SkyEventsFormat.best(highlight, timeZone) {
                    Label(best, systemImage: "clock")
                        .font(.footnote).foregroundStyle(palette.primary)
                }
                if let moon = SkyEventsFormat.moon(highlight.moon, timeZone) {
                    Label(moon, systemImage: "moon")
                        .font(.footnote)
                        .foregroundStyle(SkyEventsFormat.moonIsBad(highlight.moon) ? palette.marginal : palette.secondary)
                }
                Text(SkyEventsFormat.provenance(highlight.item.provenance))
                    .font(.caption2).foregroundStyle(palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("skyEvents.row")
    }

    private var title: some View {
        Text(highlight.item.title).font(.subheadline.bold()).foregroundStyle(palette.primary)
    }

    private var when: some View {
        Text(SkyEventsFormat.nightLabel(highlight.night, tonight: tonight))
            .font(.caption.weight(.semibold)).foregroundStyle(palette.secondary)
    }
}
