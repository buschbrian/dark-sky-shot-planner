import Foundation
import SkyCore

/// The 7-night check behind a spot's strip, its alerts and the widget. The
/// astronomy is SkyCore's planner (with the spot's skyline when it has one);
/// the verdict is SkyCore's worst-gating-factor rule over that night's
/// moon-free darkness. The Week screen owns the full outlook; this is the
/// compact per-spot version.
nonisolated enum SpotWeekPlanner {
    static let nightCount = 7
    static let config: VerdictConfig? = try? VerdictConfig.bundled()
    static let onDeviceSource = "astronomy-engine (on device)"

    struct Input: Sendable {
        let place: Place
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone
        let horizon: HorizonProfile?
    }

    @MainActor
    static func input(for spot: Spot) -> Input {
        Input(place: spot.place, latitude: spot.latitude, longitude: spot.longitude,
              timeZone: spot.place.timeZone, horizon: spot.horizonProfile)
    }

    /// Conditions requests in flight for one spot.
    static let perSpotRequests = 2
    /// The Worker's window limit, less an hour of rounding at each end.
    static let maxWindow: TimeInterval = 46 * 3600

    struct Request: Sendable {
        let window: DateInterval
        let nights: [Int]
    }

    /// Consecutive nights' darkness (±1 h) merged into windows of at most
    /// `maxWindow`: two nights per request instead of one.
    static func requests(_ darkness: [TimeWindow?]) -> [Request] {
        var out: [Request] = []
        var current: (start: Date, end: Date, nights: [Int])?
        for (i, dark) in darkness.enumerated() {
            guard let dark else { continue }
            let s = dark.start.addingTimeInterval(-3600), e = dark.end.addingTimeInterval(3600)
            if let c = current, e.timeIntervalSince(c.start) <= maxWindow {
                current = (c.start, e, c.nights + [i])
            } else {
                if let c = current { out.append(Request(window: DateInterval(start: c.start, end: c.end), nights: c.nights)) }
                current = (s, e, [i])
            }
        }
        if let c = current { out.append(Request(window: DateInterval(start: c.start, end: c.end), nights: c.nights)) }
        return out
    }

    /// Stops early when the task is cancelled; the result is then `interrupted`.
    @concurrent
    static func compute(
        _ input: Input, conditions: any ConditionsProviding, limiter: RequestLimiter? = nil, now: Date = .now
    ) async -> SpotWeek {
        let first = NightDate.containing(now, in: input.timeZone)
        let dates = (0..<nightCount).map { first.adding(days: $0) }
        let observer = try? Observer(latitude: input.latitude, longitude: input.longitude)

        struct Astro: Sendable { let flat: NightReport?; let skyline: NightReport? }
        let astro: [Astro] = dates.map { date in
            guard let observer, !Task.isCancelled else { return Astro(flat: nil, skyline: nil) }
            let evening = date.evening(in: input.timeZone)
            let flat = try? Planner.planNight(observer, evening: evening)
            let skyline = input.horizon.flatMap { try? Planner.planNight(observer, evening: evening, horizon: $0) }
            return Astro(flat: flat, skyline: skyline)
        }

        // A night with no moon-free darkness is no-go on astronomy alone and needs no conditions.
        let needs: [TimeWindow?] = astro.map { a in
            guard let r = a.skyline ?? a.flat, !r.moonFreeWindows.isEmpty else { return nil }
            return r.darkness
        }
        let plan = requests(needs)
        var snapshots: [Int: ConditionsSnapshot] = [:]
        var fetched = 0
        await withTaskGroup(of: (Request, ConditionsSnapshot?).self) { group in
            var next = 0
            func enqueue() {
                guard next < plan.count else { return }
                let request = plan[next]
                next += 1
                group.addTask {
                    await limiter?.acquire()
                    let snapshot = Task.isCancelled ? nil : await conditions.conditions(for: input.place, window: request.window)
                    await limiter?.release()
                    return (request, snapshot)
                }
            }
            for _ in 0..<min(perSpotRequests, plan.count) { enqueue() }
            for await (request, snapshot) in group {
                if let snapshot {
                    fetched += 1
                    for i in request.nights { snapshots[i] = snapshot }
                }
                enqueue()
            }
        }
        let interrupted = Task.isCancelled

        let nights = dates.enumerated().map { i, date in
            let a = astro[i]
            let report = a.skyline ?? a.flat
            let verdict = report.flatMap { r in
                config.flatMap { try? Verdict.evaluate(night: r, conditions: snapshots[i]?.response, config: $0, now: now) }
            }
            return NightSummary(
                night: date.iso,
                moonFreeMinutes: a.flat?.moonFreeMinutes,
                skylineMoonFreeMinutes: a.skyline?.moonFreeMinutes,
                verdict: verdict.map(summary),
                usableUntil: report?.moonFreeWindows.map(\.end).max())
        }
        return SpotWeek(checkedAt: now, terrainAware: input.horizon != nil, nights: nights,
                        requestedWindows: plan.count, fetchedWindows: fetched, interrupted: interrupted)
    }

    static func summary(_ v: Verdict) -> VerdictSummary {
        let f = v.limiting
        let source = f.provenance.map { p in
            [p.source, p.model].compactMap(\.self).joined(separator: " · ")
        } ?? (f.isUnavailable ? "no conditions data" : "unknown source")
        let cause: VerdictSummary.Cause = switch v.cause {
        case .rating: .rating
        case .incompleteData: .incompleteData
        case .staleData: .staleData
        }
        return VerdictSummary(
            level: v.level,
            cause: cause,
            limitingLabel: f.factor.label,
            limitingValue: f.value.map { format($0, unit: f.factor.unit) } ?? "unavailable",
            limitingSource: source,
            // On-device astronomy has no data age; only fetched data does.
            limitingAsOf: f.provenance?.source == onDeviceSource ? nil : f.provenance?.asOfUTC,
            freshness: f.freshness,
            evaluatedAt: v.evaluatedAt)
    }

    static func format(_ value: Double, unit: String) -> String {
        let number = abs(value) >= 10 || value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// A counting semaphore for conditions requests shared across spots.
actor RequestLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { self.limit = max(1, limit) }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
