import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

import { darknessEnd, tonightIso } from "../src/state/tonight";

// A Mountain West browser: after 18:00 MDT the UTC date is already tomorrow.
const DENVER = "America/Denver";
process.env.TZ = DENVER;
afterAll(() => {
  process.env.TZ = DENVER;
});

interface TonightCase {
  id: string;
  latitude: number;
  longitude: number;
  time_zone: string;
  instant_utc: string;
  tonight: string;
}

interface EndCase {
  id: string;
  latitude: number;
  longitude: number;
  time_zone: string;
  night: string;
  end_utc: string | null;
}

const GOLDEN: { tolerance: { time_s: number }; cases: TonightCase[]; darkness_end: EndCase[] } = JSON.parse(
  readFileSync(resolve(__dirname, "../../shared/golden/tonight.json"), "utf8"),
);

describe("tonightIso without a site (calendar rule)", () => {
  it("runs in the zone the regression needs", () => {
    expect(new Date("2026-09-26T12:00:00Z").getTimezoneOffset()).toBe(360);
  });

  it("keeps the local date in the evening, when the UTC date has rolled over", () => {
    const evening = new Date("2026-09-27T02:30:00Z"); // 20:30 MDT on the 26th
    expect(evening.toISOString().slice(0, 10)).toBe("2026-09-27");
    expect(tonightIso(evening)).toBe("2026-09-26");
  });

  it("before local noon, names the night that began yesterday", () => {
    expect(tonightIso(new Date("2026-09-27T08:00:00Z"))).toBe("2026-09-26"); // 02:00 MDT
    expect(tonightIso(new Date("2026-09-27T17:59:00Z"))).toBe("2026-09-26"); // 11:59 MDT
  });

  it("from local noon, names tonight", () => {
    expect(tonightIso(new Date("2026-09-27T18:00:00Z"))).toBe("2026-09-27"); // 12:00 MDT
  });

  it("crosses month and year boundaries", () => {
    expect(tonightIso(new Date("2026-10-01T09:00:00Z"))).toBe("2026-09-30"); // 03:00 MDT Oct 1
    expect(tonightIso(new Date("2027-01-01T10:00:00Z"))).toBe("2026-12-31"); // 03:00 MST Jan 1
  });
});

describe("tonightIso with a site: last night only while it is still dark (shared/golden/tonight.json)", () => {
  for (const c of GOLDEN.cases) {
    it(c.id, () => {
      process.env.TZ = c.time_zone;
      expect(tonightIso(new Date(c.instant_utc), c)).toBe(c.tonight);
    });
  }

  it("crosses a year boundary before dawn", () => {
    process.env.TZ = DENVER;
    const site = { latitude: 38.374031, longitude: -109.965416 };
    expect(tonightIso(new Date("2027-01-01T10:00:00Z"), site)).toBe("2026-12-31"); // 03:00 MST, dark
    expect(tonightIso(new Date("2027-01-01T16:00:00Z"), site)).toBe("2027-01-01"); // 09:00 MST, light
  });
});

describe("darknessEnd (shared/golden/tonight.json)", () => {
  for (const c of GOLDEN.darkness_end) {
    it(c.id, () => {
      process.env.TZ = c.time_zone;
      const end = darknessEnd(c.night, c);
      if (c.end_utc === null) {
        expect(end).toBeNull();
      } else {
        expect(end).not.toBeNull();
        expect(Math.abs(end!.getTime() - Date.parse(c.end_utc)) / 1000).toBeLessThanOrEqual(GOLDEN.tolerance.time_s);
      }
    });
  }
});
