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
 * - **Geocentric** — the number almanacs quote for a conjunction. Reported as
 *   the headline separation so this app agrees with published tables.
 * - **Topocentric** — what you actually see from one spot. Lunar parallax is
 *   up to ~1°, which is the whole difference between "close pairing" and
 *   "the planet is behind the Moon from here", so the occultation test is
 *   always topocentric.
 */

import * as Astronomy from "astronomy-engine";

/** Half-width of the default window around the selected date, in days. */
export const DEFAULT_WINDOW_DAYS = 30;

/** Moon's mean angular semidiameter (deg): the "possible occultation" flag. */
export const OCCULTATION_FLAG_DEG = 0.27;

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
          visibility: evt.visibility,
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
  /** Moon altitude at that minimum — negative means it happens below the horizon. */
  moonAltitudeDeg: number;
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
  /** Closest *observable* approach: < 5°, both > 5° up, sun below −6°. */
  at: Date;
  separationDeg: number;
  moonAltitudeDeg: number;
  bodyAltitudeDeg: number;
  moonIllumFraction: number;
  /** Geocentric minimum over the whole window, whether observable or not. */
  geocentricMinDeg: number;
  geocentricMinAt: Date;
  /** Geocentric minimum below the Moon's mean semidiameter. */
  possibleOccultation: boolean;
  /** Only computed when `possibleOccultation`. */
  occultation: OccultationFromHere | null;
}

/**
 * Closest observable Moon–planet approach per pair inside the window.
 *
 * Hourly coarse scan, then a one-minute refinement around the best hour. The
 * observability gate (both bodies above 5°, sun below −6°) is applied at the
 * observer, so a pairing that is only close while it is under the horizon here
 * is correctly *not* reported as something to go look at — but its geocentric
 * minimum is still carried, because that is what triggers the occultation
 * check.
 */
export function moonPlanetPairings(site: Site, window: TimeWindow): MoonPairing[] {
  const out: MoonPairing[] = [];
  for (const body of PAIRING_BODIES) {
    const pairing = pairingFor(site, window, body);
    if (pairing) out.push(pairing);
  }
  return out.sort(byTime);
}

function pairingFor(site: Site, window: TimeWindow, body: Astronomy.Body): MoonPairing | null {
  let bestVisible: { at: Date; sep: number } | null = null;
  let bestGeo: { at: Date; sep: number } | null = null;

  for (let t = window.start.getTime(); t <= window.end.getTime(); t += HOUR_MS) {
    const when = new Date(t);
    const sep = geocentricSeparationDeg(Astronomy.Body.Moon, body, when);
    if (!bestGeo || sep < bestGeo.sep) bestGeo = { at: when, sep };
    // Altitude work is comparatively expensive; only pay for it near a pairing.
    if (sep > PAIRING_MAX_SEPARATION_DEG) continue;
    if (!observable(site, body, when)) continue;
    if (!bestVisible || sep < bestVisible.sep) bestVisible = { at: when, sep };
  }
  if (!bestGeo) return null;

  const geoMin = refineGeocentricMinimum(body, bestGeo.at, window);
  const possibleOccultation = geoMin.sep < OCCULTATION_FLAG_DEG;
  if (!bestVisible) {
    // No observable approach here, but a flagged near-miss is still worth the
    // occultation answer ("from here it stays clear of the disc").
    if (!possibleOccultation) return null;
    return {
      body,
      at: geoMin.at,
      separationDeg: round3(geoMin.sep),
      moonAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Moon, geoMin.at)),
      bodyAltitudeDeg: round1(altitudeDeg(site, body, geoMin.at)),
      moonIllumFraction: round3(Astronomy.Illumination(Astronomy.Body.Moon, geoMin.at).phase_fraction),
      geocentricMinDeg: round3(geoMin.sep),
      geocentricMinAt: geoMin.at,
      possibleOccultation,
      occultation: occultationFromHere(site, body, geoMin.at),
    };
  }

  const refined = refineVisibleMinimum(site, body, bestVisible.at, window);
  return {
    body,
    at: refined.at,
    separationDeg: round3(refined.sep),
    moonAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Moon, refined.at)),
    bodyAltitudeDeg: round1(altitudeDeg(site, body, refined.at)),
    moonIllumFraction: round3(Astronomy.Illumination(Astronomy.Body.Moon, refined.at).phase_fraction),
    geocentricMinDeg: round3(geoMin.sep),
    geocentricMinAt: geoMin.at,
    possibleOccultation,
    occultation: possibleOccultation ? occultationFromHere(site, body, geoMin.at) : null,
  };
}

function observable(site: Site, body: Astronomy.Body, when: Date): boolean {
  if (altitudeDeg(site, Astronomy.Body.Sun, when) >= PAIRING_MAX_SUN_ALTITUDE_DEG) return false;
  if (altitudeDeg(site, Astronomy.Body.Moon, when) <= PAIRING_MIN_ALTITUDE_DEG) return false;
  return altitudeDeg(site, body, when) > PAIRING_MIN_ALTITUDE_DEG;
}

function refineGeocentricMinimum(
  body: Astronomy.Body,
  around: Date,
  window: TimeWindow,
): { at: Date; sep: number } {
  let best = { at: around, sep: geocentricSeparationDeg(Astronomy.Body.Moon, body, around) };
  const from = Math.max(window.start.getTime(), around.getTime() - HOUR_MS);
  const to = Math.min(window.end.getTime(), around.getTime() + HOUR_MS);
  for (let t = from; t <= to; t += 60_000) {
    const when = new Date(t);
    const sep = geocentricSeparationDeg(Astronomy.Body.Moon, body, when);
    if (sep < best.sep) best = { at: when, sep };
  }
  return best;
}

function refineVisibleMinimum(
  site: Site,
  body: Astronomy.Body,
  around: Date,
  window: TimeWindow,
): { at: Date; sep: number } {
  let best = { at: around, sep: geocentricSeparationDeg(Astronomy.Body.Moon, body, around) };
  const from = Math.max(window.start.getTime(), around.getTime() - HOUR_MS);
  const to = Math.min(window.end.getTime(), around.getTime() + HOUR_MS);
  for (let t = from; t <= to; t += 60_000) {
    const when = new Date(t);
    const sep = geocentricSeparationDeg(Astronomy.Body.Moon, body, when);
    if (sep >= best.sep) continue;
    if (!observable(site, body, when)) continue;
    best = { at: when, sep };
  }
  return best;
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

  let best: { at: Date; sep: number } | null = null;
  let disappearsAt: Date | null = null;
  let reappearsAt: Date | null = null;
  let inside = false;

  for (let t = from; t <= to; t += step) {
    const when = new Date(t);
    const sep = topocentricSeparationDeg(site, Astronomy.Body.Moon, body, when);
    if (!best || sep < best.sep) best = { at: when, sep };
    const hidden = sep < moonAngularRadiusDeg(site, when);
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
    moonAltitudeDeg: round1(altitudeDeg(site, Astronomy.Body.Moon, at)),
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
    if (!twilight) break;
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
