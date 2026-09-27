import Foundation
import OSLog
import SkyCore

/// What Tonight needs beyond the shared contract: the cached copy at once
/// (stale-while-revalidate) and the models' latest runs, so it refreshes when
/// a newer run exists rather than on a timer.
protocol LiveConditionsProviding: ConditionsProviding {
    func cachedConditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot?
    /// Latest run per `meta.json` id; empty offline.
    func latestRuns() async -> [String: ModelRunInfo]
    var workerConfigured: Bool { get }
    /// A refresh with its status and the time to ask again (M11).
    func fetch(for place: Place, window: DateInterval) async -> ConditionsFetch
    /// When the saved copy for this place and window should be refreshed:
    /// `max(next_update_expected_utc, now + 60 s)`, for Week and the Spots background refresh.
    func nextRefresh(for place: Place, window: DateInterval, now: Date) async -> Date
}

extension LiveConditionsProviding {
    /// The saved copy at once (if any), then a refresh each time the Worker
    /// expects new data. Ends when the consumer's task is cancelled.
    func updates(for place: Place, window: DateInterval) -> AsyncStream<ConditionsFetch> {
        AsyncStream { continuation in
            let task = Task {
                if let saved = await cachedConditions(for: place, window: window) {
                    continuation.yield(ConditionsFetch(
                        snapshot: saved, status: .offlineCache(fetchedAt: saved.fetchedUTC),
                        nextRefresh: .now, isSavedCopy: true))
                }
                while !Task.isCancelled {
                    let result = await fetch(for: place, window: window)
                    if Task.isCancelled { break }
                    continuation.yield(result)
                    try? await Task.sleep(for: .seconds(max(result.nextRefresh.timeIntervalSinceNow, 1)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension ConditionsProviding {
    /// A refresh with where it came from (review B-4): `fetch(for:window:)`
    /// for the real client; any other provider's snapshot reads as a fresh
    /// answer, and none as `.nothing`.
    func fetchWithStatus(for place: Place, window: DateInterval) async -> ConditionsFetch {
        if let live = self as? any LiveConditionsProviding {
            return await live.fetch(for: place, window: window)
        }
        let snapshot = await conditions(for: place, window: window)
        return ConditionsFetch(
            snapshot: snapshot, status: ConditionsStatus.of(snapshot, cached: false, workerConfigured: true),
            nextRefresh: .distantFuture)
    }
}

/// The real `ConditionsProviding` (M4). The Worker first, hedged: if it has not
/// answered in `hedgeDelay`, or fails, cloud cover is fetched straight from
/// Open-Meteo in parallel (everything else then unavailable). With no Worker
/// configured the direct fetch is the normal mode. With no network, the newest
/// cached snapshot. Only the 0.05° cell ever leaves the phone (ADR-0010).
/// Identical concurrent requests share one fetch.
///
/// M11: the saved copy's `ETag` goes back as `If-None-Match`; a 304 keeps the
/// body and its `fetched_utc` and records the response `Date` as the check
/// time. The next refresh is `ConditionsSchedule.nextFetch`.
nonisolated struct ConditionsClient: LiveConditionsProviding {
    static let workerURLKey = "DarkSkyWorkerURL"
    static let hedgeDelay = Duration.seconds(3)
    static let log = Logger(subsystem: "DarkSky", category: "conditions")

    let workerBase: URL?
    let networkEnabled: Bool
    let store: SnapshotStore
    /// nil: the shared session, created on first use off the main actor
    /// (building one at app launch cost ~15 ms of main-thread time). Tests
    /// inject a session whose protocol classes stub the network.
    var injectedSession: URLSession? = nil
    var hedgeDelay: Duration = Self.hedgeDelay
    nonisolated var workerConfigured: Bool { workerBase != nil }
    var session: URLSession { injectedSession ?? Self.sharedSession }
    private static let sharedSession = URLSession(configuration: sessionConfiguration())
    let inFlight = InFlight()
    let meta = MetaCache()

    /// No URL cache: revalidation is ours (`If-None-Match` from the saved
    /// snapshot), so a 304 always reaches this code instead of being folded
    /// into a cached 200 by URLSession.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 8
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }

    /// Reads the Worker URL from Info.plist. The UI tests launch with
    /// `-DarkSkyUITest`: no network and an empty, throwaway cache.
    /// `-DarkSkyOffline` keeps the real cache but never touches the network,
    /// the simulator's stand-in for airplane mode.
    static func live(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> ConditionsClient {
        let testing = arguments.contains("-DarkSkyUITest")
        let workerBase = workerURL(bundle.object(forInfoDictionaryKey: workerURLKey) as? String)
        #if DEBUG
        RefreshMeasurement.runIfAsked(arguments, workerBase: workerBase)
        #endif
        return ConditionsClient(
            workerBase: workerBase,
            networkEnabled: !testing && !arguments.contains("-DarkSkyOffline"),
            store: testing ? .temporary() : .applicationSupport())
    }

    /// Empty, or a value mangled by xcconfig's `//` comment rule, means "no Worker".
    static func workerURL(_ raw: String?) -> URL? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    private func request(_ place: Place, _ window: DateInterval) -> ConditionsRequest? {
        try? ConditionsRequest.make(latitude: place.latitude, longitude: place.longitude, window: window, now: .now).get()
    }

    func cachedConditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        guard let r = request(place, window) else { return nil }
        return await store.best(for: r.cell, window: r.window)
    }

    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? {
        await fetch(for: place, window: window).snapshot
    }

    func fetch(for place: Place, window: DateInterval) async -> ConditionsFetch {
        guard let r = request(place, window) else {
            return ConditionsFetch(snapshot: nil, status: .nothing, nextRefresh: .distantFuture)
        }
        if networkEnabled {
            let key = "\(r.cell.key)|\(r.start.timeIntervalSince1970)|\(r.end.timeIntervalSince1970)"
            if let fresh = await inFlight.run(key, { await fetchFresh(r) }) { return fresh }
        }
        let saved = await store.best(for: r.cell, window: r.window)
        return ConditionsFetch(
            snapshot: saved,
            status: saved.map { .offlineCache(fetchedAt: $0.fetchedUTC) } ?? .nothing,
            nextRefresh: .now.addingTimeInterval(ConditionsSchedule.retryWait))
    }

    func nextRefresh(for place: Place, window: DateInterval, now: Date = .now) async -> Date {
        guard let r = request(place, window) else { return .distantFuture }
        let saved = await store.best(for: r.cell, window: r.window)
        return ConditionsSchedule.nextFetch(after: saved, now: now, workerConfigured: workerConfigured)
    }

    /// Worker (or direct) answer, saved, with its status and next refresh; nil
    /// when nothing answered.
    private func fetchFresh(_ r: ConditionsRequest) async -> ConditionsFetch? {
        let saved = await store.exact(for: r.cell, window: r.window)
        guard let answer = await race(r, saved: saved) else { return nil }
        var snapshot = answer.snapshot
        if snapshot.response.isDirectFallback {
            let cached = await store.best(for: r.cell, window: r.window)
            snapshot = ConditionsSnapshot(
                response: OpenMeteoDirect.withLastGood(snapshot.response, from: cached?.response),
                fetchedUTC: snapshot.fetchedUTC)
        }
        await store.save(snapshot)
        let status: ConditionsStatus = switch answer.source {
        case .worker(let code, _):
            .liveWorker(confirmedAt: snapshot.confirmedUTC, revalidated: code == 304)
        case .direct:
            workerConfigured ? .workerSilentDirect(fetchedAt: snapshot.fetchedUTC) : .notSetUp(fetchedAt: snapshot.fetchedUTC)
        }
        var out = ConditionsFetch(
            snapshot: snapshot, status: status,
            nextRefresh: ConditionsSchedule.nextFetch(after: snapshot, now: .now, workerConfigured: workerConfigured))
        if case .worker(let code, let took) = answer.source {
            out.workerHTTPStatus = code
            out.workerDuration = took
        }
        return out
    }

    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? {
        if networkEnabled, let base = workerBase {
            var url = base.appending(path: "v1/space-weather")
            if let place {
                let cell = ConditionsCell(latitude: place.latitude, longitude: place.longitude)
                url.append(queryItems: [
                    URLQueryItem(name: "lat", value: cell.latitudeText),
                    URLQueryItem(name: "lon", value: cell.longitudeText),
                ])
            }
            if let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let decoded = try? SpaceWeatherResponse.decode(data) {
                await store.saveSpaceWeather(data)
                return decoded
            }
        }
        return await store.spaceWeather()
    }

    /// Conditional GETs (`If-None-Match`): an unchanged `meta.json` costs a 304.
    /// These requests carry no coordinates.
    func latestRuns() async -> [String: ModelRunInfo] {
        guard networkEnabled else { return [:] }
        let ids = Set(RefreshPolicy.metaIDs.values)
        return await withTaskGroup(of: (String, ModelRunInfo?).self) { group in
            for id in ids {
                group.addTask { (id, await runInfo(id)) }
            }
            var out: [String: ModelRunInfo] = [:]
            for await (id, info) in group { out[id] = info }
            return out
        }
    }

    private func runInfo(_ metaID: String) async -> ModelRunInfo? {
        let url = OpenMeteoDirect.host.appending(path: "data/\(metaID)/static/meta.json")
        var req = URLRequest(url: url)
        let cached = await meta.entry(metaID)
        if let etag = cached?.etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await session.data(for: req), let http = response as? HTTPURLResponse else {
            return cached?.info
        }
        if http.statusCode == 304 { return cached?.info }
        guard http.statusCode == 200, let info = ModelRunInfo.parse(data) else { return cached?.info }
        await meta.store(metaID, etag: http.value(forHTTPHeaderField: "ETag"), info: info)
        return info
    }

    struct Answer: Sendable {
        enum Source: Sendable {
            case worker(status: Int, took: Duration)
            case direct
        }
        let snapshot: ConditionsSnapshot
        let source: Source
    }

    /// Worker first; the direct fetch starts after `hedgeDelay` or as soon as the
    /// Worker fails. A Worker answer always wins over the cloud-only fallback.
    private func race(_ r: ConditionsRequest, saved: ConditionsSnapshot?) async -> Answer? {
        guard let base = workerBase else { return await fetchDirect(r).map { Answer(snapshot: $0, source: .direct) } }
        enum Outcome: Sendable { case worker(Answer?), hedge, direct(ConditionsSnapshot?) }
        let hedgeDelay = hedgeDelay
        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .worker(await fetchWorker(r, base: base, saved: saved)) }
            group.addTask {
                try? await Task.sleep(for: hedgeDelay)
                return .hedge
            }
            var directStarted = false
            var directDone = false
            var direct: ConditionsSnapshot?
            var workerFailed = false
            func directAnswer() -> Answer? { direct.map { Answer(snapshot: $0, source: .direct) } }
            while let outcome = await group.next() {
                switch outcome {
                case .worker(let a?):
                    group.cancelAll()
                    return a
                case .worker(nil):
                    workerFailed = true
                    if directDone {
                        group.cancelAll()
                        return directAnswer()
                    }
                    if !directStarted {
                        directStarted = true
                        group.addTask { .direct(await fetchDirect(r)) }
                    }
                case .hedge:
                    if !directStarted {
                        directStarted = true
                        group.addTask { .direct(await fetchDirect(r)) }
                    }
                case .direct(let s):
                    directDone = true
                    direct = s
                    if workerFailed {
                        group.cancelAll()
                        return directAnswer()
                    }
                }
            }
            return directAnswer()
        }
    }

    /// A 200 is a new body with its `ETag`; a 304 is the saved body confirmed
    /// at the response's `Date` (never a new `fetched_utc`).
    private func fetchWorker(_ r: ConditionsRequest, base: URL, saved: ConditionsSnapshot?) async -> Answer? {
        var req = URLRequest(url: r.workerURL(base: base))
        if let etag = saved?.etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let clock = ContinuousClock.now
        do {
            let (data, response) = try await session.data(for: req)
            let took = ContinuousClock.now - clock
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let etag = http.value(forHTTPHeaderField: "ETag")
            switch http.statusCode {
            case 200:
                let snapshot = try ConditionsSnapshot(workerJSON: data, fetchedUTC: .now, etag: etag)
                Self.log.info("Worker 200 in \(Self.ms(took), privacy: .public) ms, \(data.count, privacy: .public) bytes")
                return Answer(snapshot: snapshot, source: .worker(status: 200, took: took))
            case 304:
                guard let saved else { throw URLError(.badServerResponse) }
                let checked = HTTPDate.parse(http.value(forHTTPHeaderField: "Date")) ?? .now
                Self.log.info("Worker 304 in \(Self.ms(took), privacy: .public) ms")
                return Answer(snapshot: saved.confirmed(at: checked, etag: etag), source: .worker(status: 304, took: took))
            default:
                throw URLError(.badServerResponse)
            }
        } catch {
            Self.log.notice("Worker unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchDirect(_ r: ConditionsRequest) async -> ConditionsSnapshot? {
        let fetches = await withTaskGroup(of: OpenMeteoDirect.ModelFetch.self) { group in
            for model in OpenMeteoDirect.models {
                group.addTask { await fetchModel(model, r) }
            }
            var out: [OpenMeteoDirect.ModelFetch] = []
            for await f in group { out.append(f) }
            return out
        }
        let order = OpenMeteoDirect.models.map(\.id)
        let sorted = fetches.sorted { order.firstIndex(of: $0.model.id)! < order.firstIndex(of: $1.model.id)! }
        guard !OpenMeteoDirect.nothingReached(sorted) else { return nil }
        let at = Date.now
        return ConditionsSnapshot(
            response: OpenMeteoDirect.response(
                request: r, fetches: sorted, fetchedUTC: at, workerConfigured: workerConfigured),
            fetchedUTC: at)
    }

    private func fetchModel(_ model: OpenMeteoDirect.Model, _ r: ConditionsRequest) async -> OpenMeteoDirect.ModelFetch {
        async let run = runInfo(model.meta)
        do {
            let (data, response) = try await session.data(from: OpenMeteoDirect.forecastURL(model, r))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let info = await run
            return OpenMeteoDirect.ModelFetch(model: model, forecast: (status, data), meta: info.map(Self.metaBody))
        } catch {
            _ = await run
            return OpenMeteoDirect.ModelFetch(model: model, forecast: nil, forecastError: error.localizedDescription, meta: nil)
        }
    }

    /// `OpenMeteoDirect` reads the run from a `meta.json` body; rebuild the one field it needs.
    private static func metaBody(_ info: ModelRunInfo) -> Data {
        Data("{\"last_run_initialisation_time\":\(Int(info.run.timeIntervalSince1970))}".utf8)
    }
}

/// One fetch per identical request, however many screens ask at once.
actor InFlight {
    private var tasks: [String: Task<ConditionsFetch?, Never>] = [:]

    func run(_ key: String, _ work: @escaping @Sendable () async -> ConditionsFetch?) async -> ConditionsFetch? {
        if let task = tasks[key] { return await task.value }
        let task = Task { await work() }
        tasks[key] = task
        let value = await task.value
        tasks[key] = nil
        return value
    }
}

/// ETag and last parsed run per `meta.json`, for conditional requests.
actor MetaCache {
    struct Entry: Sendable {
        let etag: String?
        let info: ModelRunInfo
    }

    private var entries: [String: Entry] = [:]

    func entry(_ id: String) -> Entry? { entries[id] }

    func store(_ id: String, etag: String?, info: ModelRunInfo) {
        entries[id] = Entry(etag: etag, info: info)
    }
}

extension ConditionsClient {
    static func ms(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s * 1000 + attos / 1_000_000_000_000_000)
    }
}
