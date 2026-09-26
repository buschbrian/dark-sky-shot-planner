/**
 * Client-side night planning math. Pure functions: location + date in,
 * numbers out. No network, no API.
 *
 * The headline quantity is moon-free astronomical darkness: the intersection
 * of the sun-below-−18° window with the moon-below-horizon window. Nothing
 * else surfaces this number well, which is the whole reason this app exists.
 */

import * as Astronomy from "astronomy-engine";

import type { HorizonProfile } from "./horizon";

/** Sgr A*, J2000 (ICRS). Precessed to the date before any horizon math. */
export const GC_RA_HOURS = 17.7611222; // 17h 45m 40.04s
export const GC_DEC_DEG = -29.0078056; // −29° 00′ 28.1″

/** Minutes sampled when scanning for GC peak altitude. */
const GC_SAMPLE_MINUTES = 5;

export interface NightInput {
  latitude: number;
  longitude: number;
  /** Any instant during the local evening whose night we plan (UTC). */
  eveningUtc: Date;
  /** Terrain skyline (M9). Omitted: the mathematical horizon, as before. */
  horizon?: HorizonProfile;
}

export interface Interval {
  start: Date;
  end: Date;
}

export interface MoonFreeWindow extends Interval {
  minutes: number;
}

export interface GcVisibility {
  /** Max GC altitude (deg) across the moon-free dark window; null if none. */
  maxAltitudeDeg: number | null;
  maxAltitudeAt: Date | null;
  /** True when the GC actually climbs above the horizon in the dark window. */
  risesDuringDarkness: boolean;
}

export interface NightReport {
  darkness: Interval | null;
  /** True when astronomical night does not occur on this date/location. */
  noAstronomicalDarkness: boolean;
  moonIllumFraction: number;
  moonset: Date | null;
  moonrise: Date | null;
  moonFreeWindows: MoonFreeWindow[];
  /** Minutes of moon-free astronomical darkness (headline number). */
  moonFreeMinutes: number;
  gc: GcVisibility;
  /**
   * Present only when a horizon profile was given; the fields above are then
   * judged against the terrain, not the mathematical horizon.
   */
  terrain?: TerrainReport;
}

export interface TerrainReport {
  /** The GC above the skyline, clipped to astronomical darkness. */
  gcAboveSkyline: Interval[];
  /** First moment in darkness the GC climbs over the skyline; null if already clear at dusk or never. */
  gcClearsSkyline: Date | null;
  /** First moment in darkness the GC drops behind the skyline. */
  gcDropsBehindSkyline: Date | null;
  /** Moon-free darkness with the GC above the skyline. */
  gcWindows: MoonFreeWindow[];
  /** Longest of `gcWindows`, in minutes (the same rule as `moonFreeMinutes`). */
  gcMinutes: number;
}

const observer = (latitude: number, longitude: number): Astronomy.Observer =>
  new Astronomy.Observer(latitude, longitude, 0);

function toJs(t: Astronomy.AstroTime): Date {
  return t.date;
}

/**
 * Sun-below-`altDeg` interval for the night containing/after `eveningUtc`.
 * Searches begin at local noon (12 h before the given evening instant) so
 * the first descending crossing belongs to this night, never the previous
 * one.
 */
export function darknessWindow(
  latitude: number,
  longitude: number,
  eveningUtc: Date,
  altDeg = -18,
): { window: Interval | null; noDarkness: boolean } {
  const obs = observer(latitude, longitude);
  const searchStart = new Date(eveningUtc.getTime() - 12 * 3600_000);
  const dusk = Astronomy.SearchAltitude(
    Astronomy.Body.Sun,
    obs,
    -1,
    searchStart,
    1.5,
    altDeg,
  );
  if (!dusk) return { window: null, noDarkness: true };
  const dawn = Astronomy.SearchAltitude(Astronomy.Body.Sun, obs, +1, dusk.date, 2, altDeg);
  if (!dawn) return { window: null, noDarkness: true };
  return { window: { start: toJs(dusk), end: toJs(dawn) }, noDarkness: false };
}

/**
 * Up iff the most recent rise/set event was a rise: the same top-limb,
 * refracted definition `SearchRiseSet` uses for the events that follow.
 */
function isMoonUp(obs: Astronomy.Observer, when: Date): boolean {
  const rise = Astronomy.SearchRiseSet(Astronomy.Body.Moon, obs, +1, when, -2);
  const set = Astronomy.SearchRiseSet(Astronomy.Body.Moon, obs, -1, when, -2);
  if (rise && set) return rise.ut > set.ut;
  if (rise || set) return rise !== null;
  // No event within 2 days (polar latitudes only).
  const eq = Astronomy.Equator(Astronomy.Body.Moon, when, obs, true, true);
  return Astronomy.Horizon(when, obs, eq.ra, eq.dec, "normal").altitude > 0;
}

/** Moon above-horizon intervals overlapping [from, to]. */
export function moonUpIntervals(
  latitude: number,
  longitude: number,
  from: Date,
  to: Date,
): Interval[] {
  const obs = observer(latitude, longitude);
  const out: Interval[] = [];
  let cursor = new Date(from.getTime() - 12 * 3600_000);
  let up = isMoonUp(obs, cursor);
  for (let guard = 0; guard < 60 && cursor < to; guard++) {
    const evt = Astronomy.SearchRiseSet(
      Astronomy.Body.Moon,
      obs,
      up ? -1 : +1,
      cursor,
      10,
    );
    if (!evt) break;
    const t = toJs(evt);
    if (up) {
      out.push({ start: cursor, end: t });
      up = false;
    } else {
      up = true;
    }
    cursor = t;
  }
  return out.filter((iv) => iv.end > from && iv.start < to);
}

/** Intersect a dark window with moon-down periods -> moon-free sub-windows. */
export function moonFreeWindows(
  darkness: Interval,
  moonUp: Interval[],
): MoonFreeWindow[] {
  const windows: MoonFreeWindow[] = [];
  let cursor = darkness.start;
  const sorted = [...moonUp].sort((a, b) => a.start.getTime() - b.start.getTime());
  for (const up of sorted) {
    if (up.end <= darkness.start || up.start >= darkness.end) continue;
    if (up.start > cursor) pushWindow(windows, cursor, minDate(up.start, darkness.end));
    cursor = maxDate(cursor, up.end);
    if (cursor >= darkness.end) break;
  }
  if (cursor < darkness.end) pushWindow(windows, cursor, darkness.end);
  return windows;
}

function pushWindow(out: MoonFreeWindow[], start: Date, end: Date): void {
  const ms = end.getTime() - start.getTime();
  if (ms > 60_000) {
    out.push({ start, end, minutes: Math.round(ms / 60_000) });
  }
}

function minDate(a: Date, b: Date): Date {
  return a < b ? a : b;
}
function maxDate(a: Date, b: Date): Date {
  return a > b ? a : b;
}

export function moonIllumination(when: Date): number {
  return Astronomy.Illumination(Astronomy.Body.Moon, when).phase_fraction;
}

const GC_EQJ = new Astronomy.Spherical(GC_DEC_DEG, GC_RA_HOURS * 15, 1);

/**
 * GC RA/Dec on the true equator of date. `Horizon()` expects of-date
 * coordinates; feeding it the J2000 catalogue values is ~0.3° off in 2026.
 */
export function gcEquatorOfDate(when: Date): Astronomy.EquatorialCoordinates {
  const time = Astronomy.MakeTime(when);
  const eqj = Astronomy.VectorFromSphere(GC_EQJ, time);
  return Astronomy.EquatorFromVector(
    Astronomy.RotateVector(Astronomy.Rotation_EQJ_EQD(time), eqj),
  );
}

/** Geometric (unrefracted) GC position: ADR-0002, 2026-09-25 amendment. */
function gcHorizon(latitude: number, longitude: number, when: Date): Astronomy.HorizontalCoordinates {
  const eqd = gcEquatorOfDate(when);
  return Astronomy.Horizon(when, observer(latitude, longitude), eqd.ra, eqd.dec);
}

export function gcAltitude(latitude: number, longitude: number, when: Date): number {
  return gcHorizon(latitude, longitude, when).altitude;
}

export function gcAzimuth(latitude: number, longitude: number, when: Date): number {
  return gcHorizon(latitude, longitude, when).azimuth;
}

export function gcVisibility(
  latitude: number,
  longitude: number,
  moonFree: MoonFreeWindow[],
): GcVisibility {
  let best: { alt: number; at: Date } | null = null;
  for (const win of moonFree) {
    const stepMs = GC_SAMPLE_MINUTES * 60_000;
    for (let t = win.start.getTime(); ; t += stepMs) {
      const when = new Date(Math.min(t, win.end.getTime()));
      const alt = gcAltitude(latitude, longitude, when);
      if (!best || alt > best.alt) best = { alt, at: when };
      if (t >= win.end.getTime()) break;
    }
  }
  return {
    maxAltitudeDeg: best ? Math.round(best.alt * 10) / 10 : null,
    maxAltitudeAt: best?.at ?? null,
    risesDuringDarkness: best !== null && best.alt > 0,
  };
}

function findMoonEvent(
  latitude: number,
  longitude: number,
  darkness: Interval | null,
  direction: 1 | -1,
): Date | null {
  if (!darkness) return null;
  const obs = observer(latitude, longitude);
  const evt = Astronomy.SearchRiseSet(Astronomy.Body.Moon, obs, direction, darkness.start, 2);
  if (!evt) return null;
  const t = toJs(evt);
  return t >= darkness.start && t <= darkness.end ? t : null;
}

export function planNight(input: NightInput): NightReport {
  if (input.horizon) return planNightOverTerrain(input, input.horizon);
  const { window: darkness, noDarkness } = darknessWindow(
    input.latitude,
    input.longitude,
    input.eveningUtc,
  );
  const midDark = darkness
    ? new Date((darkness.start.getTime() + darkness.end.getTime()) / 2)
    : input.eveningUtc;
  const moonFree = darkness
    ? moonFreeWindows(
        darkness,
        moonUpIntervals(input.latitude, input.longitude, darkness.start, darkness.end),
      )
    : [];
  const moonFreeMinutes = Math.max(0, ...moonFree.map((w) => w.minutes));

  return {
    darkness,
    noAstronomicalDarkness: noDarkness,
    moonIllumFraction: Math.round(moonIllumination(midDark) * 1000) / 1000,
    moonset: findMoonEvent(input.latitude, input.longitude, darkness, -1),
    moonrise: findMoonEvent(input.latitude, input.longitude, darkness, +1),
    moonFreeWindows: moonFree,
    moonFreeMinutes,
    gc: gcVisibility(input.latitude, input.longitude, moonFree),
  };
}

/**
 * Terrain crossings are found by sampling every 2 minutes, then bisecting to
 * 0.1 s. A skyline notch crossed in under 2 minutes can be missed; SkyCore
 * misses it identically.
 */
const TERRAIN_SCAN_MS = 2 * 60_000;
const TERRAIN_BISECT_MS = 100;
/** astronomy-engine's MOON_EQUATORIAL_RADIUS_KM (not exported by the npm build). */
const MOON_EQUATORIAL_RADIUS_KM = 1738.1;

/**
 * Degrees the moon's top limb stands above the skyline. The limb test and
 * standard refraction follow `SearchRiseSet` (ADR-0002 amendment), with
 * refraction evaluated at the moon's altitude instead of the fixed 34′ a flat
 * horizon uses, because the skyline is usually degrees up.
 */
function moonClearanceDeg(obs: Astronomy.Observer, horizon: HorizonProfile, when: Date): number {
  const eq = Astronomy.Equator(Astronomy.Body.Moon, when, obs, true, true);
  const hor = Astronomy.Horizon(when, obs, eq.ra, eq.dec, "normal");
  const topLimb =
    hor.altitude + Astronomy.RAD2DEG * (MOON_EQUATORIAL_RADIUS_KM / Astronomy.KM_PER_AU / eq.dist);
  return topLimb - horizon.altitudeAt(hor.azimuth);
}

/** Degrees the GC stands above the skyline; geometric like every GC number. */
function gcClearanceDeg(latitude: number, longitude: number, horizon: HorizonProfile, when: Date): number {
  const p = gcHorizon(latitude, longitude, when);
  return p.altitude - horizon.altitudeAt(p.azimuth);
}

interface Crossings {
  above: Interval[];
  rises: Date[];
  sets: Date[];
}

/** Intervals in [from, to] where `clearance` > 0, with the crossing times. */
function scanCrossings(from: Date, to: Date, clearance: (when: Date) => number): Crossings {
  const fromMs = from.getTime();
  const toMs = to.getTime();
  const date = (ms: number): Date => (ms === fromMs ? from : ms === toMs ? to : new Date(ms));
  const isUp = (ms: number): boolean => clearance(date(ms)) > 0;

  const out: Crossings = { above: [], rises: [], sets: [] };
  let t0 = fromMs;
  let up0 = isUp(t0);
  let openedAt: number | null = up0 ? t0 : null;
  while (t0 < toMs) {
    const t1 = Math.min(t0 + TERRAIN_SCAN_MS, toMs);
    const up1 = isUp(t1);
    if (up1 !== up0) {
      let lo = t0;
      let hi = t1;
      while (hi - lo > TERRAIN_BISECT_MS) {
        const mid = Math.floor((lo + hi) / 2);
        if (isUp(mid) === up1) hi = mid;
        else lo = mid;
      }
      if (up1) {
        openedAt = hi;
        out.rises.push(date(hi));
      } else {
        out.above.push({ start: date(openedAt ?? fromMs), end: date(hi) });
        openedAt = null;
        out.sets.push(date(hi));
      }
    }
    t0 = t1;
    up0 = up1;
  }
  if (openedAt !== null) out.above.push({ start: date(openedAt), end: to });
  return out;
}

/** Moon above the terrain skyline within [from, to]. */
export function moonUpIntervalsOverTerrain(
  latitude: number,
  longitude: number,
  horizon: HorizonProfile,
  from: Date,
  to: Date,
): Interval[] {
  const obs = observer(latitude, longitude);
  return scanCrossings(from, to, (when) => moonClearanceDeg(obs, horizon, when)).above;
}

function intersectWindows(windows: MoonFreeWindow[], intervals: Interval[]): MoonFreeWindow[] {
  const out: MoonFreeWindow[] = [];
  for (const w of windows) {
    for (const iv of intervals) {
      if (iv.end > w.start && iv.start < w.end) pushWindow(out, maxDate(w.start, iv.start), minDate(w.end, iv.end));
    }
  }
  return out;
}

/** `gcVisibility`, counting only samples where the GC clears the skyline. */
export function gcVisibilityOverTerrain(
  latitude: number,
  longitude: number,
  moonFree: MoonFreeWindow[],
  horizon: HorizonProfile,
): GcVisibility {
  let best: { alt: number; at: Date } | null = null;
  for (const win of moonFree) {
    const stepMs = GC_SAMPLE_MINUTES * 60_000;
    for (let t = win.start.getTime(); ; t += stepMs) {
      const when = new Date(Math.min(t, win.end.getTime()));
      const p = gcHorizon(latitude, longitude, when);
      if (p.altitude > horizon.altitudeAt(p.azimuth) && (!best || p.altitude > best.alt)) {
        best = { alt: p.altitude, at: when };
      }
      if (t >= win.end.getTime()) break;
    }
  }
  return {
    maxAltitudeDeg: best ? Math.round(best.alt * 10) / 10 : null,
    maxAltitudeAt: best?.at ?? null,
    risesDuringDarkness: best !== null,
  };
}

/**
 * `planNight` against a terrain skyline: moonrise/moonset are when the moon's
 * top limb crosses the skyline, the moon-free windows are darkness with the
 * moon behind or below terrain, and the GC only counts while above the skyline.
 */
function planNightOverTerrain(input: NightInput, horizon: HorizonProfile): NightReport {
  const { latitude, longitude } = input;
  const { window: darkness, noDarkness } = darknessWindow(latitude, longitude, input.eveningUtc);
  const midDark = darkness
    ? new Date((darkness.start.getTime() + darkness.end.getTime()) / 2)
    : input.eveningUtc;

  let moonFree: MoonFreeWindow[] = [];
  let moonrise: Date | null = null;
  let moonset: Date | null = null;
  let terrain: TerrainReport = {
    gcAboveSkyline: [],
    gcClearsSkyline: null,
    gcDropsBehindSkyline: null,
    gcWindows: [],
    gcMinutes: 0,
  };
  if (darkness) {
    const obs = observer(latitude, longitude);
    const moon = scanCrossings(darkness.start, darkness.end, (when) => moonClearanceDeg(obs, horizon, when));
    moonFree = moonFreeWindows(darkness, moon.above);
    moonrise = moon.rises[0] ?? null;
    moonset = moon.sets[0] ?? null;
    const gc = scanCrossings(darkness.start, darkness.end, (when) =>
      gcClearanceDeg(latitude, longitude, horizon, when),
    );
    const gcWindows = intersectWindows(moonFree, gc.above);
    terrain = {
      gcAboveSkyline: gc.above,
      gcClearsSkyline: gc.rises[0] ?? null,
      gcDropsBehindSkyline: gc.sets[0] ?? null,
      gcWindows,
      gcMinutes: Math.max(0, ...gcWindows.map((w) => w.minutes)),
    };
  }

  return {
    darkness,
    noAstronomicalDarkness: noDarkness,
    moonIllumFraction: Math.round(moonIllumination(midDark) * 1000) / 1000,
    moonset,
    moonrise,
    moonFreeWindows: moonFree,
    moonFreeMinutes: Math.max(0, ...moonFree.map((w) => w.minutes)),
    gc: gcVisibilityOverTerrain(latitude, longitude, moonFree, horizon),
    terrain,
  };
}
