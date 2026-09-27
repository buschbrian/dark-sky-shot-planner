import CoreLocation
import Foundation
import MapLibre
import Observation
import SkyCore

/// The map engine's shared state and commands: which basemap shows, where the
/// camera is, and the owner's location. Views outside the map (the panel, the
/// map's own buttons) talk to the map only through this object.
@Observable
final class MapController {
    enum Tracking: Equatable { case none, follow, followWithHeading }

    struct Camera: Equatable {
        var center: CLLocationCoordinate2D
        var zoom: Double
        var bounds: GeoBounds

        static func == (a: Camera, b: Camera) -> Bool {
            a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude && a.zoom == b.zoom && a.bounds == b.bounds
        }
    }

    struct UserFix: Equatable {
        var coordinate: CLLocationCoordinate2D
        var horizontalAccuracy: Double
        var heading: Double?
        /// The puck is drawn inside the map's bounds.
        var onScreen: Bool

        static func == (a: UserFix, b: UserFix) -> Bool {
            a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
                && a.horizontalAccuracy == b.horizontalAccuracy && a.heading == b.heading && a.onScreen == b.onScreen
        }
    }

    private(set) var standardBasemap: Basemap
    private(set) var fieldBasemap: Basemap
    private(set) var camera: Camera?
    private(set) var tracking = Tracking.none
    private(set) var userFix: UserFix?
    private(set) var authorization: CLAuthorizationStatus
    /// Shown under the map buttons when a request can't be met right now.
    var notice: String?

    @ObservationIgnored weak var map: MLNMapView?
    /// Set by the map's coordinator: re-applies basemap visibility.
    @ObservationIgnored var onBasemapChange: (() -> Void)?
    @ObservationIgnored private let authManager = CLLocationManager()

    static let standardKey = "map.basemap.standard"
    static let fieldKey = "map.basemap.field"

    init(defaults: UserDefaults = .standard) {
        if ProcessInfo.processInfo.arguments.contains("-resetMapState") {
            defaults.removeObject(forKey: Self.standardKey)
            defaults.removeObject(forKey: Self.fieldKey)
        }
        standardBasemap = defaults.string(forKey: Self.standardKey).flatMap(Basemap.init(rawValue:)) ?? .defaultChoice(fieldMode: false)
        fieldBasemap = defaults.string(forKey: Self.fieldKey).flatMap(Basemap.init(rawValue:)) ?? .defaultChoice(fieldMode: true)
        authorization = CLLocationManager().authorizationStatus
    }

    func basemap(field: Bool) -> Basemap { field ? fieldBasemap : standardBasemap }

    /// Each mode remembers its own choice: Topo by day need not mean Topo at night.
    func setBasemap(_ b: Basemap, field: Bool) {
        if field { fieldBasemap = b } else { standardBasemap = b }
        UserDefaults.standard.set(b.rawValue, forKey: field ? Self.fieldKey : Self.standardKey)
        onBasemapChange?()
    }

    // MARK: Location

    var locationAllowed: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Location button: first tap follows, the second adds heading, the third stops.
    func cycleTracking(fieldMode: Bool) {
        guard ensureLocation(fieldMode: fieldMode) else { return }
        let next: Tracking = switch tracking {
        case .none: .follow
        case .follow: .followWithHeading
        case .followWithHeading: .none
        }
        setTracking(next)
    }

    func centerOnMe(fieldMode: Bool) {
        guard ensureLocation(fieldMode: fieldMode) else { return }
        if tracking == .none { setTracking(.follow) } else if let fix = userFix {
            map?.setCenter(fix.coordinate, animated: true)
        }
    }

    func setTracking(_ t: Tracking) {
        tracking = t
        guard let map else { return }
        let mode: MLNUserTrackingMode = switch t {
        case .none: .none
        case .follow: .follow
        case .followWithHeading: .followWithHeading
        }
        if map.userTrackingMode != mode {
            map.setUserTrackingMode(mode, animated: true, completionHandler: nil)
        }
        if t != .none, map.zoomLevel < 12 { map.setZoomLevel(13, animated: true) }
    }

    /// Turns the puck on. The iOS permission prompt can't be drawn red, so in
    /// field mode it is never raised (ios/AGENTS.md invariant 5).
    private func ensureLocation(fieldMode: Bool) -> Bool {
        authorization = authManager.authorizationStatus
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            notice = nil
            map?.showsUserLocation = true
            return true
        case .notDetermined:
            if fieldMode {
                notice = "Allow location once in standard mode: the iOS prompt can't be drawn red."
                return false
            }
            notice = nil
            map?.showsUserLocation = true
            return true
        default:
            notice = "Location is off for Dark Sky (Settings › Privacy › Location Services)."
            return false
        }
    }

    // MARK: Reports from the map

    func report(camera: Camera) {
        if self.camera != camera { self.camera = camera }
    }

    func report(fix: UserFix?) {
        if userFix != fix { userFix = fix }
        let a = authManager.authorizationStatus
        if a != authorization { authorization = a }
    }

    func report(trackingMode: MLNUserTrackingMode) {
        let t: Tracking = switch trackingMode {
        case .follow: .follow
        case .followWithHeading, .followWithCourse: .followWithHeading
        default: .none
        }
        if tracking != t { tracking = t }
    }

    /// For UI tests and the owner's timing check: where the camera starts.
    /// `-MapCamera "38.374,-109.9654,13"` (a launch-argument default).
    static var launchCamera: (CLLocationCoordinate2D, Double)? {
        guard let s = UserDefaults.standard.string(forKey: "MapCamera") else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 3 else { return nil }
        return (CLLocationCoordinate2D(latitude: p[0], longitude: p[1]), p[2])
    }
}

/// `-DarkSkyOffline`: the map's HTTP stack answers every request with "not
/// connected", so tiles come only from offline packs and the ambient cache,
/// exactly as with no signal. `-clearMapAmbientCache` empties that cache first
/// (tests that prove a pack, not the cache, drew the map).
enum MapNetwork {
    static let offline = ProcessInfo.processInfo.arguments.contains("-DarkSkyOffline")
    private static var configured = false

    static func configure() {
        guard !configured else { return }
        configured = true
        if offline {
            let config = URLSessionConfiguration.default
            config.protocolClasses = [NoNetworkProtocol.self]
            MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
        }
        if ProcessInfo.processInfo.arguments.contains("-clearMapAmbientCache") {
            MLNOfflineStorage.shared.clearAmbientCache { _ in }
        }
    }
}

/// Fails every request as if the phone had no signal.
nonisolated final class NoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
