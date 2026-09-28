import Foundation

/// When Week and the Spots background refresh ask for conditions again. Both
/// follow the fetches' `nextRefresh` (`ConditionsSchedule.nextFetch`: the
/// Worker's `next_update_expected_utc`, at least 60 s out, at most 30 min
/// after the last confirmation) instead of a fixed timer.
nonisolated enum RefreshTiming {
    /// Week's wait when no block gave a time (no provider schedule, no darkness).
    static let weekFallback: TimeInterval = 15 * 60
    static let minimumWait: TimeInterval = 1
    /// `BGAppRefreshTaskRequest.earliestBeginDate` bounds: iOS runs the task
    /// later anyway, and one sooner than 15 min only wastes the budget.
    static let spotsEarliest: TimeInterval = 15 * 60
    static let spotsLatest: TimeInterval = 3 * 3600

    /// Seconds an open Week sleeps: until the soonest block's next refresh.
    static func weekWait(nextRefreshes: [Date], now: Date) -> TimeInterval {
        let soonest = nextRefreshes.filter { $0 != .distantFuture }.min()
        guard let soonest else { return weekFallback }
        return max(soonest.timeIntervalSince(now), minimumWait)
    }

    /// The soonest stored next refresh across the spots that need checking,
    /// clamped to now + 15 min … now + 3 h; none stored means the 3 h default.
    static func spotsEarliestBegin(nextRefreshes: [Date?], now: Date) -> Date {
        let lo = now.addingTimeInterval(spotsEarliest), hi = now.addingTimeInterval(spotsLatest)
        guard let soonest = nextRefreshes.compactMap(\.self).min() else { return hi }
        return min(max(soonest, lo), hi)
    }

    /// The soonest real `nextRefresh` among several fetches (nil for none).
    static func soonest(_ dates: [Date]) -> Date? {
        dates.filter { $0 != .distantFuture }.min()
    }
}
