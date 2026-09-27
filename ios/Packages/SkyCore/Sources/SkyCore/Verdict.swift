public import Foundation

/// PLAN.md §Verdict: the worst rating among gating factors over the moon-free
/// dark window, thresholds from `config/conditions-thresholds.json`, ages from
/// `config/app-config.json` (ADR-0006).
public enum VerdictLevel: Int, Sendable, Hashable, Comparable, Codable {
    case noGo, marginal, go

    public init(_ rating: Rating) {
        switch rating {
        case .poor: self = .noGo
        case .marginal: self = .marginal
        case .good: self = .go
        }
    }

    public static func < (a: VerdictLevel, b: VerdictLevel) -> Bool { a.rawValue < b.rawValue }
}

public enum VerdictFlag: String, Sendable, Hashable, Codable, CaseIterable {
    /// A gating factor could not be rated; the verdict is at best marginal.
    case incompleteData
    /// A gating factor is stale; the verdict is at best marginal.
    case staleData
    /// Never changes the level.
    case auroraPossible
}

public enum FactorStatus: Sendable, Hashable {
    case rated(Rating)
    /// Thresholds are `null`: value and source are shown, never rated.
    case shownOnly
    case unavailable(reason: String)
    /// Nothing to weigh it over: the night has no moon-free darkness, so the
    /// factor cannot change the verdict and is not missing either (review B-5).
    case notApplicable(reason: String)
}

public struct Provenance: Sendable, Hashable {
    public let source: String
    public let model: String?
    public let modelRunUTC: Date?
    public let fetchedUTC: Date?
    /// What the age is measured from (`WorkerSeries.asOfUTC`).
    public let asOfUTC: Date?
    public let age: TimeInterval?
    public let freshness: Freshness
}

/// One model's (or one source's) value for a factor over the window.
public struct FactorReading: Sendable, Hashable {
    public let model: String?
    public let value: Double?
    public let status: FactorStatus
    public let provenance: Provenance
    /// The value is the Worker's last good copy after a failed fetch: shown, not rated.
    public let isLastGood: Bool
    /// Which cadence the value came from when a 15-minute series was involved
    /// (`ForecastCadence`): used, and to when, or why not.
    public var cadence: String? = nil
}

public struct FactorAssessment: Sendable, Hashable {
    public let key: String
    public let factor: ConditionsThresholds.Factor
    public let gatesVerdict: Bool
    public let status: FactorStatus
    /// The worst available reading's value; nil when unavailable.
    public let value: Double?
    /// Provenance of the reading that set `value` (or the first reading when unavailable).
    public let provenance: Provenance?
    /// Worst freshness among the readings used; `unavailable` when none were.
    public let freshness: Freshness
    /// Every model, available or not, in the Worker's order.
    public let readings: [FactorReading]

    public var rating: Rating? {
        if case .rated(let r) = status { r } else { nil }
    }

    public var isUnavailable: Bool {
        if case .unavailable = status { true } else { false }
    }

    public var isNotApplicable: Bool {
        if case .notApplicable = status { true } else { false }
    }

    public var severity: Double? { value.flatMap(factor.severity) }

    /// Spread across the models that could be used, shown as a band rather than averaged.
    public var band: ClosedRange<Double>? {
        let vs = readings.filter(\.isUsable).compactMap(\.value)
        guard let lo = vs.min(), let hi = vs.max() else { return nil }
        return lo...hi
    }

    public var unavailableModels: [String] {
        readings.filter { !$0.isUsable }.compactMap(\.model)
    }
}

extension FactorReading {
    var isUsable: Bool {
        switch status {
        case .rated, .shownOnly: true
        case .unavailable, .notApplicable: false
        }
    }
}

public struct VerdictConfig: Sendable, Hashable {
    public let thresholds: ConditionsThresholds
    public let freshness: ConditionsFreshness

    public init(thresholds: ConditionsThresholds, freshness: ConditionsFreshness) {
        self.thresholds = thresholds
        self.freshness = freshness
    }

    /// One window for every field.
    public init(thresholds: ConditionsThresholds, freshness: FreshnessWindow) {
        self.init(thresholds: thresholds, freshness: ConditionsFreshness(default: freshness))
    }

    public static func bundled() throws -> VerdictConfig {
        VerdictConfig(thresholds: try .bundled(), freshness: try FreshnessConfig.bundled().conditionsFreshness())
    }
}

public struct Verdict: Sendable, Hashable {
    public enum Cause: String, Sendable, Hashable {
        /// The limiting factor's own rating set the level.
        case rating
        case incompleteData
        case staleData
        /// No moon-free darkness: no-go on astronomy alone, and no condition
        /// could change that (`whyConditionsDontMatter` says why).
        case noMoonFreeDarkness
    }

    /// The words for `Cause.noMoonFreeDarkness`.
    public static let moonUpAllDarkness = "the moon is up through all of darkness"
    public static let noDarkness = "there is no astronomical darkness"

    public enum EvaluationError: Error, Sendable, Hashable {
        case noGatingFactors
    }

    public let level: VerdictLevel
    /// Always present: the factor that set (or capped) the level, or the one
    /// nearest its edge on a go night.
    public let limiting: FactorAssessment
    public let cause: Cause
    public let flags: Set<VerdictFlag>
    /// Every factor in the thresholds file, sorted by key.
    public let factors: [FactorAssessment]
    public let windows: [MoonFreeWindow]
    public let aurora: AuroraSignal?
    public let evaluatedAt: Date
    /// Set only for `Cause.noMoonFreeDarkness`: "the moon is up through all of darkness".
    public var whyConditionsDontMatter: String? = nil

    /// "No-go: the moon is up through all of darkness" when no condition
    /// could matter; nil otherwise (the views then name the limiting factor).
    public var headline: String? {
        whyConditionsDontMatter.map { "No-go: \($0)" }
    }

    /// The same reason as a sentence to set under the level word:
    /// "The moon is up through all of darkness".
    public var reasonLine: String? {
        whyConditionsDontMatter.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// The factors worth listing: all of them, or on a night with no
    /// moon-free darkness only the one that decided it.
    public var shownFactors: [FactorAssessment] {
        factors.filter { !$0.isNotApplicable }
    }

    /// Non-gating factors rated below good (dew, PM2.5, observed AQI, …).
    public var advisories: [FactorAssessment] {
        factors.filter { !$0.gatesVerdict && ($0.rating ?? .good) < .good }
    }

    public func factor(_ key: String) -> FactorAssessment? {
        factors.first { $0.key == key }
    }

    public static func evaluate(
        night: NightReport,
        conditions: ConditionsResponse?,
        aurora: AuroraSignal? = nil,
        config: VerdictConfig,
        now: Date,
        galacticCoreIsTarget: Bool = false,
        noWindowReason: String? = nil
    ) throws(EvaluationError) -> Verdict {
        let assessor = FactorAssessor(
            night: night, conditions: conditions, freshness: config.freshness,
            now: now, galacticCoreIsTarget: galacticCoreIsTarget)

        // Review B-5: with no moon-free darkness the night is no-go on
        // astronomy alone. Nothing else is weighed, so nothing is "missing".
        if night.moonFreeWindows.isEmpty {
            let reason = noWindowReason ?? (night.darkness == nil ? noDarkness : moonUpAllDarkness)
            let factors = config.thresholds.factors.keys.sorted().map { key in
                let factor = config.thresholds.factors[key]!
                return key == FactorAssessor.moonFreeKey
                    ? assessor.assess(key, factor)
                    : FactorAssessor.notApplicable(key, factor, galacticCoreIsTarget: galacticCoreIsTarget, reason: reason)
            }
            guard let limiting = factors.first(where: { $0.key == FactorAssessor.moonFreeKey && $0.gatesVerdict })
                ?? factors.first(where: \.gatesVerdict) else { throw .noGatingFactors }
            var flags = Set<VerdictFlag>()
            if aurora?.isPossible == true { flags.insert(.auroraPossible) }
            return Verdict(
                level: .noGo, limiting: limiting, cause: .noMoonFreeDarkness, flags: flags, factors: factors,
                windows: [], aurora: aurora, evaluatedAt: now, whyConditionsDontMatter: reason)
        }

        let factors = config.thresholds.factors.keys.sorted().map { key in
            assessor.assess(key, config.thresholds.factors[key]!)
        }

        let gating = factors.filter(\.gatesVerdict)
        guard !gating.isEmpty else { throw .noGatingFactors }
        let rated = gating.filter { $0.rating != nil }
        let unrated = gating.filter { $0.rating == nil }
        let stale = rated.filter { $0.freshness == .stale }
        let worst = rated.min(by: moreSevere)

        let ratedLevel = worst.flatMap(\.rating).map(VerdictLevel.init) ?? .go
        let capped = !unrated.isEmpty || !stale.isEmpty
        let level = capped ? min(ratedLevel, .marginal) : ratedLevel

        let limiting: FactorAssessment
        let cause: Cause
        if let worst, ratedLevel == level {
            (limiting, cause) = (worst, .rating)
        } else if let first = unrated.first(where: \.isUnavailable) ?? unrated.first {
            (limiting, cause) = (first, .incompleteData)
        } else {
            (limiting, cause) = (stale[0], .staleData)
        }

        var flags = Set<VerdictFlag>()
        if !unrated.isEmpty { flags.insert(.incompleteData) }
        if !stale.isEmpty { flags.insert(.staleData) }
        if aurora?.isPossible == true { flags.insert(.auroraPossible) }

        return Verdict(
            level: level, limiting: limiting, cause: cause, flags: flags, factors: factors,
            windows: night.moonFreeWindows, aurora: aurora, evaluatedAt: now)
    }

    /// The same verdict with M5's aurora result attached: the level, limiting
    /// factor and cause never change; only the flag follows `signal`.
    public func withAurora(_ signal: AuroraSignal?) -> Verdict {
        var flags = flags
        if signal?.isPossible == true { flags.insert(.auroraPossible) } else { flags.remove(.auroraPossible) }
        return Verdict(
            level: level, limiting: limiting, cause: cause, flags: flags, factors: factors,
            windows: windows, aurora: signal, evaluatedAt: evaluatedAt,
            whyConditionsDontMatter: whyConditionsDontMatter)
    }

    /// Lower rating first, then further past the edges, then key order.
    static func moreSevere(_ a: FactorAssessment, _ b: FactorAssessment) -> Bool {
        let (ra, rb) = (a.rating ?? .good, b.rating ?? .good)
        if ra != rb { return ra < rb }
        let (sa, sb) = (a.severity ?? -.infinity, b.severity ?? -.infinity)
        if sa != sb { return sa > sb }
        return a.key < b.key
    }
}

/// Where each factor's value comes from. The keys match the thresholds file;
/// a key SkyCore does not know is reported unavailable, never skipped.
struct FactorAssessor {
    enum Aggregate { case mean, worst }

    enum Source {
        case moonFreeMinutes
        case galacticCoreAltitude
        case series(field: String, Aggregate)
        case dewPointSpread
        case observedAQI
    }

    static let sources: [String: Source] = [
        "moon_free_minutes": .moonFreeMinutes,
        "cloud_cover_total": .series(field: "cloud_cover_total", .mean),
        "cloud_cover_max_hour": .series(field: "cloud_cover_total", .worst),
        "aerosol_optical_depth": .series(field: "aerosol_optical_depth", .worst),
        "smoke_column": .series(field: "smoke_column", .worst),
        "pm2_5": .series(field: "pm2_5", .worst),
        "aqi_pm25_observed": .observedAQI,
        "dust": .series(field: "dust", .worst),
        "transparency": .series(field: "transparency", .worst),
        "seeing": .series(field: "seeing", .worst),
        "wind_gust": .series(field: "wind_gust", .worst),
        "dew_point_spread": .dewPointSpread,
        "gc_max_altitude": .galacticCoreAltitude,
    ]

    static let onDeviceSource = "astronomy-engine (on device)"
    static let galacticCoreKey = "gc_max_altitude"
    static let moonFreeKey = "moon_free_minutes"

    /// A factor with nothing to weigh it over (review B-5).
    static func notApplicable(
        _ key: String, _ factor: ConditionsThresholds.Factor, galacticCoreIsTarget: Bool, reason: String
    ) -> FactorAssessment {
        FactorAssessment(
            key: key, factor: factor, gatesVerdict: factor.gatesVerdict || (galacticCoreIsTarget && key == galacticCoreKey),
            status: .notApplicable(reason: reason), value: nil, provenance: nil, freshness: .unavailable, readings: [])
    }

    let night: NightReport
    let conditions: ConditionsResponse?
    let freshness: ConditionsFreshness
    let now: Date
    let galacticCoreIsTarget: Bool

    func assess(_ key: String, _ factor: ConditionsThresholds.Factor) -> FactorAssessment {
        let gates = factor.gatesVerdict || (galacticCoreIsTarget && key == Self.galacticCoreKey)
        let readings: Result<[FactorReading], Unavailable>
        switch Self.sources[key] {
        case nil: readings = .failure(Unavailable("SkyCore has no source for this factor"))
        case .moonFreeMinutes: readings = .success([onDevice(Double(night.moonFreeMinutes), factor)])
        case .galacticCoreAltitude:
            readings = night.gc.maxAltitudeDeg.map { .success([onDevice($0, factor)]) }
                ?? .failure(Unavailable("no moon-free darkness"))
        case .series(let name, let aggregate):
            readings = field(name, unit: factor.unit).map { f in
                f.series.map { s in
                    reading(s, fine: f.series15Min?.first { $0.model == s.model }, field: name, source: f.source, factor) { samples in
                        aggregate == .mean
                            ? ForecastCadence.timeWeightedMean(samples, over: night.moonFreeWindows.map { TimeWindow(start: $0.start, end: $0.end) })
                            : samples.values.reduce(samples.values.first!, factor.worse)
                    }
                }
            }
        case .dewPointSpread: readings = dewPointSpread(factor)
        case .observedAQI: readings = observedAQI(factor)
        }
        return combine(key, factor, gates: gates, readings)
    }

    struct Unavailable: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private func combine(
        _ key: String, _ factor: ConditionsThresholds.Factor, gates: Bool,
        _ result: Result<[FactorReading], Unavailable>
    ) -> FactorAssessment {
        let readings = (try? result.get()) ?? []
        let usable = readings.filter(\.isUsable)
        let worst = usable.min { a, b in
            if let sa = a.value.flatMap(factor.severity), let sb = b.value.flatMap(factor.severity) { return sa > sb }
            guard let va = a.value, let vb = b.value else { return false }
            return va != vb && factor.worse(va, vb) == va
        }
        guard let worst else {
            let reason: String = switch result {
            case .failure(let u): u.reason
            case .success(let rs) where rs.isEmpty: "no data"
            case .success(let rs): rs.map { r in
                    let why = if case .unavailable(let why) = r.status { why } else { "unavailable" }
                    return r.model.map { "\($0): \(why)" } ?? why
                }.joined(separator: "; ")
            }
            return FactorAssessment(
                key: key, factor: factor, gatesVerdict: gates, status: .unavailable(reason: reason),
                value: nil, provenance: readings.first?.provenance, freshness: .unavailable, readings: readings)
        }
        return FactorAssessment(
            key: key, factor: factor, gatesVerdict: gates, status: worst.status, value: worst.value,
            provenance: worst.provenance, freshness: Freshness.worst(usable.map(\.provenance.freshness)),
            readings: readings)
    }

    private func status(_ value: Double, _ factor: ConditionsThresholds.Factor, _ provenance: Provenance) -> FactorStatus {
        if provenance.freshness == .unavailable { return .unavailable(reason: "no timestamp to age it by") }
        guard let rating = factor.rate(value) else {
            return value.isFinite ? .shownOnly : .unavailable(reason: "not a number")
        }
        return .rated(rating)
    }

    private func provenance(
        field: String?, source: String, model: String?, run: Date?, fetched: Date?, asOf: Date?
    ) -> Provenance {
        Provenance(
            source: source, model: model, modelRunUTC: run, fetchedUTC: fetched, asOfUTC: asOf,
            age: asOf.map { now.timeIntervalSince($0) },
            freshness: freshness.window(forField: field).freshness(since: asOf, now: now))
    }

    private func onDevice(_ value: Double, _ factor: ConditionsThresholds.Factor) -> FactorReading {
        let p = provenance(field: nil, source: Self.onDeviceSource, model: nil, run: nil, fetched: nil, asOf: now)
        return FactorReading(model: nil, value: value, status: status(value, factor, p), provenance: p, isLastGood: false)
    }

    private func field(_ name: String, unit: String, needsSeries: Bool = true) -> Result<WorkerField, Unavailable> {
        guard let conditions else { return .failure(Unavailable("no conditions data")) }
        guard let f = conditions.fields[name] else { return .failure(Unavailable("not in the Worker response")) }
        if !unit.isEmpty && Self.unit(f.unit) != Self.unit(unit) {
            return .failure(Unavailable("unit \"\(f.unit)\" does not match the thresholds' \"\(unit)\""))
        }
        if needsSeries && f.series.isEmpty { return .failure(Unavailable(f.reason ?? "no series")) }
        return .success(f)
    }

    /// Open-Meteo's µ is Greek mu; the config uses the micro sign.
    static func unit(_ u: String) -> String { u.replacingOccurrences(of: "\u{03BC}", with: "\u{00B5}") }

    private func seriesProvenance(_ s: WorkerSeries, field: String, source: String, asOf: Date?) -> Provenance {
        provenance(field: field, source: source, model: s.model, run: s.modelRunUTC, fetched: s.fetchedUTC ?? s.lastGoodUTC, asOf: asOf)
    }

    /// One model's value over the windows, from `ForecastCadence`'s points:
    /// 15-minute where the Worker sent a complete native series, hourly elsewhere.
    private func reading(
        _ s: WorkerSeries, fine: WorkerSeries?, field: String, source: String, _ factor: ConditionsThresholds.Factor,
        aggregate: ([Date: Double]) -> Double?
    ) -> FactorReading {
        let selection = ForecastCadence.select(hourly: s, fine: fine)
        let p = seriesProvenance(s, field: field, source: source, asOf: selection.asOfUTC)
        let sampled = Self.samples(selection.points, in: night.moonFreeWindows)
        let value = (try? sampled.get()).flatMap(aggregate)
        let st: FactorStatus
        if s.status != .ok {
            st = .unavailable(reason: s.reason ?? "unavailable")
        } else if case .failure(let u) = sampled {
            st = .unavailable(reason: u.reason)
        } else if let value {
            st = status(value, factor, p)
        } else {
            st = .unavailable(reason: "no value in the window")
        }
        return FactorReading(
            model: s.model, value: value, status: st, provenance: p, isLastGood: s.status != .ok && value != nil,
            cadence: selection.note)
    }

    /// Every sample inside each moon-free window plus the one at or before its start
    /// and the one at or after its end, so the whole window is covered at any cadence.
    /// A series that does not reach both edges, or has a gap (null) inside, is unavailable.
    static func samples(_ s: WorkerSeries, in windows: [MoonFreeWindow]) -> Result<[Date: Double], Unavailable> {
        samples(s.values, in: windows)
    }

    static func samples(_ values: [WorkerPoint], in windows: [MoonFreeWindow]) -> Result<[Date: Double], Unavailable> {
        guard !windows.isEmpty else { return .failure(Unavailable("no moon-free darkness")) }
        let points = values.sorted { $0.t < $1.t }
        var out: [Date: Double] = [:]
        for w in windows {
            guard let first = points.last(where: { $0.t <= w.start }),
                  let last = points.first(where: { $0.t >= w.end }) else {
                return .failure(Unavailable("does not cover the moon-free window"))
            }
            for p in points where p.t >= first.t && p.t <= last.t {
                guard let v = p.v, v.isFinite else { return .failure(Unavailable("missing values in the moon-free window")) }
                out[p.t] = v
            }
        }
        return .success(out)
    }

    /// Temperature minus dew point at matching times, per model; the worst time.
    private func dewPointSpread(_ factor: ConditionsThresholds.Factor) -> Result<[FactorReading], Unavailable> {
        field("temperature", unit: factor.unit).flatMap { temp in
            field("dew_point", unit: factor.unit).map { dew in
                temp.series.map { t in
                    let d = dew.series.first { $0.model == t.model }
                    let asOf = [t.asOfUTC, d?.asOfUTC].compactMap(\.self).min()
                    let p = seriesProvenance(t, field: "temperature", source: temp.source, asOf: d == nil ? nil : asOf)
                    guard let d else {
                        return FactorReading(model: t.model, value: nil, status: .unavailable(reason: "no dew point series"),
                                             provenance: p, isLastGood: false)
                    }
                    guard t.status == .ok, d.status == .ok else {
                        return FactorReading(model: t.model, value: nil,
                                             status: .unavailable(reason: (t.status == .ok ? d : t).reason ?? "unavailable"),
                                             provenance: p, isLastGood: false)
                    }
                    // Paired at matching times: both at 15 minutes where both have a complete
                    // native series over the same times, otherwise both hourly.
                    let tf = temp.series15Min?.first { $0.model == t.model }
                    let df = dew.series15Min?.first { $0.model == t.model }
                    var ts = ForecastCadence.select(hourly: t, fine: tf)
                    var ds = ForecastCadence.select(hourly: d, fine: df)
                    var cadence = ts.note ?? ds.note
                    if ts.fineSpan != ds.fineSpan || (ts.fineSpan != nil && ts.points.map(\.t) != ds.points.map(\.t)) {
                        if ts.fineSpan != nil || ds.fineSpan != nil {
                            cadence = "15-min temperature and dew point not at matching times; hourly used"
                        }
                        ts = ForecastCadence.select(hourly: t, fine: nil)
                        ds = ForecastCadence.select(hourly: d, fine: nil)
                    }
                    let paired = seriesProvenance(
                        t, field: "temperature", source: temp.source,
                        asOf: [ts.asOfUTC, ds.asOfUTC].compactMap(\.self).min())
                    switch (Self.samples(ts.points, in: night.moonFreeWindows), Self.samples(ds.points, in: night.moonFreeWindows)) {
                    case (.success(let tv), .success(let dv)):
                        let spreads = tv.compactMap { time, t in dv[time].map { t - $0 } }
                        guard spreads.count == tv.count, spreads.count == dv.count, let worst = spreads.min() else {
                            return FactorReading(model: t.model, value: nil,
                                                 status: .unavailable(reason: "temperature and dew point hours differ"),
                                                 provenance: paired, isLastGood: false)
                        }
                        return FactorReading(
                            model: t.model, value: worst, status: status(worst, factor, paired), provenance: paired,
                            isLastGood: false, cadence: cadence)
                    case (.failure(let u), _), (_, .failure(let u)):
                        return FactorReading(model: t.model, value: nil, status: .unavailable(reason: u.reason), provenance: paired, isLastGood: false)
                    }
                }
            }
        }
    }

    /// PM2.5 rows only (ozone and PM10 are ignored); the worst monitor.
    private func observedAQI(_ factor: ConditionsThresholds.Factor) -> Result<[FactorReading], Unavailable> {
        field("aqi_observed", unit: factor.unit, needsSeries: false).flatMap { f in
            guard f.status == .ok else { return .failure(Unavailable(f.reason ?? "unavailable")) }
            let rows = (f.observations ?? []).filter { $0.parameter.uppercased().replacingOccurrences(of: " ", with: "") == "PM2.5" }
            guard let worst = rows.max(by: { $0.aqi < $1.aqi }) else {
                return .failure(Unavailable("no PM2.5 monitor reporting (ozone rows are ignored)"))
            }
            let asOf = ([f.fetchedUTC] + rows.map(\.observedUTC)).compactMap(\.self).min()
            let p = provenance(field: "aqi_observed", source: f.source, model: nil, run: nil, fetched: f.fetchedUTC, asOf: asOf)
            return .success([FactorReading(model: nil, value: worst.aqi, status: status(worst.aqi, factor, p), provenance: p, isLastGood: false)])
        }
    }
}
