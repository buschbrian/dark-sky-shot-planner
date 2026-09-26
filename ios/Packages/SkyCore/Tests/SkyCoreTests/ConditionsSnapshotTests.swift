import Foundation
import Testing
@testable import SkyCore

@Suite("ConditionsSnapshot")
struct ConditionsSnapshotTests {
    static let golden = { try! Repo.data("shared/golden/conditions-response.json") }()
    static let received = WorkerJSON.parse("2026-09-26T00:00:00Z")!

    @Test("age and freshness come from the device fetch time and the config window")
    func ageAndFreshness() throws {
        let fetched = Self.received
        let snap = try ConditionsSnapshot(workerJSON: Self.golden, fetchedUTC: fetched)
        let w = try FreshnessConfig.bundled().conditionsWindow()
        let unit = w.unit.seconds
        #expect(snap.age(at: fetched.addingTimeInterval(5400)) == 5400)
        #expect(snap.freshness(at: fetched, window: w) == .fresh)
        #expect(snap.freshness(at: fetched.addingTimeInterval((w.freshMax + 1) * unit - 1), window: w) == .fresh)
        #expect(snap.freshness(at: fetched.addingTimeInterval((w.agingMax + 1) * unit), window: w) == .stale)
    }

    @Test("oldest data time is the oldest available series' as-of time")
    func oldestData() throws {
        let snap = try ConditionsSnapshot(workerJSON: Self.golden, fetchedUTC: Self.received)
        // RAP-Smoke's 03Z issue is the oldest ingredient in the recorded response.
        #expect(snap.oldestDataUTC == WorkerJSON.parse("2026-09-25T03:00:00Z"))
    }

    @Test("round-trips through its own encoding")
    func roundTrip() throws {
        let snap = try ConditionsSnapshot(workerJSON: Self.golden, fetchedUTC: Self.received)
        #expect(try ConditionsSnapshot.decode(snap.encoded()) == snap)
    }

    @Test("newest picks the latest device fetch")
    func newest() throws {
        let r = try ConditionsResponse.decode(Self.golden)
        let a = ConditionsSnapshot(response: r, fetchedUTC: Self.received)
        let b = ConditionsSnapshot(response: r, fetchedUTC: Self.received.addingTimeInterval(3 * 3600))
        let c = ConditionsSnapshot(response: r, fetchedUTC: Self.received.addingTimeInterval(3600))
        #expect(ConditionsSnapshot.newest([a, b, c]) == b)
        #expect(ConditionsSnapshot.newest([]) == nil)
    }
}
