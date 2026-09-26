import Foundation
import Observation
import SkyCore

/// A place the owner is planning for. Precise coordinates stay on the device;
/// anything sent to the Worker is rounded to 0.05° first (ADR-0010).
nonisolated struct Place: Hashable, Codable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    func observer() throws -> Observer {
        try Observer(latitude: latitude, longitude: longitude)
    }
}

/// State every screen shares: where, which night, and field mode. Screens read
/// and write it; none of them own it.
@Observable
final class AppState {
    var place: Place?
    /// nil means "tonight" in the place's zone, recomputed as time passes.
    var chosenNight: NightDate?
    /// Which half of the Tonight tab shows; Week rows switch it to Tonight.
    var nightScope = NightTab.Scope.tonight
    /// `-FieldMode YES` at launch starts in field mode (UI tests, screenshots).
    var fieldMode = UserDefaults.standard.bool(forKey: "FieldMode")

    func night(at now: Date = .now) -> NightDate {
        if let chosenNight { return chosenNight }
        return NightDate.containing(now, in: place?.timeZone ?? .current)
    }
}
