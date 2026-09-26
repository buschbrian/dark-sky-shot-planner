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
}

/// The real `ConditionsProviding` (M4). The Worker first, hedged: if it has not
/// answered in `hedgeDelay`, or fails, cloud cover is fetched straight from
/// Open-Meteo in parallel (everything else then unavailable). With no network,
/// the newest cached snapshot. Only the 0.05° cell ever leaves the phone
/// (ADR-0010). Identical concurrent requests share one fetch.
nonisolated struct ConditionsClient: LiveConditionsProviding {
    static let workerURLKey = "DarkSkyWorkerURL"
    static let hedgeDelay = Duration.seconds(3)
    static let log = Logger(subsystem: "DarkSky", category: "conditions")

    let workerBase: URL?
    let networkEnabled: Bool
    let store: SnapshotStore
    var workerConfigured: Bool { workerBase != nil }
    /// Created on first use, off the main actor: building a session at app
    /// launch cost ~15 ms of main-thread time before the first frame.
    var session: URLSession { Self.sharedSession }
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()
    let inFlight = InFlight()
    let meta = MetaCache()

    /// Reads the Worker URL from Info.plist. The UI tests launch with
    /// `-DarkSkyUITest`: no network and an empty, throwaway cache.
    /// `-DarkSkyOffline` keeps the real cache but never touches the network,
    /// the simulator's stand-in for airplane mode.
    static func live(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> ConditionsClient {
        let testing = arguments.contains("-DarkSkyUITest")
        return ConditionsClient(
            workerBase: workerURL(bundle.object(forInfoDictionaryKey: workerURLKey) as? String),
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
        guard let r = request(place, window) else { return nil }
        if networkEnabled {
            let key = "\(r.cell.key)|\(r.start.timeIntervalSince1970)|\(r.end.timeIntervalSince1970)"
            if var fresh = await inFlight.run(key, { await fetchFresh(r) }) {
                if fresh.response.isDirectFallback {
                    let cached = await store.best(for: r.cell, window: r.window)
                    fresh = ConditionsSnapshot(
                        response: OpenMeteoDirect.withLastGood(fresh.response, from: cached?.response),
                        fetchedUTC: fresh.fetchedUTC)
                }
                await store.save(fresh)
                return fresh
            }
        }
        return await store.best(for: r.cell, window: r.window)
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

    /// Worker first; the direct fetch starts after `hedgeDelay` or as soon as the
    /// Worker fails. A Worker answer always wins over the cloud-only fallback.
    private func fetchFresh(_ r: ConditionsRequest) async -> ConditionsSnapshot? {
        guard let base = workerBase else { return await fetchDirect(r) }
        enum Outcome: Sendable { case worker(ConditionsSnapshot?), hedge, direct(ConditionsSnapshot?) }
        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .worker(await fetchWorker(r, base: base)) }
            group.addTask {
                try? await Task.sleep(for: Self.hedgeDelay)
                return .hedge
            }
            var directStarted = false
            var directDone = false
            var direct: ConditionsSnapshot?
            var workerFailed = false
            while let outcome = await group.next() {
                switch outcome {
                case .worker(let s?):
                    group.cancelAll()
                    return s
                case .worker(nil):
                    workerFailed = true
                    if directDone {
                        group.cancelAll()
                        return direct
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
                        return s
                    }
                }
            }
            return direct
        }
    }

    private func fetchWorker(_ r: ConditionsRequest, base: URL) async -> ConditionsSnapshot? {
        do {
            let (data, response) = try await session.data(from: r.workerURL(base: base))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try ConditionsSnapshot(workerJSON: data, fetchedUTC: .now)
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
            response: OpenMeteoDirect.response(request: r, fetches: sorted, fetchedUTC: at), fetchedUTC: at)
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
    private var tasks: [String: Task<ConditionsSnapshot?, Never>] = [:]

    func run(_ key: String, _ work: @escaping @Sendable () async -> ConditionsSnapshot?) async -> ConditionsSnapshot? {
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
