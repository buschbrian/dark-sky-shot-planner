public import Foundation

/// NASA GIBS WMTS time handling for the GOES band-13 IR loop. GIBS lists a
/// layer's valid times in DescribeDomains as comma-separated instants or
/// `start/end/period` runs; runs have gaps, so frame times are never guessed.
public enum GIBSTimeDomain {
    public static let host = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"
    public static let goesWestBand13 = "GOES-West_ABI_Band13_Clean_Infrared"
    public static let tileMatrixSet = "GoogleMapsCompatible_Level6"
    public static let maxZoom = 6
    /// The acknowledgement GIBS asks every user of its imagery to display.
    public static let attribution = "We acknowledge the use of imagery provided by services from NASA's Global Imagery Browse Services (GIBS), part of NASA's Earth Science Data and Information System (ESDIS)."

    /// REST DescribeDomains for `layer` between two instants.
    public static func describeDomainsURL(layer: String = goesWestBand13, from: Date, to: Date) -> URL {
        let range = "\(iso(from))--\(iso(to))"
        return URL(string: "\(host)/1.0.0/\(layer)/default/\(tileMatrixSet)/all/\(range).xml")!
    }

    /// `{z}/{y}/{x}` template for one valid time.
    public static func tileURLTemplate(layer: String = goesWestBand13, time: Date) -> String {
        "\(host)/\(layer)/default/\(iso(time))/\(tileMatrixSet)/{z}/{y}/{x}.png"
    }

    /// Valid times in the time dimension's `<Domain>` of a DescribeDomains
    /// response, ascending and de-duplicated; empty when there is none.
    public static func times(fromDescribeDomains xml: String) -> [Date] {
        guard let m = xml.firstMatch(of: /<ows:Identifier>time<\/ows:Identifier>\s*<Domain>([^<]*)<\/Domain>/) else { return [] }
        return times(fromDomain: String(m.1))
    }

    public static func times(fromDomain domain: String) -> [Date] {
        var out = Set<Date>()
        for part in domain.split(separator: ",") {
            let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: "/").map(String.init)
            switch pieces.count {
            case 1:
                if let d = date(pieces[0]) { out.insert(d) }
            case 3:
                guard let start = date(pieces[0]), let end = date(pieces[1]),
                      let step = duration(pieces[2]), step > 0, end >= start else { continue }
                var t = start
                // A run longer than 10 000 steps is not a GIBS subdaily layer.
                var n = 0
                while t <= end, n < 10_000 {
                    out.insert(t)
                    t = t.addingTimeInterval(step)
                    n += 1
                }
            default:
                continue
            }
        }
        return out.sorted()
    }

    /// Up to `count` frames ending at the newest time, each at least
    /// `minSpacing` after the previous one; oldest first.
    public static func loopFrames(_ times: [Date], count: Int, minSpacing: TimeInterval) -> [Date] {
        var picked: [Date] = []
        for t in times.sorted().reversed() {
            if picked.count == count { break }
            if let last = picked.last, last.timeIntervalSince(t) < minSpacing { continue }
            picked.append(t)
        }
        return picked.reversed()
    }

    /// `YYYY-MM-DD` (midnight UTC) or `YYYY-MM-DDThh:mm:ssZ`.
    static func date(_ s: String) -> Date? {
        guard let m = s.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?Z)?/) else { return nil }
        var c = DateComponents(
            year: Int(m.1), month: Int(m.2), day: Int(m.3),
            hour: m.4.flatMap { Int($0) } ?? 0, minute: m.5.flatMap { Int($0) } ?? 0, second: m.6.flatMap { Int($0) } ?? 0)
        c.timeZone = TimeZone(identifier: "UTC")
        return utc.date(from: c)
    }

    /// ISO 8601 durations of days, hours, minutes and seconds (`PT10M`, `P1D`).
    static func duration(_ s: String) -> TimeInterval? {
        guard let m = s.wholeMatch(of: /P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/) else { return nil }
        let d = m.1.flatMap { Double($0) } ?? 0, h = m.2.flatMap { Double($0) } ?? 0
        let mi = m.3.flatMap { Double($0) } ?? 0, sec = m.4.flatMap { Double($0) } ?? 0
        return d * 86_400 + h * 3_600 + mi * 60 + sec
    }

    static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}

/// NOAA NESDIS HMS smoke polygons via the NESDIS ArcGIS FeatureServer
/// (keyless, GeoJSON). Same layer and fields as `worker/src/sources/hms.ts`.
public enum HMSSmoke {
    public static let layer = "https://services2.arcgis.com/C8EMgrsFcRFL6LrL/arcgis/rest/services/NOAA_Satellite_Smoke_Detection_(v1)/FeatureServer/0"
    public static let source = "NOAA NESDIS Hazard Mapping System (HMS) smoke analysis"
    public static let note = "Analyst-drawn from daytime satellite imagery; at night it shows the previous afternoon."

    /// Polygons intersecting a lon/lat box, as GeoJSON.
    public static func queryURL(west: Double, south: Double, east: Double, north: Double) -> URL {
        URL(string: "\(layer)/query?where=1%3D1&outFields=Satellite,Start,End_,Density"
            + "&geometry=\(west),\(south),\(east),\(north)&geometryType=esriGeometryEnvelope&inSR=4326"
            + "&spatialRel=esriSpatialRelIntersects&outSR=4326&geometryPrecision=3&f=geojson")!
    }

    /// Earliest start and latest end over the whole dataset (the current analysis).
    public static var statsURL: URL {
        let stats = #"[{"statisticType":"max","onStatisticField":"End_","outStatisticFieldName":"latest_end"},{"statisticType":"min","onStatisticField":"Start","outStatisticFieldName":"earliest_start"}]"#
        let q = stats.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return URL(string: "\(layer)/query?where=1%3D1&outStatistics=\(q)&f=json")!
    }

    /// HMS times are `YYYYDDD HHMM` (day of year), UTC.
    public static func time(_ s: String) -> Date? {
        guard let m = s.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\d{4})(\d{3}) (\d{2})(\d{2})/),
              let year = Int(m.1), let doy = Int(m.2), let h = Int(m.3), let mi = Int(m.4),
              (1...366).contains(doy), h < 24, mi < 60 else { return nil }
        let days = FreshnessWindow.daysFromCivil(year: year, month: 1, day: 1) + doy - 1
        return Date(timeIntervalSince1970: Double(days) * 86_400 + Double(h * 3600 + mi * 60))
    }

    /// `(start, end)` from the statistics response; nil fields stay nil.
    public static func analysisWindow(fromStats data: Data) -> (start: Date?, end: Date?) {
        struct Body: Decodable {
            struct F: Decodable { let attributes: [String: String?] }
            let features: [F]?
        }
        guard let a = (try? JSONDecoder().decode(Body.self, from: data))?.features?.first?.attributes else { return (nil, nil) }
        return ((a["earliest_start"] ?? nil).flatMap(time), (a["latest_end"] ?? nil).flatMap(time))
    }
}
