/**
 * Cross-platform golden vectors for sky events (ADR-0008).
 *
 * `shared/golden/sky-events.json` is the contract between the web agenda
 * (`app/src/events/agenda.ts` over `astronomy/events.ts` and
 * `astronomy/showers.ts`, the reference) and SkyCore's port. Each case is the
 * full `buildSkyEvents` result for one place and night, plus the raw numbers
 * underneath it, so a port that disagrees shows which number moved.
 *
 * Verdict lines are rendered with fixed-offset formatters (`utc_offset_hours`,
 * "HH:MM" and "MM-DD") so the text is part of the contract too and does not
 * depend on the zone the suite runs in.
 *
 * Regenerate after an intentional change to the events code or to
 * `config/sky-events.json`:
 *   UPDATE_GOLDEN=1 npx vitest run app/tests/sky-events-golden.test.ts
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import {
  greatestElongations,
  moonPhases,
  moonPlanetPairings,
  planetOppositions,
  seasonMarkers,
  windowAround,
  zodiacalLightRanges,
  type Site,
} from "../src/astronomy/events";
import type { MoonFreeWindow } from "../src/astronomy/planner";
import { assessShower, type ShowerNight } from "../src/astronomy/showers";
import { buildSkyEvents, type Formatters } from "../src/events/agenda";
import { CURATED, activeSpan, anchorOf, curatedEventsInWindow } from "../src/events/curated";

const GOLDEN_PATH = resolve(__dirname, "../../shared/golden/sky-events.json");

const ASTRONOMY_ENGINE_VERSION: string = JSON.parse(
  readFileSync(resolve(__dirname, "../../node_modules/astronomy-engine/package.json"), "utf8"),
).version;

/**
 * Tolerances any port must meet. Times in seconds, angles in degrees; counts,
 * categories, titles, provenance and the rendered verdict text are exact.
 */
const TOLERANCE = { time_s: 60, angle_deg: 0.01, illum_fraction: 0.002, minutes: 2 };

interface Case {
  id: string;
  note: string;
  latitude: number;
  longitude: number;
  elevation_m: number;
  centre_utc: string;
  utc_offset_hours: number;
}

const CASES: Case[] = [
  {
    id: "millcreek-2026-09-22",
    note: "The web suite's scenario: Saturn opposition, Mercury elongation, a Moon–Jupiter occultation at moonrise, zodiacal light, the equinox, the Orionids with a better night, a festival",
    latitude: 40.687, longitude: -111.824, elevation_m: 1400,
    centre_utc: "2026-09-23T03:00:00Z", utc_offset_hours: -6,
  },
  {
    id: "millcreek-2026-05-21",
    note: "Two Moon–Venus passes in one window, the second a daylight occultation; spring zodiacal light; the June solstice",
    latitude: 40.687, longitude: -111.824, elevation_m: 1400,
    centre_utc: "2026-05-22T03:00:00Z", utc_offset_hours: -6,
  },
  {
    id: "millcreek-2027-08-01",
    note: "A Moon–Mercury occultation only parallax brings onto the disc, in daylight",
    latitude: 40.687, longitude: -111.824, elevation_m: 1400,
    centre_utc: "2027-08-02T03:00:00Z", utc_offset_hours: -6,
  },
  {
    id: "canyonlands-2026-12-10",
    note: "Winter: the Leonids and Geminids (curated, unverified), both Taurid branches ending, the December solstice",
    latitude: 38.374031, longitude: -109.965416, elevation_m: 1800,
    centre_utc: "2026-12-11T04:00:00Z", utc_offset_hours: -7,
  },
  {
    id: "canyonlands-2027-02-01",
    note: "Jupiter and Mars oppositions; spring zodiacal light",
    latitude: 38.374031, longitude: -109.965416, elevation_m: 1800,
    centre_utc: "2027-02-02T04:00:00Z", utc_offset_hours: -7,
  },
  {
    id: "glacier-2026-07-20",
    note: "48.9°N: nights with no astronomical darkness early in the window",
    latitude: 48.9, longitude: -114.0, elevation_m: 0,
    centre_utc: "2026-07-21T03:00:00Z", utc_offset_hours: -6,
  },
  {
    id: "patagonia-2026-09-22",
    note: "Southern hemisphere: northern radiants below the horizon, no zodiacal light claimed",
    latitude: -40.0, longitude: -71.0, elevation_m: 0,
    centre_utc: "2026-09-23T03:00:00Z", utc_offset_hours: -3,
  },
];

const iso = (d: Date | null): string | null => (d ? d.toISOString() : null);
const finite = (v: number): number | null => (Number.isFinite(v) ? v : null);

/** "HH:MM" and "MM-DD" at a fixed UTC offset: text independent of the runner's zone. */
export function fixedOffsetFormatters(offsetHours: number): Formatters {
  const shift = (d: Date) => new Date(d.getTime() + offsetHours * 3_600_000).toISOString();
  return { time: (d) => shift(d).slice(11, 16), date: (d) => shift(d).slice(5, 10) };
}

function serialiseNight(n: ShowerNight) {
  return {
    evening_utc: iso(n.eveningUtc),
    darkness: n.darkness ? { start: iso(n.darkness.start), end: iso(n.darkness.end) } : null,
    max_altitude_deg: finite(n.maxAltitudeDeg),
    max_altitude_at: iso(n.maxAltitudeAt),
    radiant_observable: n.radiantObservable,
    radiant_window: n.radiantWindow
      ? { start: iso(n.radiantWindow.start), end: iso(n.radiantWindow.end) }
      : null,
    moon_illum_fraction: n.moonIllumFraction,
    // Built by `moonFreeWindows`, so each carries its minutes.
    usable_windows: (n.usableWindows as MoonFreeWindow[]).map((w) => ({ start: iso(w.start), end: iso(w.end), minutes: w.minutes })),
    usable_minutes: n.usableMinutes,
  };
}

function expected(c: Case) {
  const site: Site = { latitude: c.latitude, longitude: c.longitude, elevationM: c.elevation_m };
  const centre = new Date(c.centre_utc);
  const window = windowAround(centre);
  const result = buildSkyEvents(site, centre, { formatters: fixedOffsetFormatters(c.utc_offset_hours) });
  const showers = curatedEventsInWindow(CURATED.events, window.start, window.end)
    .filter((e) => e.kind === "meteor_shower" && e.radiantRaHours !== null && e.radiantDecDeg !== null)
    .map((e) => {
      const span = activeSpan(e);
      const a = assessShower(
        site,
        { raHours: e.radiantRaHours!, decDeg: e.radiantDecDeg! },
        e.peakUtc ?? anchorOf(e),
        span.start,
        span.end,
      );
      return {
        id: e.id,
        observable_here: a.observableHere,
        peak_night: serialiseNight(a.peakNight),
        better_night: a.betterNight ? serialiseNight(a.betterNight) : null,
      };
    });

  return {
    window: { start: iso(result.window.start), end: iso(result.window.end) },
    moon_phases: moonPhases(window).map((p) => ({ at: iso(p.at), angle: p.angle })),
    apparitions: [...planetOppositions(window), ...greatestElongations(window)].map((a) => ({
      at: iso(a.at),
      body: a.body,
      kind: a.kind,
      elongation_deg: a.elongationDeg,
      visibility: a.visibility,
    })),
    pairings: moonPlanetPairings(site, window).map((p) => ({
      body: p.body,
      at: iso(p.at),
      separation_deg: p.separationDeg,
      observable_here: p.observableHere,
      moon_altitude_deg: p.moonAltitudeDeg,
      body_altitude_deg: p.bodyAltitudeDeg,
      moon_illum_fraction: p.moonIllumFraction,
      geocentric_min_deg: p.geocentricMinDeg,
      geocentric_min_at: iso(p.geocentricMinAt),
      possible_occultation: p.possibleOccultation,
      occultation: p.occultation
        ? {
            min_separation_deg: p.occultation.minSeparationDeg,
            min_separation_at: iso(p.occultation.minSeparationAt),
            moon_radius_deg: p.occultation.moonRadiusDeg,
            moon_altitude_deg: p.occultation.moonAltitudeDeg,
            sun_altitude_deg: p.occultation.sunAltitudeDeg,
            behind_disc_from_here: p.occultation.behindDiscFromHere,
            disappears_at: iso(p.occultation.disappearsAt),
            reappears_at: iso(p.occultation.reappearsAt),
            reappear_moon_altitude_deg: p.occultation.reappearMoonAltitudeDeg,
          }
        : null,
    })),
    zodiacal: zodiacalLightRanges(site, window).map((r) => ({
      season: r.season,
      start: iso(r.start),
      end: iso(r.end),
      nights: r.nights,
    })),
    seasons: seasonMarkers(window).map((s) => ({ at: iso(s.at), name: s.name })),
    showers,
    items: result.items.map((i) => ({
      at: iso(i.at),
      until: iso(i.until),
      category: i.category,
      title: i.title,
      verdict: i.verdict,
      provenance: i.provenance,
    })),
    problems: result.problems,
  };
}

function build() {
  return {
    generated_by: "app/tests/sky-events-golden.test.ts (buildSkyEvents, astronomy-engine, TypeScript)",
    astronomy_engine: ASTRONOMY_ENGINE_VERSION,
    curated_file: "config/sky-events.json",
    window_days: 30,
    tolerance: TOLERANCE,
    cases: CASES.map((c) => ({ ...c, expected: expected(c) })),
  };
}

describe("golden sky-events vectors", () => {
  const current = build();

  it("match the committed cross-platform contract", () => {
    if (process.env.UPDATE_GOLDEN) {
      writeFileSync(GOLDEN_PATH, `${JSON.stringify(current, null, 2)}\n`);
    }
    expect(current).toEqual(JSON.parse(readFileSync(GOLDEN_PATH, "utf8")));
  });

  it("covers every item category the agenda can produce", () => {
    const categories = new Set<string>(current.cases.flatMap((c) => c.expected.items.map((i) => i.category)));
    for (const k of ["moon", "planet", "conjunction", "meteor_shower", "zodiacal", "season", "place"]) {
      expect(categories.has(k), k).toBe(true);
    }
  });
});
