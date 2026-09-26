import Foundation
import Testing
@testable import DarkSky
import SkyCore

/// M11: the conditions client against stubbed HTTP (never the network): ETag
/// revalidation and 304s, the refresh time, and the status the views word.
@Suite("Conditions client", .serialized)
struct ConditionsClientTests {
    let place = Place(name: "Stub", latitude: 38.36, longitude: -109.94, timeZoneID: "America/Denver")
    let window = DateInterval(start: .now.addingTimeInterval(3600), duration: 10 * 3600)

    var request: ConditionsRequest {
        try! ConditionsRequest.make(latitude: place.latitude, longitude: place.longitude, window: window, now: .now).get()
    }

    func client(worker: Bool = true, network: Bool = true, store: SnapshotStore = .temporary()) -> ConditionsClient {
        ConditionsClient(
            workerBase: worker ? StubNetwork.workerBase : nil, networkEnabled: network, store: store,
            injectedSession: StubNetwork.session(), hedgeDelay: .milliseconds(200))
    }

    /// A Worker that answers 200 with `etag`, or 304 when asked `If-None-Match: etag`.
    func revalidatingWorker(etag: String, checkedAt: Date, nextUpdate: Date?) -> StubNetwork.Handler {
        let body = StubNetwork.workerBody(request, nextUpdate: nextUpdate)
        let date = StubNetwork.httpDate(checkedAt)
        return { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            if r.value(forHTTPHeaderField: "If-None-Match") == etag {
                return (304, ["ETag": etag, "Date": date], Data())
            }
            return (200, ["ETag": etag, "Date": date, "Content-Type": "application/json"], body)
        }
    }

    @Test("200 stores the ETag; the next request sends it; 304 keeps the body and fetched_utc and records the Date")
    func etagAnd304() async throws {
        let checked = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 30).rounded(.down))
        StubNetwork.install(revalidatingWorker(etag: "\"v1\"", checkedAt: checked, nextUpdate: nil))
        let c = client()

        let first = await c.fetch(for: place, window: window)
        let s1 = try #require(first.snapshot)
        #expect(first.workerHTTPStatus == 200)
        #expect(s1.etag == "\"v1\"")
        #expect(s1.checkedUTC == nil)
        #expect(first.status == .liveWorker(confirmedAt: s1.fetchedUTC, revalidated: false))
        #expect(StubNetwork.requests(host: StubNetwork.workerHost).first?.value(forHTTPHeaderField: "If-None-Match") == nil)

        let second = await c.fetch(for: place, window: window)
        let s2 = try #require(second.snapshot)
        let sent = StubNetwork.requests(host: StubNetwork.workerHost)
        #expect(sent.count == 2)
        #expect(sent.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(second.workerHTTPStatus == 304)
        // On disk times keep whole seconds; the 304 never moves fetched_utc beyond that.
        #expect(abs(s2.fetchedUTC.timeIntervalSince(s1.fetchedUTC)) < 1)
        #expect(s2.fetchedUTC <= s1.fetchedUTC)
        #expect(s2.response == s1.response)
        #expect(s2.checkedUTC == checked)
        #expect(second.status == .liveWorker(confirmedAt: checked, revalidated: true))

        // The confirmation is saved: offline, the copy shows its original fetch time and the check.
        let saved = try #require(await c.cachedConditions(for: place, window: window))
        #expect(saved.fetchedUTC == s2.fetchedUTC)
        #expect(saved.checkedUTC == checked)
        #expect(StubNetwork.requests(host: "api.open-meteo.com").isEmpty)
    }

    @Test("a changed body (200 with a new ETag) replaces the copy and clears the check time")
    func changedBody() async throws {
        let store = SnapshotStore.temporary()
        StubNetwork.install(revalidatingWorker(etag: "\"v1\"", checkedAt: .now, nextUpdate: nil))
        _ = await client(store: store).fetch(for: place, window: window)
        _ = await client(store: store).fetch(for: place, window: window)
        let body2 = StubNetwork.workerBody(request, nextUpdate: nil, cloud: 60)
        StubNetwork.install { r in
            if r.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return (200, ["ETag": "\"v2\""], body2)
            }
            throw URLError(.badServerResponse)
        }
        let third = await client(store: store).fetch(for: place, window: window)
        let s3 = try #require(third.snapshot)
        #expect(third.workerHTTPStatus == 200)
        #expect(s3.etag == "\"v2\"")
        #expect(s3.checkedUTC == nil)
        #expect(s3.response.fields["cloud_cover_total"]?.series.first?.values.first?.v == 60)
    }

    @Test("refresh at the Worker's next expected update")
    func nextRefreshFollowsWorker() async throws {
        let next = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 20 * 60).rounded(.down))
        StubNetwork.install(revalidatingWorker(etag: "\"a\"", checkedAt: .now, nextUpdate: next))
        let c = client()
        let result = await c.fetch(for: place, window: window)
        #expect(result.nextRefresh == next)
        #expect(await c.nextRefresh(for: place, window: window, now: .now) == next)
    }

    @Test("a late run (expected time passed) refreshes a minute from now, not in a loop")
    func lateRun() async throws {
        StubNetwork.install(revalidatingWorker(etag: "\"a\"", checkedAt: .now, nextUpdate: .now.addingTimeInterval(-300)))
        let before = Date.now
        let result = await client().fetch(for: place, window: window)
        let wait = result.nextRefresh.timeIntervalSince(before)
        #expect(wait >= 60 && wait < 70, "waits \(wait) s")
    }

    @Test("Worker silent: clouds come direct, and the status says the Worker didn't answer")
    func workerSilent() async throws {
        StubNetwork.install { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            return (503, [:], Data())
        }
        let result = await client().fetch(for: place, window: window)
        let s = try #require(result.snapshot)
        #expect(s.response.isDirectFallback)
        #expect(s.response.fields["cloud_cover_total"]?.source == OpenMeteoDirect.source)
        guard case .workerSilentDirect = result.status else {
            Issue.record("status \(result.status)")
            return
        }
        #expect(result.workerHTTPStatus == nil)
        #expect(result.nextRefresh.timeIntervalSinceNow <= ConditionsSchedule.retryWait + 1)
    }

    @Test("no Worker configured is a normal mode: direct clouds, calm wording, no Worker request")
    func notSetUp() async throws {
        StubNetwork.install { r in
            if let direct = StubNetwork.openMeteo(r) { return direct }
            throw URLError(.cannotFindHost)
        }
        let result = await client(worker: false).fetch(for: place, window: window)
        let s = try #require(result.snapshot)
        guard case .notSetUp = result.status else {
            Issue.record("status \(result.status)")
            return
        }
        #expect(s.response.fields["cloud_cover_total"]?.source == OpenMeteoDirect.directSource)
        #expect(s.response.fields["wind_gust"]?.reason == OpenMeteoDirect.notSetUpReason)
        #expect(StubNetwork.requests(host: StubNetwork.workerHost).isEmpty)
        #expect(result.status.summary(now: .now).range(of: "unreachable") == nil)
        #expect(abs(result.nextRefresh.timeIntervalSince(s.confirmedUTC) - ConditionsSchedule.maximumWait) < 1)
    }

    @Test("nothing reachable: the saved copy, labelled offline")
    func offlineCache() async throws {
        let store = SnapshotStore.temporary()
        StubNetwork.install(revalidatingWorker(etag: "\"v1\"", checkedAt: .now, nextUpdate: nil))
        let saved = try #require(await client(store: store).fetch(for: place, window: window).snapshot)
        StubNetwork.install(StubNetwork.offline)
        let result = await client(store: store).fetch(for: place, window: window)
        let shown = try #require(result.snapshot)
        #expect(shown.response == saved.response)
        #expect(abs(shown.fetchedUTC.timeIntervalSince(saved.fetchedUTC)) < 1)
        #expect(result.status == .offlineCache(fetchedAt: shown.fetchedUTC))
        #expect(!result.status.isLive)
    }

    @Test("nothing reachable and nothing saved")
    func nothing() async {
        StubNetwork.install(StubNetwork.offline)
        let result = await client().fetch(for: place, window: window)
        #expect(result.snapshot == nil)
        #expect(result.status == .nothing)
    }

    @Test("network disabled (UI tests, -DarkSkyOffline) never makes a request")
    func networkDisabled() async {
        StubNetwork.install(revalidatingWorker(etag: "\"v1\"", checkedAt: .now, nextUpdate: nil))
        let result = await client(network: false).fetch(for: place, window: window)
        #expect(result.status == .nothing)
        #expect(StubNetwork.requests.isEmpty)
    }

    @Test("updates: the saved copy first, then the live answer") @MainActor
    func updates() async throws {
        let store = SnapshotStore.temporary()
        StubNetwork.install(revalidatingWorker(etag: "\"v1\"", checkedAt: .now, nextUpdate: nil))
        _ = await client(store: store).fetch(for: place, window: window)
        var seen: [ConditionsStatus] = []
        for await update in client(store: store).updates(for: place, window: window) {
            seen.append(update.status)
            if seen.count == 2 { break }
        }
        guard seen.count == 2, case .offlineCache = seen[0], case .liveWorker(_, true) = seen[1] else {
            Issue.record("statuses \(seen)")
            return
        }
    }

    @Test("status for a snapshot the caller holds")
    func statusOf() throws {
        let s = try ConditionsSnapshot(workerJSON: StubNetwork.workerBody(request, nextUpdate: nil), fetchedUTC: .now)
        #expect(ConditionsStatus.of(nil, cached: false, workerConfigured: true) == .nothing)
        #expect(ConditionsStatus.of(s, cached: true, workerConfigured: true) == .offlineCache(fetchedAt: s.fetchedUTC))
        #expect(ConditionsStatus.of(s, cached: false, workerConfigured: true) == .liveWorker(confirmedAt: s.fetchedUTC, revalidated: false))
        let direct = ConditionsSnapshot(
            response: OpenMeteoDirect.response(request: request, fetches: [], fetchedUTC: .now), fetchedUTC: .now)
        #expect(ConditionsStatus.of(direct, cached: false, workerConfigured: true) == .workerSilentDirect(fetchedAt: direct.fetchedUTC))
        #expect(ConditionsStatus.of(direct, cached: false, workerConfigured: false) == .notSetUp(fetchedAt: direct.fetchedUTC))
    }
}
