public import Foundation

/// ADR-0010 point 2: coordinates leave the device only on the 0.05° grid.
/// The Worker rejects anything else (`worker/src/params.ts` `gridCoord`).
public struct ConditionsCell: Sendable, Hashable, Codable {
    public static let stepDeg = 0.05

    public let latitude: Double
    public let longitude: Double

    /// Rounds precise coordinates to the nearest grid point.
    public init(latitude: Double, longitude: Double) {
        self.latitude = Self.round(latitude)
        self.longitude = Self.round(longitude)
    }

    public static func round(_ degrees: Double) -> Double {
        let steps = (degrees / stepDeg).rounded()
        let snapped = (steps * stepDeg * 100).rounded() / 100
        return snapped == 0 ? 0 : snapped
    }

    /// Two decimals, exactly as sent in a query string.
    public var latitudeText: String { Self.text(latitude) }
    public var longitudeText: String { Self.text(longitude) }

    /// Stable file-name-safe key, e.g. `38.35_-109.95`.
    public var key: String { "\(latitudeText)_\(longitudeText)" }

    static func text(_ degrees: Double) -> String { String(format: "%.2f", degrees) }

    public func matches(_ cell: WorkerCell) -> Bool {
        abs(cell.lat - latitude) < 1e-9 && abs(cell.lon - longitude) < 1e-9
    }
}

/// One `/v1/conditions` request, already checked against the Worker's rules
/// (docs/ios/PLAN.md §Request rules), so the direct fallback obeys them too.
public struct ConditionsRequest: Sendable, Hashable {
    public static let maxWindow: TimeInterval = 48 * 3600
    static let maxPast: TimeInterval = 2 * 86_400
    static let maxAhead: TimeInterval = 16 * 86_400

    public let cell: ConditionsCell
    /// Hour-aligned, like the Worker: start rounds down, end rounds up.
    public let start: Date
    public let end: Date

    public enum Refusal: Error, Sendable, Hashable {
        case emptyWindow
        case windowTooLong
        case tooFarInThePast
        case beyondForecastHorizon

        public var message: String {
            switch self {
            case .emptyWindow: "empty time window"
            case .windowTooLong: "window longer than 48 h"
            case .tooFarInThePast: "more than 2 days ago: no forecast kept"
            case .beyondForecastHorizon: "beyond the 16-day forecast"
            }
        }
    }

    public static func make(
        latitude: Double, longitude: Double, window: DateInterval, now: Date
    ) -> Result<ConditionsRequest, Refusal> {
        let start = floorHour(window.start)
        let end = ceilHour(window.end)
        guard end > start else { return .failure(.emptyWindow) }
        guard end.timeIntervalSince(start) <= maxWindow else { return .failure(.windowTooLong) }
        guard start >= now.addingTimeInterval(-maxPast) else { return .failure(.tooFarInThePast) }
        guard end <= now.addingTimeInterval(maxAhead) else { return .failure(.beyondForecastHorizon) }
        return .success(ConditionsRequest(
            cell: ConditionsCell(latitude: latitude, longitude: longitude), start: start, end: end))
    }

    public var window: DateInterval { DateInterval(start: start, end: end) }

    public var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "lat", value: cell.latitudeText),
            URLQueryItem(name: "lon", value: cell.longitudeText),
            URLQueryItem(name: "start", value: Self.iso(start)),
            URLQueryItem(name: "end", value: Self.iso(end)),
        ]
    }

    public func workerURL(base: URL) -> URL {
        base.appending(path: "v1/conditions").appending(queryItems: queryItems)
    }

    /// UTC calendar dates the window touches (`startDate`/`endDate` in the Worker).
    var startDate: String { Self.day(start) }
    var endDate: String { Self.day(end.addingTimeInterval(-1)) }

    func contains(_ t: Date) -> Bool { t >= start && t <= end }

    /// The span Tonight asks for: 16:00 local on the night's date to 10:00 the
    /// next morning, which holds every darkness window south of the Arctic.
    public static func nightWindow(_ night: NightDate, in timeZone: TimeZone) -> DateInterval {
        let evening = night.evening(in: timeZone)
        return DateInterval(start: evening.addingTimeInterval(-5 * 3600), end: evening.addingTimeInterval(13 * 3600))
    }

    static func iso(_ d: Date) -> String { d.formatted(Date.ISO8601FormatStyle()) }

    static func day(_ d: Date) -> String {
        String(iso(d).prefix(10))
    }

    static func floorHour(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    static func ceilHour(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.up) * 3600)
    }
}
