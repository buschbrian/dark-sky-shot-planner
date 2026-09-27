import Charts
import SkyCore
import SwiftData
import SwiftUI

/// M11, answer first: "Core clears the ridge 23:40, 1 h 55 min moon-free,
/// clouds 10–25 % across 4 models (HRRR run 20Z, 40 min old)", then the
/// verdict over those same minutes with its limiting factor, the target's
/// path against the skyline, and one tap for every model and what's missing.
/// Astronomy is computed on the phone, so the first half works offline.
struct ShotWindowCard: View {
    let place: Place
    let night: NightDate
    /// The spot's skyline; nil means a flat 0° horizon, and the card says so.
    let horizon: HorizonProfile?
    let plan: ShotPlan
    let snapshot: ConditionsSnapshot?
    let status: ConditionsStatus
    let now: Date

    @Environment(\.palette) private var palette
    @State private var shot: Result<ShotWindow, ShotFailure>?
    @State private var readout: ShotReadout?
    @State private var showEvidence = false

    struct ShotFailure: Error { let message: String }

    private var timeZone: TimeZone { place.timeZone }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shot window · \(plan.target.name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondary)
            switch shot {
            case nil:
                Text("Working out the shot window…").foregroundStyle(palette.secondary)
            case .failure(let f):
                Text(f.message).foregroundStyle(palette.poor)
            case .success(let shot):
                answer(shot)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .task(id: AstronomyKey(place: place, night: night, horizon: horizon, plan: plan)) {
            shot = await Self.compute(place: place, night: night, horizon: horizon, plan: plan)
        }
        .task(id: ReadoutKey(shot: try? shot?.get(), fetched: snapshot?.fetchedUTC, confirmed: snapshot?.confirmedUTC,
                             minute: Int(now.timeIntervalSince1970 / 60))) {
            guard case .success(let s) = shot else {
                readout = nil
                return
            }
            readout = await Self.readout(s, snapshot: snapshot, now: now)
        }
    }

    @ViewBuilder
    private func answer(_ shot: ShotWindow) -> some View {
        let clock = Self.clock(timeZone)
        Text(ShotText.headline(shot, readout: readout, clock: clock))
            .font(.headline)
            .foregroundStyle(palette.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("shot.headline")
        if shot.best != nil, let readout {
            Text(ShotText.verdictLine(readout))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(readout.level))
                .accessibilityIdentifier("shot.verdict")
        }
        if let best = shot.best {
            Text(windowLine(shot, best: best, clock: clock))
                .font(.subheadline)
                .foregroundStyle(palette.primary)
        }
        Text(shot.terrainAware
             ? "Against this spot's saved skyline; the Moon counts as up only above it."
             : "Flat 0° horizon: save this spot with a skyline for terrain-aware times.")
            .font(.footnote)
            .foregroundStyle(palette.secondary)
        if shot.track.count > 1 {
            ShotTrackChart(track: shot.track, timeZone: timeZone)
                .frame(height: 110)
        }
        Text(status.summary(now: now))
            .font(.footnote)
            .foregroundStyle(palette.secondary)
            .accessibilityIdentifier("shot.conditionsStatus")
        if let readout, shot.best != nil {
            Button(showEvidence ? "Hide the evidence" : "Every model and what's missing") {
                showEvidence.toggle()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.accent)
            .buttonStyle(.plain)
            .frame(minHeight: 32)
            .accessibilityIdentifier("shot.evidence")
            if showEvidence { evidence(readout) }
        }
    }

    private func evidence(_ readout: ShotReadout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(readout.limiting.factor.label), over the shot window:")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.primary)
            ForEach(ShotText.modelLines(readout), id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(palette.primary)
            }
            if readout.missing.isEmpty {
                Text("Nothing missing among the factors that gate the verdict.")
                    .font(.footnote).foregroundStyle(palette.secondary)
            } else {
                Text("Missing:").font(.footnote.weight(.semibold)).foregroundStyle(palette.primary)
                ForEach(readout.missing, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(palette.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func windowLine(_ shot: ShotWindow, best: ShotWindow.Window, clock: (Date) -> String) -> String {
        var text = "\(clock(best.start))–\(clock(best.end)), \(Self.edge(best.opensBy)) to \(Self.edge(best.closesBy))"
        if let peak = shot.peak {
            text += ". Peak \(Int(peak.position.altitudeDeg.rounded()))° at \(clock(peak.date)), looking "
                + "\(Self.compass(peak.position.azimuthDeg)) (\(Int(peak.position.azimuthDeg.rounded()))°)"
        }
        return text
    }

    private func color(_ level: VerdictLevel) -> Color {
        switch level {
        case .go: palette.good
        case .marginal: palette.marginal
        case .noGo: palette.poor
        }
    }

    static func edge(_ e: ShotWindow.Edge) -> String {
        switch e {
        case .dusk: "dusk"
        case .dawn: "dawn"
        case .targetClears: "clearing"
        case .targetDrops: "setting"
        case .moonset: "moonset"
        case .moonrise: "moonrise"
        }
    }

    static func compass(_ azimuth: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int(((azimuth.truncatingRemainder(dividingBy: 360) + 360) / 22.5).rounded()) % 16
        return names[i]
    }

    static func clock(_ tz: TimeZone) -> @Sendable (Date) -> String {
        { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz)) }
    }

    struct AstronomyKey: Hashable {
        let place: Place
        let night: NightDate
        let horizon: HorizonProfile?
        let plan: ShotPlan
    }

    struct ReadoutKey: Hashable {
        let shot: ShotWindow?
        let fetched: Date?
        let confirmed: Date?
        let minute: Int
    }

    nonisolated static let verdictConfig: VerdictConfig? = try? VerdictConfig.bundled()

    @concurrent
    nonisolated static func compute(
        place: Place, night: NightDate, horizon: HorizonProfile?, plan: ShotPlan
    ) async -> Result<ShotWindow, ShotFailure> {
        guard let observer = try? Observer(latitude: place.latitude, longitude: place.longitude) else {
            return .failure(ShotFailure(message: "Those coordinates are out of range."))
        }
        do {
            return .success(try ShotWindow.compute(
                observer, night: night, timeZone: place.timeZone, horizon: horizon, target: plan.target,
                minAltitudeDeg: plan.minAltitudeDeg))
        } catch {
            return .failure(ShotFailure(message: "The shot window calculation failed (\(error.operation))."))
        }
    }

    @concurrent
    nonisolated static func readout(_ shot: ShotWindow, snapshot: ConditionsSnapshot?, now: Date) async -> ShotReadout? {
        guard let config = verdictConfig, let verdict = try? shot.verdict(conditions: snapshot?.response, config: config, now: now)
        else { return nil }
        return ShotReadout(verdict)
    }
}

/// The target's altitude across the window, with the skyline under it.
struct ShotTrackChart: View {
    let track: [ShotWindow.Sample]
    let timeZone: TimeZone
    @Environment(\.palette) private var palette

    var body: some View {
        Chart {
            ForEach(track, id: \.date) { s in
                LineMark(x: .value("Time", s.date), y: .value("Altitude", s.position.altitudeDeg), series: .value("Line", "Target"))
                    .foregroundStyle(palette.accent)
                LineMark(x: .value("Time", s.date), y: .value("Altitude", s.position.altitudeDeg - s.clearanceDeg), series: .value("Line", "Skyline"))
                    .foregroundStyle(palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(palette.secondary.opacity(0.3))
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))°").foregroundStyle(palette.secondary) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .accessibilityLabel("Target altitude over the shot window, with the skyline beneath it")
    }
}

/// The embeddable unit for Tonight: the card, the target picker behind one
/// button, the remembered plan, and the spot's skyline looked up from Spots.
struct ShotWindowSection: View {
    let place: Place
    let night: NightDate
    /// Tonight's current snapshot (`TonightModel.snapshot`).
    let snapshot: ConditionsSnapshot?
    /// True when that snapshot is the saved copy, not this refresh.
    var snapshotIsCached = false
    let now: Date

    @AppStorage(ShotPlan.storageKey) private var plan = ShotPlan()
    @Query private var spots: [Spot]
    @Environment(\.conditions) private var provider
    @Environment(\.palette) private var palette
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShotWindowCard(
                place: place, night: night, horizon: horizon, plan: plan, snapshot: snapshot,
                status: ConditionsStatus.of(snapshot, cached: snapshotIsCached, workerConfigured: workerConfigured),
                now: now)
            Button(choosing ? "Done choosing" : "Change target") { choosing.toggle() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .buttonStyle(.plain)
                .frame(minHeight: 36)
                .accessibilityIdentifier("shot.changeTarget")
            if choosing {
                ShotTargetPicker(plan: $plan)
                    .padding(14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var workerConfigured: Bool {
        (provider as? any LiveConditionsProviding)?.workerConfigured ?? false
    }

    /// A saved spot within about 50 m of the place lends its skyline.
    private var horizon: HorizonProfile? {
        spots.first { abs($0.latitude - place.latitude) < 0.0005 && abs($0.longitude - place.longitude) < 0.0005 }?
            .horizonProfile
    }
}
