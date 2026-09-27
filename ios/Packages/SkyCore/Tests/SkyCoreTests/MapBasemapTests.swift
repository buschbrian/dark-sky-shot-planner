import Foundation
import Testing
@testable import SkyCore

@Suite("Map basemaps and offline estimates")
struct MapBasemapTests {
    static let candlestick = (latitude: 38.3740, longitude: -109.9654)

    @Test("tile indices match the slippy-map formula at Candlestick Camp")
    func tileIndices() {
        // Checked against the USGS tiles fetched on 2026-09-26 (12/1574/796, 15/12596/6374).
        #expect(TileMath.tileX(longitude: Self.candlestick.longitude, zoom: 12) == 796)
        #expect(TileMath.tileY(latitude: Self.candlestick.latitude, zoom: 12) == 1574)
        #expect(TileMath.tileX(longitude: Self.candlestick.longitude, zoom: 15) == 6374)
        #expect(TileMath.tileY(latitude: Self.candlestick.latitude, zoom: 15) == 12596)
        #expect(TileMath.tileX(longitude: 180, zoom: 3) == 7)
        #expect(TileMath.tileY(latitude: 89.9, zoom: 3) == 0)
    }

    @Test("tile count covers the box, one tile when it is inside one")
    func counts() {
        let tiny = GeoBounds.around(latitude: 38.3740, longitude: -109.9654, radiusMeters: 10)
        #expect(TileMath.count(tiny, zoom: 5) == 1)
        let spot = GeoBounds.around(latitude: 38.3740, longitude: -109.9654, radiusMeters: OfflineArea.spotRadiusMeters)
        // 10 km across; a z15 tile is ~960 m wide here, so 11-12 tiles a side.
        let n = TileMath.count(spot, zoom: 15)
        #expect((100...160).contains(n), "z15 tiles \(n)")
        #expect(abs(spot.widthMeters - 10_000) < 50)
        #expect(abs(spot.heightMeters - 10_000) < 50)
    }

    @Test("a saved spot's pack stays small enough to keep several")
    func spotEstimate() {
        let spot = GeoBounds.around(latitude: 38.3740, longitude: -109.9654, radiusMeters: OfflineArea.spotRadiusMeters)
        let e = OfflineEstimate.make(
            bounds: spot, minZoom: OfflineArea.spotZooms.lowerBound, maxZoom: OfflineArea.spotZooms.upperBound,
            sources: OfflineArea.sources(includeImagery: false))
        #expect(e.rows.map(\.sourceID) == ["usgs-topo", "aws-terrain"])
        // Terrain stops at its own z12; overzoomed above that.
        let dem = e.rows[1]
        #expect(dem.tiles == (8...12).map { TileMath.count(spot, zoom: $0) }.reduce(0, +))
        #expect(e.bytes > 2_000_000 && e.bytes < 20_000_000, "\(e.bytes) bytes")
        let withImagery = OfflineEstimate.make(
            bounds: spot, minZoom: 8, maxZoom: 16, sources: OfflineArea.sources(includeImagery: true))
        #expect(withImagery.bytes > e.bytes)
    }

    @Test("view zooms keep context and end at the caches' deepest level")
    func viewZooms() {
        #expect(OfflineArea.viewZooms(currentZoom: 13.4) == 11...16)
        #expect(OfflineArea.viewZooms(currentZoom: 3) == 5...16)
        #expect(OfflineArea.viewZooms(currentZoom: 18) == 14...16)
    }

    @Test("byte table falls back to the nearest sampled zoom")
    func bytesFallback() {
        #expect(BasemapSource.usgsTopo.bytes(atZoom: 16) == 8_300)
        #expect(BasemapSource.usgsTopo.bytes(atZoom: 3) == 27_000)
        #expect(BasemapSource.awsTerrain.bytes(atZoom: 15) == 127_600)
    }

    @Test("every basemap names public-domain, keyless sources with credit")
    func sources() {
        for b in Basemap.allCases {
            #expect(!b.sources.isEmpty)
            for s in b.sources {
                #expect(s.license.contains("Public domain"))
                #expect(!s.attribution.isEmpty)
                #expect(s.tileTemplate.hasPrefix("https://"))
                #expect(!s.tileTemplate.contains("key") && !s.tileTemplate.contains("token"))
                #expect(s.tileTemplate.contains("{z}") && s.tileTemplate.contains("{x}") && s.tileTemplate.contains("{y}"))
            }
        }
        // ArcGIS caches are row-major: z/y/x.
        #expect(BasemapSource.usgsTopo.tileTemplate.hasSuffix("/tile/{z}/{y}/{x}"))
        #expect(Basemap.darkRelief.sources.contains(.usgsTopo))
        #expect(Basemap.defaultChoice(fieldMode: true) == .darkRelief)
        #expect(Basemap.defaultChoice(fieldMode: false) == .topo)
    }

    @Test("USGS 'Data refreshed' dates, as the services wrote them on 2026-09-26")
    func refreshed() {
        let topo = "USGS The National Map: National Boundaries Dataset, 3DEP Elevation Program; NOAA National Centers for Environmental Information. Data refreshed September 4, 2026-v1.2"
        #expect(USGSServiceInfo.refreshed(fromCopyright: topo) == "September 4, 2026")
        #expect(USGSServiceInfo.refreshed(fromCopyright: "USGS The National Map: Orthoimagery and US Topo. Data refreshed April, 2026.v1.2.") == "April, 2026")
        #expect(USGSServiceInfo.refreshed(fromCopyright: "No date here") == nil)
        let json = Data(#"{"copyrightText":"X. Data Refreshed July, 2026."}"#.utf8)
        #expect(USGSServiceInfo.refreshed(fromServiceJSON: json) == "July, 2026")
        #expect(USGSServiceInfo.refreshed(fromServiceJSON: Data("{}".utf8)) == nil)
    }
}
