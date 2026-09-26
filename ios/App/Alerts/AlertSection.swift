import SkyCore
import SwiftData
import SwiftUI
import UIKit

/// "Alert me when a night this week is Go at <spot>", with an honest account
/// of when iOS last let the check run.
struct AlertSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.conditions) private var conditions
    @Environment(\.modelContext) private var context
    @Bindable var spot: Spot

    @State private var allowed: Bool?
    @State private var checking = false
    @State private var testSent: Bool?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { spot.alertGoThisWeek }, set: setRule)) {
                Text("Alert me when a night this week is Go at \(spot.name)")
            }
            .toggleStyle(PaletteToggleStyle(palette: palette))
            .accessibilityIdentifier("alert-toggle")

            if spot.alertGoThisWeek {
                if allowed == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications are off for Dark Sky, so this rule cannot alert you.")
                            .font(.footnote).foregroundStyle(palette.poor)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    CheckStatus(spot: spot)
                        .font(.footnote)
                        .accessibilityIdentifier("alert-last-checked")
                    HStack(spacing: 4) {
                        Text("Last background run:")
                        if let bg = SpotRefresh.lastBackgroundRun {
                            AgeText(date: bg)
                            if SpotRefresh.lastBackgroundInterrupted { Text("(cut short by iOS)") }
                        } else {
                            Text("not yet")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    if !spot.alertNotifiedNights.isEmpty {
                        Text("Alerted for: \(spot.alertNotifiedNights.sorted().compactMap(NightDate.init(iso:)).map { SpotRefresh.weekdayLabel($0, timeZone: spot.place.timeZone) }.joined(separator: ", "))")
                            .font(.caption)
                            .accessibilityIdentifier("alert-notified")
                    }
                }
                Button(checking ? "Checking…" : "Check now") {
                    Task {
                        checking = true
                        await SpotRefresh.check(spot, conditions: conditions, background: false)
                        try? context.save()
                        checking = false
                    }
                }
                .disabled(checking)
                .accessibilityIdentifier("alert-check-now")
                Button("Send a test notification") {
                    Task { testSent = await SpotRefresh.sendTest(spot) }
                }
                if let testSent {
                    Text(testSent ? "Sent; it arrives in about 5 s. Leave the app or lock the phone to see it." : "Could not send: notifications are not allowed.")
                        .font(.caption).foregroundStyle(testSent ? palette.secondary : palette.poor)
                }
            }
        } header: {
            SectionHeader("Alert")
        } footer: {
            Text("iOS runs background checks when it chooses: usually a few times a day for an app you open often, less for one you don't, and never after you swipe the app away. Each Go night alerts once. Notifications are drawn by iOS, not in field-mode red.")
                .font(.caption)
                .foregroundStyle(palette.secondary)
        }
        .paletteRow(palette)
        .task { allowed = await SpotRefresh.notificationsAllowed() }
    }

    func setRule(_ on: Bool) {
        spot.alertGoThisWeek = on
        try? context.save()
        guard on else {
            SpotRefresh.schedule(context.container)
            return
        }
        Task {
            allowed = await SpotRefresh.requestPermission()
            SpotRefresh.schedule(context.container)
        }
    }
}
