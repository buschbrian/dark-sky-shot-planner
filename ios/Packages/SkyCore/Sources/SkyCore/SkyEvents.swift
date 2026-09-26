public import Foundation
import CAstronomy

/// Swift port of `app/src/astronomy/events.ts` (ADR-0008): what else is
/// happening in the sky around a night, from one spot. The TypeScript is the
/// reference; each step calls the same astronomy-engine function with the same
/// arguments and the same millisecond arithmetic, so the two agree on
/// `shared/golden/sky-events.json`. Change the TypeScript first, then mirror it.
///
/// Separations are geocentric only to find a lunar pass and to decide whether
/// an occultation is worth checking; everything reported is topocentric.
public enum SkyEvents {
    public static let defaultWindowDays = 30.0
    /// Moon's mean semidiameter: a geocentric minimum below this is an occultation somewhere on Earth.
    public static let occultationFlagDeg = 0.27
    /// Lunar semidiameter plus horizontal parallax: wider than this cannot occult from anywhere.
    public static let occultationCheckDeg = 1.3
    public static let pairingMaxSeparationDeg = 5.0
    public static let pairingMinAltitudeDeg = 5.0
    public static let pairingMaxSunAltitudeDeg = -6.0
    public static let zodiacalMaxMoonIllum = 0.15

    static let zodiacalOffsetHours = 1.0
    static let zodiacalAutumnMorningMonths = [8, 9, 10, 11]
    static let zodiacalSpringEveningMonths = [2, 3, 4]
    static let moonRadiusKm = 1737.4
    static let kmPerAU = 1.495978707e8
    static let passMaxGeocentricDeg = pairingMaxSeparationDeg + 1.5

    public static let oppositionBodies: [SkyObject] = [.mars, .jupiter, .saturn]
    public static let elongationBodies: [SkyObject] = [.mercury, .venus]
    public static let pairingBodies: [SkyObject] = [.mercury, .venus, .mars, .jupiter, .saturn]

    /// The window of `days` either side of an instant.
    public static func window(around centre: Date, days: Double = defaultWindowDays) -> TimeWindow {
        let c = JSTime.ms(centre)
        return TimeWindow(start: JSTime.date(c - days * JSTime.day), end: JSTime.date(c + days * JSTime.day))
    }

    /// The civil date a night belongs to, from longitude rather than any device zone.
    public static func siteCivilDate(_ when: Date, longitude: Double) -> (year: Int, month: Int, day: Int) {
        let shifted = JSTime.date(JSTime.ms(when) + (longitude / 15) * JSTime.hour)
        let c = JSTime.utcCalendar.dateComponents([.year, .month, .day], from: shifted)
        return (c.year!, c.month!, c.day!)
    }

    // MARK: separations and positions

    /// Angular separation (deg) between two equatorial coordinates.
    public static func angularSeparationDeg(ra1Hours: Double, dec1Deg: Double, ra2Hours: Double, dec2Deg: Double) -> Double {
        let a1 = ra1Hours * 15 * deg, d1 = dec1Deg * deg
        let a2 = ra2Hours * 15 * deg, d2 = dec2Deg * deg
        let c = sin(d1) * sin(d2) + cos(d1) * cos(d2) * cos(a1 - a2)
        return acos(min(1, max(-1, c))) / deg
    }

    /// Earth-centred separation: the number almanacs quote.
    public static func geocentricSeparationDeg(_ a: SkyObject, _ b: SkyObject, at when: Date) -> Double {
        angleBetween(geoVector(a, when), geoVector(b, when))
    }

    /// Observer-centred separation: what is seen from this spot.
    public static func topocentricSeparationDeg(_ site: Observer, _ a: SkyObject, _ b: SkyObject, at when: Date) -> Double {
        let ea = equator(a, when, site), eb = equator(b, when, site)
        return angularSeparationDeg(ra1Hours: ea.ra, dec1Deg: ea.dec, ra2Hours: eb.ra, dec2Deg: eb.dec)
    }

    /// Topocentric altitude (deg), refracted, of a solar-system body.
    public static func altitudeDeg(_ site: Observer, _ object: SkyObject, at when: Date) -> Double {
        let eq = equator(object, when, site)
        var time = AstroTime.from(when)
        return Astronomy_Horizon(&time, site.c, eq.ra, eq.dec, REFRACTION_NORMAL).altitude
    }

    /// Topocentric angular radius of the lunar disc (deg).
    public static func moonAngularRadiusDeg(_ site: Observer, at when: Date) -> Double {
        let eq = equator(.moon, when, site)
        return asin(moonRadiusKm / (eq.dist * kmPerAU)) / deg
    }

    public static func moonIllumination(at when: Date) -> Double {
        Astronomy_Illumination(BODY_MOON, AstroTime.from(when)).phase_fraction
    }

    // MARK: moon phases

    public struct MoonPhase: Sendable, Hashable {
        public let at: Date
        /// 0, 90, 180 or 270.
        public let angle: Int
        public var name: String { Self.names[angle] ?? "" }

        static let names = [0: "New Moon", 90: "First Quarter", 180: "Full Moon", 270: "Last Quarter"]
    }

    /// Every quarter-phase instant inside the window.
    public static func moonPhases(_ window: TimeWindow) -> [MoonPhase] {
        var out: [MoonPhase] = []
        let startMs = JSTime.ms(window.start), endMs = JSTime.ms(window.end)
        let spanDays = (endMs - startMs) / JSTime.day + 1
        for angle in [0, 90, 180, 270] {
            var cursor = window.start
            for _ in 0..<(Int(ceil(spanDays / 25)) + 2) {
                let r = Astronomy_SearchMoonPhase(Double(angle), AstroTime.from(cursor), spanDays)
                guard r.status == ASTRO_SUCCESS else { break }
                let at = AstroTime.date(r.time)
                if at > window.end { break }
                if at >= window.start { out.append(MoonPhase(at: at, angle: angle)) }
                cursor = JSTime.date(JSTime.ms(at) + JSTime.day)
            }
        }
        return out.stableSorted { $0.at < $1.at }
    }

    // MARK: planet apparitions

    public struct PlanetApparition: Sendable, Hashable {
        public enum Kind: String, Sendable { case opposition, greatestElongation = "greatest_elongation" }
        public enum Side: String, Sendable { case morning, evening }
        public let at: Date
        public let body: SkyObject
        public let kind: Kind
        /// Greatest elongation only: degrees from the Sun, rounded to 0.1.
        public let elongationDeg: Double?
        public let visibility: Side?
    }

    /// Oppositions of Mars, Jupiter and Saturn inside the window.
    public static func planetOppositions(_ window: TimeWindow) -> [PlanetApparition] {
        var out: [PlanetApparition] = []
        for object in oppositionBodies {
            let r = Astronomy_SearchRelativeLongitude(object.body!, 0, AstroTime.from(window.start))
            guard r.status == ASTRO_SUCCESS else { continue }
            let at = AstroTime.date(r.time)
            if at >= window.start && at <= window.end {
                out.append(PlanetApparition(at: at, body: object, kind: .opposition, elongationDeg: nil, visibility: nil))
            }
        }
        return out.stableSorted { $0.at < $1.at }
    }

    /// Greatest elongations of Mercury and Venus inside the window.
    public static func greatestElongations(_ window: TimeWindow) -> [PlanetApparition] {
        var out: [PlanetApparition] = []
        for object in elongationBodies {
            var cursor = window.start
            for _ in 0..<6 {
                let e = Astronomy_SearchMaxElongation(object.body!, AstroTime.from(cursor))
                guard e.status == ASTRO_SUCCESS else { break }
                let at = AstroTime.date(e.time)
                if at > window.end { break }
                if at >= window.start {
                    out.append(PlanetApparition(
                        at: at, body: object, kind: .greatestElongation,
                        elongationDeg: jsRound(e.elongation * 10) / 10,
                        visibility: e.visibility == VISIBLE_MORNING ? .morning : .evening))
                }
                cursor = JSTime.date(JSTime.ms(at) + 10 * JSTime.day)
            }
        }
        return out.stableSorted { $0.at < $1.at }
    }

    // MARK: moon–planet pairings

    public struct OccultationFromHere: Sendable, Hashable {
        public let minSeparationDeg: Double
        public let minSeparationAt: Date
        public let moonRadiusDeg: Double
        /// Negative: the minimum happens with the Moon below the horizon.
        public let moonAltitudeDeg: Double
        /// Above −6°: a bright sky.
        public let sunAltitudeDeg: Double
        public let behindDiscFromHere: Bool
        public let disappearsAt: Date?
        public let reappearsAt: Date?
        public let reappearMoonAltitudeDeg: Double?
    }

    public struct MoonPairing: Sendable, Hashable {
        public let body: SkyObject
        /// Closest observable approach of this pass (both > 5° up, sun < −6°), or
        /// the topocentric occultation minimum when nothing was observable.
        public let at: Date
        /// Topocentric separation at `at`.
        public let separationDeg: Double
        public let observableHere: Bool
        public let moonAltitudeDeg: Double
        public let bodyAltitudeDeg: Double
        public let moonIllumFraction: Double
        /// The almanac figure for the same pass, for reference only.
        public let geocentricMinDeg: Double
        public let geocentricMinAt: Date
        public let possibleOccultation: Bool
        public let occultation: OccultationFromHere?
    }

    /// Moon–planet approaches, one per lunar pass per planet.
    public static func moonPlanetPairings(_ site: Observer, _ window: TimeWindow) -> [MoonPairing] {
        var hours: [Date] = []
        var t = JSTime.ms(window.start)
        let endMs = JSTime.ms(window.end)
        while t <= endMs { hours.append(JSTime.date(t)); t += JSTime.hour }
        let moonTrack = hours.map { geoVector(.moon, $0) }
        var out: [MoonPairing] = []
        for object in pairingBodies {
            for pass in lunarPasses(object, hours, moonTrack) {
                if let p = pairingForPass(site, window, object, pass) { out.append(p) }
            }
        }
        return out.stableSorted { $0.at < $1.at }
    }

    struct HourSample { let at: Date; let geoSep: Double }

    static func lunarPasses(_ object: SkyObject, _ hours: [Date], _ moonTrack: [Vec]) -> [[HourSample]] {
        var passes: [[HourSample]] = []
        var open = false
        let planetTrack = slowTrack(object, hours)
        for (i, at) in hours.enumerated() {
            let geoSep = angleBetween(moonTrack[i], planetTrack[i])
            if geoSep > passMaxGeocentricDeg { open = false; continue }
            if !open { passes.append([]); open = true }
            passes[passes.count - 1].append(HourSample(at: at, geoSep: geoSep))
        }
        return passes
    }

    /// Exact every 6 h, linear between: only pass detection uses it.
    static func slowTrack(_ object: SkyObject, _ hours: [Date]) -> [Vec] {
        let stride = 6
        var exact: [Int: Vec] = [:]
        func at(_ i: Int) -> Vec {
            let k = min(i, hours.count - 1)
            if let v = exact[k] { return v }
            let v = geoVector(object, hours[k])
            exact[k] = v
            return v
        }
        return hours.indices.map { i in
            let i0 = i - i % stride
            let i1 = min(i0 + stride, hours.count - 1)
            if i == i0 || i1 == i0 { return at(i) }
            let a = at(i0), b = at(i1)
            let f = Double(i - i0) / Double(i1 - i0)
            return Vec(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, z: a.z + (b.z - a.z) * f)
        }
    }

    static func pairingForPass(_ site: Observer, _ window: TimeWindow, _ object: SkyObject, _ pass: [HourSample]) -> MoonPairing? {
        var closest = pass[0]
        for s in pass where s.geoSep < closest.geoSep { closest = s }
        let geoMin = refineGeocentricMinimum(object, around: closest.at, window)
        let possibleOccultation = geoMin.sep < occultationCheckDeg
        let occultation = possibleOccultation ? occultationFromHere(site, object, around: geoMin.at) : nil

        var bestVisible: (at: Date, sep: Double)?
        for s in pass {
            guard let sep = visibleTopocentricSeparation(site, object, s.at) else { continue }
            if bestVisible == nil || sep < bestVisible!.sep { bestVisible = (s.at, sep) }
        }

        func make(at: Date, separation: Double, observable: Bool) -> MoonPairing {
            MoonPairing(
                body: object, at: at, separationDeg: separation, observableHere: observable,
                moonAltitudeDeg: round1(altitudeDeg(site, .moon, at: at)),
                bodyAltitudeDeg: round1(altitudeDeg(site, object, at: at)),
                moonIllumFraction: round3(moonIllumination(at: at)),
                geocentricMinDeg: round3(geoMin.sep), geocentricMinAt: geoMin.at,
                possibleOccultation: possibleOccultation, occultation: occultation)
        }

        if let bestVisible {
            let refined = refineVisibleMinimum(site, object, around: bestVisible, window)
            return make(at: refined.at, separation: round3(refined.sep), observable: true)
        }
        guard let occultation else { return nil }
        if !occultationAboveHorizon(site, occultation) && geoMin.sep >= occultationFlagDeg { return nil }
        return make(at: occultation.minSeparationAt, separation: occultation.minSeparationDeg, observable: false)
    }

    static func occultationAboveHorizon(_ site: Observer, _ occ: OccultationFromHere) -> Bool {
        if !occ.behindDiscFromHere { return false }
        if occ.moonAltitudeDeg >= 0 { return true }
        if let r = occ.reappearMoonAltitudeDeg, r >= 0 { return true }
        guard let d = occ.disappearsAt else { return false }
        return altitudeDeg(site, .moon, at: d) >= 0
    }

    static func visibleTopocentricSeparation(_ site: Observer, _ object: SkyObject, _ when: Date) -> Double? {
        guard observable(site, object, when) else { return nil }
        let sep = topocentricSeparationDeg(site, .moon, object, at: when)
        return sep <= pairingMaxSeparationDeg ? sep : nil
    }

    static func observable(_ site: Observer, _ object: SkyObject, _ when: Date) -> Bool {
        if altitudeDeg(site, .sun, at: when) >= pairingMaxSunAltitudeDeg { return false }
        if altitudeDeg(site, .moon, at: when) <= pairingMinAltitudeDeg { return false }
        return altitudeDeg(site, object, at: when) > pairingMinAltitudeDeg
    }

    /// Ternary search to the minute over ±1 h (JS `new Date(t)` truncates, so do we).
    static func refineGeocentricMinimum(_ object: SkyObject, around: Date, _ window: TimeWindow) -> (at: Date, sep: Double) {
        func sepAt(_ t: Double) -> Double { geocentricSeparationDeg(.moon, object, at: JSTime.date(t)) }
        let a = JSTime.ms(around)
        var lo = max(JSTime.ms(window.start), a - JSTime.hour)
        var hi = min(JSTime.ms(window.end), a + JSTime.hour)
        while hi - lo > 60_000 {
            let m1 = lo + (hi - lo) / 3
            let m2 = hi - (hi - lo) / 3
            if sepAt(m1) < sepAt(m2) { hi = m2 } else { lo = m1 }
        }
        let at = JSTime.date(jsRound((lo + hi) / 2 / 60_000) * 60_000)
        return (at, sepAt(JSTime.ms(at)))
    }

    static func refineVisibleMinimum(
        _ site: Observer, _ object: SkyObject, around: (at: Date, sep: Double), _ window: TimeWindow
    ) -> (at: Date, sep: Double) {
        func scan(_ centre: Date, _ half: Double, _ step: Double, _ start: (at: Date, sep: Double)) -> (at: Date, sep: Double) {
            var best = start
            let c = JSTime.ms(centre)
            let from = max(JSTime.ms(window.start), c - half)
            let to = min(JSTime.ms(window.end), c + half)
            var t = from
            while t <= to {
                let when = JSTime.date(t)
                if let sep = visibleTopocentricSeparation(site, object, when), sep < best.sep { best = (when, sep) }
                t += step
            }
            return best
        }
        let coarse = scan(around.at, JSTime.hour, 5 * 60_000, around)
        return scan(coarse.at, 5 * 60_000, 60_000, coarse)
    }

    /// Minute scan across ±3 h of the geocentric minimum: is the planet behind
    /// the disc from here, and when does it come back out?
    public static func occultationFromHere(_ site: Observer, _ object: SkyObject, around: Date) -> OccultationFromHere {
        let a = JSTime.ms(around)
        var best: (at: Date, sep: Double, radius: Double)?
        var disappearsAt: Date?, reappearsAt: Date?
        var inside = false
        var t = a - 3 * JSTime.hour
        while t <= a + 3 * JSTime.hour {
            let when = JSTime.date(t)
            let moon = equator(.moon, when, site), planet = equator(object, when, site)
            let sep = angularSeparationDeg(ra1Hours: moon.ra, dec1Deg: moon.dec, ra2Hours: planet.ra, dec2Deg: planet.dec)
            let radius = asin(moonRadiusKm / (moon.dist * kmPerAU)) / deg
            if best == nil || sep < best!.sep { best = (when, sep, radius) }
            let hidden = sep < radius
            if hidden && !inside { disappearsAt = when; inside = true }
            else if !hidden && inside { reappearsAt = when; inside = false }
            t += 60_000
        }
        let at = best?.at ?? around
        return OccultationFromHere(
            minSeparationDeg: round3(best?.sep ?? .nan),
            minSeparationAt: at,
            moonRadiusDeg: round3(best?.radius ?? .nan),
            moonAltitudeDeg: round1(altitudeDeg(site, .moon, at: at)),
            sunAltitudeDeg: round1(altitudeDeg(site, .sun, at: at)),
            behindDiscFromHere: disappearsAt != nil,
            disappearsAt: disappearsAt,
            reappearsAt: reappearsAt,
            reappearMoonAltitudeDeg: reappearsAt.map { round1(altitudeDeg(site, .moon, at: $0)) })
    }

    // MARK: zodiacal light

    public enum ZodiacalSeason: String, Sendable { case autumnMorning = "autumn_morning", springEvening = "spring_evening" }

    public struct ZodiacalRange: Sendable, Hashable {
        public let season: ZodiacalSeason
        /// First and last qualifying observing instant (dawn − 1 h / dusk + 1 h).
        public var start: Date
        public var end: Date
        public var nights: Int
    }

    /// Northern-hemisphere zodiacal-light nights with the Moon out of the way,
    /// collapsed into ranges. Returns nothing south of the equator (ADR-0008 §5).
    public static func zodiacalLightRanges(_ site: Observer, _ window: TimeWindow) -> [ZodiacalRange] {
        if site.latitude <= 0 { return [] }
        let morning = collapse(qualifyingNights(site, window, .autumnMorning), .autumnMorning)
        let evening = collapse(qualifyingNights(site, window, .springEvening), .springEvening)
        return (morning + evening).stableSorted { $0.start < $1.start }
    }

    static func qualifyingNights(_ site: Observer, _ window: TimeWindow, _ season: ZodiacalSeason) -> [Date] {
        let direction = season == .autumnMorning ? DIRECTION_RISE : DIRECTION_SET
        let months = season == .autumnMorning ? zodiacalAutumnMorningMonths : zodiacalSpringEveningMonths
        let offset = (season == .autumnMorning ? -1.0 : 1.0) * zodiacalOffsetHours * JSTime.hour
        var nights: [Date] = []
        var cursor = window.start
        let spanDays = (JSTime.ms(window.end) - JSTime.ms(window.start)) / JSTime.day
        for _ in 0..<Int(ceil(spanDays + 4)) {
            let r = Astronomy_SearchAltitude(BODY_SUN, site.c, direction, AstroTime.from(cursor), 2, -18)
            guard r.status == ASTRO_SUCCESS else {
                cursor = JSTime.date(JSTime.ms(cursor) + JSTime.day)
                if cursor > window.end { break }
                continue
            }
            let edge = AstroTime.date(r.time)
            if edge > window.end { break }
            cursor = JSTime.date(JSTime.ms(edge) + 6 * JSTime.hour)
            if !months.contains(siteCivilDate(edge, longitude: site.longitude).month) { continue }
            let sample = JSTime.date(JSTime.ms(edge) + offset)
            if moonSpoils(site, sample) { continue }
            nights.append(sample)
        }
        return nights
    }

    static func moonSpoils(_ site: Observer, _ when: Date) -> Bool {
        if altitudeDeg(site, .moon, at: when) <= 0 { return false }
        return moonIllumination(at: when) >= zodiacalMaxMoonIllum
    }

    static func collapse(_ nights: [Date], _ season: ZodiacalSeason) -> [ZodiacalRange] {
        var out: [ZodiacalRange] = []
        for night in nights {
            if let last = out.last, JSTime.ms(night) - JSTime.ms(last.end) <= 36 * JSTime.hour {
                out[out.count - 1].end = night
                out[out.count - 1].nights += 1
            } else {
                out.append(ZodiacalRange(season: season, start: night, end: night, nights: 1))
            }
        }
        return out
    }

    // MARK: seasons

    public struct SeasonMarker: Sendable, Hashable {
        public let at: Date
        public let name: String
    }

    /// Equinoxes and solstices inside the window.
    public static func seasonMarkers(_ window: TimeWindow) -> [SeasonMarker] {
        var out: [SeasonMarker] = []
        let first = JSTime.utcCalendar.component(.year, from: window.start)
        let last = JSTime.utcCalendar.component(.year, from: window.end)
        for year in first...last {
            let s = Astronomy_Seasons(Int32(year))
            guard s.status == ASTRO_SUCCESS else { continue }
            for (time, name) in [
                (s.mar_equinox, "March equinox"), (s.jun_solstice, "June solstice"),
                (s.sep_equinox, "September equinox"), (s.dec_solstice, "December solstice"),
            ] {
                let at = AstroTime.date(time)
                if at >= window.start && at <= window.end { out.append(SeasonMarker(at: at, name: name)) }
            }
        }
        return out.stableSorted { $0.at < $1.at }
    }

    // MARK: eclipses (ADR-0008 §6)

    public enum EclipseKind: String, Sendable, Hashable {
        case penumbral, partial, annular, total

        init?(_ k: astro_eclipse_kind_t) {
            switch k {
            case ECLIPSE_PENUMBRAL: self = .penumbral
            case ECLIPSE_PARTIAL: self = .partial
            case ECLIPSE_ANNULAR: self = .annular
            case ECLIPSE_TOTAL: self = .total
            default: return nil
            }
        }

        public var capitalised: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    public struct LunarEclipse: Sendable, Hashable {
        public let kind: EclipseKind
        public let peak: Date
        /// Fraction of the lunar disc in the umbra at peak (0 for penumbral).
        public let obscuration: Double
        public let penumbralBegin: Date
        public let penumbralEnd: Date
        public let partialBegin: Date?
        public let partialEnd: Date?
        public let totalBegin: Date?
        public let totalEnd: Date?
        /// Moon altitude here at peak and at both ends of the main (umbral, else penumbral) phase.
        public let moonAltitudeAtPeakDeg: Double
        public let moonAltitudeAtBeginDeg: Double
        public let moonAltitudeAtEndDeg: Double
    }

    /// Lunar eclipses peaking inside the window, judged by the Moon's altitude here.
    public static func lunarEclipses(_ site: Observer, _ window: TimeWindow) -> [LunarEclipse] {
        var out: [LunarEclipse] = []
        var e = Astronomy_SearchLunarEclipse(AstroTime.from(window.start))
        for _ in 0..<6 {
            guard e.status == ASTRO_SUCCESS, let kind = EclipseKind(e.kind) else { break }
            let peak = AstroTime.date(e.peak)
            if peak > window.end { break }
            let peakMs = JSTime.ms(peak)
            func at(_ minutes: Double) -> Date { JSTime.date(peakMs + minutes * 60_000) }
            let main = e.sd_partial > 0 ? e.sd_partial : e.sd_penum
            out.append(LunarEclipse(
                kind: kind, peak: peak, obscuration: round3(e.obscuration),
                penumbralBegin: at(-e.sd_penum), penumbralEnd: at(e.sd_penum),
                partialBegin: e.sd_partial > 0 ? at(-e.sd_partial) : nil,
                partialEnd: e.sd_partial > 0 ? at(e.sd_partial) : nil,
                totalBegin: e.sd_total > 0 ? at(-e.sd_total) : nil,
                totalEnd: e.sd_total > 0 ? at(e.sd_total) : nil,
                moonAltitudeAtPeakDeg: round1(altitudeDeg(site, .moon, at: peak)),
                moonAltitudeAtBeginDeg: round1(altitudeDeg(site, .moon, at: at(-main))),
                moonAltitudeAtEndDeg: round1(altitudeDeg(site, .moon, at: at(main)))))
            e = Astronomy_NextLunarEclipse(e.peak)
        }
        return out
    }

    /// Grazing partial eclipses covering less than this are not listed.
    public static let solarEclipseMinObscuration = 0.01

    public struct SolarEclipse: Sendable, Hashable {
        /// What this observer sees.
        public let kind: EclipseKind
        public let obscuration: Double
        public let begin: Date
        public let peak: Date
        public let end: Date
        public let sunAltitudeAtBeginDeg: Double
        public let sunAltitudeAtPeakDeg: Double
        public let sunAltitudeAtEndDeg: Double
    }

    /// Solar eclipses seen from here with the Sun up for part of them.
    public static func solarEclipses(_ site: Observer, _ window: TimeWindow) -> [SolarEclipse] {
        var out: [SolarEclipse] = []
        var e = Astronomy_SearchLocalSolarEclipse(AstroTime.from(window.start), site.c)
        for _ in 0..<6 {
            guard e.status == ASTRO_SUCCESS, let kind = EclipseKind(e.kind) else { break }
            let peak = AstroTime.date(e.peak.time)
            if peak > window.end { break }
            let visible = e.partial_begin.altitude > 0 || e.peak.altitude > 0 || e.partial_end.altitude > 0
            if visible && e.obscuration >= solarEclipseMinObscuration {
                out.append(SolarEclipse(
                    kind: kind, obscuration: round3(e.obscuration),
                    begin: AstroTime.date(e.partial_begin.time), peak: peak, end: AstroTime.date(e.partial_end.time),
                    sunAltitudeAtBeginDeg: round1(e.partial_begin.altitude),
                    sunAltitudeAtPeakDeg: round1(e.peak.altitude),
                    sunAltitudeAtEndDeg: round1(e.partial_end.altitude)))
            }
            e = Astronomy_NextLocalSolarEclipse(e.peak.time, site.c)
        }
        return out
    }

    // MARK: supermoons

    /// A full moon closer than this (geocentric km) is a supermoon (ADR-0008 §6).
    public static let supermoonMaxDistanceKm = 360_000.0
    public static let moonMeanDistanceKm = 384_400.0

    public struct Supermoon: Sendable, Hashable {
        public let at: Date
        public let distanceKm: Int
        /// Apparent diameter and brightness against a full moon at the mean distance.
        public let sizeRatio: Double
        public let brightnessRatio: Double
    }

    public static func supermoons(_ window: TimeWindow) -> [Supermoon] {
        moonPhases(window).filter { $0.angle == 180 }.compactMap { p in
            let v = Astronomy_GeoMoon(AstroTime.from(p.at))
            let km = jsRound((v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() * kmPerAU)
            guard km <= supermoonMaxDistanceKm else { return nil }
            let size = moonMeanDistanceKm / km
            return Supermoon(at: p.at, distanceKm: Int(km), sizeRatio: round3(size), brightnessRatio: round3(size * size))
        }
    }

    // MARK: Milky Way core season

    public struct CoreNight: Sendable, Hashable {
        public let eveningUtc: Date
        /// Highest GC altitude in astronomical darkness, Moon ignored (0.1°).
        public let maxAltitudeDeg: Double
        public let maxAltitudeAt: Date
    }

    public struct CoreSeasonRange: Sendable, Hashable {
        public var first: CoreNight
        public var last: CoreNight
        public var nights: Int
        /// The night before `first` was scanned and did not qualify.
        public var opens: Bool
        /// The night after `last` was scanned and did not qualify.
        public var closes: Bool
    }

    /// Nights the GC clears `minAltitudeDeg` in astronomical darkness, whatever
    /// the Moon does, stepped a day at a time from the window's first evening.
    public static func coreSeasonRanges(_ site: Observer, _ window: TimeWindow, minAltitudeDeg: Double) throws(AstronomyError) -> [CoreSeasonRange] {
        let seaLevel = (try? Observer(latitude: site.latitude, longitude: site.longitude)) ?? site
        var out: [CoreSeasonRange] = []
        var isOpen = false
        var scannedBefore = false
        var t = JSTime.ms(window.start)
        let endMs = JSTime.ms(window.end)
        while t <= endMs {
            let evening = JSTime.date(t)
            var night: CoreNight?
            if let dark = try Planner.darknessWindow(seaLevel, evening: evening).window {
                let gc = Planner.gcVisibility(
                    seaLevel, moonFree: [MoonFreeWindow(start: dark.start, end: dark.end, minutes: 0)])
                if let alt = gc.maxAltitudeDeg, let at = gc.maxAltitudeAt, alt >= minAltitudeDeg {
                    night = CoreNight(eveningUtc: evening, maxAltitudeDeg: alt, maxAltitudeAt: at)
                }
            }
            if let night {
                if isOpen {
                    out[out.count - 1].last = night
                    out[out.count - 1].nights += 1
                } else {
                    out.append(CoreSeasonRange(first: night, last: night, nights: 1, opens: scannedBefore, closes: false))
                    isOpen = true
                }
            } else if isOpen {
                out[out.count - 1].closes = true
                isOpen = false
            }
            scannedBefore = true
            t += JSTime.day
        }
        return out
    }

    // MARK: internals

    static let deg = Double.pi / 180
    /// astronomy-engine JS `RAD2DEG`.
    static let rad2deg = 57.295779513082321

    struct Vec { let x, y, z: Double }

    static func geoVector(_ object: SkyObject, _ when: Date) -> Vec {
        let v = Astronomy_GeoVector(object.body!, AstroTime.from(when), ABERRATION)
        return Vec(x: v.x, y: v.y, z: v.z)
    }

    /// astronomy-engine JS `AngleBetween`, operation for operation.
    static func angleBetween(_ a: Vec, _ b: Vec) -> Double {
        let aa = a.x * a.x + a.y * a.y + a.z * a.z
        let bb = b.x * b.x + b.y * b.y + b.z * b.z
        let dot = (a.x * b.x + a.y * b.y + a.z * b.z) / (aa * bb).squareRoot()
        if dot <= -1 { return 180 }
        if dot >= 1 { return 0 }
        return rad2deg * acos(dot)
    }

    static func equator(_ object: SkyObject, _ when: Date, _ site: Observer) -> astro_equatorial_t {
        var time = AstroTime.from(when)
        return Astronomy_Equator(object.body!, &time, site.c, EQUATOR_OF_DATE, ABERRATION)
    }
}

func round1(_ v: Double) -> Double { jsRound(v * 10) / 10 }
func round3(_ v: Double) -> Double { jsRound(v * 1000) / 1000 }

/// JavaScript `Date` arithmetic: instants are whole milliseconds and
/// `new Date(x)` truncates a fractional `x` toward zero.
enum JSTime {
    static let hour = 3_600_000.0
    static let day = 86_400_000.0

    static func ms(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }
    static func date(_ ms: Double) -> Date { AstroTime.jsDate(ms: ms) }

    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}

extension Array {
    /// `Array.prototype.sort` is stable; Swift's `sorted` does not promise it.
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
