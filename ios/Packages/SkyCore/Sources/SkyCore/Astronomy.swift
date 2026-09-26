import Foundation
import CAstronomy

/// A failure reported by astronomy-engine other than "search found nothing"
/// (which the API models as `nil`, like the TypeScript library's `null`).
public struct AstronomyError: Error, Sendable, Hashable {
    public let status: Int32
    public let operation: String
}

public enum ObserverError: Error, Sendable, Hashable {
    case latitudeOutOfRange(Double)
    case longitudeOutOfRange(Double)
}

/// A place on the Earth's surface. Height defaults to 0 m, matching the web
/// planner's `new Astronomy.Observer(lat, lon, 0)`.
public struct Observer: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double
    public let heightMeters: Double

    public init(latitude: Double, longitude: Double, heightMeters: Double = 0) throws(ObserverError) {
        guard latitude.isFinite, (-90...90).contains(latitude) else {
            throw .latitudeOutOfRange(latitude)
        }
        guard longitude.isFinite, (-180...180).contains(longitude) else {
            throw .longitudeOutOfRange(longitude)
        }
        self.latitude = latitude
        self.longitude = longitude
        self.heightMeters = heightMeters
    }

    var c: astro_observer_t {
        astro_observer_t(latitude: latitude, longitude: longitude, height: heightMeters)
    }
}

public enum Refraction: Sendable, Hashable {
    /// Geometric position (airless). The web planner's GC numbers use this.
    case none
    /// Apparent position with standard atmospheric refraction.
    case normal

    var c: astro_refraction_t { self == .none ? REFRACTION_NONE : REFRACTION_NORMAL }
}

public struct HorizontalPosition: Sendable, Hashable, Codable {
    public let altitudeDeg: Double
    /// Degrees clockwise from true north.
    public let azimuthDeg: Double
}

/// Date <-> astronomy-engine time, reproducing astronomy-engine JS exactly:
/// `ut` is days since 2000-01-01T12:00Z, and times coming back out are
/// truncated to whole milliseconds like a JavaScript `Date`, because the web
/// planner feeds those truncated instants into its next search.
enum AstroTime {
    static let j2000UnixMs = 946_728_000_000.0
    static let msPerDay = 86_400_000.0

    static func from(_ date: Date) -> astro_time_t {
        Astronomy_TimeFromDays((date.timeIntervalSince1970 * 1000 - j2000UnixMs) / msPerDay)
    }

    static func date(_ time: astro_time_t) -> Date {
        jsDate(ms: j2000UnixMs + time.ut * msPerDay)
    }

    static func jsDate(ms: Double) -> Date {
        Date(timeIntervalSince1970: ms.rounded(.towardZero) / 1000)
    }
}

/// JavaScript `Math.round`: halves round toward +infinity (Swift's default
/// rounds them away from zero, which differs for negative altitudes).
func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

func check(_ status: astro_status_t, _ operation: String) throws(AstronomyError) {
    guard status == ASTRO_SUCCESS else {
        throw AstronomyError(status: Int32(bitPattern: status.rawValue), operation: operation)
    }
}

/// Search result with "not found" as nil, every other failure thrown.
func searchResult(_ result: astro_search_result_t, _ operation: String) throws(AstronomyError) -> Date? {
    if result.status == ASTRO_SEARCH_FAILURE { return nil }
    try check(result.status, operation)
    return AstroTime.date(result.time)
}
