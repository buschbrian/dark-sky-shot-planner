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
    /// The target across the longest window, every `sampleStep` (both ends included).
    public let track: [Sample]
    /// GC visibility over `windows`, for the verdict's GC factor.
    let gcInWindows: GCVisibility

    /// Longest window in minutes (the planner's rule for `moonFreeMinutes`).
    public var usableMinutes: Int { windows.map(\.minutes).max() ?? 0 }
    public var totalMinutes: Int { windows.reduce(0) { $0 + $1.minutes } }
    public var best: Window? { windows.max { $0.minutes < $1.minutes } }
    public var peak: Sample? { track.max { $0.position.altitudeDeg < $1.position.altitudeDeg } }

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
                targetUp: [], clears: nil, drops: nil, clearsOverTerrain: false, windows: [], track: [],
                gcInWindows: GCVisibility(maxAltitudeDeg: nil, maxAltitudeAt: nil, risesDuringDarkness: false))
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
        var track: [Sample] = []
        if let best = windows.max(by: { $0.minutes < $1.minutes }) {
            var t = best.start
            while true {
                let p = try target.placement(observer, at: t, threshold: threshold)
                track.append(Sample(date: t, position: p.position, clearanceDeg: p.clearanceDeg))
                if t >= best.end { break }
                t = min(t.addingTimeInterval(sampleStep), best.end)
            }
        }
        let gc = horizon.map { Planner.gcVisibility(observer, moonFree: cut, horizon: $0) }
            ?? Planner.gcVisibility(observer, moonFree: cut)
        return ShotWindow(
            target: target, minAltitudeDeg: minAltitudeDeg, terrainAware: horizon != nil, night: night,
            targetUp: crossings.above, clears: clears, drops: crossings.sets.first, clearsOverTerrain: overTerrain,
            windows: windows, track: track, gcInWindows: gc)
    }

    /// The night as the verdict should see it: the shot's windows are the
    /// "moon-free window", so every factor is sampled over exactly these minutes.
    ///
    /// Decision rule (deliberate; review 2026-09-26): the verdict covers **every**
    /// usable window, not only `best`. The headline, the window line and the chart
    /// show the longest window, so when there is more than one the card must say
    /// the verdict's scope beside it (`ShotText.verdictScope`). This is the
    /// conservative whole-set assessment, the same rule the night verdict applies
    /// to several moon-free windows; a per-window verdict would need its own
    /// window picker. Change both together or neither.
    public var nightForVerdict: NightReport {
        let mf = windows.map { MoonFreeWindow(start: $0.start, end: $0.end, minutes: $0.minutes) }
        return NightReport(
            darkness: night.darkness, noAstronomicalDarkness: night.noAstronomicalDarkness,
            moonIllumFraction: night.moonIllumFraction, moonset: night.moonset, moonrise: night.moonrise,
            moonFreeWindows: mf, moonFreeMinutes: usableMinutes, gc: gcInWindows, terrain: night.terrain)
    }

    static let targetNeverUp = "the target is never up in moon-free darkness"

    /// PLAN.md §Verdict over the shot window rather than the whole night.
    /// A GC shot makes the GC's altitude a gate, as the thresholds file says.
    public func verdict(
        conditions: ConditionsResponse?, aurora: AuroraSignal? = nil, config: VerdictConfig, now: Date
    ) throws(Verdict.EvaluationError) -> Verdict {
        try Verdict.evaluate(
            night: nightForVerdict, conditions: conditions, aurora: aurora, config: config, now: now,
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
