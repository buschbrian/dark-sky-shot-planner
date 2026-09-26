import Foundation
import Testing
@testable import SkyCore

@Suite("Map feeds: GIBS time domains, HMS times (M6)")
struct MapFeedsTests {
    /// Recorded from GIBS on 2026-09-26 (REST DescribeDomains, GOES-West band 13).
    static let describeDomains = """
        <Domains xmlns:ows='http://www.opengis.net/ows/1.1'><SpaceDomain><BoundingBox crs='urn:ogc:def:crs:EPSG::3857' \
        maxx='20037508.342789' miny='-20037508.342789' minx='-20037508.342789' maxy='20037508.342789'/></SpaceDomain>\
        <DimensionDomain><ows:Identifier>time</ows:Identifier><Domain>2026-09-25/2026-09-25T17:00:00Z/PT10M,\
        2026-09-25T17:30:00Z/2026-09-25T19:10:00Z/PT10M,2026-09-25T19:30:00Z/2026-09-26T19:00:00Z/PT10M</Domain>\
        <Size>3</Size></DimensionDomain></Domains>
        """

    @Test("DescribeDomains runs expand to valid times, keeping the gaps")
    func domainTimes() throws {
        let times = GIBSTimeDomain.times(fromDescribeDomains: Self.describeDomains)
        #expect(times.first == (try ISO.date("2026-09-25T00:00:00Z")))
        #expect(times.last == (try ISO.date("2026-09-26T19:00:00Z")))
        // 103 + 11 + 142 ten-minute steps.
        #expect(times.count == 103 + 11 + 142)
        #expect(!times.contains(try ISO.date("2026-09-25T17:10:00Z")))
        #expect(!times.contains(try ISO.date("2026-09-25T19:20:00Z")))
        #expect(times.contains(try ISO.date("2026-09-25T19:10:00Z")))
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("single instants, durations, and junk")
    func parsing() throws {
        #expect(GIBSTimeDomain.times(fromDomain: "2026-09-26T01:00:00Z, 2026-09-26T00:50:00Z") == [
            try ISO.date("2026-09-26T00:50:00Z"), try ISO.date("2026-09-26T01:00:00Z"),
        ])
        #expect(GIBSTimeDomain.duration("PT10M") == 600)
        #expect(GIBSTimeDomain.duration("P1DT1H") == 90_000)
        #expect(GIBSTimeDomain.duration("10M") == nil)
        #expect(GIBSTimeDomain.times(fromDomain: "nonsense,2026-13-40/x/PT10M").isEmpty)
        #expect(GIBSTimeDomain.times(fromDescribeDomains: "<Domains/>").isEmpty)
    }

    @Test("loop frames end at the newest valid time and skip across gaps")
    func loopFrames() throws {
        let times = GIBSTimeDomain.times(fromDescribeDomains: Self.describeDomains)
        let frames = GIBSTimeDomain.loopFrames(times, count: 6, minSpacing: 1200)
        #expect(frames.count == 6)
        #expect(frames.last == (try ISO.date("2026-09-26T19:00:00Z")))
        #expect(frames.first == (try ISO.date("2026-09-26T17:20:00Z")))
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 1200 })
        #expect(GIBSTimeDomain.loopFrames([], count: 6, minSpacing: 600).isEmpty)
    }

    @Test("GIBS URLs carry the layer, time and tile matrix set")
    func urls() throws {
        let t = try ISO.date("2026-09-26T19:00:00Z")
        #expect(GIBSTimeDomain.tileURLTemplate(time: t)
            == "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/GOES-West_ABI_Band13_Clean_Infrared/default/2026-09-26T19:00:00Z/GoogleMapsCompatible_Level6/{z}/{y}/{x}.png")
        #expect(GIBSTimeDomain.describeDomainsURL(from: t.addingTimeInterval(-3600), to: t).absoluteString
            == "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/GOES-West_ABI_Band13_Clean_Infrared/default/GoogleMapsCompatible_Level6/all/2026-09-26T18:00:00Z--2026-09-26T19:00:00Z.xml")
    }

    @Test("HMS day-of-year times, as the Worker parses them")
    func hmsTimes() throws {
        #expect(HMSSmoke.time("2026269 1700") == (try ISO.date("2026-09-26T17:00:00Z")))
        #expect(HMSSmoke.time("2024366 2359") == (try ISO.date("2024-12-31T23:59:00Z")))
        #expect(HMSSmoke.time("2026269 2500") == nil)
        #expect(HMSSmoke.time("26-09-26") == nil)
        // Recorded statistics response, 2026-09-26.
        let stats = Data(#"{"features":[{"attributes":{"latest_end":"2026269 1700","earliest_start":"2026269 1200"}}]}"#.utf8)
        let w = HMSSmoke.analysisWindow(fromStats: stats)
        #expect(w.start == (try ISO.date("2026-09-26T12:00:00Z")))
        #expect(w.end == (try ISO.date("2026-09-26T17:00:00Z")))
        #expect(HMSSmoke.analysisWindow(fromStats: Data("{}".utf8)).end == nil)
        #expect(HMSSmoke.queryURL(west: -120, south: 31.3, east: -102, north: 49.1).absoluteString.contains("geometry=-120.0,31.3,-102.0,49.1"))
    }
}
