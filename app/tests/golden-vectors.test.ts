/**
 * Cross-platform golden vectors for the night planner.
 *
 * `shared/golden/night-report.json` is the contract between this TypeScript
 * planner (the reference implementation) and any port of it, starting with
 * the iOS app's SkyCore package (ADR-0009). Both suites read the same file;
 * if a port disagrees beyond the stated tolerances, the port is wrong until
 * proven otherwise.
 *
 * Regenerate after an intentional change to the planner:
 *   UPDATE_GOLDEN=1 npx vitest run app/tests/golden-vectors.test.ts
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { gcAltitude, gcAzimuth, planNight, type NightReport } from "../src/astronomy/planner";

const GOLDEN_PATH = resolve(__dirname, "../../shared/golden/night-report.json");
const GC_HORIZON_PATH = resolve(__dirname, "../../shared/golden/gc-horizon.json");

/** The installed library, read at generation time: ports must vendor the same one. */
const ASTRONOMY_ENGINE_VERSION: string = JSON.parse(
  readFileSync(resolve(__dirname, "../../node_modules/astronomy-engine/package.json"), "utf8"),
).version;

/** Tolerances any port must meet. Times in seconds, angles in degrees. */
const TOLERANCE = { time_s: 60, altitude_deg: 0.1, illum_fraction: 0.002, minutes: 2 };

interface Case {
  id: string;
  note: string;
  latitude: number;
  longitude: number;
  evening_utc: string;
}

// The planner test edge cases (brief §5), plus real Mountain West sites.
const CASES: Case[] = [
  { id: "slc-2026-09-15", note: "Near equinox, 40°N", latitude: 40.76, longitude: -111.89, evening_utc: "2026-09-16T03:00:00Z" },
  { id: "glacier-2026-06-20", note: "Summer solstice at 49°N: no astronomical darkness", latitude: 48.99, longitude: -114.0, evening_utc: "2026-06-21T04:00:00Z" },
  { id: "slc-2026-12-21", note: "Winter solstice, near full moon: zero moon-free minutes", latitude: 40.76, longitude: -111.89, evening_utc: "2026-12-22T02:00:00Z" },
  { id: "canyonlands-2026-06-15", note: "Near new moon, GC season", latitude: 38.374031, longitude: -109.965416, evening_utc: "2026-06-16T03:00:00Z" },
  { id: "canyonlands-2026-06-29", note: "Near full moon", latitude: 38.374031, longitude: -109.965416, evening_utc: "2026-06-30T03:00:00Z" },
  { id: "great-basin-2026-08-07", note: "Partial moon: moon-free window shorter than the night", latitude: 38.98, longitude: -114.3, evening_utc: "2026-08-08T03:00:00Z" },
  { id: "bryce-2026-04-18", note: "Spring: GC only before dawn", latitude: 37.593, longitude: -112.187, evening_utc: "2026-04-19T03:00:00Z" },
  { id: "craters-2026-09-10", note: "Idaho, new moon: whole night moon-free", latitude: 43.417, longitude: -113.563, evening_utc: "2026-09-11T03:00:00Z" },
];

const iso = (d: Date | null): string | null => (d ? d.toISOString() : null);

function serialise(r: NightReport) {
  return {
    darkness: r.darkness ? { start: iso(r.darkness.start), end: iso(r.darkness.end) } : null,
    no_astronomical_darkness: r.noAstronomicalDarkness,
    moon_illum_fraction: r.moonIllumFraction,
    moonset: iso(r.moonset),
    moonrise: iso(r.moonrise),
    moon_free_windows: r.moonFreeWindows.map((w) => ({
      start: iso(w.start),
      end: iso(w.end),
      minutes: w.minutes,
    })),
    moon_free_minutes: r.moonFreeMinutes,
    gc: {
      max_altitude_deg: r.gc.maxAltitudeDeg === null ? null : Math.round(r.gc.maxAltitudeDeg * 100) / 100,
      max_altitude_at: iso(r.gc.maxAltitudeAt),
      rises_during_darkness: r.gc.risesDuringDarkness,
    },
  };
}

function build() {
  return {
    generated_by: "app/tests/golden-vectors.test.ts (astronomy-engine, TypeScript)",
    astronomy_engine: ASTRONOMY_ENGINE_VERSION,
    tolerance: TOLERANCE,
    cases: CASES.map((c) => ({
      ...c,
      expected: serialise(
        planNight({ latitude: c.latitude, longitude: c.longitude, eveningUtc: new Date(c.evening_utc) }),
      ),
    })),
  };
}

// GC alt/az spot checks for ports: peaks, twilight edges, and below-horizon.
const GC_POINTS = [
  { id: "canyonlands-peak", latitude: 38.374031, longitude: -109.965416, utc: "2026-06-16T07:27:18.530Z" },
  { id: "slc-evening", latitude: 40.76, longitude: -111.89, utc: "2026-09-16T03:36:01.331Z" },
  { id: "bryce-predawn", latitude: 37.593, longitude: -112.187, utc: "2026-04-19T11:14:07.491Z" },
  { id: "great-basin-dusk", latitude: 38.98, longitude: -114.3, utc: "2026-08-08T04:24:27.001Z" },
  { id: "craters-midnight", latitude: 43.417, longitude: -113.563, utc: "2026-09-11T06:00:00.000Z" },
  { id: "glacier-noon-below", latitude: 48.99, longitude: -114.0, utc: "2026-06-21T19:00:00.000Z" },
];

function buildGcHorizon() {
  return {
    generated_by: "app/tests/golden-vectors.test.ts (planner.ts gcAltitude/gcAzimuth)",
    astronomy_engine: ASTRONOMY_ENGINE_VERSION,
    tolerance: { altitude_deg: 0.1, azimuth_deg: 0.1 },
    points: GC_POINTS.map((p) => {
      const when = new Date(p.utc);
      return {
        ...p,
        altitude_deg: Math.round(gcAltitude(p.latitude, p.longitude, when) * 1e4) / 1e4,
        azimuth_deg: Math.round(gcAzimuth(p.latitude, p.longitude, when) * 1e4) / 1e4,
      };
    }),
  };
}

describe("golden files record the astronomy-engine that wrote them", () => {
  it.each([GOLDEN_PATH, GC_HORIZON_PATH])("%s", (path) => {
    expect(JSON.parse(readFileSync(path, "utf8")).astronomy_engine).toBe(ASTRONOMY_ENGINE_VERSION);
  });
});

describe("golden GC horizon points", () => {
  it("match the committed cross-platform contract", () => {
    const current = buildGcHorizon();
    if (process.env.UPDATE_GOLDEN) {
      writeFileSync(GC_HORIZON_PATH, `${JSON.stringify(current, null, 2)}\n`);
    }
    expect(current).toEqual(JSON.parse(readFileSync(GC_HORIZON_PATH, "utf8")));
  });
});

describe("golden night-report vectors", () => {
  it("match the committed cross-platform contract", () => {
    const current = build();
    if (process.env.UPDATE_GOLDEN) {
      mkdirSync(dirname(GOLDEN_PATH), { recursive: true });
      writeFileSync(GOLDEN_PATH, `${JSON.stringify(current, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(GOLDEN_PATH, "utf8"));
    expect(current).toEqual(committed);
  });
});
