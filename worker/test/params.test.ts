import { describe, expect, it } from "vitest";
import { BadRequest, gridCoord, parseBbox, parseCell, parseWindow } from "../src/params.ts";
import { fixtureFetch, get, makeDeps, RECORDED } from "./helpers.ts";

const p = (s: string) => new URLSearchParams(s);

describe("0.05° grid (ADR-0010 point 2)", () => {
  it("accepts coordinates already on the grid", () => {
    expect(parseCell(p("lat=38.35&lon=-109.95"))).toEqual({
      lat: 38.35,
      lon: -109.95,
      rounding_deg: 0.05,
    });
    expect(gridCoord("40", "lat", 90)).toBe(40);
    expect(gridCoord("-0.05", "lat", 90)).toBe(-0.05);
  });

  it("rejects precise or off-grid coordinates", () => {
    for (const bad of ["38.351", "38.33", "38.3512345", "38.36"]) {
      expect(() => gridCoord(bad, "lat", 90)).toThrow(BadRequest);
    }
    expect(() => gridCoord("91", "lat", 90)).toThrow(/out of range/);
    expect(() => gridCoord(null, "lat", 90)).toThrow(/required/);
    expect(() => gridCoord("abc", "lat", 90)).toThrow(BadRequest);
  });

  it("answers 400 before any upstream call", async () => {
    const f = fixtureFetch();
    const res = await get(
      "/v1/conditions?lat=38.351&lon=-109.95&start=2026-09-26T00:00Z&end=2026-09-26T14:00Z",
      makeDeps(f.fetch),
    );
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/grid/);
    expect(f.calls).toEqual([]);
  });
});

describe("time window", () => {
  it("rounds outward to whole hours and records the UTC dates", () => {
    const w = parseWindow(p("start=2026-09-26T00:20Z&end=2026-09-26T13:10Z"), RECORDED);
    expect(w.start.toISOString()).toBe("2026-09-26T00:00:00.000Z");
    expect(w.end.toISOString()).toBe("2026-09-26T14:00:00.000Z");
    expect([w.startDate, w.endDate]).toEqual(["2026-09-26", "2026-09-26"]);
  });

  it("spans two dates when the window crosses midnight UTC", () => {
    const w = parseWindow(p("start=2026-09-26T20:00Z&end=2026-09-27T12:00Z"), RECORDED);
    expect([w.startDate, w.endDate]).toEqual(["2026-09-26", "2026-09-27"]);
  });

  it("rejects bad windows", () => {
    const bad = [
      "start=2026-09-26T00:00&end=2026-09-26T14:00Z",
      "start=2026-09-26T14:00Z&end=2026-09-26T00:00Z",
      "start=2026-09-26T00:00Z&end=2026-09-28T01:00Z",
      "start=2026-09-01T00:00Z&end=2026-09-01T10:00Z",
      "start=2026-10-20T00:00Z&end=2026-10-20T10:00Z",
      "end=2026-09-26T10:00Z",
    ];
    for (const q of bad) expect(() => parseWindow(p(q), RECORDED)).toThrow(BadRequest);
  });
});

describe("bbox", () => {
  it("requires grid-aligned corners, min < max, and a bounded size", () => {
    expect(parseBbox(p("bbox=-114.05,37,-109,42"))).toEqual([-114.05, 37, -109, 42]);
    expect(() => parseBbox(p("bbox=-114.03,37,-109,42"))).toThrow(/grid/);
    expect(() => parseBbox(p("bbox=-109,37,-114,42"))).toThrow(/min < max/);
    expect(() => parseBbox(p("bbox=-140,20,-100,50"))).toThrow(/limited/);
    expect(() => parseBbox(p("bbox=1,2,3"))).toThrow(/four/);
  });
});
