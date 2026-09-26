import SkyCore
import SwiftUI

/// M2 + M4: answer first (moon-free minutes, then the verdict and its limiting
/// factor), then darkness, moon and GC, then the night strip. Astronomy is
/// computed on the phone, so everything but the conditions works offline.
struct TonightScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var provider
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TonightModel()
    @State private var remembered: RememberedPlace?
    @State private var restored = false
    @State private var showLocation = false
    @State private var showCalendar = false
    @State private var showFactors = false
    /// The charts join a frame after the headline, so their first layout never delays it.
    @State private var showDetails = false

    private var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("-DarkSkyUITest") }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
            .background(palette.background)
            .navigationTitle("Tonight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Tonight").font(.headline).foregroundStyle(palette.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLocation = true } label: {
                        Label("Location", systemImage: "mappin.and.ellipse")
                    }
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("tonight.location")
                }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
                ToolbarItem(placement: .topBarTrailing) { FieldModeToggle() }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
            }
        }
        .fieldSafe(state.fieldMode)
        .sheet(isPresented: $showLocation) {
            LocationSheet(onChoose: apply)
        }
        .onAppear {
            Perf.screenAppeared()
            restore()
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let night = state.night(at: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let place = state.place {
                    PlaceHeader(place: place, zoneIsGuess: zoneIsGuess(place)) { showLocation = true }
                    NightPicker(
                        night: night,
                        tonight: NightDate.containing(now, in: place.timeZone),
                        choose: choose,
                        openCalendar: { showCalendar = true })
                    answer(place: place, night: night, now: now)
                } else {
                    NoPlace { showLocation = true }
                }
            }
            .padding()
        }
        .task(id: LoadKey(place: state.place, night: night)) {
            guard let place = state.place else { return }
            await model.load(place: place, night: night, provider: provider)
        }
        .task(id: WatchKey(place: state.place, night: night, active: scenePhase == .active)) {
            guard let place = state.place, scenePhase == .active else { return }
            await model.watchForNewRuns(place: place, night: night, provider: provider)
        }
        .task(id: state.place) { await retryZoneLookup() }
        .sheet(isPresented: $showCalendar) {
            NightCalendar(selected: night, tonight: NightDate.containing(now, in: state.place?.timeZone ?? .current), choose: choose)
        }
        .sheet(isPresented: $showFactors) {
            if let verdict = model.verdict {
                FactorsSheet(verdict: verdict, now: now)
            }
        }
    }

    @ViewBuilder
    private func answer(place: Place, night: NightDate, now: Date) -> some View {
        switch model.astronomy {
        case nil:
            Text("Working out the night…")
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .failure(let failure):
            Text(failure.message).foregroundStyle(palette.poor).card(palette)
        case .success(let astro):
            let tz = place.timeZone
            AnswerCard(report: astro.report, timeZone: tz)
                .onAppear {
                    Perf.headlineShown()
                    if !showDetails { Task { showDetails = true } }
                }
            VerdictCard(
                verdict: model.verdict, conditions: model.conditions, refreshing: model.refreshing, now: now,
                showFactors: { showFactors = true },
                refresh: { Task { await model.loadConditions(place: place, night: night, provider: provider) } })
            AstronomyDetails(report: astro.report, timeZone: tz, config: model.appConfig)
            if showDetails {
            NightStripChart(strip: astro.strip, timeZone: tz, now: now, gcThreshold: model.appConfig?.gcMinUsefulAltitudeDeg)
            ConditionsStripChart(
                rows: StripRow.rows(from: model.snapshot?.response), span: astro.strip.span,
                darkness: astro.strip.darkness, timeZone: tz, now: now, loading: isLoading)
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = model.conditions { true } else { false }
    }

    private func zoneIsGuess(_ place: Place) -> Bool {
        remembered?.place == place && remembered?.zoneIsDeviceGuess == true
    }

    private func choose(_ night: NightDate) {
        let tonight = NightDate.containing(.now, in: state.place?.timeZone ?? .current)
        state.chosenNight = night == tonight ? nil : night
    }

    private func apply(_ choice: LocationChoice) {
        state.place = choice.place
        if let night = choice.night { choose(night) }
        let r = RememberedPlace(place: choice.place, zoneIsDeviceGuess: choice.zoneIsDeviceGuess)
        r.save()
        remembered = r
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        if uiTesting || ProcessInfo.processInfo.arguments.contains("-DarkSkyUITestLive") {
            UserDefaults.standard.removeObject(forKey: RememberedPlace.key)
            return
        }
        guard let r = RememberedPlace.load() else { return }
        remembered = r
        if state.place == nil { state.place = r.place }
        if let place = state.place { model.prime(place: place, night: state.night()) }
    }

    /// A zone guessed offline is looked up again once the phone can reach Apple.
    private func retryZoneLookup() async {
        guard !uiTesting, let place = state.place, zoneIsGuess(place),
              let zone = await TimeZoneLookup.zone(latitude: place.latitude, longitude: place.longitude),
              state.place == place else { return }
        var fixed = place
        fixed.timeZoneID = zone.identifier
        apply(LocationChoice(place: fixed, zoneIsDeviceGuess: false, night: nil))
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

private struct NoPlace: View {
    let choose: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where are you shooting?")
                .font(.title2.bold())
                .foregroundStyle(palette.primary)
            Text("Use GPS, pick a saved spot, or type coordinates. Everything about the dark is worked out on this phone, so it works with no signal.")
                .foregroundStyle(palette.secondary)
            Button("Choose a location", action: choose)
                .buttonStyle(PaletteButtonStyle(palette: palette, prominent: true))
                .accessibilityIdentifier("tonight.chooseLocation")
        }
        .card(palette)
    }
}

private struct PlaceHeader: View {
    let place: Place
    let zoneIsGuess: Bool
    let change: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: change) {
            VStack(alignment: .leading, spacing: 2) {
                let coordinate = Format.coordinate(place.latitude, place.longitude)
                if place.name != coordinate {
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(palette.primary)
                }
                Text(coordinate)
                    .font(place.name == coordinate ? .headline.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(place.name == coordinate ? palette.primary : palette.secondary)
                Text(zoneText)
                    .font(.footnote)
                    .foregroundStyle(zoneIsGuess ? palette.marginal : palette.secondary)
                    .accessibilityIdentifier("tonight.timeZone")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Changes the location")
        .accessibilityIdentifier("tonight.place")
    }

    private var zoneText: String {
        let tz = place.timeZone
        let abbr = tz.abbreviation() ?? ""
        let base = "Times in \(tz.identifier)\(abbr.isEmpty ? "" : " (\(abbr))")"
        return zoneIsGuess ? "\(base): this phone's zone, because the spot's zone couldn't be looked up offline" : base
    }
}
