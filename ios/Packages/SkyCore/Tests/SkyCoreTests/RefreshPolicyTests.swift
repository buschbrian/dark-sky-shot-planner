import Foundation
import Testing
@testable import SkyCore

@Suite struct RefreshPolicyTests {
    static func meta(_ id: String) throws -> Data {
        let obj = try JSONSerialization.jsonObject(with: Repo.data("worker/test/fixtures/recorded/open-meteo-meta-\(id).json")) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: obj["body"]!)
    }

    static func recordedMeta() throws -> [String: ModelRunInfo] {
        var out: [String: ModelRunInfo] = [:]
        for id in ["ncep_hrrr_conus", "ncep_gfs013", "dwd_icon", "ecmwf_ifs025", "cams_global"] {
            let info = try #require(ModelRunInfo.parse(try meta(id)))
            out[id] = info
        }
        return out
    }

    static func goldenSnapshot(fetched: String = "2026-09-25T23:39:36Z") throws -> ConditionsSnapshot {
        ConditionsSnapshot(
            response: try ConditionsResponse.decode(Repo.data("shared/golden/conditions-response.json")),
            fetchedUTC: try ISO.date(fetched))
    }

    @Test func parsesRecordedMeta() throws {
        let hrrr = try #require(ModelRunInfo.parse(try Self.meta("ncep_hrrr_conus")))
        #expect(hrrr.run == Date(timeIntervalSince1970: 1_790_373_600))
        #expect(hrrr.available == Date(timeIntervalSince1970: 1_790_379_321))
        #expect(hrrr.updateInterval == 3600)
        #expect(ModelRunInfo.parse(Data("{\"error\":true,\"reason\":\"x\"}".utf8)) == nil)
        #expect(ModelRunInfo.parse(nil) == nil)
    }

    @Test func metaIDsCoverEveryOpenMeteoModelInTheGoldenResponse() throws {
        let runs = RefreshPolicy.runs(in: try Self.goldenSnapshot().response)
        for model in ["hrrr", "gfs", "icon", "ecmwf", "cams_global"] {
            #expect(runs[model] != nil, "\(model)")
            #expect(RefreshPolicy.metaIDs[model] != nil, "\(model)")
        }
    }

    @Test func sameRunsAndYoungSnapshotNeedNothing() throws {
        let snap = try Self.goldenSnapshot()
        let now = try ISO.date("2026-09-26T00:10:00Z")
        #expect(RefreshPolicy.reason(snapshot: snap, latest: try Self.recordedMeta(), now: now) == nil)
    }

    @Test func aNewerHRRRRunTriggersARefresh() throws {
        var latest = try Self.recordedMeta()
        let old = latest["ncep_hrrr_conus"]!
        latest["ncep_hrrr_conus"] = ModelRunInfo(run: old.run.addingTimeInterval(3600), available: nil, updateInterval: 3600)
        let now = try ISO.date("2026-09-26T00:10:00Z")
        #expect(RefreshPolicy.reason(snapshot: try Self.goldenSnapshot(), latest: latest, now: now) == .newerRun(model: "hrrr"))
    }

    @Test func otherReasons() throws {
        let now = try ISO.date("2026-09-26T00:40:00Z")
        #expect(RefreshPolicy.reason(snapshot: nil, latest: [:], now: now) == .noSnapshot)
        #expect(RefreshPolicy.reason(snapshot: try Self.goldenSnapshot(), latest: [:], now: now) == .tooOld)
        let direct = OpenMeteoDirect.response(
            request: try OpenMeteoDirectTests.request(), fetches: try OpenMeteoDirectTests.recordedFetches(),
            fetchedUTC: OpenMeteoDirectTests.fetched)
        let snap = ConditionsSnapshot(response: direct, fetchedUTC: now)
        #expect(RefreshPolicy.reason(snapshot: snap, latest: [:], now: now) == .fallback)
        #expect(RefreshPolicy.reason(snapshot: snap, latest: [:], now: now, workerConfigured: false) == nil)
    }

    @Test func nextCheckFollowsTheSoonestExpectedRun() throws {
        let latest = try Self.recordedMeta()
        let hrrr = latest["ncep_hrrr_conus"]!
        // Five minutes before the next hourly HRRR run is due: check just after it lands.
        let now = hrrr.available!.addingTimeInterval(3300)
        #expect(RefreshPolicy.nextCheck(latest: latest, now: now) == hrrr.available!.addingTimeInterval(3600 + 120))
        // Just after a run: the next is ~1 h away, so wait the 30 min cap.
        let early = hrrr.available!.addingTimeInterval(60)
        #expect(RefreshPolicy.nextCheck(latest: latest, now: early) == early.addingTimeInterval(RefreshPolicy.maxCheckInterval))
        // Overdue runs are checked again soon, never in a tight loop.
        let late = RefreshPolicy.nextCheck(latest: latest, now: now.addingTimeInterval(86_400))
        #expect(late.timeIntervalSince(now.addingTimeInterval(86_400)) == RefreshPolicy.maxCheckInterval)
        #expect(RefreshPolicy.nextCheck(latest: [:], now: now) == now.addingTimeInterval(RefreshPolicy.maxCheckInterval))
        let soon = ModelRunInfo(run: now, available: now.addingTimeInterval(-3600 - 60), updateInterval: 3600)
        #expect(RefreshPolicy.nextCheck(latest: ["x": soon], now: now) == now.addingTimeInterval(RefreshPolicy.minCheckInterval))
    }
}
