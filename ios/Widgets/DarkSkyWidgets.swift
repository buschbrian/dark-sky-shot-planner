import SkyCore
import SwiftUI
import WidgetKit

@main
struct DarkSkyWidgets: WidgetBundle {
    var body: some Widget {
        TonightWidget()
    }
}

/// One night at the pinned spot. The astronomy is computed here, into the
/// timeline (one entry per night, from the previous night's dawn: review
/// B-2's "tonight"); only the verdict comes
/// from the app through the App Group, with the age of the data behind it.
struct NightCard: Sendable {
    let spotName: String
    let night: NightDate
    let isTonight: Bool
    let moonFreeMinutes: Int?
    let aboveSkyline: Bool
    let verdict: VerdictSummary?
    /// The verdict's data aged past its freshness window at this entry: shown
    /// as stale, never as the old level (PLAN §Verdict).
    let verdictStale: Bool
}

struct TonightEntry: TimelineEntry {
    let date: Date
    /// nil: no shared pinned spot (none pinned, or no App Group on this signing).
    let card: NightCard?
    let relevance: TimelineEntryRelevance?
}

struct TonightProvider: TimelineProvider {
    static let nights = 3

    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now, card: nil, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(Self.entries(payload: SharedStore.read(), now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let payload = SharedStore.read()
        // No spot: wait for the app's reload. Otherwise the astronomy is
        // already in the entries; ask again after the last night.
        completion(Timeline(entries: Self.entries(payload: payload, now: .now), policy: payload == nil ? .never : .atEnd))
    }

    static let freshness: FreshnessWindow? = try? FreshnessConfig.bundled().conditionsWindow()

    static func entries(payload: PinnedSpotPayload?, now: Date) -> [TonightEntry] {
        guard let payload, let tz = TimeZone(identifier: payload.timeZoneID),
              let observer = try? Observer(latitude: payload.latitude, longitude: payload.longitude)
        else { return [TonightEntry(date: now, card: nil, relevance: nil)] }
        let horizon = payload.horizonCSV.flatMap { try? HorizonProfile.parse(csv: $0) }
        let current = NightDate.currentSpan(at: now, observer: observer, timeZone: tz)
        var out: [TonightEntry] = []
        var start = now
        var end = current.until
        for k in 0..<nights {
            let night = current.night.adding(days: k)
            let evening = night.evening(in: tz)
            // A night is "tonight" from the previous night's dawn to its own (NightDate.current).
            if k > 0 {
                start = end
                end = night.adding(days: 1).becomesCurrent(observer: observer, timeZone: tz)
            }
            let report = try? Planner.planNight(observer, evening: evening, horizon: horizon)
            let verdict = payload.week?.night(night)?.verdict
            // Entry times: the night's start, and the moment its data turns stale if that falls inside it.
            var times = [start]
            if let asOf = verdict?.limitingAsOf, let stale = staleAt(asOf), stale > start, stale < end { times.append(stale) }
            for t in times {
                let isStale = verdict?.limitingAsOf.map { asOf in staleAt(asOf).map { t >= $0 } ?? false } ?? false
                out.append(TonightEntry(
                    date: t,
                    // Each entry shows while its night is the current one.
                    card: NightCard(spotName: payload.name, night: night, isTonight: true,
                                    moonFreeMinutes: report?.moonFreeMinutes, aboveSkyline: horizon != nil,
                                    verdict: verdict, verdictStale: isStale),
                    relevance: relevance(verdict: isStale ? nil : verdict, from: t, darknessEnd: report?.darkness?.end)))
            }
        }
        return out
    }

    /// When data as of `asOf` leaves the aging band (config `freshness_hours`).
    static func staleAt(_ asOf: Date) -> Date? {
        freshness.map { asOf.addingTimeInterval($0.agingMax * $0.unit.seconds) }
    }

    /// Smart Stack: a Go night is worth surfacing until its darkness ends.
    static func relevance(verdict: VerdictSummary?, from: Date, darknessEnd: Date?) -> TimelineEntryRelevance? {
        guard let v = verdict, let end = darknessEnd, end > from else { return nil }
        let score: Float = switch v.level {
        case .go: 1
        case .marginal: 0.3
        case .noGo: 0.05
        }
        return TimelineEntryRelevance(score: score, duration: end.timeIntervalSince(from))
    }
}

/// Always the field-mode red (Palette.field): a widget is looked at in the dark.
enum WidgetPalette {
    static let background = Color.black
    static let primary = Color(red: 0.85, green: 0, blue: 0)
    static let secondary = Color(red: 0.55, green: 0, blue: 0)
    static let accent = Color(red: 1.0, green: 0, blue: 0)
}

struct TonightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TonightEntry

    var body: some View {
        Group {
            if let card = entry.card {
                switch family {
                case .accessoryInline: Text("\(verdictWord(card)) · \(minutesText(card))")
                case .accessoryRectangular: rectangular(card)
                default: small(card)
                }
            } else {
                Text(family == .accessoryInline ? "Pin a spot in Dark Sky" : "Open Dark Sky to pin a spot")
                    .font(.footnote)
                    .foregroundStyle(WidgetPalette.primary)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(WidgetPalette.background, for: .widget)
    }

    func minutesText(_ c: NightCard) -> String {
        c.moonFreeMinutes.map { "\($0) min moon-free" } ?? "minutes unavailable"
    }

    func verdictWord(_ c: NightCard) -> String {
        guard let v = c.verdict else { return "Verdict unavailable" }
        return c.verdictStale ? "Stale data" : v.shortLevel
    }

    /// "Open-Meteo · hrrr, 2 hr old", or the on-device source alone.
    @ViewBuilder func dataLine(_ v: VerdictSummary) -> some View {
        if let asOf = v.limitingAsOf {
            Text("\(v.limitingSource), \(Text(asOf, style: .relative)) old")
        } else {
            Text(v.limitingSource)
        }
    }

    func small(_ c: NightCard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.spotName).font(.caption2.weight(.semibold)).foregroundStyle(WidgetPalette.secondary).lineLimit(1)
            Text(c.isTonight ? "Tonight" : c.night.iso).font(.caption2).foregroundStyle(WidgetPalette.secondary)
            Text(verdictWord(c)).font(c.verdict == nil ? .footnote.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(WidgetPalette.accent).lineLimit(1).minimumScaleFactor(0.7)
            if let v = c.verdict {
                Text(v.limitingLine).font(.caption2).foregroundStyle(WidgetPalette.primary).lineLimit(1).minimumScaleFactor(0.8)
                dataLine(v).font(.caption2).foregroundStyle(WidgetPalette.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text(c.moonFreeMinutes.map(String.init) ?? "–")
                .font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(WidgetPalette.primary)
            Text(c.aboveSkyline ? "min moon-free, above skyline" : "min moon-free")
                .font(.caption2).foregroundStyle(WidgetPalette.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func rectangular(_ c: NightCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(verdictWord(c)) · \(c.spotName)").font(.headline).lineLimit(1).widgetAccentable()
            Text(minutesText(c) + (c.aboveSkyline ? " (skyline)" : "")).font(.caption).lineLimit(1)
            if let v = c.verdict {
                Text(v.limitingLine).font(.caption2).lineLimit(1)
            } else {
                Text("conditions unavailable").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's verdict and moon-free minutes for the spot pinned in Dark Sky.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}
