import Foundation
import Testing
@testable import DarkSky
import SkyCore

/// Review B-4: Tonight, Week and the Spots planner word where conditions came
/// from with `ConditionsStatus`, so a 304 on an old copy reads "unchanged",
/// never "offline". Part of the serialized client suite: one stub handler at a time.
extension ConditionsClientTests {
    /// Tonight's night window and the request the client will make for it.
    func tonightRequest() throws -> (night: NightDate, request: ConditionsRequest) {
        let night = place.tonight()
        let window = ConditionsRequest.nightWindow(night, in: place.timeZone)
        let request = try ConditionsRequest.make(
            latitude: place.latitude, longitude: place.longitude, window: window, now: .now).get()
        return (night, request)
    }

    /// 200 with `etag`, or 304 when the request sends it back.
    func worker(_ request: ConditionsRequest, etag: String) -> StubNetwork.Handler {
        let body = StubNetwork.workerBody(request, nextUpdate: nil)
        return { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            let date = StubNetwork.httpDate(.now)
            if r.value(forHTTPHeaderField: "If-None-Match") == etag { return (304, ["ETag": etag, "Date": date], Data()) }
            return (200, ["ETag": etag, "Date": date, "Content-Type": "application/json"], body)
        }
    }

    @Test("Tonight: 200 reads live; a 304 on a two-hour-old copy reads 'checked …, unchanged', never offline")
    @MainActor
    func tonightOriginAfter304() async throws {
        let (night, request) = try tonightRequest()
        let store = SnapshotStore.temporary()
        StubNetwork.install(worker(request, etag: "\"v1\""))
        let model = TonightModel()

        await model.loadConditions(place: place, night: night, provider: client(store: store))
        let live = model.conditions.originLine(refreshing: false, now: .now)
        #expect(live == "Live conditions, fetched just now", "\(live)")
        guard case .loaded(_, .liveWorker(_, false)) = model.conditions else {
            Issue.record("state \(model.conditions)")
            return
        }

        // The saved copy is two hours old: the case the old `fetchedUTC < asked - 5 s` rule called offline.
        let saved = try #require(model.snapshot)
        let old = Date.now.addingTimeInterval(-2 * 3600)
        await store.save(ConditionsSnapshot(response: saved.response, fetchedUTC: old, etag: "\"v1\""))

        await model.loadConditions(place: place, night: night, provider: client(store: store))
        #expect(StubNetwork.requests(host: StubNetwork.workerHost).last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        let shown = try #require(model.snapshot)
        #expect(abs(shown.fetchedUTC.timeIntervalSince(old)) < 1, "a 304 keeps the old fetch time")
        guard case .loaded(_, .liveWorker(_, true)) = model.conditions else {
            Issue.record("state \(model.conditions)")
            return
        }
        let line = model.conditions.originLine(refreshing: false, now: .now)
        #expect(line.hasPrefix("Live conditions, checked "), "\(line)")
        #expect(line.hasSuffix(", unchanged"), "\(line)")
        #expect(!line.localizedCaseInsensitiveContains("offline"), "\(line)")
        #expect(!line.contains("No connection"), "\(line)")
    }

    @Test("Tonight: a configured Worker that fails reads with the workerSilentDirect words, never 'Worker unreachable'")
    @MainActor
    func tonightOriginWorkerSilent() async throws {
        let (night, _) = try tonightRequest()
        StubNetwork.install { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            return (503, [:], Data())
        }
        let model = TonightModel()
        await model.loadConditions(place: place, night: night, provider: client())
        guard case .loaded(_, .workerSilentDirect(let at)) = model.conditions else {
            Issue.record("state \(model.conditions)")
            return
        }
        let now = Date.now
        let line = model.conditions.originLine(refreshing: false, now: now)
        #expect(line == ConditionsStatus.workerSilentDirect(fetchedAt: at).summary(now: now))
        #expect(line.hasPrefix("The conditions service didn't answer"), "\(line)")
        #expect(!line.contains("unreachable"), "\(line)")
    }

    @Test("Tonight: offline with a saved copy says so, and 'refreshing' while a fetch runs")
    @MainActor
    func tonightOriginOffline() async throws {
        let (night, request) = try tonightRequest()
        let store = SnapshotStore.temporary()
        StubNetwork.install(worker(request, etag: "\"v1\""))
        _ = await client(store: store).fetch(for: place, window: request.window)
        StubNetwork.install(StubNetwork.offline)
        let model = TonightModel()
        await model.loadConditions(place: place, night: night, provider: client(store: store))
        guard case .loaded(_, .offlineCache) = model.conditions else {
            Issue.record("state \(model.conditions)")
            return
        }
        #expect(model.conditions.originLine(refreshing: false, now: .now).hasPrefix("No connection: showing the copy saved"))
        #expect(model.conditions.originLine(refreshing: true, now: .now).hasPrefix("Conditions: saved copy from"))
    }

    @Test("Week: the status line follows the client, 200 then 304 'unchanged'")
    func weekStatusLine() async throws {
        let block = WeekBlock(window: window, nights: [])
        let store = SnapshotStore.temporary()
        StubNetwork.install(revalidatingWorker(etag: "\"w\"", checkedAt: .now, nextUpdate: nil))
        let first = await WeekPlanner.fetch([block], place: place, provider: client(store: store))
        #expect(first.statusLine(now: .now) == "Live conditions, fetched just now.")
        let second = await WeekPlanner.fetch([block], place: place, provider: client(store: store))
        let line = try #require(second.statusLine(now: .now))
        #expect(line.hasPrefix("Live conditions, checked ") && line.hasSuffix(", unchanged."), "\(line)")

        StubNetwork.install(StubNetwork.offline)
        let offline = await WeekPlanner.fetch([block], place: place, provider: client(store: store))
        #expect(offline.statusLine(now: .now)?.hasPrefix("No connection: showing the copy saved") == true)
        let merged = second.keepingNewestRuns(from: await WeekPlanner.fetch([block], place: place, provider: client(network: false)))
        #expect(merged.statuses.first.map { if case .offlineCache = $0 { true } else { false } } == true,
                "a kept copy with no new answer reads offline, not empty")
    }

    @Test("Spots: the week records the weakest window's status")
    func spotWeekStatus() async throws {
        let input = SpotWeekPlanner.Input(
            place: place, latitude: place.latitude, longitude: place.longitude, timeZone: place.timeZone, horizon: nil)
        StubNetwork.install { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            return (503, [:], Data())
        }
        let week = await SpotWeekPlanner.compute(input, conditions: client())
        if week.requestedWindows > 0 {
            guard case .workerSilentDirect? = week.conditionsStatus else {
                Issue.record("status \(String(describing: week.conditionsStatus))")
                return
            }
        } else {
            #expect(week.conditionsStatus == nil)
        }
        // Saved with the spot (whole seconds on disk).
        let decoded = try SpotWeek.decode(week.encoded())
        if case .workerSilentDirect(let saved)? = decoded.conditionsStatus,
           case .workerSilentDirect(let original)? = week.conditionsStatus {
            #expect(abs(saved.timeIntervalSince(original)) < 1)
        } else {
            #expect(decoded.conditionsStatus == nil && week.conditionsStatus == nil)
        }
    }

    @Test("combined status is the least live, then the oldest")
    func combined() {
        let t0 = Date(timeIntervalSince1970: 1_000_000), t1 = t0.addingTimeInterval(60)
        #expect(ConditionsStatus.combined([]) == nil)
        #expect(ConditionsStatus.combined([.liveWorker(confirmedAt: t1, revalidated: true), .offlineCache(fetchedAt: t1)])
                == .offlineCache(fetchedAt: t1))
        #expect(ConditionsStatus.combined([.liveWorker(confirmedAt: t1, revalidated: false), .liveWorker(confirmedAt: t0, revalidated: true)])
                == .liveWorker(confirmedAt: t0, revalidated: true))
        #expect(ConditionsStatus.combined([.nothing, .notSetUp(fetchedAt: t0)]) == .nothing)
    }
}
