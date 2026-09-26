public import Foundation

extension ConditionsSnapshot {
    /// The newest cached snapshot for this grid cell whose window overlaps the
    /// one asked for: what an offline screen shows, with its age.
    public static func best(
        for cell: ConditionsCell, window: DateInterval, in snapshots: some Sequence<ConditionsSnapshot>
    ) -> ConditionsSnapshot? {
        newest(snapshots.filter { s in
            cell.matches(s.response.cell)
                && s.response.window.startUTC < window.end
                && s.response.window.endUTC > window.start
        })
    }

    /// Snapshots old enough to delete: the Worker keeps last-good values a
    /// week, so an older copy is never the best answer.
    public static func expired(_ snapshots: [ConditionsSnapshot], now: Date, keep: TimeInterval = 8 * 86_400) -> [ConditionsSnapshot] {
        snapshots.filter { now.timeIntervalSince($0.fetchedUTC) > keep }
    }
}
