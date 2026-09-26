import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { HorizonProfile } from "../src/astronomy/horizon";
import { moonUpIntervalsOverTerrain, planNight } from "../src/astronomy/planner";

const candlestick = HorizonProfile.parse(
  readFileSync(resolve(__dirname, "../../config/horizon-profiles/candlestick-camp.csv"), "utf8"),
);
const CAMP = { latitude: 38.374031, longitude: -109.965416 };

describe("HorizonProfile", () => {
  it("parses the Candlestick Camp profile as the README describes it", () => {
    expect(candlestick.samples).toHaveLength(360);
    const alts = candlestick.samples.map((s) => s.altitudeDeg);
    expect(Math.min(...alts)).toBe(1.024);
    expect(Math.max(...alts)).toBe(8.7);
    expect(candlestick.altitudeAt(326)).toBe(1.024);
    expect(candlestick.altitudeAt(14)).toBe(8.7);
    // README: "The 1° file interpolates to 4.91° there" (azimuth 82.60°).
    expect(candlestick.altitudeAt(82.6)).toBeCloseTo(4.9142, 4);
  });

  it("wraps across north", () => {
    const between = (4.418 + 4.396) / 2;
    expect(candlestick.altitudeAt(359.5)).toBeCloseTo(between, 12);
    expect(candlestick.altitudeAt(-0.5)).toBeCloseTo(between, 12);
    expect(candlestick.altitudeAt(360)).toBe(4.396);
    expect(candlestick.altitudeAt(720 + 14)).toBe(8.7);
  });

  it("interpolates uneven samples, including the wrap segment", () => {
    const p = new HorizonProfile([
      { azimuthDeg: 10, altitudeDeg: 2 },
      { azimuthDeg: 100, altitudeDeg: 11 },
      { azimuthDeg: 300, altitudeDeg: -1 },
    ]);
    expect(p.altitudeAt(55)).toBeCloseTo(6.5, 12);
    expect(p.altitudeAt(200)).toBeCloseTo(5, 12);
    // 300 -> 370 (10): 70° span, 5 is 65° in.
    expect(p.altitudeAt(5)).toBeCloseTo(-1 + (3 * 65) / 70, 12);
    expect(HorizonProfile.flat(3).altitudeAt(123)).toBe(3);
  });

  it("rejects malformed files", () => {
    expect(() => HorizonProfile.parse("az,alt\n0,1\n")).toThrow(/header/);
    expect(() => HorizonProfile.parse("azimuth_deg,horizon_alt_deg\n0,x\n")).toThrow(/line 2/);
    expect(() => HorizonProfile.parse("azimuth_deg,horizon_alt_deg\n0,1\n0,2\n")).toThrow(/increase/);
    expect(() => HorizonProfile.parse("azimuth_deg,horizon_alt_deg\n360,1\n")).toThrow(/azimuth/);
    expect(() => HorizonProfile.parse("azimuth_deg,horizon_alt_deg\n0,91\n")).toThrow(/altitude/);
    expect(() => HorizonProfile.parse("azimuth_deg,horizon_alt_deg\n")).toThrow(/no samples/);
    expect(HorizonProfile.parse("azimuth_deg,horizon_alt_deg\r\n0,1\r\n90,2\r\n").samples).toHaveLength(2);
  });
});

describe("planNight over terrain", () => {
  const night = { ...CAMP, eveningUtc: new Date("2026-05-07T03:00:00Z") };

  it("is unchanged without a profile", () => {
    const report = planNight(night);
    expect(report.terrain).toBeUndefined();
    expect(planNight({ ...night, horizon: undefined })).toEqual(report);
  });

  it("with a flat 0° skyline stays within the golden tolerances of the flat planner", () => {
    for (const evening of ["2026-05-07T03:00:00Z", "2026-06-25T03:00:00Z", "2026-09-16T03:00:00Z"]) {
      const input = { ...CAMP, eveningUtc: new Date(evening) };
      const flat = planNight(input);
      const zero = planNight({ ...input, horizon: HorizonProfile.flat(0) });
      for (const key of ["moonrise", "moonset"] as const) {
        expect(zero[key] === null).toBe(flat[key] === null);
        if (zero[key] && flat[key]) {
          expect(Math.abs(zero[key]!.getTime() - flat[key]!.getTime())).toBeLessThan(60_000);
        }
      }
      expect(Math.abs(zero.moonFreeMinutes - flat.moonFreeMinutes)).toBeLessThanOrEqual(2);
      expect(Math.abs(zero.gc.maxAltitudeDeg! - flat.gc.maxAltitudeDeg!)).toBeLessThanOrEqual(0.1);
    }
  });

  it("delays moonrise behind the Candlestick skyline and adds moon-free minutes", () => {
    const flat = planNight(night);
    const terrain = planNight({ ...night, horizon: candlestick });
    expect(terrain.moonrise!.getTime()).toBeGreaterThan(flat.moonrise!.getTime() + 20 * 60_000);
    expect(terrain.moonFreeMinutes).toBeGreaterThan(flat.moonFreeMinutes + 20);
    expect(flat.gc.maxAltitudeDeg!).toBeLessThan(12);
    expect(terrain.gc.maxAltitudeDeg!).toBeGreaterThanOrEqual(12);

    const up = moonUpIntervalsOverTerrain(
      CAMP.latitude,
      CAMP.longitude,
      candlestick,
      terrain.darkness!.start,
      terrain.darkness!.end,
    );
    for (const w of terrain.moonFreeWindows) {
      for (const u of up) expect(w.end <= u.start || u.end <= w.start).toBe(true);
    }
    const t = terrain.terrain!;
    expect(t.gcClearsSkyline).not.toBeNull();
    expect(t.gcAboveSkyline[0]!.start).toEqual(t.gcClearsSkyline);
    expect(t.gcMinutes).toBe(Math.max(...t.gcWindows.map((w) => w.minutes)));
    for (const w of t.gcWindows) expect(w.start >= t.gcClearsSkyline!).toBe(true);
  });

  it("brings moonset forward on a waxing night", () => {
    const input = { ...CAMP, eveningUtc: new Date("2026-06-25T03:00:00Z") };
    const flat = planNight(input);
    const terrain = planNight({ ...input, horizon: candlestick });
    expect(terrain.moonset!.getTime()).toBeLessThan(flat.moonset!.getTime() - 10 * 60_000);
    expect(terrain.moonFreeMinutes).toBeGreaterThan(flat.moonFreeMinutes);
  });

  it("hides the moon and the GC entirely behind a wall", () => {
    const report = planNight({ ...night, horizon: HorizonProfile.flat(60) });
    expect(report.moonrise).toBeNull();
    expect(report.moonFreeMinutes).toBe(
      Math.round((report.darkness!.end.getTime() - report.darkness!.start.getTime()) / 60_000),
    );
    expect(report.gc).toEqual({ maxAltitudeDeg: null, maxAltitudeAt: null, risesDuringDarkness: false });
    expect(report.terrain!.gcAboveSkyline).toEqual([]);
    expect(report.terrain!.gcMinutes).toBe(0);
  });

  it("keeps the moon up longer below a negative (dipped) skyline", () => {
    const flat = planNight(night);
    const dipped = planNight({ ...night, horizon: HorizonProfile.flat(-2) });
    expect(dipped.moonrise!.getTime()).toBeLessThan(flat.moonrise!.getTime());
    expect(dipped.moonFreeMinutes).toBeLessThan(flat.moonFreeMinutes);
  });
});
