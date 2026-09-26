import { describe, expect, it } from "vitest";
import { clipRing, hmsTime } from "../src/sources/hms.ts";
import { applySmokeCalibration, issuanceProblem, parseIdentify } from "../src/sources/ndgdsmoke.ts";
import { fixtureFetch, get, type Json, makeDeps, Q, recorded } from "./helpers.ts";

const coords = (g: Json): number[][] =>
  g.type === "Polygon" ? g.coordinates.flat() : g.coordinates.flat(2);

describe("HMS smoke polygons", () => {
  it("parses the day-of-year timestamps", () => {
    expect(hmsTime("2026268 1700")).toBe("2026-09-25T17:00:00Z");
    expect(hmsTime("2026001 0000")).toBe("2026-01-01T00:00:00Z");
    expect(hmsTime("bad")).toBeNull();
  });

  it("clips a ring to the bbox", () => {
    const square: [number, number][] = [
      [0, 0],
      [4, 0],
      [4, 4],
      [0, 4],
      [0, 0],
    ];
    const clipped = clipRing(square, [2, 1, 10, 3])!;
    expect(clipped[0]).toEqual(clipped.at(-1));
    expect(new Set(clipped.map((p) => p.join()))).toEqual(new Set(["2,1", "4,1", "4,3", "2,3"]));
    expect(clipRing(square, [5, 5, 6, 6])).toBeNull();
  });

  it("returns clipped GeoJSON with the analysis time", async () => {
    const bbox = [-125, 30, -100, 50];
    const { status, body } = await get(
      `/v1/smoke?bbox=${bbox.join(",")}`,
      makeDeps(fixtureFetch().fetch),
    );
    expect(status).toBe(200);
    expect(body.type).toBe("FeatureCollection");
    expect(body.status).toBe("ok");
    expect(body.source).toMatch(/HMS/);
    expect(body.analysis_time_utc).toBe("2026-09-25T20:00:00Z");
    expect(body.analysis_date).toBe("2026-09-25");
    expect(body.note).toMatch(/previous afternoon/);
    const raw = recorded("hms-query").body as Json;
    expect(body.features).toHaveLength(raw.features.length);
    for (const f of body.features) {
      for (const [x, y] of coords(f.geometry)) {
        expect(x).toBeGreaterThanOrEqual(bbox[0]!);
        expect(y).toBeGreaterThanOrEqual(bbox[1]!);
        expect(x).toBeLessThanOrEqual(bbox[2]!);
        expect(y).toBeLessThanOrEqual(bbox[3]!);
      }
      expect(f.properties.start_utc).toMatch(/Z$/);
      expect(["Light", "Medium", "Heavy"]).toContain(f.properties.density);
    }
  });

  it("keeps the analysis time when the bbox has no smoke", async () => {
    const { body } = await get(
      "/v1/smoke?bbox=-110,38,-109.5,38.5",
      makeDeps(fixtureFetch().fetch),
    );
    expect(body.status).toBe("ok");
    expect(body.features).toEqual([]);
    expect(body.analysis_time_utc).toBe("2026-09-25T20:00:00Z");
  });

  it("rejects an off-grid or oversized bbox", async () => {
    const f = fixtureFetch();
    expect((await get("/v1/smoke?bbox=-114.01,37,-109,42", makeDeps(f.fetch))).status).toBe(400);
    expect((await get("/v1/smoke?bbox=-150,20,-100,50", makeDeps(f.fetch))).status).toBe(400);
    expect(f.calls).toEqual([]);
  });
});

describe("NDGD RAP-Smoke", () => {
  const slice = (validIso: string, issuedIso: string, subset: string, fcst: number) => ({
    attributes: {
      idp_validtime: Date.parse(validIso),
      idp_issueddate: Date.parse(issuedIso),
      idp_subset: subset,
      idp_fcst_hour: fcst,
    },
  });

  it("drops Alaska slices and keeps the newest issuance per hour", () => {
    const pts = parseIdentify({
      value: "1e-07",
      properties: { Values: ["1e-07", "0", "2e-07"] },
      catalogItems: {
        features: [
          slice("2026-09-26T01:00:00Z", "2026-09-25T03:00:00Z", "conus", 22),
          slice("2026-09-26T01:00:00Z", "2026-09-26T03:00:00Z", "alaska", 0),
          slice("2026-09-26T01:00:00Z", "2026-09-24T03:00:00Z", "conus", 46),
        ],
      },
    });
    expect(pts).toEqual([
      { t: "2026-09-26T01:00:00Z", v: 1e-7, issued_utc: "2026-09-25T03:00:00Z", fcst_hour: 22 },
    ]);
  });

  it("flags an issuance that doesn't look like RAP-Smoke", () => {
    const p = (issued: string, fcst: number) => ({
      t: "2026-09-26T01:00:00Z",
      v: 1,
      issued_utc: issued,
      fcst_hour: fcst,
    });
    expect(issuanceProblem([p("2026-09-25T03:00:00Z", 22)])).toBeNull();
    expect(issuanceProblem([p("2026-09-25T06:00:00Z", 19)])).toMatch(/issue hour 06:00Z/);
    expect(issuanceProblem([p("2026-09-25T03:00:00Z", 60)])).toMatch(/forecast hour/);
  });

  it("marks a flagged issuance unavailable but keeps its values", async () => {
    const shift = (name: string) => {
      const f = recorded(name);
      const b = structuredClone(f.body) as Json;
      for (const c of b.catalogItems.features) c.attributes.idp_issueddate += 3 * 3_600_000;
      return { ...f, body: b };
    };
    const f = fixtureFetch({
      "ndgd-smoke-vert-identify": shift("ndgd-smoke-vert-identify"),
      "ndgd-smoke-sfc-identify": shift("ndgd-smoke-sfc-identify"),
    });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    const s = body.fields.smoke_column.series[0];
    expect(s.status).toBe("unavailable");
    expect(s.reason).toMatch(/source may have changed/);
    expect(s.values.length).toBeGreaterThan(0);
  });

  it("applies the calibration hook, or passes raw values through flagged", () => {
    expect(applySmokeCalibration(4.3e-7, { unit: "mg/m²", factor: 1e6, note: "" })).toEqual({
      v: 0.43,
      unit: "mg/m²",
    });
    expect(applySmokeCalibration(4.3e-7, null)).toEqual({ v: 4.3e-7, unit: "uncalibrated" });
  });

  it("answers unavailable outside CONUS coverage without calling the service", async () => {
    const f = fixtureFetch();
    const { body } = await get(
      "/v1/conditions?lat=61&lon=-150&start=2026-09-26T00:00Z&end=2026-09-26T14:00Z",
      makeDeps(f.fetch),
    );
    expect(body.fields.smoke_column.status).toBe("unavailable");
    expect(body.fields.smoke_column.reason).toMatch(/outside the NDGD CONUS/);
    expect(f.calls.some((u) => u.includes("ndgd_smoke"))).toBe(false);
  });

  it("treats an empty catalog as unavailable, never as clean air", async () => {
    const empty = {
      ...recorded("ndgd-smoke-vert-identify"),
      body: { value: "0", properties: { Values: [] }, catalogItems: { features: [] } },
    };
    const f = fixtureFetch({ "ndgd-smoke-vert-identify": empty });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    expect(body.fields.smoke_column.status).toBe("unavailable");
    expect(body.fields.smoke_column.series[0].values).toEqual([]);
  });
});
