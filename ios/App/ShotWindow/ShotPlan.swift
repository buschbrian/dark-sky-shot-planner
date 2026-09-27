import Foundation
import SkyCore

/// The shot being planned: a target and the lowest altitude worth shooting
/// it at (0° means "just clear the skyline"). Remembered between launches.
nonisolated struct ShotPlan: Hashable, Sendable {
    var target: ShotTarget = .galacticCore
    var minAltitudeDeg: Double = 0

    static let storageKey = "ShotWindow.plan"
    static let minAltitudeChoices: [Double] = [0, 5, 10, 15, 20, 25, 30]
}

/// `@AppStorage` needs a `RawRepresentable` with a `String` raw value. The
/// JSON goes through a separate type: a `RawRepresentable` that is also
/// `Codable` would encode itself through `rawValue` and recurse.
extension ShotPlan: RawRepresentable {
    private struct Stored: Codable {
        let target: ShotTarget
        let minAltitudeDeg: Double
    }

    init?(rawValue: String) {
        guard let s = try? JSONDecoder().decode(Stored.self, from: Data(rawValue.utf8)) else { return nil }
        self.init(target: s.target, minAltitudeDeg: s.minAltitudeDeg)
    }

    var rawValue: String {
        (try? JSONEncoder().encode(Stored(target: target, minAltitudeDeg: minAltitudeDeg)))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
