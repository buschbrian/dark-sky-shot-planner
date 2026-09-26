import SwiftUI
import WidgetKit

/// M0 stub. M8 fills the timeline with precomputed astronomy + conditions.
@main
struct DarkSkyWidgets: WidgetBundle {
    var body: some Widget {
        TonightWidget()
    }
}

struct TonightEntry: TimelineEntry {
    let date: Date
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(TonightEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        completion(Timeline(entries: [TonightEntry(date: .now)], policy: .never))
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Tonight", provider: TonightProvider()) { _ in
            Text("Dark Sky")
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's verdict and moon-free minutes.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
