import Foundation
import SkyCore

/// Source and freshness for one map layer (invariant 3, ADR-0006), shown
/// next to its toggle.
struct LayerProvenance: Equatable {
    let source: String
    let license: String
    let freshness: Freshness
    let detail: String
    let origin: PagesOrigin?
}

extension MapData {
    private static let freshnessConfig = try? FreshnessConfig.bundled()

    func provenance(_ layer: MapLayer, now: Date = .now) -> LayerProvenance {
        switch layer {
        case .lightPollution, .land, .places:
            return pagesProvenance(layer, now: now)
        case .smoke:
            let end = smokeAnalysis.end
            let fresh = Self.freshnessConfig.flatMap { try? $0.conditionsWindow() }?.freshness(since: end, now: now) ?? .unavailable
            var parts: [String] = []
            if let end {
                let start = smokeAnalysis.start.map { Self.utc($0, withDate: false) + "–" } ?? ""
                parts.append("Analysis \(start)\(Self.utc(end, withDate: true)), \(Self.age(end, now: now)) old")
            } else {
                parts.append("No analysis time")
            }
            parts.append(HMSSmoke.note)
            if smoke == nil { parts.append("Not downloaded yet") } else if failed.contains("hms/smoke.geojson") {
                parts.append("Offline: showing the copy from \(fetched["hms/smoke.geojson"].map { Self.age($0, now: now) } ?? "?") ago")
            }
            return LayerProvenance(
                source: HMSSmoke.source, license: "Public domain (NOAA)", freshness: smoke == nil ? .unavailable : fresh,
                detail: parts.joined(separator: " "), origin: nil)
        case .infrared:
            let newest = irFrames.last
            let fresh = Self.freshnessConfig.flatMap { try? $0.conditionsWindow() }?.freshness(since: newest, now: now) ?? .unavailable
            var parts: [String] = []
            if let first = irFrames.first, let newest {
                parts.append("\(irFrames.count) frames \(Self.utc(first, withDate: false))–\(Self.utc(newest, withDate: true)); newest \(Self.age(newest, now: now)) old (valid times from DescribeDomains).")
            } else {
                parts.append("No valid frame times yet.")
            }
            parts.append(GIBSTimeDomain.attribution)
            return LayerProvenance(
                source: "NASA GIBS: GOES-West ABI band 13 clean IR", license: "NASA open data",
                freshness: newest == nil ? .unavailable : fresh, detail: parts.joined(separator: " "), origin: nil)
        }
    }

    private func pagesProvenance(_ layer: MapLayer, now: Date) -> LayerProvenance {
        let p = layer.pages!
        let manifest = manifests[p.layerId]
        let window = Self.freshnessConfig?.layers[p.layerId]
        let fresh = window?.freshness(publicationDate: manifest?.publication_date, today: now) ?? .unavailable
        let origin = origin(layer)
        var parts: [String] = []
        parts.append("Published \(manifest?.publication_date ?? "date not given")")
        if layer == .places { parts.append("Manually curated, not exhaustive.") }
        if layer == .land {
            parts.append("Shows who manages the land, not what is allowed there: check the manager's rules for camping and night access.")
        }
        if let caveat = origin.caveat { parts.append(caveat) }
        if manifest == nil { parts.append("Manifest not downloaded yet.") }
        if let t = fetched["\(p.dir)/manifest.json"] { parts.append("Checked \(Self.age(t, now: now)) ago.") }
        return LayerProvenance(
            source: manifest?.source_name ?? "Pages site data/out/\(p.dir)", license: manifest?.license ?? "—",
            freshness: fresh, detail: parts.joined(separator: " "), origin: origin)
    }

    static func utc(_ date: Date, withDate: Bool) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        let hm = String(format: "%02d:%02d UTC", c.hour!, c.minute!)
        guard withDate else { return String(hm.dropLast(4)) }
        let month = cal.shortMonthSymbols[c.month! - 1]
        return "\(hm) \(month) \(c.day!)"
    }

    static func age(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 2 * 86_400 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86_400)) d"
    }
}
