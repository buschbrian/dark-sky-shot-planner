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
    /// Called after "Plan this" has set the night and target (Tonight scrolls to its shot plan).
    var onPlan: (() -> Void)? = nil

    @Environment(\.palette) private var palette
    private let store = SkyEventsStore.shared

    var body: some View {
        SectionCard(title) {
            content
        }
        .task(id: SkyEventsStore.RunKey(key: SkyEventsStore.key(place: place, night: night), first: night)) {
            await store.load(place: place, night: night)
        }
        .onAppear { store.viewAppeared("section") }
        .accessibilityIdentifier("skyEvents.section")
    }

    private var title: String {
        night == place.tonight()
            ? "In the sky tonight & this week"
            : "In the sky from \(SkyEventsFormat.nightLabel(night, tonight: place.tonight()))"
    }

    @ViewBuilder private var content: some View {
        if case .failed(let message)? = store.entry(place: place, night: night) {
            UnavailableValue(reason: message)
        } else if let all = store.highlights(place: place, first: night) {
            VStack(alignment: .leading, spacing: DS.Space.l) { rows(all) }
                .onAppear { store.contentShown(place: place, night: night, by: "section") }
        } else {
            // The rows' shape while the agenda is worked out, so the page below does not jump.
            VStack(alignment: .leading, spacing: DS.Space.l) {
                ForEach(0..<2, id: \.self) { _ in SkyEventPlaceholderRow() }
            }
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working out what else is in the sky")
        }
    }

    /// Highlights arrive precomputed (off the main actor); this only filters.
    @ViewBuilder private func rows(_ all: [SkyEventHighlight]) -> some View {
        let week = all.filter { $0.night <= night.adding(days: 6) && $0.significance >= SkyEventHighlights.sectionThreshold }
        let later = all.filter { $0.night > night.adding(days: 6) && $0.significance >= SkyEventHighlights.sectionThreshold }
        let tonight = place.tonight()

        if week.isEmpty {
            Text("Nothing notable in the sky this week beyond the Moon and the Milky Way.")
                .font(.dsCallout).foregroundStyle(palette.secondary)
        }
        ForEach(week.prefix(limit)) { h in
            SkyEventHighlightRow(highlight: h, timeZone: place.timeZone, tonight: tonight, onPlan: onPlan)
        }
        if week.count < 2, let next = later.sorted(by: { $0.night < $1.night }).first {
            Text("Coming up").eyebrow(palette)
            SkyEventHighlightRow(highlight: next, timeZone: place.timeZone, tonight: tonight, onPlan: onPlan)
        }
        NavigationLink {
            SkyEventsList(place: place, night: night)
        } label: {
            HStack {
                Text("All sky events, ±30 days")
                Spacer()
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.dsCallout.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(minHeight: DS.minTarget)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("skyEvents.all")
    }
}

/// One highlight: symbol, title and night, then why, the best time from
/// this place (not the event's global peak), the Moon and the source, and
/// "Plan this" when the event has one target.
struct SkyEventHighlightRow: View {
    let highlight: SkyEventHighlight
    let timeZone: TimeZone
    let tonight: NightDate
    var onPlan: (() -> Void)? = nil
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @AppStorage(ShotPlan.storageKey) private var plan = ShotPlan()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                Image(systemName: SkyEventsFormat.symbol(highlight.item))
                    .foregroundStyle(palette.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            title
                            Spacer(minLength: DS.Space.s)
                            when
                        }
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            title
                            when
                        }
                    }
                    Text(highlight.whyItMatters)
                        .font(.dsCallout).foregroundStyle(palette.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let best = SkyEventsFormat.best(highlight, timeZone) {
                        Label("Best from here: \(best)", systemImage: "clock")
                            .font(.dsFootnote).foregroundStyle(palette.primary)
                    }
                    if let moon = SkyEventsFormat.moon(highlight.moon, timeZone) {
                        Label(moon, systemImage: "moon")
                            .font(.dsFootnote)
                            .foregroundStyle(SkyEventsFormat.moonIsBad(highlight.moon) ? palette.marginal : palette.secondary)
                    }
                    Text(SkyEventsFormat.provenance(highlight.item.provenance))
                        .font(.dsData).foregroundStyle(palette.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("skyEvents.row")
            if let target = highlight.shotTarget {
                Button { planThis(target) } label: {
                    Label("Plan this: \(target.shortName), \(SkyEventsFormat.nightLabel(highlight.night, tonight: tonight))",
                          systemImage: "scope")
                }
                .buttonStyle(ActionButtonStyle(.secondary, compact: true))
                .padding(.leading, 22 + DS.Space.m)
                .accessibilityIdentifier("skyEvents.plan")
            }
        }
    }

    /// The event's night and target become Tonight's shot plan.
    private func planThis(_ target: ShotTarget) {
        plan.target = target
        state.chosenNight = highlight.night == state.tonight() ? nil : highlight.night
        state.prefetchSkyEvents()
        onPlan?()
    }

    private var title: some View {
        Text(highlight.item.title).font(.dsCallout.weight(.semibold)).foregroundStyle(palette.primary)
    }

    private var when: some View {
        Text(SkyEventsFormat.nightLabel(highlight.night, tonight: tonight))
            .font(.dsFootnote.weight(.semibold)).foregroundStyle(palette.secondary)
    }
}

/// A highlight's shape, drawn redacted while the agenda loads.
private struct SkyEventPlaceholderRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Image(systemName: "sparkles").frame(width: 22)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Jupiter at opposition · Sat, Oct 10").font(.dsCallout.weight(.semibold))
                Text("At its closest and brightest, up from dusk to dawn, all night long.").font(.dsCallout)
                Text("Best from here: all night").font(.dsFootnote)
                Text("computed").font(.dsData)
            }
        }
    }
}
