import Foundation
import OSLog
import SkyCore

/// Tonight's numbers for one place and night: astronomy computed off the main
/// actor and cached per place+night (neighbouring nights precomputed), the
/// cached conditions shown at once and then refreshed, and the verdict.
@Observable
final class TonightModel {
    struct Astronomy: Sendable {
        let report: NightReport
        let strip: NightStrip
        let evening: Date
        /// Astronomical dawn, or civil dawn without astronomical darkness (`NightDate.darknessEnd`).
        var darknessEnd: Date? = nil
    }

    struct AstronomyFailure: Error {
        let message: String
    }

    enum ConditionsState {
        case idle
        case loading
        /// `status`: where the copy came from (review B-4). A Worker 304 keeps
        /// the old `fetchedUTC` but is `.liveWorker(revalidated: true)`, never
        /// offline; `.offlineCache` is an older copy from disk.
        case loaded(ConditionsSnapshot, status: ConditionsStatus)
        case none(reason: String)

        /// The origin line under the verdict.
        func originLine(refreshing: Bool, now: Date) -> String {
            switch self {
            case .idle, .loading:
                return "Conditions: fetching…"
            case .none(let reason):
                return "Conditions: \(reason)"
            case .loaded(_, let status):
                if refreshing, case .offlineCache(let at) = status {
                    return "Conditions: saved copy from \(ConditionsStatus.ago(at, now)), refreshing…"
                }
                return status.summary(now: now)
            }
        }
    }

    private(set) var key: String?
    private(set) var astronomy: Result<Astronomy, AstronomyFailure>?
    private(set) var conditions = ConditionsState.idle
    private(set) var refreshing = false
    private(set) var verdict: Verdict?

    let appConfig = try? AppConfig.bundled()
    let verdictConfig = try? VerdictConfig.bundled()

    @ObservationIgnored private var cache: [String: Astronomy] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    private static let cacheLimit = 24

    var snapshot: ConditionsSnapshot? {
        if case .loaded(let s, _) = conditions { s } else { nil }
    }

    static func key(_ place: Place, _ night: NightDate) -> String {
        "\(place.latitude),\(place.longitude),\(place.timeZoneID),\(night.iso)"
    }

    /// The night's astronomy, then its neighbours'. Conditions follow in
    /// `follow(place:night:provider:)`, which runs while the screen is active.
    func load(place: Place, night: NightDate) async {
        await loadAstronomy(place: place, night: night)
        await prefetchNeighbours(place: place, night: night)
    }

    /// First frame only: the night takes a few milliseconds to compute, which
    /// is cheaper than waiting for the main actor to come back from a detached
    /// task while the first render holds it. Later nights go through `load`.
    func prime(place: Place, night: NightDate) {
        guard astronomy == nil, key == nil else { return }
        key = Self.key(place, night)
        let result = Self.computeNow(place: place, night: night)
        if case .success(let a) = result { remember(key!, a) }
        astronomy = result
        updateVerdict()
    }

    func loadAstronomy(place: Place, night: NightDate) async {
        let key = Self.key(place, night)
        // Same key: either done, or another caller (`load` / `follow`) is computing it.
        guard key != self.key else { return }
        self.key = key
        conditions = .idle
        verdict = nil
        if let hit = cache[key] {
            astronomy = .success(hit)
            updateVerdict()
            return
        }
        astronomy = nil
        let result = await Self.compute(place: place, night: night)
        guard key == self.key else { return }
        if case .success(let a) = result { remember(key, a) }
        astronomy = result
        updateVerdict()
    }

    /// Stale-while-revalidate: the newest cached snapshot paints first, then the fetch replaces it.
    func loadConditions(place: Place, night: NightDate, provider: any ConditionsProviding) async {
        let window = ConditionsRequest.nightWindow(night, in: place.timeZone)
        if case .failure(let refusal) = ConditionsRequest.make(
            latitude: place.latitude, longitude: place.longitude, window: window, now: .now) {
            conditions = .none(reason: "No forecast for this night: \(refusal.message).")
            updateVerdict()
            return
        }
        let key = self.key
        if case .idle = conditions {
            conditions = .loading
            if let live = provider as? any LiveConditionsProviding,
               let cached = await live.cachedConditions(for: place, window: window), key == self.key {
                conditions = .loaded(cached, status: .offlineCache(fetchedAt: cached.fetchedUTC))
                updateVerdict()
            }
        }
        refreshing = true
        let interval = Perf.signposter.beginInterval("Conditions fetch")
        let result = await provider.fetchWithStatus(for: place, window: window)
        Perf.signposter.endInterval("Conditions fetch", interval)
        guard key == self.key else { return }
        refreshing = false
        if let snapshot = result.snapshot {
            conditions = .loaded(snapshot, status: result.status)
        } else if self.snapshot == nil {
            conditions = .none(reason: "Offline, and nothing cached for this place and night.")
        }
        updateVerdict()
    }

    /// Follows the conditions for this place and night: the saved copy at
    /// once, then a fetch, then another each time the Worker expects new data
    /// (`LiveConditionsProviding.updates`, which sleeps until the fetch's
    /// `nextRefresh`: `ConditionsSchedule.nextFetch`). Runs while the screen
    /// is visible and the app active; ends when that task is cancelled.
    func follow(place: Place, night: NightDate, provider: any ConditionsProviding) async {
        await loadAstronomy(place: place, night: night)
        guard let live = provider as? any LiveConditionsProviding else {
            return await loadConditions(place: place, night: night, provider: provider)
        }
        let window = ConditionsRequest.nightWindow(night, in: place.timeZone)
        if case .failure(let refusal) = ConditionsRequest.make(
            latitude: place.latitude, longitude: place.longitude, window: window, now: .now) {
            conditions = .none(reason: "No forecast for this night: \(refusal.message).")
            updateVerdict()
            return
        }
        let key = self.key
        if case .idle = conditions { conditions = .loading }
        refreshing = true
        var interval: OSSignpostIntervalState? = Perf.signposter.beginInterval("Conditions fetch")
        for await update in live.updates(for: place, window: window) {
            guard key == self.key, !Task.isCancelled else { break }
            if update.isSavedCopy {
                // A copy already on screen for this night (a return to the app) is at least as new.
                if case .loaded = conditions { continue }
            } else {
                if let i = interval { Perf.signposter.endInterval("Conditions fetch", i) }
                interval = nil
                refreshing = false
                Perf.log.info("Conditions: \(String(describing: update.status), privacy: .public); next refresh in \(Int(update.nextRefresh.timeIntervalSinceNow), privacy: .public) s")
            }
            if let snapshot = update.snapshot {
                conditions = .loaded(snapshot, status: update.status)
            } else if !update.isSavedCopy, self.snapshot == nil {
                conditions = .none(reason: "Offline, and nothing cached for this place and night.")
            }
            updateVerdict()
        }
        if key == self.key { refreshing = false }
    }

    private func prefetchNeighbours(place: Place, night: NightDate) async {
        for n in [night.adding(days: 1), night.adding(days: -1)] {
            let key = Self.key(place, n)
            guard cache[key] == nil, case .success(let a) = await Self.compute(place: place, night: n, priority: .utility) else { continue }
            remember(key, a)
        }
    }

    private func remember(_ key: String, _ a: Astronomy) {
        cache[key] = a
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }

    private static func compute(
        place: Place, night: NightDate, priority: TaskPriority = .userInitiated
    ) async -> Result<Astronomy, AstronomyFailure> {
        guard let observer = try? place.observer() else {
            return .failure(AstronomyFailure(message: "Those coordinates are out of range."))
        }
        let zone = place.timeZone
        return await Task.detached(priority: priority) {
            run(observer: observer, night: night, timeZone: zone)
        }.value
    }

    private static func computeNow(place: Place, night: NightDate) -> Result<Astronomy, AstronomyFailure> {
        guard let observer = try? place.observer() else {
            return .failure(AstronomyFailure(message: "Those coordinates are out of range."))
        }
        return run(observer: observer, night: night, timeZone: place.timeZone)
    }

    nonisolated private static func run(observer: Observer, night: NightDate, timeZone: TimeZone) -> Result<Astronomy, AstronomyFailure> {
        let evening = night.evening(in: timeZone)
        let interval = Perf.signposter.beginInterval("Astronomy")
        let t0 = Date.now
        defer {
            Perf.signposter.endInterval("Astronomy", interval)
            Perf.log.info("astronomy \(Int(Date.now.timeIntervalSince(t0) * 1000), privacy: .public) ms")
        }
        do {
            let report = try Planner.planNight(observer, evening: evening)
            let strip = try NightStrip.build(report: report, observer: observer, evening: evening)
            let end = report.darkness?.end ?? night.darknessEnd(observer: observer, timeZone: timeZone)
            return .success(Astronomy(report: report, strip: strip, evening: evening, darknessEnd: end))
        } catch {
            return .failure(AstronomyFailure(message: "The astronomy calculation failed (\(error.operation))."))
        }
    }

    /// The date row's second line: "tonight", "tomorrow night", and for the
    /// night before tonight "last night (ended 5:43 AM)" once its astronomy
    /// is in (review B-2: the app no longer opens on it after dawn).
    func relativeLabel(night: NightDate, tonight: NightDate, place: Place) -> String {
        let label = Self.relativeLabel(night: night, tonight: tonight)
        guard night.adding(days: 1) == tonight, key == Self.key(place, night),
              case .success(let a)? = astronomy, let end = a.darknessEnd else { return label }
        return "\(label) (ended \(Format.clock(end, place.timeZone)))"
    }

    static func relativeLabel(night: NightDate, tonight: NightDate) -> String {
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: Format.noon(tonight), to: Format.noon(night)).day ?? 0
        switch days {
        case 0: return "tonight"
        case 1: return "tomorrow night"
        case -1: return "last night"
        case let d where d > 0: return "in \(d) nights"
        default: return "\(-days) nights ago"
        }
    }

    private func updateVerdict() {
        guard case .success(let astro) = astronomy, let verdictConfig else {
            verdict = nil
            return
        }
        verdict = try? Verdict.evaluate(
            night: astro.report, conditions: snapshot?.response, config: verdictConfig, now: .now)
    }
}

/// Signposts (Instruments › Points of Interest) and one launch timing line:
/// process start to the first headline on screen.
nonisolated enum Perf {
    static let log = Logger(subsystem: "DarkSky", category: "perf")
    static let signposter = OSSignposter(subsystem: "DarkSky", category: .pointsOfInterest)
    @MainActor private static var headlineLogged = false
    @MainActor private static var appearedAt: Date?

    @MainActor static func screenAppeared() {
        if appearedAt == nil { appearedAt = .now }
    }

    @MainActor static func headlineShown() {
        guard !headlineLogged else { return }
        headlineLogged = true
        signposter.emitEvent("Headline shown")
        if let start = processStart() {
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            let fromAppear = appearedAt.map { Int(Date.now.timeIntervalSince($0) * 1000) } ?? -1
            log.notice("launch-to-headline \(ms, privacy: .public) ms (screen-appear-to-headline \(fromAppear, privacy: .public) ms)")
        }
    }

    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
