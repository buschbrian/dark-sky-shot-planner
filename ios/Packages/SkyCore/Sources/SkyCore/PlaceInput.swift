import Foundation

/// A location typed or pasted by the owner: plain coordinates, or the web
/// app's share link (`#lat=38.53&lon=-109.90&date=2026-08-22`, see
/// `app/src/state/urlstate.ts`), which may also name the night.
public struct PlaceInput: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let night: NightDate?

    public init(latitude: Double, longitude: Double, night: NightDate? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.night = night
    }

    /// nil when the text holds no valid coordinate pair.
    public static func parse(_ text: String) -> PlaceInput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("lat=") { return parseLink(trimmed) }
        return parseCoordinates(trimmed)
    }

    /// Same acceptance as the web app's `parseUrlState`: numbers in range,
    /// rounded to 1e-5; a malformed `date` is ignored, not fatal.
    static func parseLink(_ text: String) -> PlaceInput? {
        let fragment: Substring
        if let hash = text.firstIndex(of: "#") {
            fragment = text[text.index(after: hash)...]
        } else if let query = text.firstIndex(of: "?") {
            fragment = text[text.index(after: query)...]
        } else {
            fragment = text[...]
        }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, params[String(kv[0])] == nil else { continue }
            params[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
        }
        guard let lat = number(params["lat"], limit: 90), let lon = number(params["lon"], limit: 180) else { return nil }
        return PlaceInput(latitude: lat, longitude: lon, night: params["date"].flatMap(NightDate.init(iso:)))
    }

    /// `38.35, -109.95`, `38.35 -109.95`, or `38.35° N, 109.95° W`.
    static func parseCoordinates(_ text: String) -> PlaceInput? {
        let pattern = /^([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSns])?\s*(?:[,;]\s*|\s+)([+-]?\d+(?:\.\d+)?)\s*°?\s*([EWew])?$/
        guard let m = text.wholeMatch(of: pattern),
              var lat = Double(m.1), var lon = Double(m.3) else { return nil }
        if let h = m.2 {
            guard lat >= 0 else { return nil }
            if h.uppercased() == "S" { lat = -lat }
        }
        if let h = m.4 {
            guard lon >= 0 else { return nil }
            if h.uppercased() == "W" { lon = -lon }
        }
        guard let la = number(String(lat), limit: 90), let lo = number(String(lon), limit: 180) else { return nil }
        return PlaceInput(latitude: la, longitude: lo)
    }

    static func number(_ raw: String?, limit: Double) -> Double? {
        guard let raw, let v = Double(raw), v.isFinite, abs(v) <= limit else { return nil }
        let rounded = jsRound(v * 1e5) / 1e5
        return rounded == 0 ? 0 : rounded
    }
}
