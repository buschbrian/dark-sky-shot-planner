import SkyCore
import SwiftUI

/// M2 + M4: the answer first (moon-free minutes, the night, the verdict with
/// its limiting factor), then the evidence (sky facts, altitude, conditions
/// by hour). Astronomy is computed on the phone, so everything but the
/// conditions works offline. The header and location sheet belong to `NightTab`.
struct TonightScreen: View {
    let chooseLocation: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var provider
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TonightModel()
    @State private var remembered: RememberedPlace?
    @State private var showCalendar = false
    @State private var showFactors = false
    /// The charts join a frame after the headline, so their first layout never delays it.
    @State private var showDetails = false

    private var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("-DarkSkyUITest") }
    private var workerConfigured: Bool { (provider as? any LiveConditionsProviding)?.workerConfigured ?? false }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .onAppear {
            Perf.screenAppeared()
            if let place = state.place { model.prime(place: place, night: state.night()) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let night = state.night(at: now)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                if let place = state.place {
                    PlaceHeader(place: place, zoneIsGuess: zoneIsGuess(place), now: now, change: chooseLocation)
                    let tonight = state.tonight(at: now)
                    NightPicker(
                        night: night,
                        tonight: tonight,
                        relative: model.relativeLabel(night: night, tonight: tonight, place: place),
                        choose: choose,
                        openCalendar: { showCalendar = true })
                    answer(place: place, night: night, now: now, scrollToPlan: {
                        withAnimation(.snappy) { proxy.scrollTo("tonight.top", anchor: .top) }
                    })
                } else {
                    EmptyState(
                        symbol: "location.magnifyingglass", title: "Where are you shooting?",
                        message: "Use GPS, pick a saved spot, or type coordinates. The darkness is worked out on this phone, so it works with no signal.",
                        actionTitle: "Choose a location", actionID: "tonight.chooseLocation", action: chooseLocation)
                        .padding(.top, DS.Space.xxl)
                }
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
            .id("tonight.top")
        }
        }
        .refreshable {
            guard let place = state.place else { return }
            await model.loadConditions(place: place, night: night, provider: provider)
        }
        .task(id: LoadKey(place: state.place, night: night)) {
            guard let place = state.place else { return }
            await model.load(place: place, night: night)
        }
        .task(id: WatchKey(place: state.place, night: night, active: scenePhase == .active)) {
            guard let place = state.place, scenePhase == .active else { return }
            await model.follow(place: place, night: night, provider: provider)
        }
        .task(id: state.place) {
            remembered = RememberedPlace.load()
            await retryZoneLookup()
        }
        .sheet(isPresented: $showCalendar) {
            NightCalendar(selected: night, tonight: state.tonight(at: now), choose: choose)
        }
        .sheet(isPresented: $showFactors) {
            if let verdict = model.verdict {
                FactorsSheet(verdict: verdict, now: now, workerConfigured: workerConfigured,
                             moonFreeMinutes: moonFreeMinutes)
            }
        }
    }

    /// Answer first (product review 2026-09-27 §1): the shot window for the
    /// remembered target, then the night's moon-free darkness and verdict,
    /// the sky facts, what else is in the sky, and the charts. Each block
    /// keeps its height while it loads, so nothing above the fold moves.
    @ViewBuilder
    private func answer(place: Place, night: NightDate, now: Date, scrollToPlan: @escaping () -> Void) -> some View {
        ShotWindowSection(place: place, night: night, snapshot: model.snapshot, status: conditionsStatus,
                          refreshing: model.refreshing, now: now)
        switch model.astronomy {
        case nil:
            SectionCard("Moon-free darkness") {
                Text("Working out the night…")
                    .font(.dsCallout)
                    .foregroundStyle(palette.secondary)
            }
            .frame(minHeight: answerHeight, alignment: .top)
        case .failure(let failure):
            SectionCard {
                StatusBadge(level: .unavailable)
                Text(failure.message).font(.dsBody).foregroundStyle(palette.primary)
            }
        case .success(let astro):
            let tz = place.timeZone
            AnswerCard(
                report: astro.report, strip: astro.strip, timeZone: tz, now: now,
                verdict: model.verdict, origin: origin(now: now), workerConfigured: workerConfigured,
                showFactors: { showFactors = true },
                refresh: { Task { await model.loadConditions(place: place, night: night, provider: provider) } })
                .onAppear {
                    Perf.headlineShown()
                    if !showDetails { Task { showDetails = true } }
                }
            AstronomyDetails(report: astro.report, timeZone: tz, config: model.appConfig)
            SkyEventsSection(place: place, night: night, onPlan: scrollToPlan)
            if showDetails {
                NightStripChart(strip: astro.strip, timeZone: tz, now: now, gcThreshold: model.appConfig?.gcMinUsefulAltitudeDeg)
                ConditionsStripChart(
                    rows: StripRow.rows(from: model.snapshot?.response), span: astro.strip.span,
                    darkness: astro.strip.darkness, timeZone: tz, now: now, loading: isLoading)
            } else {
                // The charts' own heights, until they join a frame later.
                SectionCard("Altitude tonight") { Color.clear.frame(height: chartHeight) }
                SectionCard("Conditions by hour") { Color.clear.frame(height: stripHeight) }
            }
        }
    }

    @ScaledMetric(relativeTo: .body) private var answerHeight = 420.0
    @ScaledMetric(relativeTo: .caption) private var chartHeight = 214.0
    @ScaledMetric(relativeTo: .caption) private var stripHeight = 260.0

    private var moonFreeMinutes: Int? {
        guard case .success(let a)? = model.astronomy, !a.report.noAstronomicalDarkness else { return nil }
        return a.report.moonFreeMinutes
    }

    private var conditionsStatus: ConditionsStatus? {
        switch model.conditions {
        case .loaded(_, let status): status
        case .none: .nothing
        case .idle, .loading: nil
        }
    }

    /// Where the conditions came from, in the one voice (`Voice`).
    private func origin(now: Date) -> ConditionsSourceStatus {
        switch model.conditions {
        case .idle, .loading:
            return .checking
        case .none(let reason):
            return .none(reason: reason)
        case .loaded(let s, let status):
            return ConditionsSourceStatus(status, snapshot: s, refreshing: model.refreshing)
        }
    }

    private var isLoading: Bool {
        if case .loading = model.conditions { true } else { false }
    }

    private func zoneIsGuess(_ place: Place) -> Bool {
        remembered?.place == place && remembered?.zoneIsDeviceGuess == true
    }

    private func choose(_ night: NightDate) {
        state.chosenNight = night == state.tonight() ? nil : night
        state.prefetchSkyEvents()
    }

    /// A zone guessed offline is looked up again once the phone can reach Apple.
    private func retryZoneLookup() async {
        guard !uiTesting, let place = state.place, zoneIsGuess(place),
              let zone = await TimeZoneLookup.zone(latitude: place.latitude, longitude: place.longitude),
              state.place == place else { return }
        var fixed = place
        fixed.timeZoneID = zone.identifier
        let r = RememberedPlace(place: fixed, zoneIsDeviceGuess: false)
        r.save()
        remembered = r
        state.place = fixed
    }

    struct LoadKey: Hashable {
        let place: Place?
        let night: NightDate
    }

    struct WatchKey: Hashable {
        let place: Place?
        let night: NightDate
        let active: Bool
    }
}

/// The place in one line, its coordinates and zone in the data face. Tapping
/// it changes the location. The same header opens Week.
struct PlaceHeader: View {
    let place: Place
    var zoneIsGuess = false
    var now: Date = .now
    let change: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: change) {
            HStack(alignment: .center, spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    let coordinate = Format.coordinate(place.latitude, place.longitude)
                    Text(place.name == coordinate ? "Entered coordinates" : place.name)
                        .font(.dsTitle)
                        .foregroundStyle(palette.primary)
                        .lineLimit(2)
                    Text("\(coordinate) · \(Format.zone(place.timeZone, at: now))")
                        .font(.dsData)
                        .foregroundStyle(palette.secondary)
                    if zoneIsGuess {
                        Label("Time zone \(Voice.estimated) from this phone: couldn't look it up offline", systemImage: "clock.badge.questionmark")
                            .font(.dsFootnote)
                            .foregroundStyle(palette.marginal)
                            .accessibilityIdentifier("tonight.timeZone")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.dsFootnote.weight(.semibold))
                    .foregroundStyle(palette.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Changes the location")
        .accessibilityIdentifier("tonight.place")
    }
}

extension ConditionsSourceStatus {
    /// The status line for a `ConditionsStatus` (review B-4): offline only for
    /// a saved copy, a 304 reads as confirmed. nil status means still checking.
    init(_ status: ConditionsStatus?, snapshot: ConditionsSnapshot?, refreshing: Bool) {
        guard let status else {
            self = .checking
            return
        }
        switch status {
        case .offlineCache(let at): self = .lastGood(fetched: snapshot?.fetchedUTC ?? at, refreshing: refreshing)
        case .workerSilentDirect: self = .direct(serviceConfigured: true)
        case .notSetUp: self = .direct(serviceConfigured: false)
        case .liveWorker(let checked, let revalidated):
            let fetched = snapshot?.fetchedUTC ?? checked
            self = revalidated ? .confirmed(fetched: fetched, checked: checked) : .service(fetched: fetched)
        case .nothing: self = .none(reason: "No connection, and nothing saved for this place and night yet.")
        }
    }
}

extension View {
    /// At least `lines` lines of `font` tall, so text that changes as data
    /// arrives does not move what is below it.
    func reservingLines(_ lines: Int, font: Font) -> some View {
        ZStack(alignment: .topLeading) {
            Text(String(repeating: "\n", count: max(lines - 1, 0)) + " ")
                .font(font)
                .hidden()
                .accessibilityHidden(true)
            self
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
