import Foundation
import Observation
import SkyCore

/// One shared, memoised copy of the ±30-day sky-events agenda per place and
/// centre night (ADR-0008 consequences: the sweep is deferred and memoised).
/// Tonight's section, every Week-row badge and the full list read the same
/// entry, so the ephemeris runs once per place, off the main thread.
@Observable
final class SkyEventsStore {
    static let shared = SkyEventsStore()

    enum Entry {
        case loading
        case loaded(SkyEventsResult)
        case failed(String)
    }

    struct Key: Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let timeZoneID: String
        let centre: NightDate
    }

    private(set) var entries: [Key: Entry] = [:]
    @ObservationIgnored private var order: [Key] = []
    private let capacity = 6

    /// Nights within this many days of tonight share tonight's agenda, so a
    /// Week list and Tonight's section never compute two overlapping sweeps.
    static let shareDays = 21

    static func key(place: Place, night: NightDate, now: Date = .now) -> Key {
        let tonight = NightDate.containing(now, in: place.timeZone)
        let centre = abs(days(from: tonight, to: night)) <= shareDays ? tonight : night
        return Key(latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID, centre: centre)
    }

    func entry(place: Place, night: NightDate) -> Entry? {
        entries[Self.key(place: place, night: night)]
    }

    /// Computes the agenda once per key; later calls return immediately.
    func load(place: Place, night: NightDate) async {
        let key = Self.key(place: place, night: night)
        if entries[key] != nil { return }
        entries[key] = .loading
        remember(key)
        let tz = place.timeZone
        let latitude = place.latitude, longitude = place.longitude
        let entry: Entry = await Task.detached(priority: .utility) {
            do {
                let site = try Observer(latitude: latitude, longitude: longitude)
                let threshold = (try? AppConfig.bundled())?.gcMinUsefulAltitudeDeg
                let result = try SkyEventsAgenda.build(
                    site, centre: key.centre.evening(in: tz), formatters: .local(tz), gcMinAltitudeDeg: threshold)
                return .loaded(result)
            } catch {
                return .failed("Sky events unavailable: \(error)")
            }
        }.value
        entries[key] = entry
    }

    private func remember(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }

    static func days(from a: NightDate, to b: NightDate) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let da = cal.date(from: DateComponents(year: a.year, month: a.month, day: a.day))!
        let db = cal.date(from: DateComponents(year: b.year, month: b.month, day: b.day))!
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }
}
