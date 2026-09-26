import Foundation
import SkyCore
import SwiftUI

/// Where screens get live conditions (M4). The Tonight agent implements the
/// real client (Worker, direct Open-Meteo fallback for clouds, on-disk
/// snapshot cache) and injects it in `RootView`; other screens only call it.
/// Implementations round coordinates to the 0.05° grid before any request
/// (ADR-0010) and never throw for "offline": they return the newest cached
/// snapshot, or nil.
protocol ConditionsProviding: Sendable {
    /// Conditions for the place over `window` (at most 48 h per Worker call).
    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot?
    /// Kp observed + forecast and the aurora summary; nil when unavailable.
    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse?
}

/// Default until the real client lands: everything is unavailable, never zero.
struct UnavailableConditions: ConditionsProviding {
    func conditions(for place: Place, window: DateInterval) async -> ConditionsSnapshot? { nil }
    func spaceWeather(near place: Place?) async -> SpaceWeatherResponse? { nil }
}

private struct ConditionsProviderKey: EnvironmentKey {
    static let defaultValue: any ConditionsProviding = UnavailableConditions()
}

extension EnvironmentValues {
    var conditions: any ConditionsProviding {
        get { self[ConditionsProviderKey.self] }
        set { self[ConditionsProviderKey.self] = newValue }
    }
}
