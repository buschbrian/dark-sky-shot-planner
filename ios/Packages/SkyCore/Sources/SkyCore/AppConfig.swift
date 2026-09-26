public import Foundation

/// The parts of `config/app-config.json` SkyCore needs. The JSON is bundled
/// as a byte-identical copy of the repo-root file (see `ios/scripts/sync-shared.sh`
/// and `SharedFilesTests`), so thresholds are never restated in Swift.
public struct AppConfig: Sendable, Hashable, Decodable {
    public let version: Int
    /// GC peak altitude below which the web app calls the night unusable for the core.
    public let gcMinUsefulAltitudeDeg: Double

    enum CodingKeys: String, CodingKey {
        case version
        case gcMinUsefulAltitudeDeg = "gc_min_useful_altitude_deg"
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
