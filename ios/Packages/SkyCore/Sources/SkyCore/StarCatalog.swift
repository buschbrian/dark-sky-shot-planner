public import Foundation

/// One star of the bundled Yale Bright Star Catalogue (BSC5, preliminary 5th
/// revised edition via NASA HEASARC; `docs/data-licensing.md`). J2000
/// positions and proper motions, V magnitude and B−V colour.
public struct CatalogStar: Sendable, Hashable {
    /// Harvard Revised (HR) number, the BSC's own identifier.
    public let hr: Int
    public let raDeg: Double
    public let decDeg: Double
    public let vmag: Double
    /// Nil where the catalogue has no B−V.
    public let bv: Double?
    /// Proper motion in RA as μα·cos δ, and in Dec, milliarcseconds a year.
    public let pmRAmas: Double
    public let pmDecmas: Double
}

/// A constellation figure (IAU / Sky & Telescope stick figures via
/// d3-celestial; `docs/data-licensing.md`) as polylines of HR numbers.
public struct ConstellationFigure: Sendable, Hashable, Identifiable {
    /// IAU three-letter abbreviation ("Ori").
    public let abbreviation: String
    public let name: String
    /// 1 = prominent, 3 = faint (d3-celestial's rank), for label priority.
    public let rank: Int
    public let labelRADeg: Double
    public let labelDecDeg: Double
    public let lines: [[Int]]

    public var id: String { abbreviation }

    /// Every HR number the figure uses, once.
    public var starHRs: [Int] {
        var seen = Set<Int>()
        return lines.flatMap { $0 }.filter { seen.insert($0).inserted }
    }
}

public enum StarCatalogError: Error, Sendable, Hashable {
    case badRow(file: String, line: Int)
    case unknownStar(hr: Int, file: String)
}

/// The bundled bright stars, their IAU names and the constellation figures.
/// Parsed once (about 8,400 rows) and shared.
public struct StarCatalog: Sendable {
    /// Sorted by HR number.
    public let stars: [CatalogStar]
    public let names: [Int: String]
    public let constellations: [ConstellationFigure]
    private let indexByHR: [Int: Int]

    public init(stars: [CatalogStar], names: [Int: String], constellations: [ConstellationFigure]) {
        self.stars = stars
        self.names = names
        self.constellations = constellations
        indexByHR = Dictionary(stars.enumerated().map { ($1.hr, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func index(ofHR hr: Int) -> Int? { indexByHR[hr] }
    public func star(hr: Int) -> CatalogStar? { indexByHR[hr].map { stars[$0] } }

    /// The bundled catalogue, parsed on first use.
    public static func bundled() throws -> StarCatalog {
        try cache.get()
    }

    private static let cache: Result<StarCatalog, any Error> = Result {
        try parse(
            stars: String(decoding: SharedResources.data("sky/bsc5-stars.csv"), as: UTF8.self),
            names: String(decoding: SharedResources.data("sky/star-names.csv"), as: UTF8.self),
            constellations: String(decoding: SharedResources.data("sky/constellations.csv"), as: UTF8.self))
    }

    public static func parse(stars starsCSV: String, names namesCSV: String, constellations figuresCSV: String) throws -> StarCatalog {
        var stars: [CatalogStar] = []
        stars.reserveCapacity(8500)
        for (n, line) in rows(starsCSV) {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count == 7, let hr = Int(f[0]), let ra = Double(f[1]), let dec = Double(f[2]),
                  let v = Double(f[3]), let pmra = Double(f[5]), let pmdec = Double(f[6]) else {
                throw StarCatalogError.badRow(file: "bsc5-stars.csv", line: n)
            }
            stars.append(CatalogStar(hr: hr, raDeg: ra, decDeg: dec, vmag: v, bv: Double(f[4]), pmRAmas: pmra, pmDecmas: pmdec))
        }
        let known = Set(stars.map(\.hr))
        var names: [Int: String] = [:]
        for (n, line) in rows(namesCSV) {
            let f = line.split(separator: ",", maxSplits: 1)
            guard f.count == 2, let hr = Int(f[0]) else { throw StarCatalogError.badRow(file: "star-names.csv", line: n) }
            guard known.contains(hr) else { throw StarCatalogError.unknownStar(hr: hr, file: "star-names.csv") }
            names[hr] = String(f[1])
        }
        var figures: [ConstellationFigure] = []
        for (n, line) in rows(figuresCSV) {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count == 6, let rank = Int(f[2]), let ra = Double(f[3]), let dec = Double(f[4]) else {
                throw StarCatalogError.badRow(file: "constellations.csv", line: n)
            }
            var lines: [[Int]] = []
            for part in f[5].split(separator: ";") {
                let hrs = part.split(separator: " ").compactMap { Int($0) }
                guard hrs.count >= 2 else { throw StarCatalogError.badRow(file: "constellations.csv", line: n) }
                for hr in hrs where !known.contains(hr) { throw StarCatalogError.unknownStar(hr: hr, file: "constellations.csv") }
                lines.append(hrs)
            }
            figures.append(ConstellationFigure(
                abbreviation: String(f[0]), name: String(f[1]), rank: rank, labelRADeg: ra, labelDecDeg: dec, lines: lines))
        }
        return StarCatalog(stars: stars, names: names, constellations: figures)
    }

    /// Non-empty data lines after the header, with 1-based line numbers.
    private static func rows(_ csv: String) -> [(Int, Substring)] {
        csv.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .dropFirst().filter { !$0.element.isEmpty }.map { ($0.offset + 1, $0.element) }
    }
}
