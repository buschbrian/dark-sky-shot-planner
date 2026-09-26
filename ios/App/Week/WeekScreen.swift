import OSLog
import SkyCore
import SwiftData
import SwiftUI

/// M5: the next seven nights for `AppState.place`, one row each. Astronomy is
/// computed on the phone and shows at once; conditions arrive from
/// `ConditionsProviding` and read "unavailable" when it has none.
struct WeekScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var conditions
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0

    var body: some View {
        NavigationStack {
            Group {
                if let place = state.place {
                    WeekList(place: place, provider: provider, refresh: refresh)
                } else {
                    NoPlacePrompt()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .paletteChrome("Week") {
                if state.place != nil {
                    Button { refresh += 1 } label: {
                        Label("Refresh conditions", systemImage: "arrow.clockwise")
                    }
                    .tint(palette.accent)
                }
            }
        }
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

    /// How often an open Week asks the provider again, to pick up a newer model run.
    static let refreshInterval = Duration.seconds(15 * 60)
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
            let key = WeekCache.Key(place: place, first: NightDate.containing(now, in: zone))
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
    let refresh: Int

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var loader = WeekLoader()

    private struct LoadKey: Hashable {
        let place: Place
        let refresh: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let failure = loader.failure {
                    Card {
                        Text("The week could not be computed for this place.").foregroundStyle(palette.primary)
                        Text(failure).font(.caption).foregroundStyle(palette.secondary)
                    }
                }
                ForEach(Array(loader.nights.enumerated()), id: \.element.id) { index, night in
                    Button { open(night) } label: {
                        WeekRowView(night: night, place: place, isTonight: index == 0, now: loader.computedAt)
                    }
                    .buttonStyle(PressDimStyle())
                    .accessibilityHint("Opens this night in Tonight")
                    .accessibilityIdentifier("week.row.\(night.id.iso)")
                }
                if !loader.nights.isEmpty { sources }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .task(id: LoadKey(place: place, refresh: refresh)) {
            await loader.load(place: place, provider: provider)
            while !Task.isCancelled {
                try? await Task.sleep(for: WeekLoader.refreshInterval)
                guard !Task.isCancelled else { break }
                await loader.load(place: place, provider: provider)
            }
        }
    }

    private func open(_ night: WeekNight) {
        state.chosenNight = night.id
        state.nightScope = .tonight
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name).font(.title2.bold()).foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)
            Text("Next \(WeekOutlook.defaultNightCount) nights. Tap a night to open it in Tonight.")
                .font(.subheadline).foregroundStyle(palette.secondary)
            Text(status).font(.footnote).foregroundStyle(palette.secondary)
                .accessibilityIdentifier("week.status")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        switch loader.phase {
        case .computing: return "Computing the nights on this phone…"
        case .fetching:
            guard let receipt = loader.conditions.oldestReceipt else { return "Astronomy ready. Checking conditions…" }
            return "Conditions received \(WeekFormat.age(loader.computedAt.timeIntervalSince(receipt))). Checking for a newer run…"
        case .done:
            let c = loader.conditions
            guard let receipt = c.oldestReceipt else {
                return "Conditions unavailable (offline, or none cached yet). Astronomy is computed on this phone."
            }
            let answered = c.answeredBlocks == c.blocks.count
                ? "" : " for \(c.answeredBlocks) of \(c.blocks.count) forecast windows"
            return "Conditions received \(WeekFormat.age(loader.computedAt.timeIntervalSince(receipt)))\(answered)."
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").font(.footnote.bold())
            Text("Moon-free minutes: astronomy-engine, computed on this phone for \(place.name).")
            Text("Cloud: mean over each night's moon-free darkness, one value per forecast model, shown as a range. Ages count from the older of model run and fetch.")
            Text("Verdict: worst gating factor, thresholds from conditions-thresholds.json. Aurora: planetary Kp against the NOAA G-scale latitudes; it never changes the verdict.")
        }
        .font(.footnote)
        .foregroundStyle(palette.secondary)
        .padding(.top, 4)
    }
}

struct WeekRowView: View {
    let night: WeekNight
    let place: Place
    let isTonight: Bool
    let now: Date
    @Environment(\.palette) private var palette

    var body: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 8)
                    badge
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    badge
                }
            }
            Text(limitingText).font(.subheadline).foregroundStyle(palette.primary)
            line("moon.stars", moonText, detail: nil)
            line("cloud", cloudText, detail: cloudDetail)
            line("sparkles", WeekFormat.aurora(night.aurora.outlook), detail: auroraDetail)
        }
        .multilineTextAlignment(.leading)
    }

    private var title: some View {
        Text(WeekFormat.nightTitle(night.outlook, place: place, isTonight: isTonight))
            .font(.headline).foregroundStyle(palette.primary)
    }

    @ViewBuilder private var badge: some View {
        switch night.verdict {
        case .success(let v):
            let color = WeekFormat.color(v.level, palette)
            Text(WeekFormat.level(v.level))
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .overlay(Capsule().stroke(color, lineWidth: 1.5))
        case .failure:
            Text("Verdict unavailable").font(.subheadline.bold()).foregroundStyle(palette.secondary)
        }
    }

    private var limitingText: String {
        switch night.verdict {
        case .success(let v): WeekFormat.limiting(v)
        case .failure: "No gating factors in the thresholds file."
        }
    }

    private var moonText: String {
        let report = night.outlook.report
        let moon = "moon \(WeekFormat.percent(report.moonIllumFraction * 100)) lit"
        if report.noAstronomicalDarkness { return "No astronomical darkness · \(moon)" }
        return "\(WeekFormat.minutes(night.outlook.moonFreeMinutes)) moon-free · \(moon)"
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
            return text
        }
    }

    private var cloudDetail: String? {
        let c = night.cloud
        guard case .band = c.state(moonFreeMinutes: night.outlook.moonFreeMinutes) else { return nil }
        var parts = c.usable.compactMap { m in
            m.mean.mean.map { v in
                "\(m.model) \(WeekFormat.percent(v))" + (m.runUTC.map { " (\(WeekFormat.run($0, now: now)) run)" } ?? "")
            }
        }
        if !c.missingModels.isEmpty { parts.append("\(c.missingModels.joined(separator: ", ")) unavailable") }
        var provenance = c.source ?? "source unknown"
        if let asOf = c.asOfUTC { provenance += " · oldest input \(WeekFormat.age(now.timeIntervalSince(asOf)))" }
        provenance += " · \(c.freshness.label)"
        return parts.joined(separator: ", ") + "\n" + provenance
    }

    private var auroraDetail: String? {
        guard let asOf = night.aurora.asOfUTC else { return nil }
        return "\(night.aurora.source) · \(WeekFormat.age(now.timeIntervalSince(asOf))) · \(night.auroraFreshness.label)"
    }

    private func line(_ symbol: String, _ text: String, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.subheadline).foregroundStyle(palette.primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(palette.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(palette.secondary).accessibilityHidden(true)
        }
    }
}

private struct NoPlacePrompt: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Query(sort: \Spot.name) private var spots: [Spot]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.largeTitle)
                    .foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
                Text("Choose a place first")
                    .font(.title2.bold())
                    .foregroundStyle(palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(spots.isEmpty
                     ? "The week outlook is for one place. Save a spot in the Spots tab, and its next seven nights appear here."
                     : "The week outlook is for one place. Pick a saved spot:")
                    .font(.body)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                ForEach(spots) { spot in
                    Button { state.place = spot.place } label: {
                        Text(spot.name)
                            .font(.headline)
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressDimStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("week.noPlace")
    }
}
