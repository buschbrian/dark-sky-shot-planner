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

/// A shot the owner chose to keep: where, which night, the target and the
/// selected window. Saved on this iPhone only (precise coordinates never
/// leave it); a saved-plans list and Calendar export come later, so for now
/// "Save plan" records the selection and says so.
nonisolated struct SavedShotPlan: Codable, Hashable, Sendable {
    let placeName: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    let night: String
    let targetID: String
    let targetName: String
    let minAltitudeDeg: Double
    let windowStart: Date
    let windowEnd: Date
    let terrainAware: Bool
    let savedAt: Date
}

enum SavedShotPlans {
    static let key = "ShotWindow.savedPlans"
    static let limit = 50
    /// UI tests keep their plans in memory, so a test never leaves one behind.
    private static var memory: [SavedShotPlan] = []
    private static var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("-DarkSkyUITest") }

    static var all: [SavedShotPlan] {
        if uiTesting { return memory }
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedShotPlan].self, from: data)) ?? []
    }

    static func record(_ plan: SavedShotPlan) {
        var plans = all.filter { !($0.night == plan.night && $0.targetID == plan.targetID && $0.placeName == plan.placeName) }
        plans.insert(plan, at: 0)
        plans = Array(plans.prefix(limit))
        if uiTesting { memory = plans; return }
        UserDefaults.standard.set(try? JSONEncoder().encode(plans), forKey: key)
    }

    static func contains(place: Place, night: NightDate, target: ShotTarget, start: Date) -> Bool {
        all.contains {
            $0.placeName == place.name && $0.night == night.iso && $0.targetID == target.id && $0.windowStart == start
        }
    }
}

/// The activity a target stands for, in words for the status lines: a night
/// with no window says what it has no window *for*.
enum ShotActivity {
    static func isMilkyWay(_ t: ShotTarget) -> Bool {
        switch t {
        case .galacticCore, .milkyWayArch: true
        default: false
        }
    }

    /// "No moon-free Milky Way window", "No dark window for the Moon".
    static func noWindowTitle(_ t: ShotTarget) -> String {
        if isMilkyWay(t) { return "No moon-free Milky Way window" }
        if t == .moon { return "No dark window for the Moon" }
        return "No moon-free window for \(t.name)"
    }

    /// For the factor sheet when the Moon rules out the night.
    static func weatherNote(_ t: ShotTarget) -> String {
        let shots = isMilkyWay(t) ? "moon-free Milky Way shots" : "moon-free shots of \(t.name)"
        return "For \(shots), no weather can change that tonight. Clouds and haze still matter for moonlit landscapes and the Moon itself."
    }
}

extension ShotTarget {
    /// The Sky tab's find target for this shot target.
    var skyFindTarget: SkyFindTarget? {
        switch self {
        case .galacticCore: return .body(.galacticCenter)
        case .moon: return .body(.moon)
        case .planet(let p): return .body(p)
        case .milkyWayArch(let s): return .constellation(s.toL > 90 ? "Cyg" : "Aql")
        case .fixed(let f):
            let stars = ["Betelgeuse": 2061, "Sirius": 2491, "Arcturus": 5340, "Antares": 6134, "Vega": 7001,
                         "Altair": 7557, "Deneb": 7924, "Polaris": 424]
            if let hr = stars[f.name] { return .star(hr: hr) }
            if f.name.contains("M31") { return .constellation("And") }
            if f.name.contains("M45") { return .constellation("Tau") }
            if f.name.contains("M42") { return .constellation("Ori") }
            return nil
        }
    }
}

extension SkyEventHighlight {
    /// What "Plan this" aims at: the planet at opposition or elongation, the
    /// Moon for its phases, eclipses and pairings, the core for its season.
    /// nil when there is no single target (showers, zodiacal light, festivals).
    var shotTarget: ShotTarget? {
        switch item.detail {
        case .apparition(let a): .planet(a.body)
        case .moonPhase, .supermoon, .lunarEclipse, .pairing: .moon
        case .coreSeason: .galacticCore
        case .solarEclipse, .zodiacal, .season, .shower, .place: nil
        }
    }
}
