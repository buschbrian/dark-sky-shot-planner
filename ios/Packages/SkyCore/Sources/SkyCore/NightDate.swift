public import Foundation

/// A night named by the calendar date of its evening, as in the web app's
/// `#date=2026-09-26`: the night that starts on that date and contains the
/// following local midnight. Planned from 21:00 local on that date
/// (`eveningUtcFor` in `app/src/main.ts`), in the spot's time zone.
public struct NightDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Local hour the web app plans a night from.
    static let eveningHour = 21
    /// Before this local hour an instant belongs to the night that began the
    /// previous evening (`eveningFor` in `app/src/astronomy/showers.ts`).
    static let nightRolloverHour = 12

    public init?(year: Int, month: Int, day: Int) {
        let comps = DateComponents(year: year, month: month, day: day)
        guard comps.isValidDate(in: Self.utcCalendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`, the web app's URL `date` format.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    public static func < (a: NightDate, b: NightDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public func adding(days: Int) -> NightDate {
        let cal = Self.utcCalendar
        let noon = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        let next = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: days, to: noon)!)
        return NightDate(year: next.year!, month: next.month!, day: next.day!)!
    }

    /// 21:00 local time on this date in `timeZone`: the instant `planNight` is given.
    public func evening(in timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = DateComponents(year: year, month: month, day: day, hour: Self.eveningHour)
        // Only nil for invalid components, which init rules out.
        return cal.date(from: comps)!
    }

    /// The night `instant` belongs to in `timeZone`: the local date, or the
    /// previous one before local noon (the night containing the midnight just past).
    public static func containing(_ instant: Date, in timeZone: TimeZone) -> NightDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let local = cal.dateComponents([.year, .month, .day, .hour], from: instant)
        let date = NightDate(year: local.year!, month: local.month!, day: local.day!)!
        return local.hour! < nightRolloverHour ? date.adding(days: -1) : date
    }

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}
