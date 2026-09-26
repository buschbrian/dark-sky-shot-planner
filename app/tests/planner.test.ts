import * as Astronomy from "astronomy-engine";
import { describe, expect, it } from "vitest";

import {
  GC_DEC_DEG,
  GC_RA_HOURS,
  darknessWindow,
  gcAltitude,
  gcAzimuth,
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

  it("seeds moon-up from the last rise/set, not refracted centre altitude", () => {
    // Central Utah, 2026-04-21: the scan starts (darkness − 12 h) at 15:46:13Z,
    // ~53 s after moonrise (top limb) while the centre is still at −0.11°
    // refracted. The moon then sets 07:42Z, four hours into darkness.
    const report = planNight({
      latitude: 38.44,
      longitude: -111.89,
      eveningUtc: evening("2026-04-22T03:00:00Z"),
    });
    const darkStart = report.darkness!.start;
    expect(report.moonset).not.toBeNull();
    expect(report.moonset!.getTime()).toBeGreaterThan(darkStart.getTime() + 3 * 3600_000);
    const up = moonUpIntervals(38.44, -111.89, darkStart, report.darkness!.end);
    expect(up[0]!.start.getTime()).toBeLessThan(darkStart.getTime());
    expect(Math.abs(up[0]!.end.getTime() - report.moonset!.getTime())).toBeLessThan(1000);
    expect(Math.abs(report.moonFreeWindows[0]!.start.getTime() - report.moonset!.getTime())).toBeLessThan(1000);
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

/**
 * Independent reference for the GC's horizon position: Meeus, *Astronomical
 * Algorithms* 2nd ed., rigorous precession (eqs. 21.2–21.4), GMST (eq. 12.4)
 * and horizontal coordinates (eqs. 13.5–13.6). No nutation or aberration;
 * together they move the GC by < 0.01°.
 */
const RAD = Math.PI / 180;

function meeusPrecess(raDeg: number, decDeg: number, jd: number): { ra: number; dec: number } {
  const T = (jd - 2451545.0) / 36525;
  const arcsec = (x: number): number => (x / 3600) * RAD;
  const zeta = arcsec(2306.2181 * T + 0.30188 * T ** 2 + 0.017998 * T ** 3);
  const z = arcsec(2306.2181 * T + 1.09468 * T ** 2 + 0.018203 * T ** 3);
  const theta = arcsec(2004.3109 * T - 0.42665 * T ** 2 - 0.041833 * T ** 3);
  const a0 = raDeg * RAD;
  const d0 = decDeg * RAD;
  const A = Math.cos(d0) * Math.sin(a0 + zeta);
  const B = Math.cos(theta) * Math.cos(d0) * Math.cos(a0 + zeta) - Math.sin(theta) * Math.sin(d0);
  const C = Math.sin(theta) * Math.cos(d0) * Math.cos(a0 + zeta) + Math.cos(theta) * Math.sin(d0);
  return { ra: ((Math.atan2(A, B) + z) / RAD + 360) % 360, dec: Math.asin(C) / RAD };
}

function meeusGmstDeg(jd: number): number {
  const T = (jd - 2451545.0) / 36525;
  const g = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T ** 2 - T ** 3 / 38710000;
  return ((g % 360) + 360) % 360;
}

function meeusGc(lat: number, lon: number, when: Date): { alt: number; az: number } {
  const jd = when.getTime() / 86_400_000 + 2440587.5;
  const { ra, dec } = meeusPrecess(GC_RA_HOURS * 15, GC_DEC_DEG, jd);
  const H = (meeusGmstDeg(jd) + lon - ra) * RAD;
  const phi = lat * RAD;
  const d = dec * RAD;
  const alt = Math.asin(Math.sin(phi) * Math.sin(d) + Math.cos(phi) * Math.cos(d) * Math.cos(H));
  const azFromSouth = Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(phi) - Math.tan(d) * Math.cos(phi));
  return { alt: alt / RAD, az: (azFromSouth / RAD + 180 + 360) % 360 };
}

function separationDeg(a: { alt: number; az: number }, b: { alt: number; az: number }): number {
  const c =
    Math.sin(a.alt * RAD) * Math.sin(b.alt * RAD) +
    Math.cos(a.alt * RAD) * Math.cos(b.alt * RAD) * Math.cos((a.az - b.az) * RAD);
  return Math.acos(Math.min(1, c)) / RAD;
}

describe("GC position against an independent precessed reference", () => {
  it("reproduces Meeus's worked examples 21.b (precession) and 12.b (GMST)", () => {
    const p = meeusPrecess(41.054063, 49.22775, 2462088.69);
    expect(p.ra).toBeCloseTo(41.547214, 5);
    expect(p.dec).toBeCloseTo(49.348483, 5);
    expect(meeusGmstDeg(2446896.30625)).toBeCloseTo(128.7378734, 6);
  });

  const sites = [
    { lat: 38.374031, lon: -109.965416, utc: "2026-06-16T07:27:18.530Z" },
    { lat: 40.76, lon: -111.89, utc: "2026-09-16T03:36:01.331Z" },
    { lat: 37.593, lon: -112.187, utc: "2026-04-19T11:14:07.491Z" },
    { lat: 43.417, lon: -113.563, utc: "2026-09-11T06:00:00.000Z" },
  ];

  it.each(sites)("gcAltitude/gcAzimuth agree within 0.02° at $utc", ({ lat, lon, utc }) => {
    const when = new Date(utc);
    const ref = meeusGc(lat, lon, when);
    const ours = { alt: gcAltitude(lat, lon, when), az: gcAzimuth(lat, lon, when) };
    expect(separationDeg(ours, ref)).toBeLessThan(0.02);
    // The pre-fix J2000-as-of-date position misses the reference by ~0.3°.
    const h = Astronomy.Horizon(when, new Astronomy.Observer(lat, lon, 0), GC_RA_HOURS, GC_DEC_DEG);
    expect(separationDeg({ alt: h.altitude, az: h.azimuth }, ref)).toBeGreaterThan(0.2);
  });
});
