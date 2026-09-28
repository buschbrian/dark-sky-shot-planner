import Foundation
import Testing
@testable import DarkSky
import SkyCore

/// Review P2 (1): an HMS analysis with no polygons over the area is an
/// answer ("No smoke polygons…"); "unavailable" is kept for a failed fetch.
/// Runs `MapData.refreshSmoke` against stubbed NESDIS answers.
@MainActor
@Suite(.serialized)
struct MapSmokeStatusTests {
    /// Answers the two HMS requests; everything else fails.
    final class HMSStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var polygons: (Int, Data) = (500, Data())
        nonisolated(unsafe) static var stats: (Int, Data) = (500, Data())

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let q = request.url?.query() ?? ""
            let (status, body) = q.contains("outStatistics") ? Self.stats : q.contains("geometry=") ? Self.polygons : (404, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static let empty = Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
    static let emptyStats = Data(#"{"features":[{"attributes":{"latest_end":null,"earliest_start":null}}]}"#.utf8)
    static let twoPolygons = Data(#"""
    {"type":"FeatureCollection","features":[
     {"type":"Feature","properties":{"Density":"Light","Satellite":"GOES-WEST","Start":"2026270 1500","End_":"2026270 2100"},
      "geometry":{"type":"Polygon","coordinates":[[[-110,38],[-109,38],[-109,39],[-110,38]]]}},
     {"type":"Feature","properties":{"Density":"Medium","Satellite":"GOES-WEST","Start":"2026270 1500","End_":"2026270 2100"},
      "geometry":{"type":"Polygon","coordinates":[[[-111,38],[-110,38],[-110,39],[-111,38]]]}}]}
    """#.utf8)
    static let stats = Data(#"{"features":[{"attributes":{"latest_end":"2026270 2100","earliest_start":"2026270 1500"}}]}"#.utf8)

    func mapData() -> MapData {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HMSStub.self]
        let dir = FileManager.default.temporaryDirectory.appending(path: "MapSmoke-\(UUID().uuidString)")
        return MapData(cacheDir: dir, session: URLSession(configuration: config))
    }

    @Test("Zero polygons: 'No smoke polygons in the current HMS analysis (checked N min ago)', never unavailable")
    func zeroPolygons() async {
        HMSStub.polygons = (200, Self.empty)
        HMSStub.stats = (200, Self.emptyStats)
        let data = mapData()
        await data.refreshSmoke()
        guard case .none(let checked) = data.smokeStatus() else {
            Issue.record("expected .none, got \(data.smokeStatus())")
            return
        }
        #expect(data.smokeSummary(now: checked.addingTimeInterval(3 * 60))
            == "No smoke polygons in the current HMS analysis (checked 3 min ago)")
        #expect(!data.smokeSummary().contains(Voice.unavailable))
        #expect(data.provenance(.smoke, now: checked.addingTimeInterval(180)).freshness != .unavailable)
    }

    @Test("A failed fetch with no earlier copy reads unavailable")
    func failedFetch() async {
        HMSStub.polygons = (500, Data())
        HMSStub.stats = (500, Data())
        let data = mapData()
        await data.refreshSmoke()
        #expect(data.smokeStatus() == .unavailable)
        #expect(data.smokeSummary() == "Smoke unavailable: the HMS request failed.")
        #expect(data.provenance(.smoke).freshness == .unavailable)
    }

    @Test("Polygons are counted; a later failure keeps them as the last good copy")
    func polygonsThenFailure() async {
        HMSStub.polygons = (200, Self.twoPolygons)
        HMSStub.stats = (200, Self.stats)
        let data = mapData()
        await data.refreshSmoke()
        guard case .polygons(2, let end, _) = data.smokeStatus() else {
            Issue.record("expected 2 polygons, got \(data.smokeStatus())")
            return
        }
        #expect(end != nil)
        HMSStub.polygons = (500, Data())
        await data.refreshSmoke()
        guard case .lastGood(2, _) = data.smokeStatus() else {
            Issue.record("expected last good copy, got \(data.smokeStatus())")
            return
        }
        #expect(data.smokeSummary().contains(Voice.lastGood))
    }
}
