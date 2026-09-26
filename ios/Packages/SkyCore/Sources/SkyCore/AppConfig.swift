public import Foundation

/// The parts of `config/app-config.json` SkyCore needs. The JSON is bundled
/// as a byte-identical copy of the repo-root file (see `ios/scripts/sync-shared.sh`
/// and `SharedFilesTests`), so thresholds are never restated in Swift.
public struct AppConfig: Sendable, Hashable, Decodable {
    public let version: Int
    /// GC peak altitude below which the web app calls the night unusable for the core.
    public let gcMinUsefulAltitudeDeg: Double
    public let arOverlay: AROverlayConfig
    /// The area of interest: what the map fetches live layers for.
    public let aoi: AreaOfInterest

    enum CodingKeys: String, CodingKey {
        case version
        case gcMinUsefulAltitudeDeg = "gc_min_useful_altitude_deg"
        case arOverlay = "ar_overlay"
        case aoi
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public static func bundled() throws -> AppConfig {
        guard let url = bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    static var bundledURL: URL? { Bundle.module.url(forResource: "app-config", withExtension: "json") }
}

/// `ar_overlay` in `config/app-config.json` (iOS Night AR only).
public struct AROverlayConfig: Sendable, Hashable, Decodable {
    /// Largest `CLHeading.headingAccuracy` (degrees) at which the overlay may look confident.
    public let headingAccuracyConfidentMaxDeg: Double

    enum CodingKeys: String, CodingKey {
        case headingAccuracyConfidentMaxDeg = "heading_accuracy_confident_max_deg"
    }
}

/// `aoi` in `config/app-config.json`; never restated in Swift (AGENTS.md).
public struct AreaOfInterest: Sendable, Hashable, Decodable {
    public struct Bbox: Sendable, Hashable, Decodable {
        public let west: Double
        public let south: Double
        public let east: Double
        public let north: Double
    }

    public let name: String
    public let bbox: Bbox
}
