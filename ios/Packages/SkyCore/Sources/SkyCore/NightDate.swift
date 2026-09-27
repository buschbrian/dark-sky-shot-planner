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

    /// The calendar rule: the local date, or the previous one before local
    /// noon (the night containing the midnight just past). For "tonight" as the
    /// app means it, use `current(at:observer:timeZone:)`; this is for grouping
    /// instants (events, a pinned time) by night.
    public static func containing(_ instant: Date, in timeZone: TimeZone) -> NightDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let local = cal.dateComponents([.year, .month, .day, .hour], from: instant)
        let date = NightDate(year: local.year!, month: local.month!, day: local.day!)!
        return local.hour! < nightRolloverHour ? date.adding(days: -1) : date
    }

    /// "Tonight" at `instant` for this observer (review B-2): the previous
    /// evening's night only while it is still dark there, that is before its
    /// astronomical dawn (civil dawn when the sun never reaches −18°);
    /// otherwise the night that starts this evening. Where it never gets darker
    /// than civil twilight, today's evening. Mirrors `tonightIso` in
    /// `app/src/state/tonight.ts`; `shared/golden/tonight.json` holds both.
    public static func current(at instant: Date, observer: Observer, timeZone: TimeZone) -> NightDate {
        currentSpan(at: instant, observer: observer, timeZone: timeZone).night
    }

    /// `current(at:)` with the interval over which it holds, so a caller can
    /// reuse the answer until `until` instead of recomputing the twilight.
    public static func currentSpan(at instant: Date, observer: Observer, timeZone: TimeZone) -> CurrentNight {
        let today = localDate(of: instant, in: timeZone)
        let todayStarts = today.becomesCurrent(observer: observer, timeZone: timeZone)
        let night = instant < todayStarts ? today.adding(days: -1) : today
        let from = night == today ? todayStarts : night.becomesCurrent(observer: observer, timeZone: timeZone)
        let until = night == today ? today.adding(days: 1).becomesCurrent(observer: observer, timeZone: timeZone) : todayStarts
        return CurrentNight(night: night, from: from, until: until)
    }

    /// When this night becomes "tonight": the end of the previous night's
    /// darkness (`darknessEnd`), but never before local midnight starting
    /// this date.
    public func becomesCurrent(observer: Observer, timeZone: TimeZone) -> Date {
        let midnight = Self.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day))!
        guard let end = adding(days: -1).darknessEnd(observer: observer, timeZone: timeZone) else { return midnight }
        return max(midnight, end)
    }

    /// When this night's darkness ends: astronomical dawn, or civil dawn when
    /// the sun never reaches −18°. nil when it never gets darker than civil
    /// twilight (or a search lands outside this night, which only polar
    /// latitudes can do).
    public func darknessEnd(observer: Observer, timeZone: TimeZone) -> Date? {
        let evening = evening(in: timeZone)
        // Noon the next day: a dawn after it belongs to no night of this date.
        let latest = evening.addingTimeInterval(15 * 3600)
        for altitude in [-18.0, -6.0] {
            guard let found = try? Planner.darknessWindow(observer, evening: evening, altitudeDeg: altitude) else { return nil }
            if let window = found.window { return window.end <= latest ? window.end : nil }
        }
        return nil
    }

    static func localDate(of instant: Date, in timeZone: TimeZone) -> NightDate {
        let local = calendar(timeZone).dateComponents([.year, .month, .day], from: instant)
        return NightDate(year: local.year!, month: local.month!, day: local.day!)!
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}

/// The current night and the interval over which it is current.
public struct CurrentNight: Sendable, Hashable {
    public let night: NightDate
    /// When it became "tonight" (the previous night's dawn, or local midnight).
    public let from: Date
    /// When the next night takes over (this night's dawn, or the next local midnight).
    public let until: Date

    public func contains(_ instant: Date) -> Bool { instant >= from && instant < until }
}
