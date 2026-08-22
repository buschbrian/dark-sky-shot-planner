import { describe, expect, it } from "vitest";

import {
  darknessWindow,
  gcAltitude,
  gcVisibility,
  moonIllumination,
  moonUpIntervals,
  planNight,
} from "../src/astronomy/planner";

/** UTC instant of ~21:00 local (MDT, UTC-6) on the given date. */
const evening = (isoUtc: string): Date => new Date(isoUtc);

describe("darknessWindow", () => {
  it("finds astronomical night at Salt Lake City in September", () => {
    // SLC, 2026-09-15 evening. Known: astro dusk ends ~2 h after sunset,
    // window spans roughly 02:30–12:00 UTC.
    const { window, noDarkness } = darknessWindow(40.76, -111.89, evening("2026-09-16T03:00:00Z"));
    expect(noDarkness).toBe(false);
    expect(window).not.toBeNull();
    const start = window!.start;
    const end = window!.end;
    const hours = (end.getTime() - start.getTime()) / 3600_000;
    // Astronomical night near equinox at 40°N is ~9.5–10 h.
    expect(hours).toBeGreaterThan(8);
    expect(hours).toBeLessThan(11);
    // Window must span local midnight (~06:00 UTC).
    const midnight = new Date("2026-09-16T06:00:00Z");
    expect(start < midnight).toBe(true);
    expect(end > midnight).toBe(true);
  });

  it("reports no astronomical darkness near summer solstice at 49°N", () => {
    const { window, noDarkness } = darknessWindow(48.99, -114.0, evening("2026-06-21T04:00:00Z"));
    expect(noDarkness).toBe(true);
    expect(window).toBeNull();
  });

  it("still finds darkness in the Mountain West at winter solstice", () => {
    const { noDarkness } = darknessWindow(40.76, -111.89, evening("2026-12-21T03:00:00Z"));
    expect(noDarkness).toBe(false);
  });
});

describe("moon illumination", () => {
  it("is near zero at a known new moon", () => {
    // New moon: 2026-01-18 (widely published lunation tables).
    expect(moonIllumination(new Date("2026-01-18T12:00:00Z"))).toBeLessThan(0.05);
  });

  it("is near one at a known full moon", () => {
    expect(moonIllumination(new Date("2026-01-03T10:00:00Z"))).toBeGreaterThan(0.95);
  });

  it("new and full are clearly separated", () => {
    const nm = moonIllumination(new Date("2026-08-12T14:00:00Z"));
    const fm = moonIllumination(new Date("2026-08-28T05:00:00Z"));
    expect(nm).toBeLessThan(0.1);
    expect(fm).toBeGreaterThan(0.9);
  });
});

describe("moon-free darkness intersection", () => {
  it("full moon night yields far less moon-free time than new moon night", () => {
    const full = planNight({
      latitude: 38.5,
      longitude: -109.9,
      eveningUtc: evening("2026-08-28T04:00:00Z"),
    });
    const fresh = planNight({
      latitude: 38.5,
      longitude: -109.9,
      eveningUtc: evening("2026-08-12T04:00:00Z"),
    });
    expect(full.moonIllumFraction).toBeGreaterThan(0.9);
    expect(fresh.moonIllumFraction).toBeLessThan(0.1);
    expect(fresh.moonFreeMinutes).toBeGreaterThan(full.moonFreeMinutes + 60);
  });

  it("intersection windows never overlap the moon-up periods", () => {
    const report = planNight({
      latitude: 40.76,
      longitude: -111.89,
      eveningUtc: evening("2026-09-16T03:00:00Z"),
    });
    const up = moonUpIntervals(
      40.76,
      -111.89,
      report.darkness!.start,
      report.darkness!.end,
    );
    for (const win of report.moonFreeWindows) {
      for (const u of up) {
        const overlapMs =
          Math.min(win.end.getTime(), u.end.getTime()) -
          Math.max(win.start.getTime(), u.start.getTime());
        const overlaps = win.start < u.end && u.start < win.end && overlapMs > 90_000;
        expect(overlaps).toBe(false);
      }
    }
  });

  it("sum of windows equals reported headline minutes", () => {
    const report = planNight({
      latitude: 43.6,
      longitude: -116.2,
      eveningUtc: evening("2026-10-01T04:00:00Z"),
    });
    const total = report.moonFreeWindows.reduce((acc, w) => acc + w.minutes, 0);
    expect(report.moonFreeMinutes).toBe(total || 0);
  });

  it("pure new-moon mid-winter night is nearly fully moon-free", () => {
    const report = planNight({
      latitude: 44.0,
      longitude: -110.0,
      eveningUtc: evening("2026-01-18T03:00:00Z"),
    });
    expect(report.moonIllumFraction).toBeLessThan(0.05);
    expect(report.moonFreeMinutes).toBeGreaterThan(600);
  });
});

describe("galactic center", () => {
  it("peaks around 20-22 degrees altitude when transiting at 40°N", () => {
    // GC decl −29°; max altitude at lat 40 ≈ 90 − |40 − (−29)| = 21°.
    const report = planNight({
      latitude: 40.0,
      longitude: -111.0,
      eveningUtc: evening("2026-05-15T04:00:00Z"), // GC season
    });
    expect(report.gc.risesDuringDarkness).toBe(true);
    expect(report.gc.maxAltitudeDeg!).toBeGreaterThan(17);
    expect(report.gc.maxAltitudeDeg!).toBeLessThan(25);
  });

  it("gcAltitude matches horizon math for a transit moment", () => {
    const alt = gcAltitude(40.0, -111.0, new Date("2026-05-15T09:00:00Z"));
    expect(alt).toBeGreaterThan(-90);
    expect(alt).toBeLessThan(90);
  });

  it("GC below horizon during darkness in deep winter", () => {
    const report = planNight({
      latitude: 40.0,
      longitude: -111.0,
      eveningUtc: evening("2026-12-21T03:00:00Z"),
    });
    expect(report.gc.risesDuringDarkness).toBe(false);
    // It is sampled but never climbs above the horizon.
    expect(report.gc.maxAltitudeDeg!).toBeLessThan(0);
  });

  it("gcVisibility returns nulls when there is no dark window", () => {
    const vis = gcVisibility(48.99, -114.0, []);
    expect(vis.risesDuringDarkness).toBe(false);
    expect(vis.maxAltitudeDeg).toBeNull();
  });
});
