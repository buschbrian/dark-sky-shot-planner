import Foundation
import Observation
import OSLog
import SkyCore

/// One shared, memoised copy of the ±30-day sky-events agenda per place and
/// centre night (ADR-0008 consequences: the sweep is deferred and memoised),
/// plus the highlights for each run of nights asked for. Tonight's section,
/// every Week-row badge and the full list read the same entry. All ephemeris
/// and highlight work runs off the main actor; views only filter and draw.
@Observable
final class SkyEventsStore {
    static let shared = SkyEventsStore()

    enum Entry {
        case loading
        case loaded(SkyEventsResult)
        case failed(String)
    }

    struct Key: Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let timeZoneID: String
        let centre: NightDate
    }

    struct RunKey: Hashable, Sendable {
        let key: Key
        let first: NightDate
    }

    /// Nights the section looks ahead (this week, then "coming up").
    nonisolated static let runNights = 30

    private(set) var entries: [Key: Entry] = [:]
    private(set) var runs: [RunKey: [SkyEventHighlight]] = [:]
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var pendingRuns: Set<RunKey> = []
    private let capacity = 6

    /// Nights within this many days of tonight share tonight's agenda, so a
    /// Week list and Tonight's section never compute two overlapping sweeps.
    static let shareDays = 21

    static func key(place: Place, night: NightDate, now: Date = .now) -> Key {
        let tonight = place.tonight(at: now)
        let centre = abs(days(from: tonight, to: night)) <= shareDays ? tonight : night
        return Key(latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID, centre: centre)
    }

    func entry(place: Place, night: NightDate) -> Entry? {
        entries[Self.key(place: place, night: night)]
    }

    /// Highlights for the `runNights` nights from `first`, once computed.
    func highlights(place: Place, first: NightDate) -> [SkyEventHighlight]? {
        runs[RunKey(key: Self.key(place: place, night: first), first: first)]
    }

    /// Starts the computation now, on a background thread, without waiting:
    /// call it as soon as the place and night are known (Tonight's restore),
    /// so the answer is ready by the time the section first draws instead of
    /// queueing behind Tonight's own work on the main actor.
    func prefetch(place: Place, night first: NightDate) {
        _ = start(place: place, first: first)
    }

    /// Computes the agenda (once per key) and the highlights from `first`
    /// (once per run), off the main actor, then publishes both at once.
    func load(place: Place, night first: NightDate) async {
        guard let (run, task) = start(place: place, first: first) else { return }
        let (entry, highlights) = await task.value
        if runs[run] == nil {
            entries[run.key] = entry
            runs[run] = highlights
        }
        inflight[run] = nil
    }

    @ObservationIgnored private var inflight: [RunKey: Task<(Entry, [SkyEventHighlight]), Never>] = [:]

    /// The in-flight task for a run, created (and started) if needed; nil when already published.
    private func start(place: Place, first: NightDate) -> (RunKey, Task<(Entry, [SkyEventHighlight]), Never>)? {
        let key = Self.key(place: place, night: first)
        let run = RunKey(key: key, first: first)
        if runs[run] != nil { return nil }
        if let task = inflight[run] { return (run, task) }
        if requestedAt[key] == nil { requestedAt[key] = .now }
        let cached: SkyEventsResult? = if case .loaded(let r)? = entries[key] { r } else { nil }
        if entries[key] == nil { remember(key) }
        let task = Task.detached(priority: .userInitiated) { Self.compute(run, cached: cached) }
        inflight[run] = task
        // Publishes on its own, so a prefetch needs nobody awaiting it.
        Task { await self.load(place: place, night: first) }
        return (run, task)
    }

    private nonisolated static func compute(_ run: RunKey, cached: SkyEventsResult?) -> (Entry, [SkyEventHighlight]) {
        let started = Date.now
        let key = run.key
        let tz = TimeZone(identifier: key.timeZoneID) ?? .current
        do {
            let site = try Observer(latitude: key.latitude, longitude: key.longitude)
            let threshold = (try? AppConfig.bundled())?.gcMinUsefulAltitudeDeg
            let result = try cached ?? SkyEventsAgenda.build(
                site, centre: key.centre.evening(in: tz), formatters: .local(tz), gcMinAltitudeDeg: threshold)
            let highlights = SkyEventHighlights.highlights(result, first: run.first, nights: runNights, timeZone: tz, site: site)
            log.notice("agenda\(cached == nil ? "" : " (cached)", privacy: .public) and highlights computed in \(Int(Date.now.timeIntervalSince(started) * 1000), privacy: .public) ms")
            return (.loaded(result), highlights)
        } catch {
            return (.failed("Sky events unavailable: \(error)"), [])
        }
    }

    private func remember(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let old = order.removeFirst()
            entries[old] = nil
            runs = runs.filter { $0.key.key != old }
        }
    }

    static func days(from a: NightDate, to b: NightDate) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let da = cal.date(from: DateComponents(year: a.year, month: a.month, day: a.day))!
        let db = cal.date(from: DateComponents(year: b.year, month: b.month, day: b.day))!
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }

    // MARK: timing (Console: subsystem DarkSky, category skyevents)

    nonisolated static let log = Logger(subsystem: "DarkSky", category: "skyevents")
    @ObservationIgnored private var requestedAt: [Key: Date] = [:]
    @ObservationIgnored private var shown: Set<String> = []
    @ObservationIgnored private var appearedAt: [String: Date] = [:]

    /// Called when a view appears (loaded or not).
    func viewAppeared(_ view: String) {
        if appearedAt[view] == nil { appearedAt[view] = .now }
    }

    /// Called when a view first draws loaded content: appear-to-content time.
    func contentShown(place: Place, night: NightDate, by view: String) {
        guard !shown.contains(view), let at = appearedAt[view] else { return }
        shown.insert(view)
        let requested = requestedAt[Self.key(place: place, night: night)]
        Self.log.notice("\(view, privacy: .public) content shown \(Int(Date.now.timeIntervalSince(at) * 1000), privacy: .public) ms after the view appeared (\(requested.map { Int(Date.now.timeIntervalSince($0) * 1000) } ?? -1, privacy: .public) ms after the first request)")
    }
}
