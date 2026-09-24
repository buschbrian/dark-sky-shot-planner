/**
 * What a meteor shower actually does at *this* spot on *this* night.
 *
 * The curated file (`config/sky-events.json`) stores only what a human read
 * on a cited page: active range, peak instant in UTC, ZHR, radiant. Whether
 * the radiant ever clears the horizon here, when it is highest, and whether
 * the Moon ruins it are all computed in the browser — a shower is a different
 * event in Millcreek than it is in Patagonia, and a stored "best time" would
 * be wrong for everyone but its author. ADR-0008.
 *
 * Visibility rule: a shower is worth listing only if its radiant rises above
 * 10° during astronomical darkness at the observer. Below that the atmosphere
 * and foreground swallow the rate, and quoting a ZHR would be a lie.
 */

import * as Astronomy from "astronomy-engine";

import {
  darknessWindow,
  moonFreeWindows,
  moonIllumination,
  moonUpIntervals,
  type Interval,
} from "./planner";
import { type Site, observerOf } from "./events";

/** A radiant must clear this altitude in dark hours to count as observable. */
export const RADIANT_MIN_ALTITUDE_DEG = 10;

/** Minutes between altitude samples when scanning a night. */
const SAMPLE_MINUTES = 5;

/** How many nights either side of the peak to consider for a better night. */
const NEIGHBOUR_NIGHTS = 3;

const DAY_MS = 86_400_000;

export interface Radiant {
  /** J2000 right ascension, hours. */
  raHours: number;
  /** J2000 declination, degrees. */
  decDeg: number;
}

export interface ShowerNight {
  /** Local evening instant the night is keyed on (21:00 site mean time). */
  eveningUtc: Date;
  darkness: Interval | null;
  /** Peak radiant altitude during darkness, degrees. */
  maxAltitudeDeg: number;
  maxAltitudeAt: Date | null;
  /** True when the radiant clears the 10° cutoff during darkness. */
  radiantObservable: boolean;
  /** Dark hours with the radiant above the cutoff. */
  radiantWindow: Interval | null;
  /** Moon illuminated fraction at the middle of the radiant window. */
  moonIllumFraction: number;
  /** Moon-down sub-spans of the radiant window; empty means the Moon is up throughout. */
  usableWindows: Interval[];
  /** Minutes of the radiant window with the Moon down. */
  usableMinutes: number;
}

export interface ShowerAssessment {
  /** The night containing the published peak, assessed at the observer. */
  peakNight: ShowerNight;
  /**
   * The night inside the active range with the most moonless radiant time,
   * when that is a different (and materially better) night than the peak.
   */
  betterNight: ShowerNight | null;
  /** False when the radiant never clears 10° in darkness on any assessed night. */
  observableHere: boolean;
}

/**
 * Radiant altitude at the observer. The curated radiant is J2000; precession
 * to the date of observation is applied rather than ignored, because the same
 * file is meant to outlive the year it was verified in.
 */
export function radiantAltitudeDeg(site: Site, radiant: Radiant, when: Date): number {
  const obs = observerOf(site);
  const time = Astronomy.MakeTime(when);
  const j2000 = Astronomy.VectorFromSphere(
    new Astronomy.Spherical(radiant.decDeg, radiant.raHours * 15, 1),
    time,
  );
  const ofDate = Astronomy.RotateVector(Astronomy.Rotation_EQJ_EQD(time), j2000);
  const eq = Astronomy.EquatorFromVector(ofDate);
  return Astronomy.Horizon(when, obs, eq.ra, eq.dec, "normal").altitude;
}

/**
 * Assess the peak night and its neighbours inside the active range.
 *
 * `activeFrom`/`activeTo` bound which nights may be suggested: a shower's
 * second-best night is only useful advice while the shower is still running.
 */
export function assessShower(
  site: Site,
  radiant: Radiant,
  peakUtc: Date,
  activeFrom: Date,
  activeTo: Date,
): ShowerAssessment {
  const peakNight = assessNight(site, radiant, eveningFor(peakUtc, site.longitude));
  let betterNight: ShowerNight | null = null;
  let observableHere = peakNight.radiantObservable;

  for (let offset = -NEIGHBOUR_NIGHTS; offset <= NEIGHBOUR_NIGHTS; offset++) {
    if (offset === 0) continue;
    const evening = new Date(peakNight.eveningUtc.getTime() + offset * DAY_MS);
    if (evening < activeFrom || evening > activeTo) continue;
    const night = assessNight(site, radiant, evening);
    observableHere ||= night.radiantObservable;
    // "Materially better" is half an hour: anything less is not worth telling
    // someone to move their night.
    if (night.usableMinutes > peakNight.usableMinutes + 30) {
      if (!betterNight || night.usableMinutes > betterNight.usableMinutes) betterNight = night;
    }
  }

  return { peakNight, betterNight, observableHere };
}

/** Assess one night, keyed on an evening instant. */
export function assessNight(site: Site, radiant: Radiant, eveningUtc: Date): ShowerNight {
  const { window: darkness } = darknessWindow(site.latitude, site.longitude, eveningUtc);
  if (!darkness) {
    return {
      eveningUtc,
      darkness: null,
      maxAltitudeDeg: Number.NEGATIVE_INFINITY,
      maxAltitudeAt: null,
      radiantObservable: false,
      radiantWindow: null,
      moonIllumFraction: moonIllumination(eveningUtc),
      usableWindows: [],
      usableMinutes: 0,
    };
  }

  const stepMs = SAMPLE_MINUTES * 60_000;
  let best: { alt: number; at: Date } | null = null;
  let above: { start: Date; end: Date } | null = null;
  for (let t = darkness.start.getTime(); t <= darkness.end.getTime(); t += stepMs) {
    const when = new Date(Math.min(t, darkness.end.getTime()));
    const alt = radiantAltitudeDeg(site, radiant, when);
    if (!best || alt > best.alt) best = { alt, at: when };
    if (alt >= RADIANT_MIN_ALTITUDE_DEG) {
      // Radiant altitude is monotone up then down across a night, so the
      // above-cutoff samples form one span; widening the ends is enough.
      if (!above) above = { start: when, end: when };
      else above.end = when;
    }
  }

  const radiantWindow = above ? { start: above.start, end: above.end } : null;
  const midpoint = radiantWindow
    ? new Date((radiantWindow.start.getTime() + radiantWindow.end.getTime()) / 2)
    : new Date((darkness.start.getTime() + darkness.end.getTime()) / 2);
  const usable = radiantWindow
    ? moonFreeWindows(
        radiantWindow,
        moonUpIntervals(site.latitude, site.longitude, radiantWindow.start, radiantWindow.end),
      )
    : [];

  return {
    eveningUtc,
    darkness,
    maxAltitudeDeg: Math.round((best?.alt ?? Number.NEGATIVE_INFINITY) * 10) / 10,
    maxAltitudeAt: best?.at ?? null,
    radiantObservable: radiantWindow !== null,
    radiantWindow,
    moonIllumFraction: Math.round(moonIllumination(midpoint) * 1000) / 1000,
    usableWindows: usable,
    usableMinutes: usable.reduce((acc, w) => acc + w.minutes, 0),
  };
}

/**
 * The evening instant (21:00 site mean solar time) of the night an event
 * belongs to. Derived from longitude, not the reader's timezone: which night
 * a 06:54 UTC peak falls on is a property of where the observer stands.
 */
export function eveningFor(instant: Date, longitudeDeg: number): Date {
  const offsetMs = (longitudeDeg / 15) * 3_600_000;
  const local = new Date(instant.getTime() + offsetMs);
  const localNight = new Date(local);
  // Before local noon the instant belongs to the night that began yesterday.
  if (local.getUTCHours() < 12) localNight.setUTCDate(local.getUTCDate() - 1);
  localNight.setUTCHours(21, 0, 0, 0);
  return new Date(localNight.getTime() - offsetMs);
}
