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

    /// "Tonight" here (review B-2): last night only while it is still dark,
    /// then the coming night. Cached until the answer changes at dawn.
    func tonight(at now: Date = .now) -> NightDate {
        TonightClock.shared.night(for: self, at: now)
    }
}

/// Remembers each place's current night and when it stops being current, so
/// screens can ask on every render without redoing the twilight search.
nonisolated final class TonightClock: @unchecked Sendable {
    static let shared = TonightClock()
    private let lock = NSLock()
    private var spans: [Place: CurrentNight] = [:]

    func night(for place: Place, at now: Date) -> NightDate {
        if let hit = lock.withLock({ spans[place] }), hit.contains(now) { return hit.night }
        guard let observer = try? place.observer() else {
            return NightDate.containing(now, in: place.timeZone)
        }
        let span = NightDate.currentSpan(at: now, observer: observer, timeZone: place.timeZone)
        lock.withLock {
            if spans.count > 32 { spans.removeAll() }
            spans[place] = span
        }
        return span.night
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
        chosenNight ?? tonight(at: now)
    }

    /// The current night whatever night is chosen (`Place.tonight`).
    func tonight(at now: Date = .now) -> NightDate {
        place?.tonight(at: now) ?? NightDate.containing(now, in: .current)
    }
}
