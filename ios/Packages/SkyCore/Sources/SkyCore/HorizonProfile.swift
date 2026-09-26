import Foundation

/// Terrain skyline around an observer: for each azimuth (0 = true north,
/// clockwise), the terrain's altitude above horizontal in degrees. The file
/// format is `config/horizon-profiles/README.md`; `horizonProfile.ts` in the
/// web app parses and interpolates identically.
public struct HorizonProfile: Sendable, Hashable, Codable {
    public struct Sample: Sendable, Hashable, Codable {
        public let azimuthDeg: Double
        public let altitudeDeg: Double

        public init(azimuthDeg: Double, altitudeDeg: Double) {
            self.azimuthDeg = azimuthDeg
            self.altitudeDeg = altitudeDeg
        }
    }

    public enum ParseError: Error, Sendable, Hashable {
        case badHeader(String)
        case badRow(line: Int, text: String)
        case azimuthOutOfRange(line: Int, azimuthDeg: Double)
        case altitudeOutOfRange(line: Int, altitudeDeg: Double)
        case azimuthsNotIncreasing(line: Int)
        case empty
    }

    public static let csvHeader = "azimuth_deg,horizon_alt_deg"

    /// Sorted by strictly increasing azimuth in [0, 360).
    public let samples: [Sample]

    public init(samples: [Sample]) throws(ParseError) {
        guard !samples.isEmpty else { throw .empty }
        for (i, s) in samples.enumerated() {
            guard s.azimuthDeg.isFinite, s.azimuthDeg >= 0, s.azimuthDeg < 360 else {
                throw .azimuthOutOfRange(line: i + 2, azimuthDeg: s.azimuthDeg)
            }
            guard s.altitudeDeg.isFinite, (-90...90).contains(s.altitudeDeg) else {
                throw .altitudeOutOfRange(line: i + 2, altitudeDeg: s.altitudeDeg)
            }
            if i > 0, s.azimuthDeg <= samples[i - 1].azimuthDeg { throw .azimuthsNotIncreasing(line: i + 2) }
        }
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey { case samples }

    /// Decoding validates like `init(samples:)`, so a cached profile cannot
    /// smuggle in unsorted azimuths.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(samples: container.decode([Sample].self, forKey: .samples))
    }

    /// A flat skyline at `altitudeDeg` everywhere.
    public static func flat(_ altitudeDeg: Double = 0) -> HorizonProfile {
        // Cannot throw: one in-range sample.
        try! HorizonProfile(samples: [Sample(azimuthDeg: 0, altitudeDeg: altitudeDeg)])
    }

    public static func parse(csv: String) throws(ParseError) -> HorizonProfile {
        let lines = csv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let header = lines.first, header == csvHeader else {
            throw .badHeader(lines.first ?? "")
        }
        var samples: [Sample] = []
        for (index, line) in lines.enumerated().dropFirst() where !line.isEmpty {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2,
                  let az = Double(fields[0].trimmingCharacters(in: .whitespaces)),
                  let alt = Double(fields[1].trimmingCharacters(in: .whitespaces))
            else { throw .badRow(line: index + 1, text: line) }
            samples.append(Sample(azimuthDeg: az, altitudeDeg: alt))
        }
        return try HorizonProfile(samples: samples)
    }

    /// A profile bundled from `config/horizon-profiles/<name>.csv`.
    public static func bundled(_ name: String) throws -> HorizonProfile {
        let data = try SharedResources.data("horizon-profiles/\(name).csv")
        return try parse(csv: String(decoding: data, as: UTF8.self))
    }

    public func csv() -> String {
        ([Self.csvHeader] + samples.map { "\(Self.format($0.azimuthDeg)),\(Self.format($0.altitudeDeg))" })
            .joined(separator: "\n") + "\n"
    }

    private static func format(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.3f", x)
    }

    /// Terrain altitude at `azimuthDeg`, linear between neighbouring samples
    /// and wrapping across north.
    public func altitudeDeg(atAzimuth azimuthDeg: Double) -> Double {
        let n = samples.count
        if n == 1 { return samples[0].altitudeDeg }
        let a = (azimuthDeg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        // Largest i with samples[i].azimuthDeg <= a, or the last sample when a
        // lies before the first (the wrap segment).
        var lo = 0, hi = n - 1, i = n - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if samples[mid].azimuthDeg <= a { i = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        let j = (i + 1) % n
        let a0 = samples[i].azimuthDeg
        let span = ((samples[j].azimuthDeg - a0) + 360).truncatingRemainder(dividingBy: 360)
        let offset = ((a - a0) + 360).truncatingRemainder(dividingBy: 360)
        return samples[i].altitudeDeg + (samples[j].altitudeDeg - samples[i].altitudeDeg) * offset / span
    }

    public var minAltitudeDeg: Double { samples.map(\.altitudeDeg).min()! }
    public var maxAltitudeDeg: Double { samples.map(\.altitudeDeg).max()! }
}
