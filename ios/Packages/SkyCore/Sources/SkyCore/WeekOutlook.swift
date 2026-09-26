public import Foundation

/// Everything the week row shows except the verdict and the aurora flag, and
/// everything a verdict for the night may read. Aurora is deliberately not
/// here, so it cannot lower (or raise) a verdict.
public struct NightOutlook: Sendable, Hashable {
    public let date: NightDate
    /// The instant given to `planNight`: 21:00 local on `date`.
    public let evening: Date
    public let report: NightReport
    /// Cloud cover over all of the night's moon-free astronomical darkness, one entry per input series.
    public let cloud: [ModelMean]

    public struct ModelMean: Sendable, Hashable {
        public let model: String
        public let mean: WindowMean
    }

    public var moonFreeMinutes: Int { report.moonFreeMinutes }
    public var darkness: TimeWindow? { report.darkness }
    public var gcPeak: GCVisibility { report.gc }
    /// Every moment of moon-free astronomical darkness (the verdict's window).
    public var moonFreeDarkness: [TimeWindow] {
        report.moonFreeWindows.map { TimeWindow(start: $0.start, end: $0.end) }
    }
}

public struct WeekRow<V: Sendable>: Sendable {
    public let night: NightOutlook
    public let verdict: V
    public let aurora: AuroraOutlook
}

extension WeekRow: Equatable where V: Equatable {}

public enum WeekOutlook {
    public static let defaultNightCount = 7

    /// The planner numbers and cloud means for one night at a spot.
    public static func night(
        _ date: NightDate,
        observer: Observer,
        timeZone: TimeZone,
        clouds: [HourlySeries]
    ) throws(AstronomyError) -> NightOutlook {
        let evening = date.evening(in: timeZone)
        let report = try Planner.planNight(observer, evening: evening)
        let windows = report.moonFreeWindows.map { TimeWindow(start: $0.start, end: $0.end) }
        return NightOutlook(
            date: date,
            evening: evening,
            report: report,
            cloud: clouds.map { .init(model: $0.model, mean: WindowMean.of($0, over: windows)) })
    }

    /// Consecutive nights from `first` (default: the night containing `now` at the spot).
    /// - Parameters:
    ///   - kp: Kp observed and forecast; nil when space weather is unavailable.
    ///   - verdict: rates one night; it never sees the aurora flag.
    public static func build<V: Sendable>(
        observer: Observer,
        timeZone: TimeZone,
        now: Date,
        first: NightDate? = nil,
        count: Int = defaultNightCount,
        clouds: [HourlySeries],
        kp: [KpReading]?,
        auroraRule: AuroraRule,
        verdict: (NightOutlook) -> V
    ) throws(AstronomyError) -> [WeekRow<V>] {
        let start = first ?? NightDate.containing(now, in: timeZone)
        var nights: [NightOutlook] = []
        for offset in 0..<max(0, count) {
            nights.append(try night(start.adding(days: offset), observer: observer, timeZone: timeZone, clouds: clouds))
        }
        let next = nights.firstIndex { ($0.darkness?.end).map { $0 > now } ?? false }
        return nights.enumerated().map { index, night in
            WeekRow(
                night: night,
                verdict: verdict(night),
                aurora: auroraRule.outlook(
                    observer, darkness: night.darkness, readings: kp ?? [], now: now,
                    isNextDarkWindow: index == next))
        }
    }
}
