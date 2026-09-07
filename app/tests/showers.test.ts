import { describe, expect, it } from "vitest";

import {
  RADIANT_MIN_ALTITUDE_DEG,
  assessNight,
  assessShower,
  eveningFor,
  radiantAltitudeDeg,
} from "../src/astronomy/showers";
import type { Site } from "../src/astronomy/events";

const MILLCREEK: Site = { latitude: 40.687, longitude: -111.824, elevationM: 1400 };

/** Orionids 2026: radiant RA 6.3 h, Dec +16, peak 2026-10-23T06:54Z. */
const ORIONIDS = { raHours: 6.3, decDeg: 16 };
/** Draconids: a high-declination radiant, circumpolar from Utah. */
const DRACONIDS = { raHours: 17.5, decDeg: 54 };

const DAY_MS = 86_400_000;

describe("radiantAltitudeDeg", () => {
  it("peaks at 90 − |latitude − declination| across a day", () => {
    // The transit altitude of a fixed point is pure geometry; anything else
    // means the J2000 → of-date conversion is wrong.
    let max = -90;
    for (let t = 0; t < 24 * 60; t += 5) {
      const when = new Date(Date.UTC(2026, 9, 23, 0, t));
      max = Math.max(max, radiantAltitudeDeg(MILLCREEK, ORIONIDS, when));
    }
    const expected = 90 - Math.abs(MILLCREEK.latitude - ORIONIDS.decDeg);
    expect(Math.abs(max - expected)).toBeLessThan(0.6);
  });

  it("applies precession rather than treating J2000 as of-date", () => {
    // 26 years of precession is ~0.35°: small, but not zero, and the curated
    // file is meant to outlive the year it was written in.
    const near = radiantAltitudeDeg(MILLCREEK, ORIONIDS, new Date("2026-10-23T11:00:00Z"));
    const far = radiantAltitudeDeg(MILLCREEK, ORIONIDS, new Date("2126-10-23T11:00:00Z"));
    expect(near).not.toBe(far);
  });
});

describe("eveningFor", () => {
  it("puts an evening peak on the night that is starting", () => {
    // 2026-10-09T01:00Z is 18:00 the previous evening in Utah.
    const evening = eveningFor(new Date("2026-10-09T01:00:00Z"), MILLCREEK.longitude);
    expect(evening.toISOString().slice(0, 10)).toBe("2026-10-09");
  });

  it("puts a morning peak on the night that just ended", () => {
    // 2026-10-23T06:54Z is 00:54 local: the night that began on the 22nd.
    const evening = eveningFor(new Date("2026-10-23T06:54:00Z"), MILLCREEK.longitude);
    const localMeanTime = new Date(
      evening.getTime() + (MILLCREEK.longitude / 15) * 3_600_000,
    );
    expect(localMeanTime.toISOString().slice(0, 13)).toBe("2026-10-22T21");
  });

  it("is stable across a whole night", () => {
    // Dusk and the small hours that follow belong to the same night.
    const dusk = eveningFor(new Date("2026-10-23T02:00:00Z"), MILLCREEK.longitude);
    const smallHours = eveningFor(new Date("2026-10-23T09:00:00Z"), MILLCREEK.longitude);
    expect(dusk.getTime()).toBe(smallHours.getTime());
  });
});

describe("assessNight", () => {
  const night = assessNight(MILLCREEK, ORIONIDS, new Date("2026-10-22T21:00:00-06:00"));

  it("finds the radiant window inside astronomical darkness", () => {
    expect(night.darkness).not.toBeNull();
    expect(night.radiantObservable).toBe(true);
    expect(night.radiantWindow!.start >= night.darkness!.start).toBe(true);
    expect(night.radiantWindow!.end <= night.darkness!.end).toBe(true);
  });

  it("never claims the radiant is up below the cutoff", () => {
    const w = night.radiantWindow!;
    for (const t of [w.start, w.end, new Date((w.start.getTime() + w.end.getTime()) / 2)]) {
      // Sampling is five-minutely, so allow one step of slack at the edges.
      expect(radiantAltitudeDeg(MILLCREEK, ORIONIDS, t)).toBeGreaterThan(
        RADIANT_MIN_ALTITUDE_DEG - 1.5,
      );
    }
  });

  it("reports the bright moon that spoils the 2026 Orionid peak", () => {
    // Full moon is 2026-10-26; the peak night moon is ~90% lit and up for
    // most of the radiant window.
    expect(night.moonIllumFraction).toBeGreaterThan(0.8);
    expect(night.usableMinutes).toBeGreaterThan(0);
    const radiantMinutes = Math.round(
      (night.radiantWindow!.end.getTime() - night.radiantWindow!.start.getTime()) / 60_000,
    );
    expect(night.usableMinutes).toBeLessThan(radiantMinutes / 2);
  });

  it("usable windows never extend past the radiant window", () => {
    for (const u of night.usableWindows) {
      expect(u.start >= night.radiantWindow!.start).toBe(true);
      expect(u.end <= night.radiantWindow!.end).toBe(true);
    }
  });
});

describe("assessShower", () => {
  const peak = new Date("2026-10-23T06:54:00Z");
  const from = new Date("2026-10-02T00:00:00Z");
  const to = new Date("2026-11-08T00:00:00Z");

  it("offers a materially better night when the peak night is moonlit", () => {
    const a = assessShower(MILLCREEK, ORIONIDS, peak, from, to);
    expect(a.observableHere).toBe(true);
    expect(a.betterNight).not.toBeNull();
    expect(a.betterNight!.usableMinutes).toBeGreaterThan(a.peakNight.usableMinutes + 30);
  });

  it("never suggests a night outside the active range", () => {
    const narrow = assessShower(
      MILLCREEK,
      ORIONIDS,
      peak,
      new Date(peak.getTime() - DAY_MS),
      new Date(peak.getTime() + DAY_MS),
    );
    if (narrow.betterNight) {
      expect(narrow.betterNight.eveningUtc >= new Date(peak.getTime() - DAY_MS)).toBe(true);
      expect(narrow.betterNight.eveningUtc <= new Date(peak.getTime() + DAY_MS)).toBe(true);
    }
  });

  it("says a northern radiant is unobservable from the southern hemisphere", () => {
    // Dec +54 from 40°S never gets above the horizon, let alone 10°.
    const patagonia: Site = { latitude: -40.0, longitude: -71.0 };
    const a = assessShower(
      patagonia,
      DRACONIDS,
      new Date("2026-10-09T01:00:00Z"),
      new Date("2026-10-06T00:00:00Z"),
      new Date("2026-10-11T00:00:00Z"),
    );
    expect(a.observableHere).toBe(false);
    expect(a.peakNight.radiantObservable).toBe(false);
    expect(a.peakNight.usableMinutes).toBe(0);
  });
});
