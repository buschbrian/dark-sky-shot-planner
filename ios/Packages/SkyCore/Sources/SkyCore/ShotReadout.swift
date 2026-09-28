public import Foundation

/// The evidence behind a shot-window verdict, ready to put into words: the
/// limiting factor with every model's value, run and age, the cloud spread
/// across models over the same minutes, and what is missing.
public struct ShotReadout: Sendable, Hashable {
    public struct ModelLine: Sendable, Hashable {
        public let model: String?
        public let value: Double?
        public let runUTC: Date?
        /// Seconds since the data's as-of time (the older of run and fetch; ADR-0006).
        public let age: TimeInterval?
        public let freshness: Freshness
        /// Why this model could not be used; nil when it was.
        public let unavailableReason: String?
        public let isLastGood: Bool
        /// `FactorReading.cadence`: 15-minute data used (to when), or why not.
        public var cadence: String? = nil
    }

    public struct Spread: Sendable, Hashable {
        public let key: String
        public let label: String
        public let unit: String
        /// Lowest to highest usable model value over the window; nil when none.
        public let band: ClosedRange<Double>?
        public let usableModels: Int
        public let totalModels: Int
        /// The model quoted with its run and age: HRRR when usable, else the newest run.
        public let reference: ModelLine?
    }

    public let level: VerdictLevel
    public let cause: Verdict.Cause
    public let limiting: FactorAssessment
    /// Every model's reading of the limiting factor, in the Worker's order.
    public let limitingModels: [ModelLine]
    /// Mean cloud cover over the window, per model.
    public let clouds: Spread?
    /// Gating factors that could not be rated, and models missing from gating
    /// factors that could, as "Label: model — reason".
    public let missing: [String]
    public let flags: Set<VerdictFlag>
    /// `Verdict.headline`: set when no condition could matter.
    public let headline: String?

    public init(_ verdict: Verdict) {
        level = verdict.level
        cause = verdict.cause
        limiting = verdict.limiting
        limitingModels = verdict.limiting.readings.map(Self.line)
        clouds = verdict.factor("cloud_cover_total").map(Self.spread)
        flags = verdict.flags
        headline = verdict.headline
        var missing: [String] = []
        for f in verdict.factors where f.gatesVerdict {
            if case .unavailable(let reason) = f.status {
                missing.append("\(f.factor.label): \(reason)")
                continue
            }
            for r in f.readings {
                if case .unavailable(let reason) = r.status {
                    missing.append("\(f.factor.label): \(ShotText.modelName(r.model) ?? "source") — \(reason)")
                }
            }
        }
        self.missing = missing
    }

    static func line(_ r: FactorReading) -> ModelLine {
        let reason: String? = if case .unavailable(let why) = r.status { why } else { nil }
        return ModelLine(
            model: r.model, value: r.value, runUTC: r.provenance.modelRunUTC, age: r.provenance.age,
            freshness: r.provenance.freshness, unavailableReason: reason, isLastGood: r.isLastGood,
            cadence: r.cadence)
    }

    static func spread(_ f: FactorAssessment) -> Spread {
        let usable = f.readings.filter(\.isUsable)
        let reference = usable.first { $0.model == "hrrr" }
            ?? usable.max { ($0.provenance.modelRunUTC ?? .distantPast) < ($1.provenance.modelRunUTC ?? .distantPast) }
        return Spread(
            key: f.key, label: f.factor.label, unit: f.factor.unit, band: f.band,
            usableModels: usable.count, totalModels: f.readings.count, reference: reference.map(line))
    }
}

/// Words for the shot window, answer first. Times are formatted by `clock`
/// (24-hour in the place's zone unless the caller passes its own).
public enum ShotText {
    public static func clock24(_ timeZone: TimeZone) -> @Sendable (Date) -> String {
        { date in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let c = cal.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
    }

    /// "1 h 55 min", "40 min", "2 h".
    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "40 min old", "2 h 33 min old", "3 d old".
    public static func age(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "just now" }
        if minutes >= 48 * 60 { return "\(minutes / 1440) d old" }
        return "\(duration(minutes: minutes)) old"
    }

    /// "20Z": the run's UTC hour, as forecasters write it.
    public static func runHour(_ run: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return String(format: "%02dZ", cal.component(.hour, from: run))
    }

    public static func modelName(_ id: String?) -> String? {
        guard let id else { return nil }
        return switch id {
        case "hrrr": "HRRR"
        case "gfs": "GFS"
        case "icon": "ICON"
        case "ecmwf": "ECMWF"
        case "cams_global": "CAMS"
        case "rap_smoke": "RAP-Smoke"
        case "7timer_astro": "7Timer"
        default: id.uppercased()
        }
    }

    /// "Core clears the ridge 23:40, 1 h 55 min moon-free"; the astronomy half
    /// of the headline, true offline.
    public static func astronomy(_ shot: ShotWindow, clock: (Date) -> String) -> String {
        astronomy(shot, window: nil, clock: clock)
    }

    /// The same for one window (nil: the longest).
    public static func astronomy(_ shot: ShotWindow, window index: Int?, clock: (Date) -> String) -> String {
        let who = shot.target.shortName
        guard let i = index ?? shot.bestIndex, shot.windows.indices.contains(i) else {
            switch shot.shortfall {
            case .noDarkness: return "No astronomical darkness this night"
            case .neverClears: return "\(who) never \(clearsPhrase(shot)) in darkness"
            case .onlyWithMoon: return "\(who) is up only while the Moon is"
            case nil: return "\(who): no usable window"
            }
        }
        let best = shot.windows[i]
        let opening: String = switch best.opensBy {
        case .targetClears: "\(who) \(clearsPhrase(shot)) \(clock(best.start))"
        case .dusk: "\(who) up at dusk \(clock(best.start))"
        case .moonset: "\(who) up, Moon behind \(shot.terrainAware ? "terrain" : "the horizon") \(clock(best.start))"
        default: "\(who) from \(clock(best.start))"
        }
        let kind = shot.target.needsMoonFree ? "moon-free" : "in darkness"
        var text = "\(opening), \(duration(minutes: best.minutes)) \(kind)"
        if shot.windows.count > 1 {
            text += " (\(duration(minutes: shot.totalMinutes - best.minutes)) more in \(shot.windows.count - 1) other window\(shot.windows.count > 2 ? "s" : ""))"
        }
        return text
    }

    /// "clears the ridge", "clears the horizon" or "reaches 15°".
    static func clearsPhrase(_ shot: ShotWindow) -> String {
        if shot.clearsOverTerrain { return "clears the ridge" }
        if shot.minAltitudeDeg > 0 { return "reaches \(Int(shot.minAltitudeDeg.rounded()))°" }
        return "clears the horizon"
    }

    /// "clouds 10–25 % across 4 models (HRRR run 20Z, 40 min old)".
    public static func clouds(_ spread: ShotReadout.Spread?) -> String {
        guard let spread, let band = spread.band else { return "clouds unavailable" }
        let lo = Int(band.lowerBound.rounded()), hi = Int(band.upperBound.rounded())
        let range = lo == hi ? "\(lo) %" : "\(lo)–\(hi) %"
        let models = spread.usableModels == spread.totalModels
            ? "\(spread.usableModels) model\(spread.usableModels == 1 ? "" : "s")"
            : "\(spread.usableModels) of \(spread.totalModels) models"
        var text = "clouds \(range) across \(models)"
        if let ref = spread.reference, let name = modelName(ref.model) {
            var parts: [String] = []
            if let run = ref.runUTC { parts.append("run \(runHour(run))") }
            if let seconds = ref.age { parts.append(Self.age(seconds)) }
            text += parts.isEmpty ? "" : " (\(name) \(parts.joined(separator: ", ")))"
        }
        return text
    }

    /// The whole answer-first line, for one window (nil: the longest).
    public static func headline(
        _ shot: ShotWindow, readout: ShotReadout?, window index: Int? = nil, clock: (Date) -> String
    ) -> String {
        let sky = astronomy(shot, window: index, clock: clock)
        guard shot.best != nil else { return sky }
        return "\(sky), \(clouds(readout?.clouds))"
    }

    /// "No-go: Cloud cover (worst hour) 80 %", with the cause when it is missing or stale data.
    public static func verdictLine(_ readout: ShotReadout) -> String {
        let word = switch readout.level {
        case .go: "Go"
        case .marginal: "Marginal"
        case .noGo: "No-go"
        }
        let f = readout.limiting
        switch readout.cause {
        case .rating:
            let value = f.value.map { format($0, unit: f.factor.unit) } ?? "unavailable"
            return "\(word): \(readout.level == .go ? "closest to its limit is " : "")\(f.factor.label.lowercasedFirst) \(value)"
        case .incompleteData:
            return "\(word): \(f.factor.label.lowercasedFirst) is unavailable"
        case .staleData:
            return "\(word): \(f.factor.label.lowercasedFirst) is stale"
        case .noMoonFreeDarkness:
            return readout.headline ?? "\(word): no moon-free darkness"
        }
    }

    /// Nil for one window; otherwise the verdict's scope, which is the
    /// selected window only (see `ShotWindow.nightForVerdict(window:)`).
    public static func verdictScope(_ shot: ShotWindow) -> String? {
        guard shot.windows.count > 1 else { return nil }
        let others = shot.windows.count - 1
        return "Verdict for this window only; \(others) other window\(others == 1 ? "" : "s") below"
    }

    /// "HRRR 12 % (run 20Z, 40 min old)" per model of the limiting factor.
    public static func modelLines(_ readout: ShotReadout) -> [String] {
        readout.limitingModels.map { m in
            let name = modelName(m.model) ?? "value"
            if let why = m.unavailableReason, !m.isLastGood { return "\(name): unavailable (\(why))" }
            let value = m.value.map { format($0, unit: readout.limiting.factor.unit) } ?? "unavailable"
            var parts: [String] = []
            if let run = m.runUTC { parts.append("run \(runHour(run))") }
            if let seconds = m.age { parts.append(Self.age(seconds)) }
            if m.isLastGood { parts.append("last good copy") }
            if let cadence = m.cadence { parts.append(cadence) }
            return "\(name) \(value)" + (parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))")
        }
    }

    public static func format(_ v: Double, unit: String) -> String {
        let number = unit.isEmpty ? String(format: "%.2f", v)
            : abs(v) >= 10 || v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
        if unit.isEmpty { return number }
        if unit == "°" { return number + unit }
        return "\(number) \(unit)"
    }
}

extension String {
    fileprivate var lowercasedFirst: String {
        guard let first else { return self }
        // Keep acronyms ("AOD", "PM2.5") as written.
        if count > 1, self[index(after: startIndex)].isUppercase { return self }
        return first.lowercased() + dropFirst()
    }
}
