public import Foundation

/// Swift port of `app/src/events/agenda.ts`: the computed and curated events
/// around a night as one date-sorted list of plain-language lines, each with
/// its provenance ("computed", or the curated row's source and `verified_on`).
/// The verdict text matches the web app's word for word
/// (`shared/golden/sky-events.json`); each item also keeps the numbers it was
/// written from (`detail`) so the app can show the best time and the Moon.
public struct SkyEventItem: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, Hashable, CaseIterable {
        case moon, planet, conjunction, eclipse
        case meteorShower = "meteor_shower"
        case milkyWay = "milky_way"
        case zodiacal, season, place
    }

    public enum Provenance: Sendable, Hashable {
        case computed
        case curated(sourceURL: String, verifiedOn: String?)

        /// ADR-0006 in spirit: a computed number has no age, a curated one has a check date.
        public var label: String {
            switch self {
            case .computed: "computed"
            case .curated(_, nil): "curated — unverified"
            case .curated(_, let on?): "curated, verified \(on)"
            }
        }
    }

    /// The numbers behind the line.
    public enum Detail: Sendable, Hashable {
        case moonPhase(SkyEvents.MoonPhase)
        case supermoon(SkyEvents.Supermoon)
        case apparition(SkyEvents.PlanetApparition)
        case lunarEclipse(SkyEvents.LunarEclipse)
        case solarEclipse(SkyEvents.SolarEclipse)
        case coreSeason(SkyEvents.CoreSeasonRange)
        case pairing(SkyEvents.MoonPairing)
        case zodiacal(SkyEvents.ZodiacalRange)
        case season(SkyEvents.SeasonMarker)
        case shower(CuratedEvent, MeteorShowers.Assessment)
        case place(CuratedEvent, distanceKm: Int?)
    }

    public let at: Date
    /// End instant for events that span nights.
    public let until: Date?
    public let category: Category
    public let title: String
    /// One plain-language line: what it means from here.
    public let verdict: String
    public let provenance: Provenance
    public let detail: Detail

    public var id: String { "\(category.rawValue)|\(title)|\(Int(JSTime.ms(at)))" }
}

public struct SkyEventsResult: Sendable, Hashable {
    public let window: TimeWindow
    public let items: [SkyEventItem]
    /// Problems in the curated file, surfaced rather than swallowed.
    public let problems: [String]
}

/// How instants print inside verdict lines. The app passes the place's zone;
/// the parity suite passes the golden file's fixed offset.
public struct SkyEventFormatters: Sendable {
    public let time: @Sendable (Date) -> String
    public let date: @Sendable (Date) -> String

    public init(time: @escaping @Sendable (Date) -> String, date: @escaping @Sendable (Date) -> String) {
        self.time = time
        self.date = date
    }

    /// "21:05" and "Sep 22" in `timeZone`.
    public static func local(_ timeZone: TimeZone, locale: Locale = .current) -> SkyEventFormatters {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        let date = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
        return SkyEventFormatters(time: { $0.formatted(time) }, date: { $0.formatted(date) })
    }

    /// "HH:MM" and "MM-DD" at a fixed UTC offset (the golden file's rendering).
    public static func fixedOffset(hours: Double) -> SkyEventFormatters {
        let tz = TimeZone(secondsFromGMT: Int(hours * 3600))!
        @Sendable func parts(_ d: Date) -> DateComponents {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            return cal.dateComponents([.month, .day, .hour, .minute], from: d)
        }
        return SkyEventFormatters(
            time: { let c = parts($0); return String(format: "%02d:%02d", c.hour!, c.minute!) },
            date: { let c = parts($0); return String(format: "%02d-%02d", c.month!, c.day!) })
    }
}

public enum SkyEventsAgenda {
    public static func build(
        _ site: Observer, centre: Date, windowDays: Double = SkyEvents.defaultWindowDays,
        formatters fmt: SkyEventFormatters, curated: CuratedLoadResult = CuratedEvents.bundled,
        gcMinAltitudeDeg: Double?
    ) throws(AstronomyError) -> SkyEventsResult {
        let window = SkyEvents.window(around: centre, days: windowDays)
        var items = moonPhaseItems(window) + supermoonItems(window) + planetItems(window)
        items += eclipseItems(site, window, fmt)
        items += SkyEvents.moonPlanetPairings(site, window).map { p in
            SkyEventItem(
                at: p.at, until: nil, category: .conjunction, title: "Moon and \(p.body.displayName)",
                verdict: pairingVerdict(p, fmt), provenance: .computed, detail: .pairing(p))
        }
        items += SkyEvents.zodiacalLightRanges(site, window).map { zodiacalItem($0, fmt) }
        if let gcMinAltitudeDeg {
            items += try SkyEvents.coreSeasonRanges(site, window, minAltitudeDeg: gcMinAltitudeDeg).map {
                coreSeasonItem($0, gcMinAltitudeDeg, fmt)
            }
        }
        items += SkyEvents.seasonMarkers(window).map { s in
            SkyEventItem(
                at: s.at, until: nil, category: .season, title: s.name,
                verdict: "Night length turns here — the darkness window changes fastest around this date.",
                provenance: .computed, detail: .season(s))
        }
        items += try curatedItems(site, window, curated.events, fmt)
        return SkyEventsResult(window: window, items: items.stableSorted { $0.at < $1.at }, problems: curated.problems)
    }

    // MARK: computed

    static let moonPhaseVerdict = [
        0: "The darkest nights of the month — no moon in the sky at any hour.",
        90: "Moon sets near local midnight; the second half of the night is moon-free.",
        180: "Up all night. There is no moon-free darkness on either side of this date.",
        270: "Moon rises near local midnight; the first half of the night is moon-free.",
    ]

    static func moonPhaseItems(_ window: TimeWindow) -> [SkyEventItem] {
        SkyEvents.moonPhases(window).map { p in
            SkyEventItem(
                at: p.at, until: nil, category: .moon, title: p.name, verdict: moonPhaseVerdict[p.angle] ?? "",
                provenance: .computed, detail: .moonPhase(p))
        }
    }

    /// "357,120" without the reader's locale (the web app's `grouped`).
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return out
    }

    static func supermoonItems(_ window: TimeWindow) -> [SkyEventItem] {
        SkyEvents.supermoons(window).map { m in
            SkyEventItem(
                at: m.at, until: nil, category: .moon, title: "Supermoon",
                verdict: "Full moon at \(grouped(m.distanceKm)) km, about \(Int(jsRound((m.sizeRatio - 1) * 100)))% wider and "
                    + "\(Int(jsRound((m.brightnessRatio - 1) * 100)))% brighter than an average full moon. "
                    + "The brightest night of the month: moonlit landscapes, not the Milky Way.",
                provenance: .computed, detail: .supermoon(m))
        }
    }

    static func eclipseItems(_ site: Observer, _ window: TimeWindow, _ fmt: SkyEventFormatters) -> [SkyEventItem] {
        let lunar = SkyEvents.lunarEclipses(site, window).map { e in
            SkyEventItem(
                at: e.peak, until: nil, category: .eclipse, title: "\(e.kind.capitalised) lunar eclipse",
                verdict: lunarEclipseVerdict(e, fmt), provenance: .computed, detail: .lunarEclipse(e))
        }
        let solar = SkyEvents.solarEclipses(site, window).map { e in
            SkyEventItem(
                at: e.peak, until: nil, category: .eclipse, title: "\(e.kind.capitalised) solar eclipse from here",
                verdict: solarEclipseVerdict(e, fmt), provenance: .computed, detail: .solarEclipse(e))
        }
        return lunar + solar
    }

    public static func lunarEclipseVerdict(_ e: SkyEvents.LunarEclipse, _ fmt: SkyEventFormatters) -> String {
        var parts: [String] = []
        switch e.kind {
        case .total:
            parts.append("Totality \(fmt.time(e.totalBegin!))–\(fmt.time(e.totalEnd!)), peak \(fmt.time(e.peak)).")
        case .partial:
            parts.append(
                "\(Int(jsRound(e.obscuration * 100)))% of the Moon in Earth's shadow at \(fmt.time(e.peak)); "
                    + "partial phase \(fmt.time(e.partialBegin!))–\(fmt.time(e.partialEnd!)).")
        default:
            parts.append("Only a subtle dimming, deepest at \(fmt.time(e.peak)): hard to see, harder to photograph.")
        }
        let begin = e.moonAltitudeAtBeginDeg, end = e.moonAltitudeAtEndDeg, peak = e.moonAltitudeAtPeakDeg
        if begin < 0 && peak < 0 && end < 0 {
            parts.append("The Moon is below the horizon here for all of it.")
        } else if begin >= 0 && peak >= 0 && end >= 0 {
            parts.append("Moon \(Int(jsRound(peak)))° up at peak; all of it is visible from here.")
        } else if begin < 0 {
            parts.append("The Moon rises during it here: \(Int(jsRound(end)))° up by the end.")
        } else {
            parts.append("The Moon sets during it here: \(Int(jsRound(begin)))° up at the start.")
        }
        return parts.joined(separator: " ")
    }

    public static func solarEclipseVerdict(_ e: SkyEvents.SolarEclipse, _ fmt: SkyEventFormatters) -> String {
        var parts = [
            "\(Int(jsRound(e.obscuration * 100)))% of the Sun covered at \(fmt.time(e.peak)) "
                + "(Sun \(Int(jsRound(e.sunAltitudeAtPeakDeg)))° up); \(fmt.time(e.begin))–\(fmt.time(e.end))."
        ]
        if e.sunAltitudeAtBeginDeg < 0 { parts.append("Already under way at sunrise.") }
        if e.sunAltitudeAtEndDeg < 0 { parts.append("Still under way at sunset.") }
        parts.append("Never look at the Sun, or point a camera at it, without a certified solar filter.")
        return parts.joined(separator: " ")
    }

    static func coreSeasonItem(_ r: SkyEvents.CoreSeasonRange, _ minAltitudeDeg: Double, _ fmt: SkyEventFormatters) -> SkyEventItem {
        let title = r.opens && !r.closes ? "Milky Way core season opens"
            : r.closes && !r.opens ? "Milky Way core season ends" : "Milky Way core season"
        return SkyEventItem(
            at: r.first.maxAltitudeAt, until: r.last.maxAltitudeAt, category: .milkyWay, title: title,
            verdict: coreSeasonVerdict(r, minAltitudeDeg, fmt), provenance: .computed, detail: .coreSeason(r))
    }

    public static func coreSeasonVerdict(_ r: SkyEvents.CoreSeasonRange, _ minAltitudeDeg: Double, _ fmt: SkyEventFormatters) -> String {
        let nights = "\(r.nights) night\(r.nights == 1 ? "" : "s")"
        let last = r.nights > 1
            ? ", \(JSFormat.number(r.last.maxAltitudeDeg))° at \(fmt.time(r.last.maxAltitudeAt)) on the last" : ""
        return "The Galactic Center clears \(JSFormat.number(minAltitudeDeg))° in astronomical darkness on \(nights), "
            + "\(fmt.date(r.first.eveningUtc)) – \(fmt.date(r.last.eveningUtc)); highest "
            + "\(JSFormat.number(r.first.maxAltitudeDeg))° at \(fmt.time(r.first.maxAltitudeAt)) on the first night\(last). "
            + "Moon not counted: the night report gives the moon-free part."
    }

    static func planetItems(_ window: TimeWindow) -> [SkyEventItem] {
        let oppositions = SkyEvents.planetOppositions(window).map { e in
            SkyEventItem(
                at: e.at, until: nil, category: .planet, title: "\(e.body.displayName) at opposition",
                verdict: "Opposite the Sun: closest, brightest, and above the horizon all night.",
                provenance: .computed, detail: .apparition(e))
        }
        let elongations = SkyEvents.greatestElongations(window).map { e in
            let side = e.visibility ?? .evening
            return SkyEventItem(
                at: e.at, until: nil, category: .planet,
                title: "\(e.body.displayName) at greatest \(side.rawValue) elongation",
                verdict: "\(JSFormat.number(e.elongationDeg ?? 0))° from the Sun — the widest separation of this apparition, "
                    + (side == .evening ? "low in the west after sunset." : "low in the east before sunrise."),
                provenance: .computed, detail: .apparition(e))
        }
        return oppositions + elongations
    }

    /// Every separation printed is topocentric, at the instant printed (ADR-0008 §4).
    public static func pairingVerdict(_ p: SkyEvents.MoonPairing, _ fmt: SkyEventFormatters) -> String {
        let moonPct = Int(jsRound(p.moonIllumFraction * 100))
        var parts: [String] = []
        if p.observableHere {
            parts.append(
                "\(JSFormat.fixed(p.separationDeg, 1))° apart at \(fmt.time(p.at)), "
                    + "\(Int(jsRound(p.moonAltitudeDeg)))° and \(Int(jsRound(p.bodyAltitudeDeg)))° up, Moon \(moonPct)% lit.")
        } else {
            parts.append(
                "Closest approach from here \(JSFormat.fixed(p.separationDeg, 1))° at \(fmt.time(p.at)), "
                    + "but not above 5° in dark sky.")
        }
        guard p.possibleOccultation, let occ = p.occultation else { return parts.joined(separator: " ") }

        if !occ.behindDiscFromHere {
            if p.geocentricMinDeg < SkyEvents.occultationFlagDeg {
                let clearance = max(0, occ.minSeparationDeg - occ.moonRadiusDeg)
                parts.append(
                    "An occultation somewhere on Earth, but not here: from this spot it misses the disc by "
                        + "\(JSFormat.fixed(clearance, 2))° at \(fmt.time(occ.minSeparationAt)).")
            }
            return parts.joined(separator: " ")
        }

        parts.append(
            "Occultation from here — \(p.body.displayName) passes behind the Moon, closest "
                + "\(JSFormat.fixed(occ.minSeparationDeg, 3))° at \(fmt.time(occ.minSeparationAt)).")
        if occ.moonAltitudeDeg < 0, let back = occ.reappearsAt, (occ.reappearMoonAltitudeDeg ?? -1) >= 0 {
            parts.append(
                "The Moon is still below the horizon at the minimum; it reappears at "
                    + "\(fmt.time(back)) with the Moon only \(JSFormat.number(occ.reappearMoonAltitudeDeg ?? 0))° up — "
                    + "you need a flat eastern horizon.")
        } else if occ.moonAltitudeDeg < 0 {
            parts.append("The whole event happens below the horizon here.")
        } else {
            if occ.sunAltitudeDeg > SkyEvents.pairingMaxSunAltitudeDeg {
                parts.append("In daylight here (Sun \(Int(jsRound(occ.sunAltitudeDeg)))° up) — a telescope job.")
            }
            if let back = occ.reappearsAt { parts.append("Reappears at \(fmt.time(back)).") }
        }
        return parts.joined(separator: " ")
    }

    static func zodiacalItem(_ r: SkyEvents.ZodiacalRange, _ fmt: SkyEventFormatters) -> SkyEventItem {
        let morning = r.season == .autumnMorning
        let look = morning
            ? "east about an hour before astronomical dawn (\(fmt.time(r.start)) on the first night)."
            : "west about an hour after astronomical dusk (\(fmt.time(r.start)) on the first night)."
        return SkyEventItem(
            at: r.start, until: r.end, category: .zodiacal,
            title: morning ? "Zodiacal light, pre-dawn" : "Zodiacal light, after dusk",
            verdict: "\(r.nights) night\(r.nights == 1 ? "" : "s") with no moon in the way, "
                + "\(fmt.date(r.start)) – \(fmt.date(r.end)). Look " + look,
            provenance: .computed, detail: .zodiacal(r))
    }

    // MARK: curated

    static func curatedItems(
        _ site: Observer, _ window: TimeWindow, _ events: [CuratedEvent], _ fmt: SkyEventFormatters
    ) throws(AstronomyError) -> [SkyEventItem] {
        var out: [SkyEventItem] = []
        for e in CuratedEvents.inWindow(events, window) {
            let provenance = SkyEventItem.Provenance.curated(sourceURL: e.sourceURL, verifiedOn: e.verifiedOn)
            if e.kind == .meteorShower, let radiant = e.radiant {
                let span = e.activeSpan
                let a = try MeteorShowers.assess(site, radiant, peak: e.anchor, activeFrom: span.start, activeTo: span.end)
                out.append(SkyEventItem(
                    at: e.anchor, until: nil, category: .meteorShower, title: e.name,
                    verdict: showerVerdict(e, a, fmt), provenance: provenance, detail: .shower(e, a)))
            } else {
                let km = e.location.map { CuratedEvents.distanceKm(site.latitude, site.longitude, $0.latitude, $0.longitude) }
                out.append(SkyEventItem(
                    at: e.anchor, until: e.activeTo, category: .place, title: e.name,
                    verdict: placeVerdict(e, km), provenance: provenance, detail: .place(e, distanceKm: km)))
            }
        }
        return out
    }

    public static func showerVerdict(_ e: CuratedEvent, _ a: MeteorShowers.Assessment, _ fmt: SkyEventFormatters) -> String {
        let active = "Active \(fmt.date(e.activeFrom)) – \(fmt.date(e.activeTo))."
        let zhr = e.zhr.map { "ZHR ~\(JSFormat.number($0)). " } ?? ""
        let cutoff = JSFormat.number(MeteorShowers.radiantMinAltitudeDeg)
        if !a.observableHere {
            return [
                "\(zhr)Below horizon here — the radiant never clears \(cutoff)° during astronomical darkness.",
                active, e.notes,
            ].filter { !$0.isEmpty }.joined(separator: " ")
        }
        var parts = [zhr + nightVerdict(a.peakNight, fmt), active]
        if let better = a.betterNight {
            parts.append(
                "A better night inside the active range: \(fmt.date(better.eveningUtc)), "
                    + "\(better.usableMinutes) min moonless with the radiant up.")
        }
        if !e.notes.isEmpty { parts.append(e.notes) }
        return parts.joined(separator: " ")
    }

    static func nightVerdict(_ night: MeteorShowers.Night, _ fmt: SkyEventFormatters) -> String {
        let cutoff = JSFormat.number(MeteorShowers.radiantMinAltitudeDeg)
        guard let w = night.radiantWindow else {
            return "Radiant below \(cutoff)° all night on the peak night; try the neighbouring dates."
        }
        let highest = "Radiant up \(fmt.time(w.start))–\(fmt.time(w.end))"
            + (night.maxAltitudeAt.map { ", highest \(JSFormat.number(night.maxAltitudeDeg))° at \(fmt.time($0))" } ?? "")
        let moonPct = Int(jsRound(night.moonIllumFraction * 100))
        if night.usableMinutes == 0 {
            return "\(highest), but a \(moonPct)% moon is up throughout — nothing usable."
        }
        if isFullyMoonless(night) { return "\(highest), moonless." }
        let usable = night.usableWindows.map { "\(fmt.time($0.start))–\(fmt.time($0.end))" }.joined(separator: ", ")
        return "\(highest). \(moonPct)% moon in the way for part of it — usable \(usable)."
    }

    /// One usable window covering the radiant window to within a minute.
    public static func isFullyMoonless(_ night: MeteorShowers.Night) -> Bool {
        guard let w = night.radiantWindow, night.usableWindows.count == 1, let u = night.usableWindows.first else { return false }
        return JSTime.ms(u.start) <= JSTime.ms(w.start) + 60_000 && JSTime.ms(u.end) >= JSTime.ms(w.end) - 60_000
    }

    static func placeVerdict(_ e: CuratedEvent, _ km: Int?) -> String {
        guard let loc = e.location, let km else { return e.notes }
        return "\(loc.place) — \(km) km from here. \(e.notes)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SkyObject {
    /// astronomy-engine's body name ("Jupiter"), as the web app prints it.
    public var displayName: String {
        self == .galacticCenter ? "Galactic Center" : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// JavaScript number rendering, so verdict text matches the web app's.
enum JSFormat {
    /// `${n}`: integers without a decimal point, otherwise the shortest round-trip form.
    static func number(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v < 0 ? "-Infinity" : "Infinity" }
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return "\(v)"
    }

    /// `Number.prototype.toFixed`: rounds the exact binary value, ties away from zero.
    static func fixed(_ v: Double, _ digits: Int) -> String {
        if !v.isFinite { return number(v) }
        let negative = v < 0
        // The exact decimal expansion of the double (Darwin's printf is exact).
        let exact = String(format: "%.120f", abs(v))
        let dot = exact.firstIndex(of: ".")!
        var intDigits = Array(exact[..<dot]).map { Int($0.asciiValue! - 48) }
        let frac = Array(exact[exact.index(after: dot)...]).map { Int($0.asciiValue! - 48) }
        var kept = Array(frac.prefix(digits))
        let roundUp = frac.count > digits && frac[digits] >= 5
        if roundUp {
            var i = kept.count - 1
            var carry = 1
            while carry == 1 && i >= 0 {
                kept[i] += 1
                if kept[i] == 10 { kept[i] = 0; i -= 1 } else { carry = 0 }
            }
            if carry == 1 {
                var j = intDigits.count - 1
                while carry == 1 && j >= 0 {
                    intDigits[j] += 1
                    if intDigits[j] == 10 { intDigits[j] = 0; j -= 1 } else { carry = 0 }
                }
                if carry == 1 { intDigits.insert(1, at: 0) }
            }
        }
        var s = intDigits.map(String.init).joined()
        if digits > 0 { s += "." + kept.map(String.init).joined() }
        // JS keeps the sign of a negative value that rounds to zero ("-0.0").
        return (negative ? "-" : "") + s
    }
}
