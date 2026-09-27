public import Foundation

/// Swift port of `app/src/events/curated.ts`: the hand-curated rows in
/// `config/sky-events.json` (bundled by `ios/scripts/sync-shared.sh`). Every
/// row carries `source_url` and `verified_on` (or an explicit null, shown as
/// unverified). A bad row is dropped and reported, never thrown: a typo in the
/// curated list must not cost the user the computed events (ADR-0008 §2).
public struct CuratedEvent: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case meteorShower = "meteor_shower", festival, comet, other
    }

    public struct Location: Sendable, Hashable {
        public let latitude: Double
        public let longitude: Double
        public let place: String
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// First and last active day, anchored at 12:00 UTC so any plausible zone prints the curated date.
    public let activeFrom: Date
    public let activeTo: Date
    public let peakUtc: Date?
    public let zhr: Double?
    public let radiant: MeteorShowers.Radiant?
    public let location: Location?
    public let notes: String
    public let sourceURL: String
    /// `YYYY-MM-DD` the row was checked against its source; nil = unverified.
    public let verifiedOn: String?

    /// The whole calendar days covered, last day included.
    public var activeSpan: TimeWindow {
        TimeWindow(
            start: JSTime.date(JSTime.ms(activeFrom) - JSTime.day / 2),
            end: JSTime.date(JSTime.ms(activeTo) + JSTime.day / 2))
    }

    /// The instant the event is dated and sorted by.
    public var anchor: Date { peakUtc ?? activeFrom }
}

public struct CuratedLoadResult: Sendable, Hashable {
    public let events: [CuratedEvent]
    /// Rows that failed validation, described well enough to fix the file.
    public let problems: [String]
}

public enum CuratedEvents {
    /// The bundled `config/sky-events.json`, parsed once.
    public static let bundled: CuratedLoadResult = {
        guard let data = try? SharedResources.data("sky-events.json") else {
            return CuratedLoadResult(events: [], problems: ["sky-events.json: not bundled"])
        }
        return parse(data)
    }()

    public static func parse(_ data: Data) -> CuratedLoadResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return CuratedLoadResult(events: [], problems: ["sky-events.json: not valid JSON"])
        }
        return parse(object: json)
    }

    /// Validation mirrors `parseCuratedEvents`, message for message.
    public static func parse(object: Any?) -> CuratedLoadResult {
        guard let rows = (object as? [String: Any])?["events"] as? [Any] else {
            return CuratedLoadResult(events: [], problems: ["sky-events.json: missing an `events` array"])
        }
        var problems: [String] = []
        var events: [CuratedEvent] = []
        var seen = Set<String>()
        for (i, row) in rows.enumerated() {
            let r = row as? [String: Any] ?? [:]
            let at = "sky-events.json row \(i + 1)"
            guard let id = str(r["id"]), let name = str(r["name"]), let kindRaw = str(r["kind"]),
                  let sourceURL = str(r["source_url"]) else {
                problems.append("\(at): id, name, kind and source_url are all required")
                continue
            }
            if seen.contains(id) {
                problems.append("\(at): duplicate id \"\(id)\"")
                continue
            }
            guard let kind = CuratedEvent.Kind(rawValue: kindRaw) else {
                problems.append("\(at) (\(id)): unknown kind \"\(kindRaw)\"")
                continue
            }
            guard let from = isoDate(r["active_from"]), let to = isoDate(r["active_to"]), to >= from else {
                problems.append("\(at) (\(id)): active_from/active_to must be ISO dates in order")
                continue
            }
            var peak: Date?
            if let raw = r["peak_utc"], !(raw is NSNull) {
                guard let s = raw as? String, let d = instant(s) else {
                    problems.append("\(at) (\(id)): peak_utc is not a valid instant")
                    continue
                }
                peak = d
            }
            let ra = num(r["radiant_ra_hours"]), dec = num(r["radiant_dec_deg"])
            if kind == .meteorShower && (ra == nil || dec == nil) {
                problems.append("\(at) (\(id)): a meteor shower needs a radiant")
                continue
            }
            events.append(CuratedEvent(
                id: id, name: name, kind: kind, activeFrom: from, activeTo: to, peakUtc: peak,
                zhr: num(r["zhr"]),
                radiant: ra.flatMap { ra in dec.map { MeteorShowers.Radiant(raHours: ra, decDeg: $0) } },
                location: location(r["location"]),
                notes: str(r["notes"]) ?? "",
                sourceURL: sourceURL,
                verifiedOn: isoDate(r["verified_on"]) != nil ? r["verified_on"] as? String : nil))
            seen.insert(id)
        }
        return CuratedLoadResult(events: events, problems: problems)
    }

    /// Curated events whose active days overlap [start, end], by anchor.
    public static func inWindow(_ events: [CuratedEvent], _ window: TimeWindow) -> [CuratedEvent] {
        events
            .filter { $0.activeSpan.end >= window.start && $0.activeSpan.start <= window.end }
            .stableSorted { $0.anchor < $1.anchor }
    }

    /// Great-circle distance, whole kilometres (the web app's `distanceKm`).
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Int {
        let r = 6371.0, toRad = Double.pi / 180
        let dLat = (lat2 - lat1) * toRad, dLon = (lon2 - lon1) * toRad
        let s1 = sin(dLat / 2), s2 = sin(dLon / 2)
        let a = s1 * s1 + cos(lat1 * toRad) * cos(lat2 * toRad) * s2 * s2
        return Int(jsRound(2 * r * asin(min(1, a.squareRoot()))))
    }

    static func str(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// A JSON number (never a JSON boolean, which Foundation also bridges to NSNumber).
    static func num(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    static func isoDate(_ v: Any?) -> Date? {
        guard let s = v as? String, s.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
        guard let night = NightDate(iso: s) else { return nil }
        return JSTime.utcCalendar.date(from: DateComponents(year: night.year, month: night.month, day: night.day, hour: 12))
    }

    static func instant(_ s: String) -> Date? {
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        return try? Date(s, strategy: Date.ISO8601FormatStyle())
    }

    static func location(_ v: Any?) -> CuratedEvent.Location? {
        guard let r = v as? [String: Any], let lat = num(r["latitude"]), let lon = num(r["longitude"]),
              let place = str(r["place"]) else { return nil }
        return CuratedEvent.Location(latitude: lat, longitude: lon, place: place)
    }
}
