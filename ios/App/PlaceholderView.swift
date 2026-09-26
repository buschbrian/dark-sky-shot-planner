import Observation
import SkyCore
import SwiftUI

/// M0 placeholder: proves the app links SkyCore. Replaced by Tonight in M2.
@Observable
final class PlaceholderModel {
    private(set) var summary = "Planning…"

    func plan(latitude: Double, longitude: Double, evening: Date) {
        do {
            let observer = try Observer(latitude: latitude, longitude: longitude)
            let report = try Planner.planNight(observer, evening: evening)
            summary = "\(report.moonFreeMinutes) min moon-free darkness"
        } catch {
            summary = "Could not plan: \(error)"
        }
    }
}

struct PlaceholderView: View {
    @State private var model = PlaceholderModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("Dark Sky")
                .font(.largeTitle.bold())
            Text(model.summary)
                .accessibilityIdentifier("placeholder.summary")
            Text("Sample point: Canyonlands, tonight")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task {
            model.plan(latitude: 38.374031, longitude: -109.965416, evening: .now)
        }
    }
}

#Preview {
    PlaceholderView()
}
