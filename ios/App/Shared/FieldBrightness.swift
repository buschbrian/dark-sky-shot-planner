import Foundation
import Observation
import UIKit

/// Field mode is remembered across launches. A `-FieldMode YES|NO` launch
/// argument (UI tests, screenshots) wins and is never written back, so a
/// test run cannot leave the next launch red.
enum FieldModePreference {
    static let key = "FieldMode"

    static func initial(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func save(_ on: Bool, _ defaults: UserDefaults = .standard,
                     arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !arguments.contains("-\(key)") else { return }
        defaults.set(on, forKey: key)
    }
}

/// The brightness rules, free of UIKit so they can be tested alone:
///
/// - Nothing changes until the owner moves the field brightness control.
/// - The first change remembers the system brightness it replaced.
/// - Leaving field mode, backgrounding or quitting gives that brightness back.
/// - The remembered value is persisted, so a process killed while holding the
///   screen still restores it on the next launch.
struct BrightnessSession: Codable, Equatable {
    /// The system brightness to give back; nil while the app holds none.
    private(set) var saved: Double?
    /// The field level the owner chose; nil until they touch the control.
    private(set) var level: Double?

    init(saved: Double? = nil, level: Double? = nil) {
        self.saved = saved
        self.level = level
    }

    /// Field mode is on and the app is in front. Returns the brightness to set, if any.
    mutating func activate(system: Double) -> Double? {
        guard let level else { return nil }
        if saved == nil { saved = system }
        return level
    }

    /// The owner moved the control. Returns the brightness to set.
    mutating func set(_ value: Double, system: Double) -> Double {
        let v = min(max(value, 0), 1)
        if saved == nil { saved = system }
        level = v
        return v
    }

    /// Leaving field mode or the foreground. Returns the brightness to restore, if the app changed it.
    mutating func release() -> Double? {
        defer { saved = nil }
        return saved
    }
}

/// What `FieldBrightness` needs from a screen (a fake in tests).
protocol ScreenBrightness {
    var brightness: CGFloat { get nonmutating set }
}

/// The active window scene's screen.
struct SystemScreenBrightness: ScreenBrightness {
    var brightness: CGFloat {
        get { screen?.brightness ?? 0.5 }
        nonmutating set { screen?.brightness = newValue }
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }
}

/// Applies `BrightnessSession` to the screen and persists it after every change.
@MainActor @Observable
final class FieldBrightness {
    static let key = "FieldBrightness"

    private(set) var session: BrightnessSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let screen: any ScreenBrightness

    init(defaults: UserDefaults = .standard, screenBrightness: any ScreenBrightness = SystemScreenBrightness()) {
        self.defaults = defaults
        self.screen = screenBrightness
        session = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(BrightnessSession.self, from: $0) }
            ?? BrightnessSession()
    }

    /// The level the control shows: the chosen one, else the screen's.
    var displayed: Double { session.level ?? Double(screen.brightness) }

    /// Call on launch and whenever field mode or the scene phase changes.
    func sync(fieldMode: Bool, active: Bool) {
        let system = Double(screen.brightness)
        let target = fieldMode && active ? session.activate(system: system) : session.release()
        persist()
        if let target { apply(target) }
    }

    func set(_ value: Double) {
        let system = Double(screen.brightness)
        apply(session.set(value, system: system))
        persist()
    }

    private func apply(_ value: Double) {
        screen.brightness = CGFloat(value)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: Self.key) }
    }
}
