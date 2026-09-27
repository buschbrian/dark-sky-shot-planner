public import Foundation

/// M11: one answer for one shot. For a place (optionally with its measured or
/// computed skyline), a night and a target: when the target clears the
/// terrain (or a chosen minimum altitude, whichever is higher) and drops
/// behind it, how much of that overlaps moon-free astronomical darkness (the
/// Moon counts as up only above the terrain, as in `planNight(horizon:)`), and
/// where the target stands across those minutes. `verdict` re-runs the
/// conditions rule over exactly those minutes.
public struct ShotWindow: Sendable, Hashable {
    /// What opened or closed a usable window.
    public enum Edge: String, Sendable, Hashable, Codable {
        case dusk, dawn
        /// The target crossed the effective horizon (terrain or minimum altitude).
        case targetClears, targetDrops
        /// The Moon crossed the terrain.
        case moonset, moonrise
    }

    /// One stretch of usable time.
    public struct Window: Sendable, Hashable {
        public let start: Date
        public let end: Date
        public let minutes: Int
        public let opensBy: Edge
        public let closesBy: Edge
    }

    public struct Sample: Sendable, Hashable {
        public let date: Date
        /// The target (for the arch, the middle of the stretch).
        public let position: HorizontalPosition
        /// Degrees above the effective horizon; for the arch, of its lowest point.
        public let clearanceDeg: Double
    }

    public let target: ShotTarget
    public let minAltitudeDeg: Double
    /// True when a skyline was given; otherwise the horizon is flat at 0°.
    public let terrainAware: Bool
    /// The night over the same skyline (`Planner.planNight(_:evening:horizon:)`).
    public let night: NightReport
    /// Target above the effective horizon, clipped to astronomical darkness.
    public let targetUp: [TimeWindow]
    /// First time in darkness the target climbs over the effective horizon; nil
    /// when it is already up at dusk or never clears.
    public let clears: Date?
    /// First time in darkness it drops behind it; nil when it stays up or never clears.
    public let drops: Date?
    /// Whether the terrain (rather than `minAltitudeDeg`) is the higher limit
    /// where the target clears; decides "clears the ridge" vs "reaches 15°".
    public let clearsOverTerrain: Bool
    /// Target up during moon-free darkness (for the Moon: during darkness), in time order.
    public let windows: [Window]
    /// The target across each window, every `sampleStep` (both ends
    /// included), parallel to `windows`.
    public let tracks: [[Sample]]
    /// GC visibility in each window, parallel to `windows`, for the verdict's GC factor.
    let gcByWindow: [GCVisibility]

    /// The target across the longest window.
    public var track: [Sample] { bestIndex.map { tracks[$0] } ?? [] }

    /// Longest window in minutes (the planner's rule for `moonFreeMinutes`).
    public var usableMinutes: Int { windows.map(\.minutes).max() ?? 0 }
    public var totalMinutes: Int { windows.reduce(0) { $0 + $1.minutes } }
    public var best: Window? { bestIndex.map { windows[$0] } }
    /// The longest window's index (the first of equals): the default selection.
    public var bestIndex: Int? { windows.indices.max { windows[$0].minutes < windows[$1].minutes } }
    public var peak: Sample? { peak(in: bestIndex) }

    /// The target's highest point across one window (nil index: none).
    public func peak(in index: Int?) -> Sample? {
        guard let index, tracks.indices.contains(index) else { return nil }
        return tracks[index].max { $0.position.altitudeDeg < $1.position.altitudeDeg }
    }

    public static let sampleStep: TimeInterval = 5 * 60

    /// Why there is no usable window, when there is none.
    public enum Shortfall: Sendable, Hashable {
        case noDarkness
        /// The target never clears the effective horizon during darkness.
        case neverClears
        /// It clears, but only while the Moon is above the terrain.
        case onlyWithMoon
    }

    public var shortfall: Shortfall? {
        guard windows.isEmpty else { return nil }
        if night.darkness == nil { return .noDarkness }
        if targetUp.isEmpty { return .neverClears }
        return .onlyWithMoon
    }

    public static func compute(
        _ observer: Observer,
        evening: Date,
        horizon: HorizonProfile?,
        target: ShotTarget,
        minAltitudeDeg: Double = 0
    ) throws(AstronomyError) -> ShotWindow {
        let night = try Planner.planNight(observer, evening: evening, horizon: horizon)
        let skyline = horizon ?? .flat(0)
        let floor = minAltitudeDeg
        let threshold: (Double) -> Double = { az in max(skyline.altitudeDeg(atAzimuth: az), floor) }

        guard let darkness = night.darkness else {
            return ShotWindow(
                target: target, minAltitudeDeg: minAltitudeDeg, terrainAware: horizon != nil, night: night,
                targetUp: [], clears: nil, drops: nil, clearsOverTerrain: false, windows: [], tracks: [],
                gcByWindow: [])
        }

        let crossings = try Planner.scanCrossings(from: darkness.start, to: darkness.end) { (d: Date) throws(AstronomyError) in
            try target.placement(observer, at: d, threshold: threshold).clearanceDeg
        }
        let clears = crossings.rises.first
        var overTerrain = horizon != nil
        if let clears {
            let p = try target.placement(observer, at: clears, threshold: threshold)
            overTerrain = horizon != nil && skyline.altitudeDeg(atAzimuth: p.position.azimuthDeg) >= floor
        }

        // The Moon as a target needs darkness only; everything else needs it moon-free.
        var span: [MoonFreeWindow] = []
        if target.needsMoonFree {
            span = night.moonFreeWindows
        } else {
            Planner.pushWindow(&span, darkness.start, darkness.end)
        }
        return try finish(
            observer, night: night, darkness: darkness, target: target, minAltitudeDeg: minAltitudeDeg,
            horizon: horizon, crossings: crossings, clears: clears, overTerrain: overTerrain,
            cut: Planner.intersect(span, crossings.above), threshold: threshold, moonEdges: target.needsMoonFree)
    }

    private static func finish(
        _ observer: Observer, night: NightReport, darkness: TimeWindow, target: ShotTarget, minAltitudeDeg: Double,
        horizon: HorizonProfile?, crossings: Planner.Crossings, clears: Date?, overTerrain: Bool,
        cut: [MoonFreeWindow], threshold: (Double) -> Double, moonEdges: Bool
    ) throws(AstronomyError) -> ShotWindow {
        func edge(_ t: Date, opening: Bool) -> Edge {
            func near(_ d: Date?) -> Bool { d.map { abs($0.timeIntervalSince(t)) < 1 } ?? false }
            if opening {
                if near(darkness.start) { return .dusk }
                if crossings.rises.contains(where: { near($0) }) { return .targetClears }
                return moonEdges ? .moonset : .targetClears
            }
            if near(darkness.end) { return .dawn }
            if crossings.sets.contains(where: { near($0) }) { return .targetDrops }
            return moonEdges ? .moonrise : .targetDrops
        }
        let windows = cut.map {
            Window(start: $0.start, end: $0.end, minutes: $0.minutes,
                   opensBy: edge($0.start, opening: true), closesBy: edge($0.end, opening: false))
        }
        var tracks: [[Sample]] = []
        for w in windows {
            var track: [Sample] = []
            var t = w.start
            while true {
                let p = try target.placement(observer, at: t, threshold: threshold)
                track.append(Sample(date: t, position: p.position, clearanceDeg: p.clearanceDeg))
                if t >= w.end { break }
                t = min(t.addingTimeInterval(sampleStep), w.end)
            }
            tracks.append(track)
        }
        let gc = cut.map { w in
            horizon.map { Planner.gcVisibility(observer, moonFree: [w], horizon: $0) }
                ?? Planner.gcVisibility(observer, moonFree: [w])
        }
        return ShotWindow(
            target: target, minAltitudeDeg: minAltitudeDeg, terrainAware: horizon != nil, night: night,
            targetUp: crossings.above, clears: clears, drops: crossings.sets.first, clearsOverTerrain: overTerrain,
            windows: windows, tracks: tracks, gcByWindow: gc)
    }

    /// The night as the verdict should see it for one window: that window is
    /// the "moon-free window", so every factor is sampled over exactly those
    /// minutes. nil means the longest window (`bestIndex`); with no window at
    /// all the report has none and the verdict is no-go on astronomy alone.
    ///
    /// Decision rule (coordinator, 2026-09-27, from the product review; it
    /// replaces the 2026-09-26 whole-set rule): the verdict describes the
    /// **selected** window only, the one the card's headline, window line and
    /// chart show. Other windows are listed beside it and can be selected,
    /// each getting its own verdict. `ShotText.verdictScope` says so when
    /// there is more than one. Change both together or neither.
    public func nightForVerdict(window index: Int? = nil) -> NightReport {
        let chosen = (index ?? bestIndex).flatMap { windows.indices.contains($0) ? $0 : nil }
        let mf = chosen.map { i in [MoonFreeWindow(start: windows[i].start, end: windows[i].end, minutes: windows[i].minutes)] } ?? []
        let gc = chosen.map { gcByWindow[$0] }
            ?? GCVisibility(maxAltitudeDeg: nil, maxAltitudeAt: nil, risesDuringDarkness: false)
        return NightReport(
            darkness: night.darkness, noAstronomicalDarkness: night.noAstronomicalDarkness,
            moonIllumFraction: night.moonIllumFraction, moonset: night.moonset, moonrise: night.moonrise,
            moonFreeWindows: mf, moonFreeMinutes: chosen.map { windows[$0].minutes } ?? 0, gc: gc, terrain: night.terrain)
    }

    /// The longest window's night (`nightForVerdict(window: nil)`).
    public var nightForVerdict: NightReport { nightForVerdict(window: nil) }

    static let targetNeverUp = "the target is never up in moon-free darkness"

    /// PLAN.md §Verdict over one shot window (default the longest) rather
    /// than the whole night. A GC shot makes the GC's altitude a gate, as the
    /// thresholds file says.
    public func verdict(
        conditions: ConditionsResponse?, aurora: AuroraSignal? = nil, config: VerdictConfig, now: Date,
        window index: Int? = nil
    ) throws(Verdict.EvaluationError) -> Verdict {
        try Verdict.evaluate(
            night: nightForVerdict(window: index), conditions: conditions, aurora: aurora, config: config, now: now,
            galacticCoreIsTarget: target == .galacticCore,
            // Moon-free darkness exists, but never with the target up.
            noWindowReason: night.moonFreeWindows.isEmpty ? nil : Self.targetNeverUp)
    }
}

extension ShotWindow {
    /// Convenience for a `NightDate` in the place's zone.
    public static func compute(
        _ observer: Observer, night: NightDate, timeZone: TimeZone, horizon: HorizonProfile?,
        target: ShotTarget, minAltitudeDeg: Double = 0
    ) throws(AstronomyError) -> ShotWindow {
        try compute(
            observer, evening: night.evening(in: timeZone), horizon: horizon, target: target,
            minAltitudeDeg: minAltitudeDeg)
    }
}
