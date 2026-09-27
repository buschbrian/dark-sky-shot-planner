import Foundation
import Testing
@testable import SkyCore

/// SwiftPM cannot bundle files from outside the package, so `config/` files
/// are copied in by `ios/scripts/sync-shared.sh`. These tests are the drift
/// alarm: if a copy differs from the repo-root original, run the script.
@Suite("Bundled shared config")
struct SharedFilesTests {
    @Test("bundled app-config.json is byte-identical to config/app-config.json")
    func appConfigIsInSync() throws {
        let url = try #require(AppConfig.bundledURL)
        let bundled = try Data(contentsOf: url)
        let original = try Repo.data("config/app-config.json")
        #expect(bundled == original, "Run ios/scripts/sync-shared.sh")
    }

    @Test(
        "every other bundled config file is byte-identical to its original",
        arguments: ["conditions-thresholds.json", "sky-events.json", "gear-presets.json", "horizon-profiles/candlestick-camp.csv"]
    )
    func bundledCopyIsInSync(_ path: String) throws {
        #expect(try SharedResources.data(path) == Repo.data("config/\(path)"), "Run ios/scripts/sync-shared.sh")
    }

    @Test("the AOI comes from config, not Swift")
    func aoiFromConfig() throws {
        struct Root: Decodable {
            struct A: Decodable { let bbox: [String: Double] }
            let aoi: A
        }
        let raw = try JSONDecoder().decode(Root.self, from: Repo.data("config/app-config.json")).aoi.bbox
        let b = try AppConfig.bundled().aoi.bbox
        #expect([b.west, b.south, b.east, b.north] == [raw["west"], raw["south"], raw["east"], raw["north"]])
        #expect(b.west < b.east && b.south < b.north)
    }

    @Test("the GC threshold comes from config, not Swift")
    func gcThresholdFromConfig() throws {
        let original = try AppConfig.decode(Repo.data("config/app-config.json"))
        let bundled = try AppConfig.bundled()
        #expect(bundled == original)

        let at = GCVisibility(maxAltitudeDeg: bundled.gcMinUsefulAltitudeDeg, maxAltitudeAt: nil, risesDuringDarkness: true)
        let below = GCVisibility(maxAltitudeDeg: bundled.gcMinUsefulAltitudeDeg - 0.1, maxAltitudeAt: nil, risesDuringDarkness: true)
        let none = GCVisibility(maxAltitudeDeg: nil, maxAltitudeAt: nil, risesDuringDarkness: false)
        #expect(at.isUsable(bundled))
        #expect(!below.isUsable(bundled))
        #expect(!none.isUsable(bundled))
    }
}
