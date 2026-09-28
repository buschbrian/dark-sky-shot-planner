import OSLog
import SkyCore
import SwiftData
import SwiftUI

/// M5: the next seven nights for `AppState.place`, one row each. Astronomy is
/// computed on the phone and shows at once; conditions arrive from
/// `ConditionsProviding` and read "unavailable" when it has none.
struct WeekScreen: View {
    let chooseLocation: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var conditions
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0

    var body: some View {
        Group {
            if let place = state.place {
                WeekList(place: place, provider: provider, refresh: $refresh, chooseLocation: chooseLocation)
            } else {
                NoPlacePrompt(chooseLocation: chooseLocation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh += 1 }
        }
        #if DEBUG
        .onAppear { WeekDebug.applyLaunchPlace(to: state) }
        #endif
    }

    private var provider: any ConditionsProviding {
        #if DEBUG
        if let fixture = WeekDebug.fixtureProvider { return fixture }
        #endif
        return conditions
    }
}

/// Astronomy and the newest conditions per place and week, kept while the app
/// runs, so switching back to Week draws at once.
@MainActor
enum WeekCache {
    struct Key: Hashable {
        let place: Place
        let first: NightDate
    }

    static var nights: [Key: [NightOutlook]] = [:]
    static var conditions: [Key: WeekConditions] = [:]
    /// The rows last drawn, painted first on return and then recomputed for the current time.
    static var rows: [Key: (rows: [WeekNight], at: Date)] = [:]
    static let maxEntries = 16

    static func trim() {
        if nights.count > maxEntries { nights.removeAll() }
        if conditions.count > maxEntries { conditions.removeAll() }
        if rows.count > maxEntries { rows.removeAll() }
    }
}

@MainActor @Observable
final class WeekLoader {
    enum Phase { case computing, fetching, done }

    var nights: [WeekNight] = []
    var conditions = WeekConditions.none
    var phase = Phase.computing
    var failure: String?
    var computedAt = Date.now

    /// How long an open Week waits before asking again: until the soonest
    /// block's `nextRefresh` (the Worker's expected update), not a fixed timer.
    var nextWait: Duration {
        .seconds(RefreshTiming.weekWait(nextRefreshes: conditions.nextRefreshes, now: .now))
    }
    private static let config = Result { try WeekConfig.bundled() }
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DarkSky", category: "Week")

    func load(place: Place, provider: any ConditionsProviding) async {
        let started = ContinuousClock.now
        let now = Date.now
        failure = nil
        do {
            let config = try Self.config.get()
            let observer = try place.observer()
            let zone = place.timeZone
            let key = WeekCache.Key(place: place, first: place.firstListedNight(at: now))
            if nights.isEmpty, let last = WeekCache.rows[key] {
                nights = last.rows
                conditions = WeekCache.conditions[key] ?? .none
                computedAt = last.at
                let ms = Self.milliseconds(started.duration(to: .now))
                Self.log.notice("Week rows shown in \(ms, format: .fixed(precision: 1)) ms from the row cache")
            }
            let cached = WeekCache.nights[key]
            let outlooks: [NightOutlook]
            if let cached {
                outlooks = cached
            } else {
                phase = .computing
                outlooks = try await WeekPlanner.nights(observer: observer, timeZone: zone, first: key.first)
                WeekCache.nights[key] = outlooks
                WeekCache.trim()
            }
            let known = WeekCache.conditions[key] ?? .none
            nights = await WeekPlanner.rows(nights: outlooks, observer: observer, now: now, conditions: known, config: config)
            conditions = known
            computedAt = now
            let ms = Self.milliseconds(started.duration(to: .now))
            Self.log.notice("Week rows shown in \(ms, format: .fixed(precision: 1)) ms, astronomy \(cached == nil ? "computed" : "cached", privacy: .public)")

            phase = .fetching
            let fetched = await WeekPlanner.fetch(WeekPlanner.blocks(for: outlooks), place: place, provider: provider)
            guard !Task.isCancelled else { return }
            let merged = (WeekCache.conditions[key] ?? .none).keepingNewestRuns(from: fetched)
            WeekCache.conditions[key] = merged
            WeekCache.trim()
            nights = await WeekPlanner.rows(nights: outlooks, observer: observer, now: now, conditions: merged, config: config)
            conditions = merged
            phase = .done
            WeekCache.rows[key] = (nights, now)
            let total = Self.milliseconds(started.duration(to: .now))
            Self.log.notice("Week conditions applied after \(total, format: .fixed(precision: 1)) ms")
            #if DEBUG
            await WeekPlanner.parityCheck(
                nights, observer: observer, timeZone: zone, now: now, first: key.first, conditions: merged, config: config)
            #endif
        } catch {
            failure = String(describing: error)
            phase = .done
        }
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

private struct WeekList: View {
    let place: Place
    let provider: any ConditionsProviding
    @Binding var refresh: Int
    let chooseLocation: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var loader = WeekLoader()

    private struct LoadKey: Hashable {
        let place: Place
        let refresh: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                PlaceHeader(place: place, change: chooseLocation)
                statusLine
                if let failure = loader.failure {
                    SectionCard {
                        StatusBadge(level: .unavailable)
                        Text("The week could not be computed for this place.").font(.dsBody).foregroundStyle(palette.primary)
                        Text(failure).font(.dsData).foregroundStyle(palette.tertiary)
                    }
                }
                ForEach(Array(loader.nights.enumerated()), id: \.element.id) { _, night in
                    Button { open(night) } label: {
                        WeekRowView(night: night, place: place, isTonight: night.id == place.tonight(), now: loader.computedAt,
                                    weekStart: loader.nights.first?.id)
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityHint("Opens this night in Tonight")
                    .accessibilityIdentifier("week.row.\(night.id.iso)")
                }
                if !loader.nights.isEmpty { sources }
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
        }
        .refreshable { refresh += 1 }
        // The rows' event badges share one agenda run from the first listed
        // night. A badge with nothing to show draws no view, so its own task
        // cannot start the load; the list does.
        .task(id: loader.nights.first?.id) {
            guard let first = loader.nights.first?.id else { return }
            await SkyEventsStore.shared.load(place: place, night: first)
        }
        .task(id: LoadKey(place: place, refresh: refresh)) {
            await loader.load(place: place, provider: provider)
            while !Task.isCancelled {
                try? await Task.sleep(for: loader.nextWait)
                guard !Task.isCancelled else { break }
                await loader.load(place: place, provider: provider)
            }
        }
    }

    private func open(_ night: WeekNight) {
        state.chosenNight = night.id
        state.nightScope = .tonight
    }

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusCaution ? palette.marginal : palette.secondary)
                .accessibilityHidden(true)
            Text(status)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("week.status")
        }
        .font(.dsFootnote)
        .foregroundStyle(palette.secondary)
    }

    private var statusCaution: Bool {
        loader.phase == .done && (loader.conditions.oldestReceipt == nil
            || loader.conditions.answeredBlocks < loader.conditions.blocks.count)
    }

    private var statusSymbol: String {
        switch loader.phase {
        case .computing, .fetching: "arrow.triangle.2.circlepath"
        case .done: loader.conditions.oldestReceipt == nil ? "wifi.slash" : "antenna.radiowaves.left.and.right"
        }
    }

    private var status: String {
        switch loader.phase {
        case .computing: return "Working out the nights on this phone…"
        case .fetching:
            guard let line = loader.conditions.statusLine(now: loader.computedAt) else { return "Next 7 nights. Checking conditions…" }
            return "\(line) Checking for a newer run…"
        case .done:
            return loader.conditions.statusLine(now: loader.computedAt)
                ?? "Conditions unavailable (offline, and nothing cached yet). Moon-free minutes are computed on this phone."
        }
    }

    private var sources: some View {
        MoreInfo(title: "How the week is worked out", id: "week.sources") {
            Text("Moon-free minutes: astronomy-engine, computed on this phone for \(place.name).")
            Text("Cloud: the mean over each night's moon-free darkness, one value per forecast model, shown as a range. Ages count from the older of model run and fetch.")
            Text("Verdict: the worst gating factor, thresholds from conditions-thresholds.json. Aurora: planetary Kp against the NOAA G-scale latitudes; it never changes the verdict.")
        }
    }
}

struct WeekRowView: View {
    let night: WeekNight
    let place: Place
    let isTonight: Bool
    let now: Date
    /// The list's first night, so every row's event badge shares one agenda run.
    var weekStart: NightDate?
    @Environment(\.palette) private var palette

    var body: some View {
        SectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    title
                    Spacer(minLength: DS.Space.s)
                    badge
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    title
                    badge
                }
            }
            SkyEventBadge(place: place, night: night.id, weekStart: weekStart)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    minutes
                    Spacer(minLength: DS.Space.s)
                    moon
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    minutes
                    moon
                }
            }
            NightBar(span: NightStrip.span(for: night.outlook.report, evening: night.outlook.evening),
                     darkness: night.outlook.darkness, moonFree: night.outlook.moonFreeDarkness,
                     timeZone: place.timeZone, showsTimes: false, height: 8)
            Text(limitingText).font(.dsCallout).foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
            line("cloud", cloudText, source: cloudSource)
            line("sparkles", WeekFormat.aurora(night.aurora.outlook), source: auroraSource)
        }
        .multilineTextAlignment(.leading)
    }

    private var title: some View {
        Text(WeekFormat.nightTitle(night.outlook, place: place, isTonight: isTonight))
            .font(.dsHeadline).foregroundStyle(palette.primary)
    }

    @ViewBuilder private var badge: some View {
        switch night.verdict {
        case .success(let v):
            StatusBadge(level: StatusLevel(v.level, moonFreeMinutes: night.outlook.report.noAstronomicalDarkness ? nil : night.outlook.moonFreeMinutes))
        case .failure: StatusBadge(level: .unavailable, qualifier: "no verdict")
        }
    }

    private var minutes: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text(minutesText).font(.dsMetric).foregroundStyle(palette.primary)
            Text(minutesUnit).font(.dsCallout).foregroundStyle(palette.secondary)
        }
    }

    private var moon: some View {
        Text("moon \(WeekFormat.percent(night.outlook.report.moonIllumFraction * 100)) lit")
            .font(.dsFootnote).foregroundStyle(palette.secondary)
    }

    private var minutesText: String {
        night.outlook.report.noAstronomicalDarkness ? "–" : "\(night.outlook.moonFreeMinutes)"
    }

    private var minutesUnit: String {
        night.outlook.report.noAstronomicalDarkness ? "no astronomical darkness" : "min moon-free"
    }

    private var limitingText: String {
        switch night.verdict {
        case .success(let v): WeekFormat.limiting(v)
        case .failure: "No gating factors in the thresholds file."
        }
    }

    private var cloudText: String {
        switch night.cloud.state(moonFreeMinutes: night.outlook.moonFreeMinutes) {
        case .noWindow: return "Cloud: no moon-free darkness to average"
        case .unavailable: return "Cloud unavailable"
        case .band(let range, let partial):
            let models = night.cloud.usable
            var text = range.lowerBound.rounded() == range.upperBound.rounded()
                ? "Cloud mean \(WeekFormat.percent(range.lowerBound))"
                : "Cloud mean \(WeekFormat.percent(range.lowerBound))–\(WeekFormat.percent(range.upperBound))"
            text += models.count == 1 ? " (\(models[0].model) only)" : " across \(models.count) models"
            if partial { text += ", part of the night only" }
            if !night.cloud.missingModels.isEmpty {
                text += "; \(night.cloud.missingModels.joined(separator: ", ")) \(Voice.unavailable)"
            }
            return text
        }
    }

    private var cloudSource: SourceInfo? {
        let c = night.cloud
        guard case .band = c.state(moonFreeMinutes: night.outlook.moonFreeMinutes) else { return nil }
        let runs = c.usable.compactMap(\.runUTC)
        return SourceInfo(source: c.source ?? "source unknown", run: runs.min(), asOf: c.asOfUTC, freshness: c.freshness)
    }

    private var auroraSource: SourceInfo? {
        guard let asOf = night.aurora.asOfUTC else { return nil }
        return SourceInfo(source: night.aurora.source, asOf: asOf, freshness: night.auroraFreshness)
    }

    private func line(_ symbol: String, _ text: String, source: SourceInfo?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.dsFootnote)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(text).font(.dsCallout).foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source { ProvenanceChip(info: source, now: now) }
            }
        }
    }
}

private struct NoPlacePrompt: View {
    let chooseLocation: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Query(sort: \Spot.name) private var spots: [Spot]

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                EmptyState(
                    symbol: "calendar", title: "Choose a place first",
                    message: "The week outlook is for one place: its next seven nights, each with a verdict and the reason for it.",
                    actionTitle: "Choose a location", actionID: "week.chooseLocation", action: chooseLocation)
                if !spots.isEmpty {
                    SectionCard("Saved spots") {
                        ForEach(spots) { spot in
                            Button { state.choose(spot: spot) } label: {
                                Disclosure {
                                    Text(spot.name).font(.dsBody).foregroundStyle(palette.primary)
                                }
                                .frame(minHeight: DS.minTarget)
                            }
                            .buttonStyle(PressDimStyle())
                        }
                    }
                }
            }
            .padding(DS.Space.screen)
            .padding(.top, DS.Space.xl)
        }
        .accessibilityIdentifier("week.noPlace")
    }
}
