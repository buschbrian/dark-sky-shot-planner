import Charts
import SkyCore
import SwiftData
import SwiftUI

/// M11, Tonight's main answer (product review 2026-09-27 §1): what is being
/// photographed, when the usable window is here (site time zone, with the
/// date when it runs past midnight), how it clears the terrain, what limits
/// it, and what to do next (Save plan, Show on map, Find in sky). The verdict
/// describes the selected window only; other windows are listed and can be
/// selected (`ShotWindow.nightForVerdict(window:)`). Astronomy is computed on
/// the phone, so everything but the verdict works offline.
struct ShotWindowCard: View {
    let place: Place
    let night: NightDate
    /// The spot's skyline; nil means a flat 0° horizon, and the card says so.
    let horizon: HorizonProfile?
    @Binding var plan: ShotPlan
    let snapshot: ConditionsSnapshot?
    /// Tonight's `ConditionsStatus` (`TonightModel.conditions`); nil while checking.
    let status: ConditionsStatus?
    var refreshing = false
    let now: Date

    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @State private var shot: Result<ShotWindow, ShotFailure>?
    @State private var selection: Int?
    @State private var readout: ShotReadout?
    @State private var choosing = false
    @State private var savedAt: Date?

    struct ShotFailure: Error { let message: String }

    private var timeZone: TimeZone { place.timeZone }
    private var clock: (Date) -> String { { Format.clock($0, place.timeZone) } }

    var body: some View {
        SectionCard("Shot plan", accessory: {
            Button(choosing ? "Done" : "Change target") { choosing.toggle() }
                .buttonStyle(ActionButtonStyle(.quiet))
                .accessibilityIdentifier("shot.changeTarget")
        }) {
            Text("\(plan.target.name) · \(place.name)")
                .font(.dsHeadline)
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shot.target")
            if choosing {
                ShotTargetPicker(plan: $plan)
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
            switch shot {
            case nil:
                ShotSkeleton()
            case .failure(let f):
                StatusBadge(level: .unavailable)
                Text(f.message).font(.dsBody).foregroundStyle(palette.primary)
            case .success(let shot):
                if let index = selected(shot) {
                    window(shot, index: index)
                } else {
                    noWindow(shot)
                }
                evidence(shot)
            }
            DataStatusLine(symbol: conditionsSource.symbol, text: conditionsSource.text(now: now, timeZone: timeZone),
                           tone: conditionsSource.tone)
                .accessibilityIdentifier("shot.conditionsStatus")
        }
        .task(id: ShotWindowCard.AstronomyKey(place: place, night: night, horizon: horizon, plan: plan)) {
            let result = await Self.compute(place: place, night: night, horizon: horizon, plan: plan)
            selection = nil
            savedAt = nil
            shot = result
        }
        .task(id: ReadoutKey(shot: try? shot?.get(), selection: selection, fetched: snapshot?.fetchedUTC,
                             confirmed: snapshot?.confirmedUTC, minute: Int(now.timeIntervalSince1970 / 60))) {
            guard case .success(let s) = shot, let index = selected(s) else {
                readout = nil
                return
            }
            readout = await Self.readout(s, window: index, snapshot: snapshot, now: now)
        }
    }

    private func selected(_ shot: ShotWindow) -> Int? {
        if let selection, shot.windows.indices.contains(selection) { return selection }
        return shot.bestIndex
    }

    // MARK: The answer

    @ViewBuilder
    private func window(_ shot: ShotWindow, index: Int) -> some View {
        let w = shot.windows[index]
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Usable \(ShotFormat.window(w.start, w.end, night: night, timeZone: timeZone))")
                .font(.dsTitle)
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shot.window")
            Text(ShotText.headline(shot, readout: readout, window: index, clock: clock))
                .font(.dsCallout)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shot.headline")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        FactRow(icon: shot.terrainAware ? "mountain.2" : "line.horizontal.3",
                label: shot.terrainAware ? "Terrain clearance, saved skyline" : "Horizon: flat 0°, \(Voice.estimated)",
                value: clearance(shot, w))
            .accessibilityIdentifier("shot.clearance")
        verdict(shot)
        if shot.windows.count > 1 { otherWindows(shot, selected: index) }
        actions(shot, index: index)
    }

    private func clearance(_ shot: ShotWindow, _ w: ShotWindow.Window) -> String {
        let who = shot.target.shortName
        var text: String
        switch w.opensBy {
        case .targetClears:
            text = shot.clearsOverTerrain ? "\(who) clears the ridge at \(clock(w.start))"
                : shot.minAltitudeDeg > 0 ? "\(who) reaches \(Int(shot.minAltitudeDeg))° at \(clock(w.start))"
                : "\(who) clears the horizon at \(clock(w.start))"
        case .dusk: text = "\(who) is already up at dusk (\(clock(w.start)))"
        case .moonset: text = "Opens when the Moon sets \(shot.terrainAware ? "behind the terrain" : "") at \(clock(w.start))"
        default: text = "Opens \(clock(w.start))"
        }
        text += "; closes at \(ShotWindowCard.edge(w.closesBy)) \(clock(w.end))"
        if let peak = shot.peak(in: selected(shot)) {
            text += ". Highest \(Int(peak.position.altitudeDeg.rounded()))° at \(clock(peak.date)), looking "
                + "\(Self.compass(peak.position.azimuthDeg)) (\(Int(peak.position.azimuthDeg.rounded()))°)"
        }
        if !shot.terrainAware { text += ". Save this spot with a skyline for terrain-aware times." }
        return text
    }

    @ViewBuilder
    private func verdict(_ shot: ShotWindow) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let readout {
                StatusBadge(level: StatusLevel(readout.level), qualifier: qualifier(readout))
                Text(ShotText.verdictLine(readout))
                    .font(.dsBody)
                    .foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceChip(info: FactorText.source(readout.limiting), now: now)
            } else {
                StatusBadge(level: .unavailable, qualifier: "checking").redacted(reason: .placeholder)
                Text("Working out the verdict for this window").font(.dsBody).redacted(reason: .placeholder)
                Text("source · model · age").font(.dsData).redacted(reason: .placeholder)
            }
            if let scope = ShotText.verdictScope(shot) {
                Text(scope).font(.dsFootnote).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("shot.verdictScope")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shot.verdict")
    }

    private func qualifier(_ r: ShotReadout) -> String? {
        if r.flags.contains(.incompleteData) { return "incomplete data" }
        if r.flags.contains(.staleData) { return "stale data" }
        return nil
    }

    private func otherWindows(_ shot: ShotWindow, selected: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Windows tonight").eyebrow(palette)
            ForEach(Array(shot.windows.enumerated()), id: \.offset) { i, w in
                Button { selection = i } label: {
                    HStack {
                        Image(systemName: i == selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(i == selected ? palette.accent : palette.secondary)
                            .accessibilityHidden(true)
                        Text(ShotFormat.window(w.start, w.end, night: night, timeZone: timeZone, zone: false))
                            .font(.dsCallout)
                            .foregroundStyle(palette.primary)
                        Spacer(minLength: DS.Space.s)
                        Text(Format.duration(minutes: w.minutes)).font(.dsCallout).foregroundStyle(palette.secondary)
                    }
                    .frame(minHeight: DS.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressDimStyle())
                .accessibilityAddTraits(i == selected ? .isSelected : [])
                .accessibilityIdentifier("shot.window.\(i)")
            }
        }
    }

    private func actions(_ shot: ShotWindow, index: Int) -> some View {
        let w = shot.windows[index]
        let saved = savedAt != nil || SavedShotPlans.contains(place: place, night: night, target: plan.target, start: w.start)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s) { actionButtons(shot, index: index, saved: saved) }
                VStack(alignment: .leading, spacing: DS.Space.s) { actionButtons(shot, index: index, saved: saved) }
            }
            if saved {
                Text("Saved on this iPhone. A list of saved plans comes in a later build.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("shot.savedNote")
            }
        }
    }

    @ViewBuilder
    private func actionButtons(_ shot: ShotWindow, index: Int, saved: Bool) -> some View {
        let w = shot.windows[index]
        Button { save(shot, w) } label: {
            Label(saved ? "Plan saved" : "Save plan", systemImage: saved ? "checkmark" : "bookmark")
        }
        .buttonStyle(ActionButtonStyle(.primary, compact: true))
        .accessibilityIdentifier("shot.save")
        Button { focus(on: .map, time: w.start) } label: {
            Label("Show on map", systemImage: "map")
        }
        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
        .accessibilityIdentifier("shot.showOnMap")
        Button { focus(on: .sky, time: shot.peak(in: index)?.date ?? w.start) } label: {
            Label("Find in sky", systemImage: "scope")
        }
        .buttonStyle(ActionButtonStyle(.secondary, compact: true))
        .disabled(plan.target.skyFindTarget == nil)
        .accessibilityIdentifier("shot.findInSky")
    }

    private func save(_ shot: ShotWindow, _ w: ShotWindow.Window) {
        SavedShotPlans.record(SavedShotPlan(
            placeName: place.name, latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID,
            night: night.iso, targetID: plan.target.id, targetName: plan.target.name,
            minAltitudeDeg: plan.minAltitudeDeg, windowStart: w.start, windowEnd: w.end,
            terrainAware: shot.terrainAware, savedAt: .now))
        savedAt = .now
    }

    /// Map and Sky follow the shared night; the target and time go in `planFocus`.
    private func focus(on tab: AppTab, time: Date) {
        state.chosenNight = night == place.tonight() ? nil : night
        state.planFocus = PlanFocus(target: plan.target, time: time, night: night)
        state.tab = tab
    }

    // MARK: No window

    @ViewBuilder
    private func noWindow(_ shot: ShotWindow) -> some View {
        let moonRules = shot.shortfall == .onlyWithMoon
            || (shot.night.darkness != nil && shot.night.moonFreeWindows.isEmpty && shot.target.needsMoonFree)
        StatusBadge(level: moonRules ? .moonUp : .noGo)
            .accessibilityIdentifier("shot.verdict")
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(moonRules ? ShotActivity.noWindowTitle(shot.target) : ShotText.astronomy(shot, clock: clock))
                .font(.dsTitle)
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
            if moonRules {
                Text(ShotText.astronomy(shot, clock: clock))
                    .font(.dsCallout).foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("shot.headline")
        NextSuitableNight(place: place, night: night, horizon: horizon, plan: plan)
    }

    // MARK: Evidence

    private func evidence(_ shot: ShotWindow) -> some View {
        MoreInfo(title: "The path, every model and what's missing", id: "shot.evidence") {
            let index = selected(shot)
            if let index, shot.tracks.indices.contains(index), shot.tracks[index].count > 1 {
                ShotTrackChart(track: shot.tracks[index], timeZone: timeZone)
                    .frame(height: 110)
            }
            if let readout {
                Text(ShotText.clouds(readout.clouds).prefix(1).uppercased() + ShotText.clouds(readout.clouds).dropFirst())
                    .font(.dsFootnote).foregroundStyle(palette.primary)
                Text("\(readout.limiting.factor.label), over this window:")
                    .font(.dsFootnote.weight(.semibold)).foregroundStyle(palette.primary)
                ForEach(ShotText.modelLines(readout), id: \.self) { line in
                    Text(line).font(.dsData).foregroundStyle(palette.secondary)
                }
                if readout.missing.isEmpty {
                    Text("Nothing missing among the factors that gate the verdict.")
                        .font(.dsFootnote).foregroundStyle(palette.secondary)
                } else {
                    Text("Missing:").font(.dsFootnote.weight(.semibold)).foregroundStyle(palette.primary)
                    ForEach(readout.missing, id: \.self) { line in
                        Text(line).font(.dsFootnote).foregroundStyle(palette.secondary)
                    }
                }
            }
            ProvenanceChip(info: SourceInfo(source: "astronomy-engine", note: Voice.onDevice))
        }
    }

    /// The card's conditions line, in the same voice as the verdict card's.
    private var conditionsSource: ConditionsSourceStatus {
        ConditionsSourceStatus(status, snapshot: snapshot, refreshing: refreshing)
    }

    // MARK: Words and computation

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

    struct AstronomyKey: Hashable {
        let place: Place
        let night: NightDate
        let horizon: HorizonProfile?
        let plan: ShotPlan
    }

    struct ReadoutKey: Hashable {
        let shot: ShotWindow?
        let selection: Int?
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
    nonisolated static func readout(
        _ shot: ShotWindow, window: Int, snapshot: ConditionsSnapshot?, now: Date
    ) async -> ShotReadout? {
        guard let config = verdictConfig,
              let verdict = try? shot.verdict(conditions: snapshot?.response, config: config, now: now, window: window)
        else { return nil }
        return ShotReadout(verdict)
    }
}

/// The shape of the answer while it is worked out, so nothing below it moves
/// when it arrives (review §D Tonight 5).
private struct ShotSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Usable 10:40 PM – 12:05 AM MDT").font(.dsTitle)
            Text("Core clears the ridge 10:40 PM, 1 h 25 min moon-free, clouds across 4 models").font(.dsCallout)
            FactRow(icon: "mountain.2", label: "Terrain clearance", value: "Clears the ridge at 10:40 PM; closes at dawn")
            StatusBadge(level: .unavailable, qualifier: "checking")
            Text("Working out the verdict for this window").font(.dsBody)
            Text("Save plan · Show on map · Find in sky").font(.dsCallout).frame(minHeight: DS.minTarget)
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working out the shot window")
    }
}

enum ShotFormat {
    /// "10:40 PM – 12:05 AM (Sun, Oct 11) MDT"; "Sun, Oct 11, 2:40 – 5:20 AM MDT"
    /// when the whole window is after midnight. Always the site's zone.
    static func window(_ start: Date, _ end: Date, night: NightDate, timeZone tz: TimeZone, zone: Bool = true) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let evening = cal.dateComponents([.year, .month, .day], from: night.evening(in: tz))
        func nextDay(_ d: Date) -> Bool { cal.dateComponents([.year, .month, .day], from: d) != evening }
        let day = { (d: Date) in d.formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).month(.abbreviated).day()) }
        let abbr = zone ? " \(Format.zone(tz, at: start))" : ""
        let s = Format.clock(start, tz), e = Format.clock(end, tz)
        switch (nextDay(start), nextDay(end)) {
        case (false, false): return "\(s) – \(e)\(abbr)"
        case (false, true): return "\(s) – \(e) (\(day(end)))\(abbr)"
        default: return "\(day(start)), \(s) – \(e)\(abbr)"
        }
    }
}

/// "Find the next suitable night": the next night within a week where the
/// same target has a usable window at this place; jumps Tonight to it.
struct NextSuitableNight: View {
    let place: Place
    let night: NightDate
    let horizon: HorizonProfile?
    let plan: ShotPlan
    nonisolated static let days = 7

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var searching = false
    @State private var none = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Button {
                Task { await find() }
            } label: {
                Label(searching ? "Looking…" : "Find the next suitable night", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(ActionButtonStyle(.primary, compact: true))
            .disabled(searching)
            .accessibilityIdentifier("shot.findNext")
            if none {
                Text("No usable window for \(plan.target.shortName) in the next \(Self.days) nights here.")
                    .font(.dsFootnote).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("shot.findNext.none")
            }
        }
        .onChange(of: night) { none = false }
    }

    private func find() async {
        searching = true
        defer { searching = false }
        if let next = await Self.search(place: place, from: night, horizon: horizon, plan: plan) {
            state.chosenNight = next == place.tonight() ? nil : next
            state.prefetchSkyEvents()
        } else {
            none = true
        }
    }

    @concurrent
    nonisolated static func search(place: Place, from night: NightDate, horizon: HorizonProfile?, plan: ShotPlan) async -> NightDate? {
        guard let observer = try? Observer(latitude: place.latitude, longitude: place.longitude) else { return nil }
        for d in 1...days {
            let n = night.adding(days: d)
            if let shot = try? ShotWindow.compute(
                observer, night: n, timeZone: place.timeZone, horizon: horizon, target: plan.target,
                minAltitudeDeg: plan.minAltitudeDeg), shot.best != nil {
                return n
            }
        }
        return nil
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
                    .foregroundStyle(palette.data.galacticCenter)
                LineMark(x: .value("Time", s.date), y: .value("Altitude", s.position.altitudeDeg - s.clearanceDeg), series: .value("Line", "Skyline"))
                    .foregroundStyle(palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis { DSChart.hourAxis(palette) }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(palette.data.grid)
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))°").foregroundStyle(palette.data.axisLabel) } }
            }
        }
        .environment(\.timeZone, timeZone)
        .accessibilityLabel("Target altitude over the shot window, with the skyline beneath it")
    }
}

/// The embeddable unit: the card with the remembered plan (default the
/// Galactic Center) and a saved spot's skyline when the place is that spot.
struct ShotWindowSection: View {
    let place: Place
    let night: NightDate
    /// Tonight's current snapshot (`TonightModel.snapshot`).
    let snapshot: ConditionsSnapshot?
    /// Where it came from (`TonightModel.conditions`); nil while checking.
    let status: ConditionsStatus?
    var refreshing = false
    let now: Date

    @AppStorage(ShotPlan.storageKey) private var plan = ShotPlan()
    @Query private var spots: [Spot]

    var body: some View {
        ShotWindowCard(place: place, night: night, horizon: Self.horizon(for: place, in: spots), plan: $plan,
                       snapshot: snapshot, status: status, refreshing: refreshing, now: now)
    }

    /// A saved spot within about 50 m of the place lends its skyline.
    static func horizon(for place: Place, in spots: [Spot]) -> HorizonProfile? {
        spots.first { abs($0.latitude - place.latitude) < 0.0005 && abs($0.longitude - place.longitude) < 0.0005 }?
            .horizonProfile
    }
}

/// SpotDetail's compact line under the week strip: the remembered target's
/// window at this spot on the selected night, against its skyline.
struct ShotWindowLine: View {
    let place: Place
    let night: NightDate
    let horizon: HorizonProfile?
    @AppStorage(ShotPlan.storageKey) private var plan = ShotPlan()
    @Environment(\.palette) private var palette
    @State private var text: String?

    var body: some View {
        Label {
            Text(text ?? "Working out the shot window…")
                .font(.dsCallout)
                .foregroundStyle(text == nil ? palette.secondary : palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "scope").foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spot.shotLine")
        .task(id: ShotWindowCard.AstronomyKey(place: place, night: night, horizon: horizon, plan: plan)) {
            let result = await ShotWindowCard.compute(place: place, night: night, horizon: horizon, plan: plan)
            switch result {
            case .success(let shot):
                let clock = { (d: Date) in Format.clock(d, place.timeZone) }
                if let best = shot.best {
                    text = "\(plan.target.name): \(ShotFormat.window(best.start, best.end, night: night, timeZone: place.timeZone)). "
                        + ShotText.astronomy(shot, clock: clock)
                } else {
                    text = "\(plan.target.name): " + (shot.night.moonFreeWindows.isEmpty && plan.target.needsMoonFree
                        ? ShotActivity.noWindowTitle(plan.target) : ShotText.astronomy(shot, clock: clock))
                }
            case .failure(let f):
                text = f.message
            }
        }
    }
}
