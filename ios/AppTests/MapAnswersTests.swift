import Foundation
import Testing
@testable import DarkSky
import SkyCore

/// Product review §3: sample data can't inform an answer. The land-manager
/// text is the only answer the app reads from a Pages layer (nothing outside
/// `ios/App/Map` reads light pollution or PAD-US), and it is given only when
/// `data-status.json` says the layer is real.
@MainActor
struct MapAnswersTests {
    let key = ManagerTaxonomy.bundled.entries.first?.key ?? "BLM"

    @Test("Fixture or unconfirmed PAD-US gives no land-manager answer, at the pin or on tap", arguments: [PagesOrigin.fixture, .unknown])
    func samplesNeverAnswer(_ origin: PagesOrigin) {
        #expect(MapAnswers.landManager(origin: origin, keysAtPin: [key]) == nil)
        #expect(MapAnswers.landManager(origin: origin, keysAtPin: []) == nil)
        #expect(MapAnswers.tappedLand(origin: origin, key: key) == nil)
    }

    @Test("Real PAD-US answers, and never says camping is allowed")
    func realAnswers() throws {
        let text = try #require(MapAnswers.landManager(origin: .real, keysAtPin: [key]))
        #expect(text.hasPrefix("Managed by"))
        #expect(text.contains("Check the manager's rules"))
        #expect(MapAnswers.landManager(origin: .real, keysAtPin: [])?.contains("no PAD-US boundary") == true)
    }

    @Test("The live data-status (fixture layers) reads as fixture, so the answer is withheld")
    func publishedStatus() {
        let status = PagesDataStatus(data: Data(#"{"built_utc":"2026-09-26T17:51Z","layers":{"light_pollution":"fixture","land_ownership":"fixture","darksky_places":"real"}}"#.utf8))
        #expect(status.origin("land_ownership") == .fixture)
        #expect(MapAnswers.landManager(origin: status.origin("land_ownership"), keysAtPin: [key]) == nil)
    }
}
