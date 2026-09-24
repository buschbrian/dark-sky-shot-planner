/**
 * Sky events around a chosen night: what else is happening in the sky near
 * this date, from this spot. Pure functions — location and a time window in,
 * numbers out. astronomy-engine only, no network, no API (ADR-0002).
 *
 * Everything here is *computed*; the hand-curated companion list (meteor
 * showers, festivals) lives in `config/sky-events.json` and is evaluated in
 * `showers.ts`. The split and its reasoning are ADR-0008.
 *
 * Two separations are used deliberately and are not interchangeable:
 *
 * - **Geocentric** — the number almanacs quote for a conjunction. Used only to
 *   find each lunar pass and to decide whether an occultation is worth checking;
 *   it is carried on the result but never printed as if it were local.
 * - **Topocentric** — what you actually see from one spot. Lunar parallax is
 *   up to ~1°, which is the whole difference between "close pairing" and
 *   "the planet is behind the Moon from here", so the displayed separation and
 *   the occultation test are both topocentric.
 */

import * as Astronomy from "astronomy-engine";

/** Half-width of the default window around the selected date, in days. */
export const DEFAULT_WINDOW_DAYS = 30;

/**
 * Moon's mean angular semidiameter (deg). A geocentric minimum below this means
 * the planet is behind the disc for observers near the sub-lunar point, so an
 * occultation happens *somewhere* on Earth.
 */
export const OCCULTATION_FLAG_DEG = 0.27;

/**
 * Geocentric minimum below which the topocentric occultation check runs: the
 * lunar semidiameter (≤ 0.28°) plus horizontal parallax (≤ 1.02°). Anything
 * wider cannot put the planet behind the disc from any spot on Earth.
 */
export const OCCULTATION_CHECK_DEG = 1.3;

/** A pairing must be closer than this to be worth reporting. */
export const PAIRING_MAX_SEPARATION_DEG = 5;

/** Both bodies must clear this altitude for the pairing to be observable. */
export const PAIRING_MIN_ALTITUDE_DEG = 5;

/** Sun must be below this for the pairing to be seen against a dark-ish sky. */
export const PAIRING_MAX_SUN_ALTITUDE_DEG = -6;

/** Moon this thin does not spoil the zodiacal light. */
export const ZODIACAL_MAX_MOON_ILLUM = 0.15;

/** Zodiacal light is checked this long before dawn / after dusk. */
const ZODIACAL_OFFSET_HOURS = 1;

/** Northern-hemisphere seasons where the zodiacal light is worth chasing. */
const ZODIACAL_AUTUMN_MORNING_MONTHS = [8, 9, 10, 11];
const ZODIACAL_SPRING_EVENING_MONTHS = [2, 3, 4];

/** Mean lunar radius, km (IAU). */
const MOON_RADIUS_KM = 1737.4;
const KM_PER_AU = 1.495978707e8;

const DEG = Math.PI / 180;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

export interface Site {
  latitude: number;
  longitude: number;
  /** Metres above sea level; 0 when unknown. */
  elevationM?: number;
}

export interface TimeWindow {
  start: Date;
  end: Date;
}

/** Superior planets whose opposition is the event worth naming. */
export const OPPOSITION_BODIES = [
  Astronomy.Body.Mars,
  Astronomy.Body.Jupiter,
  Astronomy.Body.Saturn,
] as const;

/** Inferior planets: greatest elongation, not opposition. */
export const ELONGATION_BODIES = [Astronomy.Body.Mercury, Astronomy.Body.Venus] as const;

/** Planets checked for a close Moon pairing. */
export const PAIRING_BODIES = [
  Astronomy.Body.Mercury,
  Astronomy.Body.Venus,
  Astronomy.Body.Mars,
  Astronomy.Body.Jupiter,
  Astronomy.Body.Saturn,
] as const;

export function observerOf(site: Site): Astronomy.Observer {
  return new Astronomy.Observer(site.latitude, site.longitude, site.elevationM ?? 0);
}

/** The window of `days` either side of a UTC instant. */
export function windowAround(centre: Date, days = DEFAULT_WINDOW_DAYS): TimeWindow {
  return {
    start: new Date(centre.getTime() - days * DAY_MS),
    end: new Date(centre.getTime() + days * DAY_MS),
  };
}

function within(w: TimeWindow, t: Date): boolean {
  return t >= w.start && t <= w.end;
}

/**
 * The civil date a night belongs to, derived from longitude rather than the
 * browser's zone. Month gates and night grouping must not change depending on
 * where the *reader* is sitting, and a 4 a.m. instant belongs to the night
 * that started the evening before.
 */
export function siteCivilDate(when: Date, longitudeDeg: number): { year: number; month: number; day: number } {
  const shifted = new Date(when.getTime() + (longitudeDeg / 15) * HOUR_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

// ---------------------------------------------------------------- separations

/** Angular separation (deg) between two equatorial coordinates. */
export function angularSeparationDeg(
  raHours1: number,
  decDeg1: number,
  raHours2: number,
  decDeg2: number,
): number {
  const a1 = raHours1 * 15 * DEG;
  const d1 = decDeg1 * DEG;
  const a2 = raHours2 * 15 * DEG;
  const d2 = decDeg2 * DEG;
  const cos = Math.sin(d1) * Math.sin(d2) + Math.cos(d1) * Math.cos(d2) * Math.cos(a1 - a2);
  return Math.acos(Math.min(1, Math.max(-1, cos))) / DEG;
}

/** Earth-centred separation — the number published tables quote. */
export function geocentricSeparationDeg(
  a: Astronomy.Body,
  b: Astronomy.Body,
  when: Date,
): number {
  return Astronomy.AngleBetween(
    Astronomy.GeoVector(a, when, true),
    Astronomy.GeoVector(b, when, true),
  );
}

/** Observer-centred separation — what is actually seen from this spot. */
export function topocentricSeparationDeg(
  site: Site,
  a: Astronomy.Body,
  b: Astronomy.Body,
  when: Date,
): number {
  const obs = observerOf(site);
  const ea = Astronomy.Equator(a, when, obs, true, true);
  const eb = Astronomy.Equator(b, when, obs, true, true);
  return angularSeparationDeg(ea.ra, ea.dec, eb.ra, eb.dec);
}

/** Topocentric altitude (deg), refracted, of a solar-system body. */
export function altitudeDeg(site: Site, body: Astronomy.Body, when: Date): number {
  const obs = observerOf(site);
  const eq = Astronomy.Equator(body, when, obs, true, true);
  return Astronomy.Horizon(when, obs, eq.ra, eq.dec, "normal").altitude;
}

/** Topocentric angular radius of the lunar disc (deg) at this instant. */
export function moonAngularRadiusDeg(site: Site, when: Date): number {
  const obs = observerOf(site);
  const eq = Astronomy.Equator(Astronomy.Body.Moon, when, obs, true, true);
  return Math.asin(MOON_RADIUS_KM / (eq.dist * KM_PER_AU)) / DEG;
}

// --------------------------------------------------------------- moon phases

export type MoonPhaseAngle = 0 | 90 | 180 | 270;

export const MOON_PHASE_NAME: Record<MoonPhaseAngle, string> = {
  0: "New Moon",
  90: "First Quarter",
  180: "Full Moon",
  270: "Last Quarter",
};

export interface MoonPhaseEvent {
  at: Date;
  angle: MoonPhaseAngle;
  name: string;
}

/** Every quarter-phase instant inside the window. */
export function moonPhases(window: TimeWindow): MoonPhaseEvent[] {
  const out: MoonPhaseEvent[] = [];
  const spanDays = (window.end.getTime() - window.start.getTime()) / DAY_MS + 1;
  for (const angle of [0, 90, 180, 270] as MoonPhaseAngle[]) {
    let cursor = window.start;
    // A quarter phase repeats every ~29.53 d, so a 60-day window holds at most
    // three of any one phase; the guard is generous, not tuned.
    for (let guard = 0; guard < Math.ceil(spanDays / 25) + 2; guard++) {
      const found = Astronomy.SearchMoonPhase(angle, cursor, spanDays);
      if (!found) break;
      const at = found.date;
      if (at > window.end) break;
      if (at >= window.start) out.push({ at, angle, name: MOON_PHASE_NAME[angle] });
      cursor = new Date(at.getTime() + DAY_MS);
    }
  }
  return out.sort(byTime);
}

// -------------------------------------------------------- planet apparitions

export interface PlanetApparition {
  at: Date;
  body: Astronomy.Body;
  kind: "opposition" | "greatest_elongation";
  /** Greatest elongation only: angular distance from the Sun, degrees. */
  elongationDeg: number | null;
  /** Greatest elongation only: which end of the night it favours. */
  visibility: "morning" | "evening" | null;
}

/** Oppositions of Mars, Jupiter and Saturn falling inside the window. */
export function planetOppositions(window: TimeWindow): PlanetApparition[] {
  const out: PlanetApparition[] = [];
  for (const body of OPPOSITION_BODIES) {
    // Synodic periods here are all ≥ ~370 d, so the first hit after the window
    // opens is the only candidate.
    const found = Astronomy.SearchRelativeLongitude(body, 0, window.start);
    if (found && within(window, found.date)) {
      out.push({ at: found.date, body, kind: "opposition", elongationDeg: null, visibility: null });
    }
  }
  return out.sort(byTime);
}

/** Greatest elongations of Mercury and Venus inside the window. */
export function greatestElongations(window: TimeWindow): PlanetApparition[] {
  const out: PlanetApparition[] = [];
  for (const body of ELONGATION_BODIES) {
    let cursor = window.start;
    for (let guard = 0; guard < 6; guard++) {
      const evt = Astronomy.SearchMaxElongation(body, cursor);
      if (!evt || evt.time.date > window.end) break;
      if (evt.time.date >= window.start) {
        out.push({
          at: evt.time.date,
          body,
          kind: "greatest_elongation",
          elongationDeg: Math.round(evt.elongation * 10) / 10,
          visibility: evt.visibility === "morning" ? "morning" : "evening",
        });
      }
      cursor = new Date(evt.time.date.getTime() + 10 * DAY_MS);
    }
  }
  return out.sort(byTime);
}

// ------------------------------------------------------- moon–planet pairings

export interface OccultationFromHere {
  /** Minimum observer-centred separation over the approach, degrees. */
  minSeparationDeg: number;
  minSeparationAt: Date;
  /** Topocentric angular radius of the lunar disc at that minimum, degrees. */
  moonRadiusDeg: number;
  /** Moon altitude at that minimum — negative means it happens below the horizon. */
  moonAltitudeDeg: number;
  /** Sun altitude at that minimum; above −6° the event is in a bright sky. */
  sunAltitudeDeg: number;
  /** True when the planet passes behind the lunar disc as seen from here. */
  behindDiscFromHere: boolean;
  /** Disc ingress/egress, when they occur inside the scanned approach. */
  disappearsAt: Date | null;
  reappearsAt: Date | null;
  /** Moon altitude at egress; the reappearance is only watchable if this is > 0. */
  reappearMoonAltitudeDeg: number | null;
}

export interface MoonPairing {
  body: Astronomy.Body;
  /**
   * Closest *observable* approach of this pass: topocentric separation < 5°,
   * both bodies > 5° up, sun below −6°. When nothing in the pass is observable
   * but an occultation is in play, the topocentric minimum instead.
   */
  at: Date;
  /** Topocentric separation at `at` — what is seen from here at that instant. */
  separationDeg: number;
  /** True when `at` passed the observability gate (the first case above). */
  observableHere: boolean;
  moonAltitudeDeg: number;
  bodyAltitudeDeg: number;
  moonIllumFraction: number;
  /** Geocentric minimum of this same pass (the almanac figure), kept for reference. */
  geocentricMinDeg: number;
  geocentricMinAt: Date;
  /** Geocentric minimum below `OCCULTATION_CHECK_DEG`: the occultation check ran. */
  possibleOccultation: boolean;
  /** Only computed when `possibleOccultation`; always for this same pass. */
  occultation: OccultationFromHere | null;
}

/** Hourly geocentric samples closer than this belong to one lunar pass. */
const PASS_MAX_GEOCENTRIC_DEG = PAIRING_MAX_SEPARATION_DEG + 1.5;

/**
 * Moon–planet approaches inside the window, one per lunar pass per planet.
 *
 * An hourly geocentric scan splits the window into passes (the Moon sweeps
 * past each planet roughly monthly, so a 61-day window can hold two). Within
 * each pass the observable approach is judged at the observer: the topocentric
 * separation, with both bodies above 5° and the sun below −6°. The occultation
 * check is bound to that same pass, so an item never carries another
 * conjunction's occultation.
 */
export function moonPlanetPairings(site: Site, window: TimeWindow): MoonPairing[] {
  const out: MoonPairing[] = [];
  // The Moon's position is the expensive half of every separation; compute the
  // hourly track once and share it across the planets.
  const hours: Date[] = [];
  for (let t = window.start.getTime(); t <= window.end.getTime(); t += HOUR_MS) hours.push(new Date(t));
  const moonTrack = hours.map((at) => Astronomy.GeoVector(Astronomy.Body.Moon, at, true));
  for (const body of PAIRING_BODIES) {
    for (const pass of lunarPasses(body, hours, moonTrack)) {
      const pairing = pairingForPass(site, window, body, pass);
      if (pairing) out.push(pairing);
    }
  }
  return out.sort(byTime);
}

interface HourSample {
  at: Date;
  geoSep: number;
}

/** Runs of consecutive hourly samples with the Moon near the planet. */
function lunarPasses(
  body: Astronomy.Body,
  hours: Date[],
  moonTrack: Astronomy.Vector[],
): HourSample[][] {
  const passes: HourSample[][] = [];
  let current: HourSample[] | null = null;
  const planetTrack = slowTrack(body, hours);
  for (const [i, at] of hours.entries()) {
    const geoSep = Astronomy.AngleBetween(moonTrack[i]!, planetTrack[i]!);
    if (geoSep > PASS_MAX_GEOCENTRIC_DEG) {
      current = null;
      continue;
    }
    if (!current) {
      current = [];
      passes.push(current);
    }
    current.push({ at, geoSep });
  }
  return passes;
}

/**
 * A planet's geocentric direction changes by at most a few degrees a day, so
 * over six hours a straight line between two exact positions is off by far
 * less than the pass margin. Only pass *detection* uses this; every reported
 * number is computed exactly.
 */
function slowTrack(body: Astronomy.Body, hours: Date[]): Astronomy.Vector[] {
  const STRIDE = 6;
  const exact = new Map<number, Astronomy.Vector>();
  const at = (i: number): Astronomy.Vector => {
    const k = Math.min(i, hours.length - 1);
    let v = exact.get(k);
    if (!v) {
      v = Astronomy.GeoVector(body, hours[k]!, true);
      exact.set(k, v);
    }
    return v;
  };
  return hours.map((when, i) => {
    const i0 = i - (i % STRIDE);
    const i1 = Math.min(i0 + STRIDE, hours.length - 1);
    if (i === i0 || i1 === i0) return at(i);
    const a = at(i0);
    const b = at(i1);
    const f = (i - i0) / (i1 - i0);
    return new Astronomy.Vector(
      a.x + (b.x - a.x) * f,
      a.y + (b.y - a.y) * f,
      a.z + (b.z - a.z) * f,
      new Astronomy.AstroTime(when),
    );
  });
}

function pairingForPass(
  site: Site,
  window: TimeWindow,
  body: Astronomy.Body,
  pass: HourSample[],
): MoonPairing | null {
  let closest = pass[0]!;
  for (const s of pass) if (s.geoSep < closest.geoSep) closest = s;
  const geoMin = refineGeocentricMinimum(body, closest.at, window);
  const possibleOccultation = geoMin.sep < OCCULTATION_CHECK_DEG;
  const occultation = possibleOccultation ? occultationFromHere(site, body, geoMin.at) : null;

  // Altitude work is comparatively expensive; only pay for it inside the pass.
  let bestVisible: { at: Date; sep: number } | null = null;
  for (const s of pass) {
    const sep = visibleTopocentricSeparation(site, body, s.at);
    if (sep === null) continue;
    if (!bestVisible || sep < bestVisible.sep) bestVisible = { at: s.at, sep };
  }

  const base = {
    body,
    geocentricMinDeg: round3(geoMin.sep),
    geocentricMinAt: geoMin.at,
    possibleOccultation,
    occultation,
  };

  if (bestVisible) {
    const refined = refineVisibleMinimum(site, body, bestVisible, window);
    return {
      ...base,
      ...describeAt(site, body, refined.at),
      separationDeg: round3(refined.sep),
      observableHere: true,
    };
  }

  // Nothing observable from here in this pass. Still worth a line when some
  // part of an occultation happens with the Moon up here, or when one happens
  // somewhere on Earth and the useful answer is "not from here".
  if (!occultation) return null;
  if (!occultationAboveHorizon(site, occultation) && geoMin.sep >= OCCULTATION_FLAG_DEG) {
    return null;
  }
  return {
    ...base,
    ...describeAt(site, body, occultation.minSeparationAt),
    separationDeg: occultation.minSeparationDeg,
    observableHere: false,
  };
}

/** Behind the disc from here with the Moon above the horizon at some contact. */
function occultationAboveHorizon(site: Site, occ: OccultationFromHere): boolean {
  if (!occ.behindDiscFromHere) return false;
  if (occ.moonAltitudeDeg >= 0) return true;
  if (occ.reappearMoonAltitudeDeg !== null && occ.reappearMoonAltitudeDeg >= 0) return true;
  return occ.disappearsAt !== null && altitudeDeg(site, Astronomy.Body.Moon, occ.disappearsAt) >= 0;
}

function describeAt(
  site: Site,
  body: Astronomy.Body,
  at: Date,
): { at: Date; moonAltitudeDeg: number; bodyAltitudeDeg: number; moonIllumFraction: number } {
  return {
    at,
    moonAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Moon, at)),
    bodyAltitudeDeg: round1(altitudeDeg(site, body, at)),
    moonIllumFraction: round3(Astronomy.Illumination(Astronomy.Body.Moon, at).phase_fraction),
  };
}

/** Topocentric separation when the pair is observable and within 5°, else null. */
function visibleTopocentricSeparation(
  site: Site,
  body: Astronomy.Body,
  when: Date,
): number | null {
  if (!observable(site, body, when)) return null;
  const sep = topocentricSeparationDeg(site, Astronomy.Body.Moon, body, when);
  return sep <= PAIRING_MAX_SEPARATION_DEG ? sep : null;
}

function observable(site: Site, body: Astronomy.Body, when: Date): boolean {
  if (altitudeDeg(site, Astronomy.Body.Sun, when) >= PAIRING_MAX_SUN_ALTITUDE_DEG) return false;
  if (altitudeDeg(site, Astronomy.Body.Moon, when) <= PAIRING_MIN_ALTITUDE_DEG) return false;
  return altitudeDeg(site, body, when) > PAIRING_MIN_ALTITUDE_DEG;
}

/**
 * The geocentric separation is unimodal across the ±1 h around the best hourly
 * sample, so a ternary search to the minute replaces a 121-sample scan.
 */
function refineGeocentricMinimum(
  body: Astronomy.Body,
  around: Date,
  window: TimeWindow,
): { at: Date; sep: number } {
  const sepAt = (t: number): number =>
    geocentricSeparationDeg(Astronomy.Body.Moon, body, new Date(t));
  let lo = Math.max(window.start.getTime(), around.getTime() - HOUR_MS);
  let hi = Math.min(window.end.getTime(), around.getTime() + HOUR_MS);
  while (hi - lo > 60_000) {
    const m1 = lo + (hi - lo) / 3;
    const m2 = hi - (hi - lo) / 3;
    if (sepAt(m1) < sepAt(m2)) hi = m2;
    else lo = m1;
  }
  const at = new Date(Math.round((lo + hi) / 2 / 60_000) * 60_000);
  return { at, sep: sepAt(at.getTime()) };
}

function refineVisibleMinimum(
  site: Site,
  body: Astronomy.Body,
  around: { at: Date; sep: number },
  window: TimeWindow,
): { at: Date; sep: number } {
  // Five-minute pass over ±1 h, then the minute around the best of those. The
  // gate is not smooth (the minimum often sits on a rise or twilight edge), so
  // this is a scan rather than a bracket search.
  const scan = (centre: Date, halfMs: number, stepMs: number, best: { at: Date; sep: number }) => {
    const from = Math.max(window.start.getTime(), centre.getTime() - halfMs);
    const to = Math.min(window.end.getTime(), centre.getTime() + halfMs);
    for (let t = from; t <= to; t += stepMs) {
      const when = new Date(t);
      const sep = visibleTopocentricSeparation(site, body, when);
      if (sep !== null && sep < best.sep) best = { at: when, sep };
    }
    return best;
  };
  const coarse = scan(around.at, HOUR_MS, 5 * 60_000, around);
  return scan(coarse.at, 5 * 60_000, 60_000, coarse);
}

/**
 * Does the planet actually go behind the disc from *this* spot, and if so
 * when does it come back out? Scanned at one-minute resolution across ±3 h of
 * the geocentric minimum — lunar parallax can shift the local minimum well
 * over an hour away from the Earth-centred one.
 */
export function occultationFromHere(
  site: Site,
  body: Astronomy.Body,
  aroundGeocentricMin: Date,
): OccultationFromHere {
  const step = 60_000;
  const from = aroundGeocentricMin.getTime() - 3 * HOUR_MS;
  const to = aroundGeocentricMin.getTime() + 3 * HOUR_MS;

  let best: { at: Date; sep: number; radius: number } | null = null;
  let disappearsAt: Date | null = null;
  let reappearsAt: Date | null = null;
  let inside = false;

  const obs = observerOf(site);
  for (let t = from; t <= to; t += step) {
    const when = new Date(t);
    const moon = Astronomy.Equator(Astronomy.Body.Moon, when, obs, true, true);
    const planet = Astronomy.Equator(body, when, obs, true, true);
    const sep = angularSeparationDeg(moon.ra, moon.dec, planet.ra, planet.dec);
    const radius = Math.asin(MOON_RADIUS_KM / (moon.dist * KM_PER_AU)) / DEG;
    if (!best || sep < best.sep) best = { at: when, sep, radius };
    const hidden = sep < radius;
    if (hidden && !inside) {
      disappearsAt = when;
      inside = true;
    } else if (!hidden && inside) {
      reappearsAt = when;
      inside = false;
    }
  }

  const at = best?.at ?? aroundGeocentricMin;
  const behind = disappearsAt !== null;
  return {
    minSeparationDeg: round3(best?.sep ?? Number.NaN),
    minSeparationAt: at,
    moonRadiusDeg: round3(best?.radius ?? Number.NaN),
    moonAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Moon, at)),
    sunAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Sun, at)),
    behindDiscFromHere: behind,
    disappearsAt,
    reappearsAt,
    reappearMoonAltitudeDeg:
      reappearsAt === null ? null : round1(altitudeDeg(site, Astronomy.Body.Moon, reappearsAt)),
  };
}

// ------------------------------------------------------------ zodiacal light

export type ZodiacalSeason = "autumn_morning" | "spring_evening";

export interface ZodiacalRange {
  season: ZodiacalSeason;
  /** First and last qualifying observing instant (dawn − 1 h / dusk + 1 h). */
  start: Date;
  end: Date;
  nights: number;
}

/**
 * Nights where the false dawn is worth setting an alarm for: the Moon is down
 * (or under 15% lit) one hour before astronomical dawn in the autumn morning
 * season, or one hour after astronomical dusk in the spring evening season.
 * Consecutive nights collapse into ranges.
 *
 * Northern hemisphere only — the seasonal months invert south of the equator
 * and this app's AOI is the U.S. Mountain West, so rather than half-guess the
 * southern case it returns nothing there.
 */
export function zodiacalLightRanges(site: Site, window: TimeWindow): ZodiacalRange[] {
  if (site.latitude <= 0) return [];
  const morning = qualifyingNights(site, window, "autumn_morning");
  const evening = qualifyingNights(site, window, "spring_evening");
  return [...collapse(morning, "autumn_morning"), ...collapse(evening, "spring_evening")].sort(
    (a, b) => a.start.getTime() - b.start.getTime(),
  );
}

function qualifyingNights(site: Site, window: TimeWindow, season: ZodiacalSeason): Date[] {
  const obs = observerOf(site);
  const direction = season === "autumn_morning" ? +1 : -1;
  const months =
    season === "autumn_morning"
      ? ZODIACAL_AUTUMN_MORNING_MONTHS
      : ZODIACAL_SPRING_EVENING_MONTHS;
  const offsetMs = (season === "autumn_morning" ? -1 : +1) * ZODIACAL_OFFSET_HOURS * HOUR_MS;

  const nights: Date[] = [];
  let cursor = new Date(window.start.getTime());
  const spanDays = (window.end.getTime() - window.start.getTime()) / DAY_MS;
  for (let guard = 0; guard < spanDays + 4; guard++) {
    const twilight = Astronomy.SearchAltitude(Astronomy.Body.Sun, obs, direction, cursor, 2, -18);
    if (!twilight) {
      // No astronomical darkness in the next two days (high-latitude summer).
      // Later nights in the window can still qualify, so step past it.
      cursor = new Date(cursor.getTime() + DAY_MS);
      if (cursor > window.end) break;
      continue;
    }
    const edge = twilight.date;
    if (edge > window.end) break;
    cursor = new Date(edge.getTime() + 6 * HOUR_MS);
    if (!months.includes(siteCivilDate(edge, site.longitude).month)) continue;
    const sample = new Date(edge.getTime() + offsetMs);
    if (moonSpoils(site, sample)) continue;
    nights.push(sample);
  }
  return nights;
}

function moonSpoils(site: Site, when: Date): boolean {
  if (altitudeDeg(site, Astronomy.Body.Moon, when) <= 0) return false;
  return Astronomy.Illumination(Astronomy.Body.Moon, when).phase_fraction >= ZODIACAL_MAX_MOON_ILLUM;
}

function collapse(nights: Date[], season: ZodiacalSeason): ZodiacalRange[] {
  const out: ZodiacalRange[] = [];
  for (const night of nights) {
    const last = out[out.length - 1];
    // Successive qualifying nights are ~24 h apart; 36 h absorbs the drift of
    // twilight against the clock without merging across a gap.
    if (last && night.getTime() - last.end.getTime() <= 36 * HOUR_MS) {
      last.end = night;
      last.nights += 1;
    } else {
      out.push({ season, start: night, end: night, nights: 1 });
    }
  }
  return out;
}

// ------------------------------------------------------------------- seasons

export interface SeasonMarker {
  at: Date;
  name: string;
}

const SEASON_NAMES = {
  mar_equinox: "March equinox",
  jun_solstice: "June solstice",
  sep_equinox: "September equinox",
  dec_solstice: "December solstice",
} as const;

/** Equinoxes and solstices inside the window. */
export function seasonMarkers(window: TimeWindow): SeasonMarker[] {
  const out: SeasonMarker[] = [];
  const firstYear = window.start.getUTCFullYear();
  const lastYear = window.end.getUTCFullYear();
  for (let year = firstYear; year <= lastYear; year++) {
    const s = Astronomy.Seasons(year);
    for (const key of Object.keys(SEASON_NAMES) as (keyof typeof SEASON_NAMES)[]) {
      const at = s[key].date;
      if (within(window, at)) out.push({ at, name: SEASON_NAMES[key] });
    }
  }
  return out.sort(byTime);
}

// --------------------------------------------------------------------- utils

function byTime(a: { at: Date }, b: { at: Date }): number {
  return a.at.getTime() - b.at.getTime();
}

function round1(v: number): number {
  return Math.round(v * 10) / 10;
}

function round3(v: number): number {
  return Math.round(v * 1000) / 1000;
}
