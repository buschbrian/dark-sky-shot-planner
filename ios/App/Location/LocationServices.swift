import CoreLocation
import Foundation
import MapKit
import SkyCore

/// One GPS fix, when-in-use only. Nothing here leaves the phone.
@Observable
final class LocationProvider {
    enum Status: Equatable {
        case idle, locating, denied, unavailable
    }

    private(set) var status = Status.idle

    func currentLocation(timeout: Duration = .seconds(30)) async -> CLLocation? {
        status = .locating
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let fix = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                            return nil
                        }
                        if let loc = update.location, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 1_000 {
                            return loc
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if fix == nil {
            let auth = CLLocationManager().authorizationStatus
            status = auth == .denied || auth == .restricted ? .denied : .unavailable
        } else {
            status = .idle
        }
        return fix
    }
}

/// The time zone at a coordinate. Apple's reverse geocoder is asked about the
/// 0.05° cell, never the precise point; offline it answers nothing and the
/// caller falls back to the device zone, with a note on screen.
enum TimeZoneLookup {
    static func zone(latitude: Double, longitude: Double, timeout: Duration = .seconds(8)) async -> TimeZone? {
        let cell = ConditionsCell(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: cell.latitude, longitude: cell.longitude)) else {
            return nil
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            request.cancel()
        }
        defer { timer.cancel() }
        return try? await request.mapItems.first?.timeZone
    }
}

/// The place Tonight last showed, so a relaunch at a dark site with no signal
/// opens where the owner left off. `zoneIsDeviceGuess` marks a zone that could
/// not be looked up (offline) and was taken from the phone instead.
struct RememberedPlace: Codable, Equatable {
    var place: Place
    var zoneIsDeviceGuess: Bool

    static let key = "tonight.place"
    /// `-DarkSkyUITestPersist`: a relaunch test's own key, never the owner's.
    static let testKey = "uitest.tonight.place"

    static func key(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> String {
        arguments.contains("-DarkSkyUITestPersist") ? testKey : key
    }

    /// UI tests never persist a place: a later launch (another test, or the
    /// owner's) must not open on a test's coordinates (review P2 #3). The
    /// relaunch test persists under `testKey` instead.
    static func persists(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-DarkSkyUITestPersist")
            || !(arguments.contains("-DarkSkyUITest") || arguments.contains("-DarkSkyUITestLive"))
    }

    static func load(_ defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) -> RememberedPlace? {
        defaults.data(forKey: key(arguments)).flatMap { try? JSONDecoder().decode(RememberedPlace.self, from: $0) }
    }

    func save(_ defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard Self.persists(arguments) else { return }
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(arguments)) }
    }
}
