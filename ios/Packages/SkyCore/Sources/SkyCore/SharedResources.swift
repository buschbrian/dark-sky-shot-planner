public import Foundation

/// Files copied from the repo's `config/` by `ios/scripts/sync-shared.sh`,
/// addressed by their path under `config/`.
public enum SharedResources {
    public static func url(_ configPath: String) -> URL? {
        guard let root = Bundle.module.resourceURL else { return nil }
        let url = root.appending(path: configPath)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    public static func data(_ configPath: String) throws -> Data {
        guard let url = url(configPath) else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }
}
