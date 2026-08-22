import { describe, expect, it } from "vitest";

import { parseUrlState, serializeUrlState } from "../src/state/urlstate";

describe("url state round-trip", () => {
  const cases: Parameters<typeof parseUrlState>[0][] = [
    "",
    "#",
    "#lat=38.53&lon=-109.9&date=2026-08-22&layers=lp,land,places",
    "#lat=-33.86882&lon=151.2&date=2024-01-01",
    "#lat=40&lon=-111&layers=lp",
    "#layers=land",
    "#date=2026-12-31",
  ];

  for (const hash of cases) {
    it(`round-trips: ${hash || "(empty)"}`, () => {
      const state = parseUrlState(hash);
      const serialized = serializeUrlState(state);
      const reparsed = parseUrlState(serialized);
      expect(reparsed).toEqual(state);
    });
  }

  it("rejects malformed coordinates", () => {
    expect(parseUrlState("#lat=999&lon=-111").lat).toBeNull();
    expect(parseUrlState("#lat=abc&lon=-111").lat).toBeNull();
    expect(parseUrlState("#lat=45.123456789").lat).toBe(45.12346);
  });

  it("rejects malformed dates", () => {
    expect(parseUrlState("#date=not-a-date").date).toBeNull();
    expect(parseUrlState("#date=2026-13-99").date).toBeNull();
  });

  it("drops unknown layer ids", () => {
    expect(parseUrlState("#layers=lp,bogus,land").layers).toEqual(["lp", "land"]);
  });

  it("serializes deterministically", () => {
    const a = serializeUrlState({ lat: 1.5, lon: -2.5, date: "2026-01-02", layers: ["lp"] });
    const b = serializeUrlState({ lat: 1.5, lon: -2.5, date: "2026-01-02", layers: ["lp"] });
    expect(a).toBe(b);
  });
});
