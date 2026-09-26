import BackgroundTasks
import Foundation
import SkyCore
import SwiftData
import UserNotifications
import WidgetKit

/// Re-checks spots with an alert rule (and the pinned spot) in a
/// `BGAppRefreshTask`, posts a local notification for new Go nights, and
/// hands the pinned spot to the widget. iOS decides when the task runs: it
/// is opportunistic, depends on how the app is used, and never runs after a
/// force-quit (ADR-0010), so the UI always shows when it last ran.
enum SpotRefresh {
    static var taskIdentifier: String { (Bundle.main.bundleIdentifier ?? "darksky") + ".refresh" }
    /// Earliest next run; iOS usually waits longer.
    static let interval: TimeInterval = 3 * 3600
    static let lastBackgroundRunKey = "SpotRefresh.lastBackgroundRun"

    /// Conditions for background runs, which have no view environment. The
    /// app wires the same client it injects as `\.conditions`.
    static var conditions: any ConditionsProviding = UnavailableConditions()

    static var lastBackgroundRun: Date? {
        UserDefaults.standard.object(forKey: lastBackgroundRunKey) as? Date
    }

    /// Submits the next refresh when anything needs one. Harmless to call often:
    /// a new request replaces the pending one.
    static func schedule(_ container: ModelContainer) {
        let context = ModelContext(container)
        let needed = (try? context.fetchCount(FetchDescriptor<Spot>(predicate: #Predicate { $0.alertGoThisWeek || $0.isPinned }))) ?? 0
        guard needed > 0 else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Fails in the simulator and when Background App Refresh is off; the UI's "last checked" tells the truth.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runInBackground(_ container: ModelContainer) async {
        let context = ModelContext(container)
        let spots = (try? context.fetch(FetchDescriptor<Spot>(predicate: #Predicate { $0.alertGoThisWeek || $0.isPinned }))) ?? []
        for spot in spots {
            await check(spot, conditions: conditions, background: true, notify: spot.alertGoThisWeek)
        }
        try? context.save()
        UserDefaults.standard.set(Date.now, forKey: lastBackgroundRunKey)
        schedule(container)
    }

    /// One spot's 7-night check: store it, alert on new Go nights, refresh the widget.
    @discardableResult
    static func check(_ spot: Spot, conditions: any ConditionsProviding, background: Bool, notify: Bool) async -> SpotWeek {
        let week = await SpotWeekPlanner.compute(SpotWeekPlanner.input(for: spot), conditions: conditions)
        spot.week = week
        spot.lastCheckedAt = week.checkedAt
        spot.lastCheckedInBackground = background
        if notify { await notifyNewGoNights(spot, week: week) }
        if spot.isPinned { WidgetBridge.publish(spot) }
        return week
    }

    static func notifyNewGoNights(_ spot: Spot, week: SpotWeek) async {
        let fresh = week.nights.filter { $0.verdict?.level == .go && !spot.alertNotifiedNights.contains($0.night) }
        let oldest = NightDate.containing(.now, in: spot.place.timeZone).adding(days: -7).iso
        spot.alertNotifiedNights.removeAll { $0 < oldest }
        guard !fresh.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Go at \(spot.name)"
        content.body = fresh.map { line($0, timeZone: spot.place.timeZone) }.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = "spot-alerts"
        let request = UNNotificationRequest(identifier: "go-\(spot.name)-\(fresh.map(\.night).joined(separator: ","))",
                                            content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            spot.alertNotifiedNights += fresh.map(\.night)
        } catch {
            // Not authorized: leave the nights unmarked so a later run can alert.
        }
    }

    /// "Sat 3 Oct: 212 min moon-free. Cloud cover 8 % (Open-Meteo · hrrr, 1 h old)". No coordinates.
    static func line(_ night: NightSummary, timeZone: TimeZone) -> String {
        let day = night.date.map { weekdayLabel($0, timeZone: timeZone) } ?? night.night
        let minutes = night.headlineMinutes.map { "\($0) min moon-free" } ?? "moon-free minutes unavailable"
        guard let v = night.verdict else { return "\(day): \(minutes)" }
        let age = v.limitingAsOf.map { " as of \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(day): \(minutes). \(v.limitingLine) (\(v.limitingSource)\(age))"
    }

    static func weekdayLabel(_ night: NightDate, timeZone: TimeZone) -> String {
        let style = Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated)
        return night.evening(in: timeZone).formatted(style)
    }

    // MARK: Permission

    /// Asked only when the owner turns a rule on.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    static func notificationsAllowed() async -> Bool? {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .denied: false
        case .notDetermined: nil
        @unknown default: nil
        }
    }

    static func sendTest(_ spot: Spot) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "Test: Go at \(spot.name)"
        content.body = "Alerts for this spot will look like this. Background checks run when iOS allows."
        content.threadIdentifier = "spot-alerts"
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
    }
}

/// Hands the pinned spot to the widget through the App Group.
enum WidgetBridge {
    /// False when the App Group container is unavailable (signing without App Groups).
    @discardableResult
    static func publish(_ spot: Spot?) -> Bool {
        let payload = spot.map {
            PinnedSpotPayload(
                version: PinnedSpotPayload.currentVersion, name: $0.name, latitude: $0.latitude,
                longitude: $0.longitude, timeZoneID: $0.timeZoneID, horizonCSV: $0.horizonCSV,
                week: $0.week, writtenAt: .now)
        }
        let changed = SharedStore.read()?.contentKey != payload?.contentKey
        let ok = SharedStore.write(payload)
        // Reload budget is limited (roughly 40–70 a day): only when the widget would change.
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind) }
        return ok
    }

    static var isAvailable: Bool { SharedStore.containerURL != nil }
}
