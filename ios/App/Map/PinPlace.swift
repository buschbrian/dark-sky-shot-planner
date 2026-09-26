import CoreLocation
import Foundation
import MapKit

/// Typed or pasted coordinates, so a place can be set without touching the map.
enum CoordinateText {
    /// "38.374, -109.965", "38.374 -109.965" or "38.374;-109.965".
    static func parse(_ text: String) -> (latitude: Double, longitude: Double)? {
        let parts = text.split { ", ;\t\n".contains($0) }.compactMap { Double($0) }
        guard parts.count == 2, (-90...90).contains(parts[0]), (-180...180).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    static func format(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}

/// The time zone at a pin. Apple's reverse geocoder is asked about the
/// 0.05°-rounded cell only, so the precise pin stays on the device; offline
/// the fallback (the previous place's zone) is kept.
enum PlaceTimeZone {
    static func resolve(latitude: Double, longitude: Double, fallback: TimeZone) async -> TimeZone {
        let cell = CLLocation(latitude: (latitude / 0.05).rounded() * 0.05, longitude: (longitude / 0.05).rounded() * 0.05)
        guard let request = MKReverseGeocodingRequest(location: cell),
              let items = try? await request.mapItems,
              let tz = items.first?.timeZone else { return fallback }
        return tz
    }
}
