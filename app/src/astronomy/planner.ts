/**
 * Client-side night planning math. Pure functions: location + date in,
 * numbers out. No network, no API.
 *
 * The headline quantity is moon-free astronomical darkness: the intersection
 * of the sun-below-−18° window with the moon-below-horizon window. Nothing
 * else surfaces this number well, which is the whole reason this app exists.
 */

import * as Astronomy from "astronomy-engine";

export const GC_RA_HOURS = 17.7611222; // Sgr A*: 17h 45m 40.04s
export const GC_DEC_DEG = -29.0078056; // −29° 00′ 28.1″

/** Minutes sampled when scanning for GC peak altitude. */
const GC_SAMPLE_MINUTES = 5;

export interface NightInput {
  latitude: number;
  longitude: number;
  /** Any instant during the local evening whose night we plan (UTC). */
  eveningUtc: Date;
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

function isMoonUp(obs: Astronomy.Observer, when: Date): boolean {
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

export function gcAltitude(latitude: number, longitude: number, when: Date): number {
  const obs = observer(latitude, longitude);
  return Astronomy.Horizon(when, obs, GC_RA_HOURS, GC_DEC_DEG).altitude;
}

export function gcAzimuth(latitude: number, longitude: number, when: Date): number {
  const obs = observer(latitude, longitude);
  return Astronomy.Horizon(when, obs, GC_RA_HOURS, GC_DEC_DEG).azimuth;
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
