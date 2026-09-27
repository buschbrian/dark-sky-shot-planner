import Foundation
import SkyCore

/// The one operation that changes where the app plans for. The location
/// sheet, the map (typed coordinates, a confirmed pin, "pin me here", a saved
/// spot) and the Spots and Week screens all go through `AppState.choose`, so
/// the remembered place always matches what is on screen and a relaunch opens
/// on it (review B-9; product review 2026-09-27 §4).
extension AppState {
    func choose(_ choice: LocationChoice, defaults: UserDefaults = .standard,
                arguments: [String] = ProcessInfo.processInfo.arguments) {
        place = choice.place
        if let night = choice.night {
            chosenNight = night == NightDate.containing(.now, in: choice.place.timeZone) ? nil : night
        }
        RememberedPlace(place: choice.place, zoneIsDeviceGuess: choice.zoneIsDeviceGuess).save(defaults, arguments: arguments)
    }

    /// A saved spot: its own zone, never a guess.
    func choose(spot: Spot) {
        choose(LocationChoice(place: spot.place, zoneIsDeviceGuess: false, night: nil))
    }

    /// What `restore(_:)` puts back (the map's Undo).
    struct PlaceSnapshot {
        let place: Place?
        let chosenNight: NightDate?
        let remembered: RememberedPlace?
    }

    func placeSnapshot(defaults: UserDefaults = .standard) -> PlaceSnapshot {
        PlaceSnapshot(place: place, chosenNight: chosenNight, remembered: RememberedPlace.load(defaults))
    }

    func restore(_ s: PlaceSnapshot, defaults: UserDefaults = .standard,
                 arguments: [String] = ProcessInfo.processInfo.arguments) {
        place = s.place
        chosenNight = s.chosenNight
        if let r = s.remembered {
            r.save(defaults, arguments: arguments)
        } else if RememberedPlace.persists(arguments) {
            defaults.removeObject(forKey: RememberedPlace.key(arguments))
        }
    }

    /// A launch opens where the owner left off. Plain UI tests always start
    /// empty; `-DarkSkyUITestPersist` tests use their own key, which
    /// `-resetRememberedPlace` clears once per launch.
    func restoreRememberedPlace(defaults: UserDefaults = .standard,
                                arguments: [String] = ProcessInfo.processInfo.arguments) {
        let key = RememberedPlace.key(arguments)
        if !RememberedPlace.persists(arguments) {
            defaults.removeObject(forKey: key)
            return
        }
        if arguments.contains("-resetRememberedPlace"), !PlaceChoice.didReset {
            PlaceChoice.didReset = true
            defaults.removeObject(forKey: key)
            return
        }
        if place == nil, let r = RememberedPlace.load(defaults, arguments: arguments) { place = r.place }
    }
}

enum PlaceChoice {
    nonisolated(unsafe) static var didReset = false

    /// A choice for coordinates. The zone comes from Apple's reverse geocoder
    /// for the 0.05° cell (`TimeZoneLookup`); offline, or in UI tests, it is
    /// the phone's zone and marked as a guess.
    static func coordinates(latitude: Double, longitude: Double, name: String, night: NightDate? = nil,
                            arguments: [String] = ProcessInfo.processInfo.arguments) async -> LocationChoice {
        let lookup = !arguments.contains("-DarkSkyUITest")
        let zone = lookup ? await TimeZoneLookup.zone(latitude: latitude, longitude: longitude) : nil
        let tz = zone ?? .current
        return LocationChoice(
            place: Place(name: name, latitude: latitude, longitude: longitude, timeZoneID: tz.identifier),
            zoneIsDeviceGuess: zone == nil, night: night)
    }
}
