import Foundation
import Testing
@testable import DarkSky
import SkyCore

/// Product review §4 / review B-9: every place change goes through
/// `AppState.choose`, which remembers the place for the next launch.
@MainActor
struct PlaceChoiceTests {
    let defaults: UserDefaults
    let camp = Place(name: "Candlestick Camp", latitude: 38.374, longitude: -109.9654, timeZoneID: "America/Denver")
    let pin = Place(name: "Dropped pin", latitude: 38.4529, longitude: -109.9785, timeZoneID: "America/Denver")

    init() {
        defaults = UserDefaults(suiteName: "PlaceChoiceTests.\(UUID().uuidString)")!
    }

    @Test("A choice is remembered and a new launch (a fresh AppState) opens on it")
    func chooseSurvivesRelaunch() {
        let state = AppState()
        state.choose(LocationChoice(place: pin, zoneIsDeviceGuess: false, night: nil), defaults: defaults, arguments: [])
        #expect(state.place == pin)
        #expect(RememberedPlace.load(defaults, arguments: [])?.place == pin)

        let relaunched = AppState()
        relaunched.restoreRememberedPlace(defaults: defaults, arguments: [])
        #expect(relaunched.place == pin)
    }

    @Test("Undo puts back the place, the chosen night and the remembered place")
    func undoRestoresEverything() {
        let state = AppState()
        state.choose(LocationChoice(place: camp, zoneIsDeviceGuess: false, night: nil), defaults: defaults, arguments: [])
        let before = state.placeSnapshot(defaults: defaults)
        state.choose(LocationChoice(place: pin, zoneIsDeviceGuess: true, night: nil), defaults: defaults, arguments: [])
        #expect(RememberedPlace.load(defaults, arguments: [])?.place == pin)
        state.restore(before, defaults: defaults, arguments: [])
        #expect(state.place == camp)
        #expect(RememberedPlace.load(defaults, arguments: []) == RememberedPlace(place: camp, zoneIsDeviceGuess: false))
    }

    @Test("Undo to no place clears the remembered one")
    func undoToNothing() {
        let state = AppState()
        let before = state.placeSnapshot(defaults: defaults)
        state.choose(LocationChoice(place: pin, zoneIsDeviceGuess: false, night: nil), defaults: defaults, arguments: [])
        state.restore(before, defaults: defaults, arguments: [])
        #expect(state.place == nil)
        #expect(RememberedPlace.load(defaults, arguments: []) == nil)
    }

    @Test("Plain UI tests never persist; the relaunch test uses its own key")
    func uiTestKeys() {
        let state = AppState()
        let choice = LocationChoice(place: pin, zoneIsDeviceGuess: false, night: nil)
        state.choose(choice, defaults: defaults, arguments: ["-DarkSkyUITest"])
        #expect(defaults.data(forKey: RememberedPlace.key) == nil)
        state.choose(choice, defaults: defaults, arguments: ["-DarkSkyUITest", "-DarkSkyUITestPersist"])
        #expect(defaults.data(forKey: RememberedPlace.key) == nil)
        #expect(RememberedPlace.load(defaults, arguments: ["-DarkSkyUITestPersist"])?.place == pin)
    }
}
