import Foundation
import SkyCore
import Testing
@testable import DarkSky

/// Refresh timing (embeds brief item 3): Week sleeps until its soonest block's
/// next refresh; the Spots background refresh begins no sooner than 15 min
/// and no later than 3 h out; SpotWeek keeps the soonest next refresh.
struct RefreshTimingTests {
    static let now = Date(timeIntervalSince1970: 1_790_500_000)
    static func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    @Test("Week waits until the soonest block's next refresh")
    func weekSoonest() {
        #expect(RefreshTiming.weekWait(nextRefreshes: [Self.at(22), Self.at(7), Self.at(30)], now: Self.now) == 7 * 60)
    }

    @Test("Week ignores a provider with no schedule and falls back to 15 min with none")
    func weekFallback() {
        #expect(RefreshTiming.weekWait(nextRefreshes: [], now: Self.now) == 15 * 60)
        #expect(RefreshTiming.weekWait(nextRefreshes: [.distantFuture], now: Self.now) == 15 * 60)
        #expect(RefreshTiming.weekWait(nextRefreshes: [.distantFuture, Self.at(4)], now: Self.now) == 4 * 60)
    }

    @Test("a refresh already due wakes Week at once, never a negative sleep")
    func weekOverdue() {
        #expect(RefreshTiming.weekWait(nextRefreshes: [Self.at(-5)], now: Self.now) == 1)
    }

    @Test("Spots: the soonest stored next refresh, inside 15 min … 3 h", arguments: [
        ([Double?](), 180.0),          // nothing stored: the 3 h default
        ([nil, nil], 180.0),
        ([40, 90], 40.0),              // soonest wins
        ([nil, 55], 55.0),             // a spot with no week does not pull it in
        ([2], 15.0),                   // clamped up to 15 min
        ([-30], 15.0),                 // overdue: 15 min
        ([600], 180.0),                // clamped down to 3 h
    ])
    func spotsClamp(_ stored: [Double?], _ expectedMinutes: Double) {
        let begin = RefreshTiming.spotsEarliestBegin(nextRefreshes: stored.map { $0.map(Self.at) }, now: Self.now)
        #expect(begin == Self.at(expectedMinutes))
    }

    @Test("a spot week stores its soonest next refresh and survives a round trip")
    func spotWeekStoresNextRefresh() throws {
        #expect(RefreshTiming.soonest([Self.at(30), .distantFuture, Self.at(12)]) == Self.at(12))
        #expect(RefreshTiming.soonest([.distantFuture]) == nil)
        let week = SpotWeek(checkedAt: Self.now, terrainAware: false, nights: [], requestedWindows: 2, fetchedWindows: 2,
                            interrupted: false, nextRefresh: Self.at(12))
        #expect(try SpotWeek.decode(week.encoded()).nextRefresh == Self.at(12))
        // Weeks saved before the field existed decode with none.
        let old = try JSONSerialization.jsonObject(with: week.encoded()) as! [String: Any]
        let stripped = try JSONSerialization.data(withJSONObject: old.filter { $0.key != "nextRefresh" })
        #expect(try SpotWeek.decode(stripped).nextRefresh == nil)
    }

    @Test("SpotWeekPlanner records the provider's next refresh")
    func plannerRecordsNextRefresh() async {
        let place = Place(name: "Candlestick", latitude: 38.374031, longitude: -109.965416, timeZoneID: "America/Denver")
        let input = SpotWeekPlanner.Input(place: place, latitude: place.latitude, longitude: place.longitude,
                                          timeZone: place.timeZone, horizon: nil)
        let week = await SpotWeekPlanner.compute(input, conditions: ScheduledProvider(next: Self.at(25)), now: Self.now)
        if week.requestedWindows > 0 {
            #expect(week.nextRefresh == Self.at(25))
        } else {
            #expect(week.nextRefresh == nil)
        }
    }
}

/// A live provider with nothing to say but when to ask again.
private struct ScheduledProvider: LiveConditionsProviding {
    let next: Date
    var workerConfigured: Bool { true }
    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? { nil }
    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? { nil }
    func cachedConditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? { nil }
    func latestRuns() async -> [String: ModelRunInfo] { [:] }
    func fetch(for place: Place, window: DateInterval) async -> ConditionsFetch {
        ConditionsFetch(snapshot: nil, status: .nothing, nextRefresh: next)
    }
    func nextRefresh(for place: Place, window: DateInterval, now: Date) async -> Date { next }
}
