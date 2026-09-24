import * as Astronomy from "astronomy-engine";
import { describe, expect, it } from "vitest";

import {
  OCCULTATION_CHECK_DEG,
  OCCULTATION_FLAG_DEG,
  geocentricSeparationDeg,
  greatestElongations,
  moonPhases,
  moonPlanetPairings,
  planetOppositions,
  seasonMarkers,
  siteCivilDate,
  topocentricSeparationDeg,
  windowAround,
  zodiacalLightRanges,
  type MoonPairing,
  type Site,
  type TimeWindow,
} from "../src/astronomy/events";

/**
 * Golden values were computed with astronomy-engine 2.1.19 for Millcreek,
 * Utah and are quoted in the source as local MDT (UTC−6). Assertions compare
 * UTC instants so the suite does not depend on the runner's timezone.
 *
 * Tolerances: ±2 minutes, ±0.05°.
 */
const MILLCREEK: Site = { latitude: 40.687, longitude: -111.824, elevationM: 1400 };

const MINUTE = 60_000;
const TIME_TOLERANCE_MS = 2 * MINUTE;
const ANGLE_TOLERANCE_DEG = 0.05;

/** An MDT (UTC−6) wall-clock instant, as UTC. */
const mdt = (isoLocal: string): Date => new Date(`${isoLocal}-06:00`);

/** The window the app uses for a night planned on 2026-09-22 from Millcreek. */
const AUTUMN_WINDOW: TimeWindow = {
  start: new Date("2026-08-23T00:00:00Z"),
  end: new Date("2026-10-23T00:00:00Z"),
};

function expectNear(actual: Date, expected: Date, toleranceMs = TIME_TOLERANCE_MS): void {
  const deltaMin = (actual.getTime() - expected.getTime()) / MINUTE;
  expect(
    Math.abs(actual.getTime() - expected.getTime()),
    `${actual.toISOString()} vs ${expected.toISOString()} (${deltaMin.toFixed(1)} min off)`,
  ).toBeLessThanOrEqual(toleranceMs);
}

describe("windowAround", () => {
  it("defaults to ±30 days", () => {
    const w = windowAround(new Date("2026-09-22T21:00:00Z"));
    expect(w.start.toISOString()).toBe("2026-08-23T21:00:00.000Z");
    expect(w.end.toISOString()).toBe("2026-10-22T21:00:00.000Z");
  });
});

describe("siteCivilDate", () => {
  it("assigns a small-hours instant to the night it belongs to, from longitude", () => {
    // 03:00 UTC on the 7th is 20:00 on the 6th in Utah.
    const d = siteCivilDate(new Date("2026-10-07T03:00:00Z"), MILLCREEK.longitude);
    expect(d).toEqual({ year: 2026, month: 10, day: 6 });
  });
});

describe("moon phases", () => {
  const phases = moonPhases(AUTUMN_WINDOW);

  it("finds the September 2026 new moon", () => {
    const nm = phases.find((p) => p.angle === 0 && p.at > new Date("2026-09-01T00:00:00Z"));
    expect(nm).toBeDefined();
    expectNear(nm!.at, mdt("2026-09-10T21:27:00"));
    expect(nm!.name).toBe("New Moon");
  });

  it("finds the September 2026 full moon", () => {
    const fm = phases.find((p) => p.angle === 180 && p.at > new Date("2026-09-01T00:00:00Z"));
    expectNear(fm!.at, mdt("2026-09-26T10:49:00"));
  });

  it("finds the 2026-10-03 last quarter", () => {
    const lq = phases.find((p) => p.angle === 270 && p.at > new Date("2026-10-01T00:00:00Z"));
    expectNear(lq!.at, mdt("2026-10-03T07:25:00"));
  });

  it("returns phases in time order and only inside the window", () => {
    for (const p of phases) {
      expect(p.at >= AUTUMN_WINDOW.start && p.at <= AUTUMN_WINDOW.end).toBe(true);
    }
    const times = phases.map((p) => p.at.getTime());
    expect([...times].sort((a, b) => a - b)).toEqual(times);
  });
});

describe("planet apparitions", () => {
  it("finds the 2026-10-04 Saturn opposition", () => {
    const opp = planetOppositions(AUTUMN_WINDOW);
    const saturn = opp.find((e) => e.body === Astronomy.Body.Saturn);
    expect(saturn).toBeDefined();
    expectNear(saturn!.at, mdt("2026-10-04T06:12:00"));
    expect(saturn!.kind).toBe("opposition");
  });

  it("does not invent a Jupiter or Mars opposition in autumn 2026", () => {
    // Both fall in February 2027, well outside the window.
    const bodies = planetOppositions(AUTUMN_WINDOW).map((e) => e.body);
    expect(bodies).not.toContain(Astronomy.Body.Jupiter);
    expect(bodies).not.toContain(Astronomy.Body.Mars);
  });

  it("labels a Mercury greatest elongation with its side of the night", () => {
    const events = greatestElongations(AUTUMN_WINDOW);
    const mercury = events.find((e) => e.body === Astronomy.Body.Mercury);
    expect(mercury).toBeDefined();
    expectNear(mercury!.at, mdt("2026-10-12T04:06:00"));
    expect(mercury!.visibility).toBe("evening");
    expect(mercury!.elongationDeg!).toBeGreaterThan(24);
    expect(mercury!.elongationDeg!).toBeLessThan(26);
  });
});

describe("moon–planet separations", () => {
  it("geocentric Moon–Jupiter is 1.2° at 2026-10-06 06:31 MDT", () => {
    const sep = geocentricSeparationDeg(
      Astronomy.Body.Moon,
      Astronomy.Body.Jupiter,
      mdt("2026-10-06T06:31:00"),
    );
    expect(Math.abs(sep - 1.2)).toBeLessThanOrEqual(ANGLE_TOLERANCE_DEG);
  });

  it("both bodies are ~38° up at that moment", () => {
    const when = mdt("2026-10-06T06:31:00");
    const obs = new Astronomy.Observer(MILLCREEK.latitude, MILLCREEK.longitude, 1400);
    for (const body of [Astronomy.Body.Moon, Astronomy.Body.Jupiter]) {
      const eq = Astronomy.Equator(body, when, obs, true, true);
      const alt = Astronomy.Horizon(when, obs, eq.ra, eq.dec, "normal").altitude;
      expect(alt).toBeGreaterThan(34);
      expect(alt).toBeLessThan(42);
    }
  });

  it("geocentric Moon–Mars is 3.7° at 2026-10-05 06:30 MDT", () => {
    const sep = geocentricSeparationDeg(
      Astronomy.Body.Moon,
      Astronomy.Body.Mars,
      mdt("2026-10-05T06:30:00"),
    );
    expect(Math.abs(sep - 3.69)).toBeLessThanOrEqual(ANGLE_TOLERANCE_DEG);
  });

  it("topocentric and geocentric disagree by roughly lunar parallax", () => {
    const when = mdt("2026-10-06T06:31:00");
    const geo = geocentricSeparationDeg(Astronomy.Body.Moon, Astronomy.Body.Jupiter, when);
    const topo = topocentricSeparationDeg(
      MILLCREEK,
      Astronomy.Body.Moon,
      Astronomy.Body.Jupiter,
      when,
    );
    // Not interchangeable: this is exactly why the occultation test is topocentric.
    expect(Math.abs(topo - geo)).toBeGreaterThan(0.3);
  });
});

describe("moon–planet pairings", () => {
  const pairings = moonPlanetPairings(MILLCREEK, AUTUMN_WINDOW);
  /** The October pass: the window also holds a September Moon–Jupiter pass. */
  const octoberJupiter = (): MoonPairing =>
    pairings.find(
      (p) => p.body === Astronomy.Body.Jupiter && p.at > new Date("2026-10-01T00:00:00Z"),
    )!;

  it("reports a Moon–Mars pairing under 5° with both bodies up in dark sky", () => {
    const mars = pairings.find((p) => p.body === Astronomy.Body.Mars);
    expect(mars).toBeDefined();
    expect(mars!.separationDeg).toBeLessThan(5);
    expect(mars!.moonAltitudeDeg).toBeGreaterThan(5);
    expect(mars!.bodyAltitudeDeg).toBeGreaterThan(5);
  });

  it("reports each lunar pass, not just the closest one in the window", () => {
    const jupiter = pairings.filter((p) => p.body === Astronomy.Body.Jupiter);
    expect(jupiter).toHaveLength(2);
  });

  it("flags the 2026-10-06 Moon–Jupiter approach as a possible occultation", () => {
    const jup = octoberJupiter();
    expect(jup).toBeDefined();
    expect(jup.possibleOccultation).toBe(true);
    expect(jup.geocentricMinDeg).toBeLessThan(0.27);
  });

  it("confirms Jupiter is behind the disc from Millcreek, minimum 0.171° at 02:50 MDT", () => {
    const occ = octoberJupiter().occultation!;
    expect(occ.behindDiscFromHere).toBe(true);
    expect(Math.abs(occ.minSeparationDeg - 0.171)).toBeLessThanOrEqual(ANGLE_TOLERANCE_DEG);
    expectNear(occ.minSeparationAt, mdt("2026-10-06T02:50:00"));
    // The Moon has not risen yet at the minimum — moonrise is 03:02 MDT.
    expect(occ.moonAltitudeDeg).toBeLessThan(0);
  });

  it("puts the reappearance just after moonrise, with the Moon barely up", () => {
    const occ = octoberJupiter().occultation!;
    expect(occ.reappearsAt).not.toBeNull();
    expect(occ.reappearsAt!.getTime()).toBeGreaterThanOrEqual(mdt("2026-10-06T03:05:00").getTime());
    // 03:10 on a one-minute scan grid; the hand-computed value was ~03:05–03:08.
    expect(occ.reappearsAt!.getTime()).toBeLessThanOrEqual(mdt("2026-10-06T03:11:00").getTime());
    expect(occ.reappearMoonAltitudeDeg!).toBeGreaterThanOrEqual(0);
    expect(occ.reappearMoonAltitudeDeg!).toBeLessThanOrEqual(2);
  });

  it("reports the separation seen from here at the reported instant, not the geocentric minimum", () => {
    // Geocentric minimum is 0.16° at 04:23 MDT, when the topocentric separation
    // from Millcreek is 0.92°. The first observable minute (both bodies > 5°)
    // is ~03:35 MDT, with the pair ~0.5° apart as seen from here.
    const jup = octoberJupiter();
    expect(jup.observableHere).toBe(true);
    expectNear(jup.at, mdt("2026-10-06T03:35:00"));
    expect(Math.abs(jup.separationDeg - 0.484)).toBeLessThanOrEqual(ANGLE_TOLERANCE_DEG);
    expectNear(jup.geocentricMinAt, mdt("2026-10-06T04:23:00"));
    for (const p of pairings) {
      const topo = topocentricSeparationDeg(MILLCREEK, Astronomy.Body.Moon, p.body, p.at);
      expect(Math.abs(p.separationDeg - topo)).toBeLessThanOrEqual(0.001);
    }
  });

  it("never reports an approach wider than the 5° cutoff", () => {
    for (const p of pairings) {
      if (p.occultation) continue;
      expect(p.separationDeg).toBeLessThanOrEqual(5);
    }
  });

  it("binds the occultation check to the pass it belongs to", () => {
    // Window centred 2026-05-21 holds two Moon–Venus passes: a plain 3° pairing
    // on May 18 (MDT evening) and a daylight occultation on June 17.
    const w = windowAround(new Date("2026-05-21T21:00:00-06:00"));
    const venus = moonPlanetPairings(MILLCREEK, w).filter((p) => p.body === Astronomy.Body.Venus);
    expect(venus).toHaveLength(2);
    const [may, june] = venus as [MoonPairing, MoonPairing];
    expectNear(may.at, mdt("2026-05-18T21:57:00"));
    expect(may.possibleOccultation).toBe(false);
    expect(may.occultation).toBeNull();
    expect(june.occultation?.behindDiscFromHere).toBe(true);
    const occAt = june.occultation!.minSeparationAt.getTime();
    expect(Math.abs(occAt - june.geocentricMinAt.getTime())).toBeLessThanOrEqual(3 * 3_600_000);
    expect(Math.abs(occAt - june.at.getTime())).toBeLessThan(86_400_000);
  });

  it("keeps an earlier pass when a later one in the window is closer", () => {
    // Window centred 2026-10-15: Moon–Mars on Oct 5 (~2.3°) and Nov 2 (~1.3°).
    const w = windowAround(new Date("2026-10-15T21:00:00-06:00"));
    const mars = moonPlanetPairings(MILLCREEK, w).filter((p) => p.body === Astronomy.Body.Mars);
    expect(mars).toHaveLength(2);
    expectNear(mars[0]!.at, mdt("2026-10-05T02:23:00"));
    expectNear(mars[1]!.at, mdt("2026-11-02T06:33:00"));
    expect(mars[1]!.separationDeg).toBeLessThan(mars[0]!.separationDeg);
  });

  it("catches an occultation that only parallax brings onto the disc", () => {
    // 2027-08-01 Moon–Mercury: geocentric minimum 0.287° (outside the Moon's
    // mean semidiameter), but from Millcreek Mercury passes 0.034° from the
    // centre at 08:27 MDT with the Moon ~32° up.
    const w = windowAround(new Date("2027-08-01T21:00:00-06:00"));
    const mercury = moonPlanetPairings(MILLCREEK, w).find(
      (p) => p.body === Astronomy.Body.Mercury && p.at > new Date("2027-07-25T00:00:00Z"),
    )!;
    expect(mercury).toBeDefined();
    expect(mercury.geocentricMinDeg).toBeGreaterThan(OCCULTATION_FLAG_DEG);
    expect(mercury.geocentricMinDeg).toBeLessThan(OCCULTATION_CHECK_DEG);
    const occ = mercury.occultation!;
    expect(occ.behindDiscFromHere).toBe(true);
    expect(Math.abs(occ.minSeparationDeg - 0.034)).toBeLessThanOrEqual(ANGLE_TOLERANCE_DEG);
    expectNear(occ.minSeparationAt, mdt("2027-08-01T08:27:00"));
    expect(occ.moonAltitudeDeg).toBeGreaterThan(30);
  });
});

describe("zodiacal light", () => {
  it("finds autumn morning ranges around the September 2026 new moon", () => {
    const ranges = zodiacalLightRanges(MILLCREEK, AUTUMN_WINDOW);
    expect(ranges.length).toBeGreaterThan(0);
    expect(ranges.every((r) => r.season === "autumn_morning")).toBe(true);
    const newMoon = mdt("2026-09-10T21:27:00").getTime();
    const covers = ranges.some(
      (r) => r.start.getTime() - 86_400_000 <= newMoon && r.end.getTime() + 86_400_000 >= newMoon,
    );
    expect(covers).toBe(true);
  });

  it("returns nothing in a season it does not claim to cover", () => {
    const june: TimeWindow = {
      start: new Date("2026-06-01T00:00:00Z"),
      end: new Date("2026-06-30T00:00:00Z"),
    };
    expect(zodiacalLightRanges(MILLCREEK, june)).toEqual([]);
  });

  it("finds spring evening ranges in March", () => {
    const spring: TimeWindow = {
      start: new Date("2026-03-01T00:00:00Z"),
      end: new Date("2026-04-15T00:00:00Z"),
    };
    const ranges = zodiacalLightRanges(MILLCREEK, spring);
    expect(ranges.length).toBeGreaterThan(0);
    expect(ranges.every((r) => r.season === "spring_evening")).toBe(true);
  });

  it("declines the southern hemisphere rather than inverting the seasons wrongly", () => {
    expect(zodiacalLightRanges({ latitude: -33.9, longitude: 18.4 }, AUTUMN_WINDOW)).toEqual([]);
  });
});

describe("seasons", () => {
  it("finds the 2026 September equinox", () => {
    const markers = seasonMarkers(AUTUMN_WINDOW);
    const sep = markers.find((m) => m.name === "September equinox");
    expect(sep).toBeDefined();
    expectNear(sep!.at, mdt("2026-09-22T18:05:00"));
  });

  it("excludes markers outside the window", () => {
    const markers = seasonMarkers(AUTUMN_WINDOW);
    expect(markers.map((m) => m.name)).toEqual(["September equinox"]);
  });
});
