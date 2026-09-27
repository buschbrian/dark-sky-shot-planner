import Foundation
import Testing
@testable import SkyCore

/// M11: ETag storage, 304 confirmation, the refetch time and the 15-minute
/// series, against the golden Worker response.
@Suite("Conditions revalidation")
struct ConditionsRevalidationTests {
    static func golden() throws -> ConditionsResponse {
        try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json"))
    }

    static let received = WorkerJSON.parse("2026-09-26T00:40:00Z")!

    @Test("a 304 moves only the check time; fetched_utc and the body stay")
    func confirm() throws {
        let s = ConditionsSnapshot(response: try Self.golden(), fetchedUTC: Self.received, etag: "\"abc\"")
        let later = Self.received.addingTimeInterval(900)
        let c = s.confirmed(at: later)
        #expect(c.fetchedUTC == s.fetchedUTC)
        #expect(c.response == s.response)
        #expect(c.etag == "\"abc\"")
        #expect(c.checkedUTC == later)
        #expect(c.confirmedUTC == later)
        // An out-of-order older Date never moves the check time back.
        #expect(c.confirmed(at: Self.received).checkedUTC == later)
        #expect(s.confirmedUTC == Self.received)
    }

    @Test("ETag and check time survive the disk round trip; older files still decode")
    func codable() throws {
        let s = ConditionsSnapshot(
            response: try Self.golden(), fetchedUTC: Self.received, etag: "W/\"x\"",
            checkedUTC: Self.received.addingTimeInterval(60))
        let back = try ConditionsSnapshot.decode(s.encoded())
        #expect(back.etag == "W/\"x\"")
        #expect(back.checkedUTC == s.checkedUTC)

        let old = ConditionsSnapshot(response: try Self.golden(), fetchedUTC: Self.received)
        let json = String(decoding: try old.encoded(), as: UTF8.self)
        #expect(!json.contains("\"etag\""))
        #expect(!json.contains("checked_utc"))
        let decoded = try ConditionsSnapshot.decode(Data(json.utf8))
        #expect(decoded.etag == nil && decoded.checkedUTC == nil)
    }

    @Test("refetch at max(next_update_expected_utc, now + 60 s)")
    func schedule() throws {
        let response = try Self.golden()
        let next = try #require(response.nextUpdateExpectedUTC) // 00:45:21Z
        let s = ConditionsSnapshot(response: response, fetchedUTC: Self.received)
        // Before the expected update: wait for it.
        #expect(ConditionsSchedule.nextFetch(after: s, now: Self.received) == next)
        // Run is late (expected time passed): one minute from now.
        let late = next.addingTimeInterval(300)
        #expect(ConditionsSchedule.nextFetch(after: s, now: late) == late.addingTimeInterval(60))
        // Expected in 20 s: still at least 60 s away.
        let close = next.addingTimeInterval(-20)
        #expect(ConditionsSchedule.nextFetch(after: s, now: close) == close.addingTimeInterval(60))
    }

    @Test("no estimate, or a far one, waits at most 30 min after the last confirmation")
    func cap() throws {
        var response = try Self.golden()
        response.nextUpdateExpectedUTC = nil
        let s = ConditionsSnapshot(response: response, fetchedUTC: Self.received)
        #expect(ConditionsSchedule.nextFetch(after: s, now: Self.received) == Self.received.addingTimeInterval(1800))
        response.nextUpdateExpectedUTC = Self.received.addingTimeInterval(6 * 3600)
        let far = ConditionsSnapshot(response: response, fetchedUTC: Self.received)
        #expect(ConditionsSchedule.nextFetch(after: far, now: Self.received) == Self.received.addingTimeInterval(1800))
        // A 304 counts as a confirmation: the cap runs from the check.
        let checked = far.confirmed(at: Self.received.addingTimeInterval(600))
        #expect(ConditionsSchedule.nextFetch(after: checked, now: Self.received.addingTimeInterval(600))
            == Self.received.addingTimeInterval(2400))
    }

    @Test("nothing yet, or the direct fallback with a Worker configured, retries after 2 min")
    func retry() throws {
        let now = Self.received
        #expect(ConditionsSchedule.nextFetch(after: nil, now: now) == now.addingTimeInterval(120))
        let request = try ConditionsRequest.make(
            latitude: 38.35, longitude: -109.95, window: DateInterval(start: now, duration: 3600 * 10), now: now).get()
        let direct = OpenMeteoDirect.response(request: request, fetches: [], fetchedUTC: now)
        let s = ConditionsSnapshot(response: direct, fetchedUTC: now)
        #expect(ConditionsSchedule.nextFetch(after: s, now: now) == now.addingTimeInterval(120))
        // With no Worker configured the direct copy is the normal mode: the 30-min cap.
        let normal = OpenMeteoDirect.response(request: request, fetches: [], fetchedUTC: now, workerConfigured: false)
        let n = ConditionsSnapshot(response: normal, fetchedUTC: now)
        #expect(n.response.isDirectFallback)
        #expect(ConditionsSchedule.nextFetch(after: n, now: now, workerConfigured: false) == now.addingTimeInterval(1800))
    }

    @Test("with no Worker set up, the direct fetch says so calmly")
    func notSetUpWording() throws {
        let now = Self.received
        let request = try ConditionsRequest.make(
            latitude: 38.35, longitude: -109.95, window: DateInterval(start: now, duration: 3600), now: now).get()
        let normal = OpenMeteoDirect.response(request: request, fetches: [], fetchedUTC: now, workerConfigured: false)
        #expect(normal.fields["cloud_cover_total"]?.source == "Open-Meteo (direct)")
        #expect(normal.fields["wind_gust"]?.reason == OpenMeteoDirect.notSetUpReason)
        let reason = normal.fields["wind_gust"]?.reason ?? ""
        #expect(reason.range(of: "unreachable") == nil)
    }

    @Test("the 15-minute HRRR series reach the snapshot, for charts")
    func nearTerm() throws {
        let s = ConditionsSnapshot(response: try Self.golden(), fetchedUTC: Self.received)
        #expect(Set(s.nearTermSeries.keys) == Set(ConditionsSnapshot.nearTermFields))
        let gust = try #require(s.nearTerm("wind_gust"))
        #expect(gust.resolutionMinutes == 15)
        #expect(gust.values.count == 57)
        #expect(s.nearTerm("cloud_cover_total") == nil)
        let points = s.finestPoints("wind_gust")
        #expect(points.count == 57)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.t < $1.t })
    }

    @Test("finest points hand over from 15-minute to hourly where the 15-minute series ends")
    func handover() throws {
        var response = try Self.golden()
        var field = try #require(response.fields["temperature"])
        let fine = try #require(field.series15Min?.first)
        let cut = fine.values.prefix(9) // 00:00–02:00Z
        field.series15Min = [WorkerSeries(
            model: fine.model, upstreamModel: fine.upstreamModel, modelRunUTC: fine.modelRunUTC,
            fetchedUTC: fine.fetchedUTC, status: .ok, reason: nil, lastGoodUTC: nil, values: Array(cut),
            resolutionMinutes: 15)]
        response = ConditionsResponse(
            cell: response.cell, window: response.window, generatedUTC: response.generatedUTC,
            fields: response.fields.merging(["temperature": field]) { $1 }, attribution: response.attribution)
        let points = ConditionsSnapshot(response: response, fetchedUTC: Self.received).finestPoints("temperature")
        let hourly = try #require(response.fields["temperature"]?.series.first { $0.model == "hrrr" })
        #expect(points.count == 9 + hourly.values.filter { $0.t > cut.last!.t }.count)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.t < $1.t })
    }

    @Test("HTTP Date header", arguments: [
        ("Sat, 26 Sep 2026 21:33:13 GMT", "2026-09-26T21:33:13Z"),
        ("Mon, 05 Oct 2026 07:04:00 GMT", "2026-10-05T07:04:00Z"),
    ])
    func httpDate(_ header: String, _ iso: String) {
        #expect(HTTPDate.parse(header) == WorkerJSON.parse(iso))
    }

    @Test func badHTTPDate() {
        #expect(HTTPDate.parse("yesterday") == nil)
        #expect(HTTPDate.parse(nil) == nil)
    }

    @Test("a 304 does not make the snapshot 'too old' for the meta.json policy")
    func policyUsesConfirmation() throws {
        let s = ConditionsSnapshot(response: try Self.golden(), fetchedUTC: Self.received)
        let later = Self.received.addingTimeInterval(RefreshPolicy.maxAge + 60)
        #expect(RefreshPolicy.reason(snapshot: s, latest: [:], now: later) == .tooOld)
        #expect(RefreshPolicy.reason(snapshot: s.confirmed(at: later.addingTimeInterval(-60)), latest: [:], now: later) == nil)
    }

    @Test("a copy confirmed by a 304 ranks as current as its check, and is not expired")
    func newestByConfirmation() throws {
        let r = try Self.golden()
        let a = ConditionsSnapshot(response: r, fetchedUTC: Self.received).confirmed(at: Self.received.addingTimeInterval(7200))
        let b = ConditionsSnapshot(response: r, fetchedUTC: Self.received.addingTimeInterval(3600))
        #expect(ConditionsSnapshot.newest([a, b]) == a)
        let nineDays = Self.received.addingTimeInterval(9 * 86_400)
        #expect(ConditionsSnapshot.expired([a], now: nineDays).isEmpty == false)
        #expect(ConditionsSnapshot.expired([a.confirmed(at: nineDays.addingTimeInterval(-86_400))], now: nineDays).isEmpty)
    }
}
