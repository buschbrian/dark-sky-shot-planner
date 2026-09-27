import Foundation
import SkyCore

/// Config the Week screen reads; nothing here is a literal threshold.
nonisolated struct WeekConfig: Sendable {
    let verdict: VerdictConfig
    let aurora: AuroraRule
    /// Kp ages under the default live-conditions window (`freshness_hours.weather_forecast`).
    let kpFreshness: FreshnessWindow

    static func bundled() throws -> WeekConfig {
        let freshness = try FreshnessConfig.bundled()
        return WeekConfig(
            verdict: VerdictConfig(thresholds: try .bundled(), freshness: try freshness.conditionsFreshness()),
            aurora: try .bundled(),
            kpFreshness: try freshness.conditionsWindow())
    }
}

/// One Worker request and the nights it covers.
nonisolated struct WeekBlock: Sendable, Hashable {
    let window: DateInterval
    let nights: [NightDate]
}

/// What `ConditionsProviding` returned for a week; nil entries are unavailable.
nonisolated struct WeekConditions: Sendable {
    var blocks: [(block: WeekBlock, snapshot: ConditionsSnapshot?)]
    var spaceWeather: SpaceWeatherResponse?
    /// Where each block's answer came from (review B-4), in block order.
    var statuses: [ConditionsStatus] = []

    static let none = WeekConditions(blocks: [], spaceWeather: nil)

    /// "Live conditions, checked 3 min ago, unchanged." for the weakest
    /// block that answered, with how many did; nil when none did.
    func statusLine(now: Date) -> String? {
        // The blocks that answered; the ones that did not are counted below.
        let answered = zip(blocks, statuses).filter { $0.0.snapshot != nil }.map(\.1)
        guard let status = ConditionsStatus.combined(answered) else { return nil }
        let partial = answeredBlocks == blocks.count ? "" : " (\(answeredBlocks) of \(blocks.count) forecast windows)"
        return "\(status.summary(now: now))\(partial)."
    }

    func snapshot(for date: NightDate) -> ConditionsSnapshot? {
        blocks.first { $0.block.nights.contains(date) }?.snapshot
    }

    /// Oldest device receipt time among the blocks that answered.
    var oldestReceipt: Date? { blocks.compactMap(\.snapshot?.fetchedUTC).min() }
    var answeredBlocks: Int { blocks.filter { $0.snapshot != nil }.count }

    /// Per block, whichever snapshot carries the newer model run, so a provider
    /// answering from an older cache never replaces a newer forecast on screen.
    func keepingNewestRuns(from new: WeekConditions) -> WeekConditions {
        let old = Dictionary(blocks.map { ($0.block, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        let kept = new.blocks.map { entry in
            (block: entry.block, snapshot: WeekPlanner.newer(old[entry.block] ?? nil, entry.snapshot))
        }
        // A block that answered nothing this time but still shows an earlier copy is offline, not empty.
        let statuses = kept.enumerated().map { i, entry in
            let status = i < new.statuses.count ? new.statuses[i] : .nothing
            guard status == .nothing, let shown = entry.snapshot else { return status }
            return ConditionsStatus.offlineCache(fetchedAt: shown.fetchedUTC)
        }
        return WeekConditions(
            blocks: kept, spaceWeather: WeekPlanner.newer(spaceWeather, new.spaceWeather), statuses: statuses)
    }
}

nonisolated struct CloudMean: Sendable, Hashable {
    let model: String
    let mean: WindowMean
    /// The model run this series came from (Worker `model_run_utc`).
    let runUTC: Date?
}

/// Cloud cover means over one night's moon-free darkness, per model, with where they came from.
nonisolated struct CloudSummary: Sendable, Hashable {
    enum State: Sendable, Hashable {
        /// No moon-free darkness, so there is nothing to average.
        case noWindow
        case unavailable
        /// Min and max of the per-model means (a band, never averaged away).
        case band(ClosedRange<Double>, partial: Bool)
    }

    let means: [CloudMean]
    let source: String?
    let asOfUTC: Date?
    let freshness: Freshness

    var usable: [CloudMean] { means.filter { $0.mean.mean != nil } }
    var missingModels: [String] { means.filter { $0.mean.mean == nil && $0.mean.status != .noWindow }.map(\.model) }

    func state(moonFreeMinutes: Int) -> State {
        if moonFreeMinutes == 0 { return .noWindow }
        let values = usable.compactMap(\.mean.mean)
        guard let lo = values.min(), let hi = values.max() else { return .unavailable }
        return .band(lo...hi, partial: usable.contains { $0.mean.status == .partial })
    }
}

nonisolated struct WeekNight: Sendable, Identifiable {
    let outlook: NightOutlook
    let verdict: Result<Verdict, Verdict.EvaluationError>
    let aurora: AuroraSignal
    let auroraFreshness: Freshness
    let cloud: CloudSummary
    var id: NightDate { outlook.date }
}

/// Week assembly. `WeekOutlook.build` plans the nights one after another; here
/// each night is planned concurrently with `WeekOutlook.night` and cached, and
/// conditions are laid over the cached astronomy by the same rules as `build`
/// (checked against it in Debug by `parityCheck`).
nonisolated enum WeekPlanner {
    /// The Worker's longest window (PLAN.md §Worker, request rules).
    static let maxWindow: TimeInterval = 48 * 3600
    /// Padding around each night's darkness so an hourly sample sits on both edges.
    static let edgePad: TimeInterval = 3600
    static let cloudField = "cloud_cover_total"
    static let kpFallbackSource = "NOAA Space Weather Prediction Center"

    /// Astronomy for `count` nights from `first`, one child task per night.
    @concurrent
    static func nights(
        observer: Observer, timeZone: TimeZone, first: NightDate, count: Int = WeekOutlook.defaultNightCount
    ) async throws -> [NightOutlook] {
        try await withThrowingTaskGroup(of: (Int, NightOutlook).self) { group in
            for offset in 0..<count {
                group.addTask {
                    (offset, try WeekOutlook.night(first.adding(days: offset), observer: observer, timeZone: timeZone, clouds: []))
                }
            }
            var out = [NightOutlook?](repeating: nil, count: count)
            for try await (offset, night) in group { out[offset] = night }
            return out.compactMap(\.self)
        }
    }

    /// Consecutive nights' darkness grouped into as few ≤ 48 h windows as fit.
    /// A night with no astronomical darkness needs no conditions.
    static func blocks(for nights: [NightOutlook]) -> [WeekBlock] {
        var out: [WeekBlock] = []
        var current: (start: Date, end: Date, nights: [NightDate])?
        for night in nights {
            guard let dark = night.darkness else { continue }
            let start = dark.start.addingTimeInterval(-edgePad)
            let end = dark.end.addingTimeInterval(edgePad)
            if let c = current, end.timeIntervalSince(c.start) <= maxWindow {
                current = (c.start, max(c.end, end), c.nights + [night.date])
            } else {
                if let c = current { out.append(WeekBlock(window: DateInterval(start: c.start, end: c.end), nights: c.nights)) }
                current = (start, end, [night.date])
            }
        }
        if let c = current { out.append(WeekBlock(window: DateInterval(start: c.start, end: c.end), nights: c.nights)) }
        return out
    }

    /// Worker `cloud_cover_total` series merged per model across blocks. A
    /// failed series keeps its last good values when the Worker sent them.
    static func cloudSeries(_ responses: [ConditionsResponse]) -> [HourlySeries] {
        var order: [String] = []
        var samples: [String: [HourlySample]] = [:]
        for response in responses {
            for s in response.fields[cloudField]?.series ?? [] {
                let usable = s.status == .ok || s.lastGoodUTC != nil
                if samples[s.model] == nil { order.append(s.model) }
                samples[s.model, default: []] += s.values.map { HourlySample(time: $0.t, value: usable ? $0.v : nil) }
            }
        }
        return order.map { HourlySeries(model: $0, samples: samples[$0] ?? []) }
    }

    /// The index `build` gives `isNextDarkWindow`: the first night whose darkness has not ended.
    static func nextDarkIndex(_ nights: [NightOutlook], now: Date) -> Int? {
        nights.firstIndex { ($0.darkness?.end).map { $0 > now } ?? false }
    }

    /// Rows from cached astronomy plus whatever conditions have arrived.
    @concurrent
    static func rows(
        nights: [NightOutlook], observer: Observer, now: Date, conditions: WeekConditions, config: WeekConfig
    ) async -> [WeekNight] {
        let clouds = cloudSeries(conditions.blocks.compactMap(\.snapshot?.response))
        let sw = conditions.spaceWeather
        let next = nextDarkIndex(nights, now: now)
        return nights.enumerated().map { index, night in
            let response = conditions.snapshot(for: night.date)?.response
            let signal = AuroraSignal(
                spaceWeather: sw, rule: config.aurora, observer: observer, darkness: night.darkness,
                now: now, isNextDarkWindow: index == next)
            let verdict = Verdict.weekRater(conditions: response, config: config.verdict, now: now)(night)
            return WeekNight(
                outlook: night,
                verdict: verdict.map { $0.withAurora(signal) },
                aurora: signal,
                auroraFreshness: config.kpFreshness.freshness(since: signal.asOfUTC, now: now),
                cloud: cloudSummary(night, clouds: clouds, response: response, config: config, now: now))
        }
    }

    static func cloudSummary(
        _ night: NightOutlook, clouds: [HourlySeries], response: ConditionsResponse?, config: WeekConfig, now: Date
    ) -> CloudSummary {
        let field = response?.fields[cloudField]
        let runs = Dictionary((field?.series ?? []).map { ($0.model, $0.modelRunUTC) }, uniquingKeysWith: { a, _ in a })
        let means = clouds.map { series in
            CloudMean(model: series.model, mean: WindowMean.of(series, over: night.moonFreeDarkness), runUTC: runs[series.model] ?? nil)
        }
        let used = Set(means.filter { $0.mean.mean != nil }.map(\.model))
        let asOf = field?.series.filter { used.contains($0.model) }.compactMap(\.asOfUTC).min()
        return CloudSummary(
            means: means,
            source: field?.source,
            asOfUTC: asOf,
            freshness: used.isEmpty ? .unavailable
                : config.verdict.freshness.window(forField: cloudField).freshness(since: asOf, now: now))
    }

    /// Newest model run among a snapshot's available series.
    static func newestRun(_ s: ConditionsSnapshot) -> Date? {
        s.response.fields.values.flatMap(\.series).filter { $0.status == .ok }.compactMap(\.modelRunUTC).max()
    }

    static func newer(_ a: ConditionsSnapshot?, _ b: ConditionsSnapshot?) -> ConditionsSnapshot? {
        guard let a else { return b }
        guard let b else { return a }
        let (ra, rb) = (newestRun(a) ?? .distantPast, newestRun(b) ?? .distantPast)
        if ra != rb { return ra > rb ? a : b }
        return b.fetchedUTC >= a.fetchedUTC ? b : a
    }

    static func newer(_ a: SpaceWeatherResponse?, _ b: SpaceWeatherResponse?) -> SpaceWeatherResponse? {
        guard let a else { return b }
        guard let b else { return a }
        return (b.kpAsOfUTC ?? .distantPast) >= (a.kpAsOfUTC ?? .distantPast) ? b : a
    }

    /// Everything the provider has for these blocks, requested concurrently.
    @concurrent
    static func fetch(
        _ blocks: [WeekBlock], place: Place, provider: any ConditionsProviding
    ) async -> WeekConditions {
        async let sw = provider.spaceWeather(near: place)
        let fetches = await withTaskGroup(of: (Int, ConditionsFetch).self) { group in
            for (i, block) in blocks.enumerated() {
                group.addTask { (i, await provider.fetchWithStatus(for: place, window: block.window)) }
            }
            var out = [ConditionsFetch?](repeating: nil, count: blocks.count)
            for await (i, f) in group { out[i] = f }
            return out
        }
        return WeekConditions(
            blocks: Array(zip(blocks, fetches)).map { ($0, $1?.snapshot) }, spaceWeather: await sw,
            statuses: fetches.map { $0?.status ?? .nothing })
    }

    #if DEBUG
    /// Debug builds compare the assembled rows with `WeekOutlook.build` over the
    /// same inputs; a mismatch stops the app so UI tests catch any drift.
    @concurrent
    static func parityCheck(
        _ rows: [WeekNight], observer: Observer, timeZone: TimeZone, now: Date, first: NightDate,
        conditions: WeekConditions, config: WeekConfig
    ) async {
        guard let built = try? WeekOutlook.build(
            observer: observer, timeZone: timeZone, now: now, first: first, count: rows.count,
            clouds: cloudSeries(conditions.blocks.compactMap(\.snapshot?.response)),
            kp: conditions.spaceWeather?.kpReadings, auroraRule: config.aurora,
            verdict: { night in
                Verdict.weekRater(conditions: conditions.snapshot(for: night.date)?.response, config: config.verdict, now: now)(night)
            })
        else { return assertionFailure("WeekOutlook.build failed where the concurrent planner did not") }
        for (row, ref) in zip(rows, built) {
            let sameVerdict = (try? row.verdict.get().level) == (try? ref.verdict.get().level)
                && (try? row.verdict.get().limiting.key) == (try? ref.verdict.get().limiting.key)
            let sameCloud = row.cloud.means.map { [$0.model: $0.mean] } == ref.night.cloud.map { [$0.model: $0.mean] }
            assert(row.outlook.report == ref.night.report && row.aurora.outlook == ref.aurora && sameVerdict && sameCloud,
                   "Week row \(row.id) differs from WeekOutlook.build")
        }
    }
    #endif
}
