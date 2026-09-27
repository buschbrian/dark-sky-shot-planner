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
    /// Conditions requests in flight across all spots in one run.
    static let globalRequests = 3
    static let lastBackgroundRunKey = "SpotRefresh.lastBackgroundRun"
    static let lastBackgroundInterruptedKey = "SpotRefresh.lastBackgroundInterrupted"

    static var lastBackgroundRun: Date? {
        UserDefaults.standard.object(forKey: lastBackgroundRunKey) as? Date
    }

    static var lastBackgroundInterrupted: Bool {
        UserDefaults.standard.bool(forKey: lastBackgroundInterruptedKey)
    }

    static let needsRefresh = #Predicate<Spot> { $0.alertGoThisWeek || $0.isPinned }

    /// Submits the next refresh when anything needs one. Harmless to call often:
    /// a new request replaces the pending one.
    static func schedule(_ container: ModelContainer) {
        let context = ModelContext(container)
        let needed = (try? context.fetchCount(FetchDescriptor<Spot>(predicate: needsRefresh))) ?? 0
        guard needed > 0 else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Fails in the simulator and when Background App Refresh is off; the UI's "last checked" tells the truth.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The `BGAppRefreshTask` body. SwiftUI cancels this task when iOS
    /// expires the background time; `run` then stops, records "interrupted"
    /// and keeps each spot's previous week.
    static func runInBackground(_ container: ModelContainer, conditions: any ConditionsProviding) async {
        let context = ModelContext(container)
        let spots = (try? context.fetch(FetchDescriptor<Spot>(predicate: needsRefresh))) ?? []
        await run(spots, conditions: conditions, background: true)
        try? context.save()
        UserDefaults.standard.set(Date.now, forKey: lastBackgroundRunKey)
        UserDefaults.standard.set(Task.isCancelled, forKey: lastBackgroundInterruptedKey)
        schedule(container)
    }

    /// Checks spots together under one request limit, then stores each week
    /// with its outcome, alerts on new Go nights and refreshes the widget.
    static func run(_ spots: [Spot], conditions: any ConditionsProviding, background: Bool) async {
        let limiter = RequestLimiter(globalRequests)
        let inputs = spots.map(SpotWeekPlanner.input(for:))
        let weeks = await withTaskGroup(of: (Int, SpotWeek).self) { group in
            for (i, input) in inputs.enumerated() {
                group.addTask { (i, await SpotWeekPlanner.compute(input, conditions: conditions, limiter: limiter)) }
            }
            var out: [Int: SpotWeek] = [:]
            for await (i, week) in group { out[i] = week }
            return out
        }
        for (i, spot) in spots.enumerated() {
            guard let week = weeks[i] else { continue }
            await apply(week, to: spot, background: background)
        }
    }

    static func check(_ spot: Spot, conditions: any ConditionsProviding, background: Bool) async {
        await run([spot], conditions: conditions, background: background)
    }

    static func apply(_ week: SpotWeek, to spot: Spot, background: Bool) async {
        let outcome = week.outcome
        spot.lastAttemptAt = week.checkedAt
        spot.lastAttemptOutcome = outcome.rawValue
        spot.lastCheckedInBackground = background
        // An interrupted check keeps the previous week rather than a half-filled one.
        guard outcome != .interrupted || spot.week == nil else { return }
        spot.week = week
        if outcome.counts { spot.lastCheckedAt = week.checkedAt }
        if spot.alertGoThisWeek, outcome != .interrupted { await notifyNewGoNights(spot, week: week) }
        if spot.isPinned { WidgetBridge.publish(spot) }
    }

    /// Go nights not yet alerted whose moon-free window still lies ahead. Before noon
    /// "tonight" can be the night that just ended; a label alone isn't enough.
    static func eligibleGoNights(_ week: SpotWeek, notified: [String], now: Date) -> [NightSummary] {
        week.nights.filter { n in
            n.verdict?.level == .go && !notified.contains(n.night) && (n.usableUntil.map { $0 > now } ?? false)
        }
    }

    /// Nights are marked only once iOS accepts the notification.
    static func notifyNewGoNights(_ spot: Spot, week: SpotWeek, now: Date = .now) async {
        let fresh = eligibleGoNights(week, notified: spot.alertNotifiedNights, now: now)
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
            UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
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

/// While the app is open an alert goes to Notification Center only: no
/// banner, which iOS draws in white over field mode.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list]
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
