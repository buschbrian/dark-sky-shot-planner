import Foundation
import SkyCore

/// Source and freshness for one map layer (invariant 3, ADR-0006), shown
/// next to its toggle.
enum SmokeStatus: Equatable {
    /// No copy yet and no answer yet.
    case checking
    /// The fetch failed and there is no earlier copy.
    case unavailable
    /// The current analysis has no polygons over the AOI.
    case none(checked: Date)
    case polygons(Int, analysisEnd: Date?, checked: Date)
    /// The latest fetch failed; the previous copy is shown.
    case lastGood(count: Int, fetched: Date?)
}

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
            let status = smokeStatus()
            // An empty analysis has no end time: its age is when it was checked.
            let since: Date? = switch status {
            case .none(let checked): checked
            case .polygons(_, let end, let checked): end ?? checked
            case .lastGood(_, let fetched): smokeAnalysis.end ?? fetched
            case .checking, .unavailable: nil
            }
            let fresh = Self.freshnessConfig.flatMap { try? $0.conditionsWindow() }?.freshness(since: since, now: now) ?? .unavailable
            var parts: [String] = []
            if let end = smokeAnalysis.end {
                let start = smokeAnalysis.start.map { Self.utc($0, withDate: false) + "–" } ?? ""
                parts.append("Analysis \(start)\(Self.utc(end, withDate: true)), \(Voice.age(of: end, now: now)).")
            }
            parts.append(HMSSmoke.note)
            return LayerProvenance(
                source: HMSSmoke.source, license: "Public domain (NOAA)", freshness: since == nil ? .unavailable : fresh,
                detail: parts.joined(separator: " "), origin: nil)
        case .infrared:
            let newest = irFrames.last
            let fresh = Self.freshnessConfig.flatMap { try? $0.conditionsWindow() }?.freshness(since: newest, now: now) ?? .unavailable
            var parts: [String] = []
            if let first = irFrames.first, let newest {
                parts.append("\(irFrames.count) frames \(Self.utc(first, withDate: false))–\(Self.utc(newest, withDate: true)); newest \(Voice.age(of: newest, now: now)) (valid times from DescribeDomains).")
            } else {
                parts.append("No valid frame times yet.")
            }
            parts.append(GIBSTimeDomain.attribution)
            return LayerProvenance(
                source: "NASA GIBS: GOES-West ABI band 13 clean IR", license: "NASA open data",
                freshness: newest == nil ? .unavailable : fresh, detail: parts.joined(separator: " "), origin: nil)
        }
    }

    /// What the smoke layer holds right now. "Unavailable" only when a fetch
    /// failed and there is no earlier copy; an analysis with no polygons over
    /// the AOI is an answer, not a failure (review P2 #1).
    func smokeStatus() -> SmokeStatus {
        let rel = "hms/smoke.geojson"
        let failedNow = failed.contains(rel)
        guard let count = smokeCount else {
            return failedNow || (smokeChecked && smoke == nil) ? .unavailable : .checking
        }
        if failedNow { return .lastGood(count: count, fetched: fetched[rel]) }
        let checked = fetched[rel] ?? .now
        return count == 0 ? .none(checked: checked) : .polygons(count, analysisEnd: smokeAnalysis.end, checked: checked)
    }

    /// The smoke layer's state in one line, in the one voice.
    func smokeSummary(now: Date = .now) -> String {
        switch smokeStatus() {
        case .checking:
            return "Checking the HMS smoke analysis…"
        case .unavailable:
            return "Smoke \(Voice.unavailable): the HMS request failed."
        case .none(let checked):
            return "No smoke polygons in the current HMS analysis (checked \(Voice.ago(checked, now: now)))"
        case .polygons(let n, _, let checked):
            return "\(n) smoke polygon\(n == 1 ? "" : "s") over the area (checked \(Voice.ago(checked, now: now)))"
        case .lastGood(let n, let fetched):
            let when = fetched.map { Voice.ago($0, now: now) } ?? "at an unknown time"
            return n == 0
                ? "No smoke polygons in the \(Voice.lastGood), fetched \(when); the latest check failed."
                : "\(n) smoke polygon\(n == 1 ? "" : "s") in the \(Voice.lastGood), fetched \(when); the latest check failed."
        }
    }

    /// The basemap's sources, license and the date each source gives for its
    /// data. Basemaps have no freshness window, so none is claimed.
    func basemapDetail(_ b: Basemap) -> String {
        var parts: [String] = [b.summary + "."]
        for src in b.sources {
            var line = "\(src.attribution): \(src.license)"
            if src.metadataURL != nil {
                line += refreshed(src).map { ", data refreshed \($0) (per the service)" } ?? ", refresh date not downloaded yet"
            }
            parts.append(line + ".")
        }
        if MapNetwork.offline { parts.append("Offline: tiles come from offline areas and the map's cache only.") }
        return parts.joined(separator: " ")
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
        if manifest == nil { parts.append("Manifest not downloaded yet.") }
        if let t = fetched["\(p.dir)/manifest.json"] { parts.append("Checked \(Voice.ago(t, now: now)).") }
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

}
