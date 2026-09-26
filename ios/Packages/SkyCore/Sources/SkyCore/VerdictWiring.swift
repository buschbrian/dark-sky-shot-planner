public import Foundation

/// M5's aurora result (`AuroraRule.outlook`, driven by `opportunities.kp_index`)
/// with where it came from, for display next to the verdict. It never lowers
/// the verdict: `.possible` only adds `VerdictFlag.auroraPossible`.
public struct AuroraSignal: Sendable, Hashable {
    public let outlook: AuroraOutlook
    public let source: String
    /// Oldest fetch time among the Kp blocks read; nil when none were usable.
    public let asOfUTC: Date?

    public init(outlook: AuroraOutlook, source: String, asOfUTC: Date?) {
        self.outlook = outlook
        self.source = source
        self.asOfUTC = asOfUTC
    }

    /// Runs the one aurora rule over a Worker `/v1/space-weather` response.
    /// A missing response, or blocks the Worker marks unavailable, give no Kp,
    /// so the outlook is `.unavailable(.noKpData)` and no flag.
    public init(
        spaceWeather: SpaceWeatherResponse?,
        rule: AuroraRule,
        observer: Observer,
        darkness: TimeWindow?,
        now: Date,
        isNextDarkWindow: Bool
    ) {
        self.init(
            outlook: rule.outlook(
                observer, darkness: darkness, readings: spaceWeather?.kpReadings ?? [], now: now,
                isNextDarkWindow: isNextDarkWindow),
            source: spaceWeather?.kpForecast.source ?? SpaceWeatherResponse.swpcSource,
            asOfUTC: spaceWeather?.kpAsOfUTC)
    }

    public var isPossible: Bool { outlook.isPossible }

    public func age(at now: Date) -> TimeInterval? {
        asOfUTC.map { now.timeIntervalSince($0) }
    }
}

extension SpaceWeatherResponse {
    static let swpcSource = "NOAA Space Weather Prediction Center"

    private var usableKpBlocks: [KpBlock] {
        [kpObserved, kpForecast].filter { $0.status == .ok }
    }

    /// Observed and forecast Kp for `AuroraRule`, from blocks the Worker marks ok.
    /// Last-good copies are not used: a stale storm must not raise the flag.
    public var kpReadings: [KpReading] {
        usableKpBlocks.flatMap { block in
            block.values.map { KpReading(start: $0.t, kp: $0.v, kind: .init(worker: $0.kind)) }
        }
    }

    public var kpAsOfUTC: Date? {
        usableKpBlocks.compactMap(\.fetchedUTC).min()
    }
}

extension Verdict {
    /// The verdict for one `NightOutlook` (M5's week row): same rule, same window.
    public static func evaluate(
        _ night: NightOutlook,
        conditions: ConditionsResponse?,
        aurora: AuroraSignal? = nil,
        config: VerdictConfig,
        now: Date,
        galacticCoreIsTarget: Bool = false
    ) throws(EvaluationError) -> Verdict {
        try evaluate(
            night: night.report, conditions: conditions, aurora: aurora, config: config, now: now,
            galacticCoreIsTarget: galacticCoreIsTarget)
    }

    /// A rater for `WeekOutlook.build(verdict:)`. It never sees the aurora flag;
    /// attach `WeekRow.aurora` for display with `withAurora`.
    public static func weekRater(
        conditions: ConditionsResponse?,
        config: VerdictConfig,
        now: Date,
        galacticCoreIsTarget: Bool = false
    ) -> (NightOutlook) -> Result<Verdict, EvaluationError> {
        { night in
            Result { () throws(EvaluationError) in
                try evaluate(
                    night, conditions: conditions, config: config, now: now,
                    galacticCoreIsTarget: galacticCoreIsTarget)
            }
        }
    }
}
