import Foundation
@testable import SkyCore

/// Repo-root files are read in place (tests always run from a checkout), so
/// the golden vectors have one copy: the one the web suite writes.
enum Repo {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // SkyCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SkyCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent()

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appending(path: relativePath))
    }
}

enum ISO {
    static func date(_ s: String) throws -> Date {
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        return try Date(s, strategy: Date.ISO8601FormatStyle())
    }

    static func date(_ s: String?) throws -> Date? {
        try s.map { try date($0) }
    }
}

func observer(_ lat: Double, _ lon: Double) throws -> Observer {
    try Observer(latitude: lat, longitude: lon)
}

/// Smallest angle between two azimuths, in degrees.
func azimuthDelta(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
}

/// Great-circle angle between two horizontal positions, in degrees.
func separationDeg(_ a: HorizontalPosition, _ b: HorizontalPosition) -> Double {
    let r = Double.pi / 180
    let c = sin(a.altitudeDeg * r) * sin(b.altitudeDeg * r)
        + cos(a.altitudeDeg * r) * cos(b.altitudeDeg * r) * cos((a.azimuthDeg - b.azimuthDeg) * r)
    return acos(min(1, c)) / r
}
