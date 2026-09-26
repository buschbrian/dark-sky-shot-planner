import { describe, expect, it } from "vitest";
import { auroraNearCell, parseKp, parseOvation, rowsByKey } from "../src/sources/swpc.ts";
import { fixtureFetch, get, type Json, makeDeps, memoryKv, recorded } from "./helpers.ts";

describe("SWPC parsing", () => {
  it("parses Kp by key, whatever the key's case", () => {
    const obs = parseKp(recorded("swpc-kp").body);
    const raw = recorded("swpc-kp").body as Json[];
    expect(obs).toHaveLength(raw.length);
    expect(obs.at(-1)).toEqual({ t: `${raw.at(-1).time_tag}Z`, v: raw.at(-1).Kp });
    const fc = parseKp(recorded("swpc-kp-forecast").body);
    expect(new Set(fc.map((p) => p.kind))).toEqual(new Set(["observed", "estimated", "predicted"]));
  });

  it("still reads the older header-row array format", () => {
    const rows = rowsByKey([
      ["time_tag", "Kp", "a_running", "station_count"],
      ["2026-09-25 18:00:00.000", "2.67", "12", "8"],
    ]);
    expect(parseKp(rows)).toEqual([{ t: "2026-09-25T18:00:00Z", v: 2.67 }]);
  });

  it("reduces OVATION to the non-zero grid and a near-cell probability", () => {
    const raw = recorded("swpc-ovation").body as Json;
    const ov = parseOvation(raw);
    expect(ov.points.every(([, , v]) => v > 0)).toBe(true);
    const grid = new Map<string, number>(
      raw.coordinates.map((c: number[]) => [`${c[0]},${c[1]}`, c[2]]),
    );
    const expected = Math.max(
      ...[259, 260, 261].flatMap((lon) =>
        [59, 60, 61].map((lat) => grid.get(`${lon},${lat}`) ?? 0),
      ),
    );
    expect(expected).toBeGreaterThan(0);
    expect(auroraNearCell(ov, { lat: 60, lon: -100, rounding_deg: 0.05 })).toBe(expected);
  });

  it("wraps longitude across the antimeridian", () => {
    const ov = {
      observation_time_utc: null,
      forecast_time_utc: null,
      points: [
        [0, 65, 30],
        [359, 70, 20],
      ] as [number, number, number][],
    };
    expect(auroraNearCell(ov, { lat: 65, lon: -0.95, rounding_deg: 0.05 })).toBe(30);
    expect(auroraNearCell(ov, { lat: 70, lon: 0.2, rounding_deg: 0.05 })).toBe(20);
    expect(auroraNearCell(ov, { lat: 70, lon: 3, rounding_deg: 0.05 })).toBe(0);
  });
});

describe("GET /v1/space-weather", () => {
  it("returns Kp observed, Kp forecast without observed rows, and the aurora summary", async () => {
    const f = fixtureFetch();
    const { body } = await get("/v1/space-weather?lat=38.35&lon=-109.95", makeDeps(f.fetch));
    expect(body.kp_observed.status).toBe("ok");
    expect(body.kp_observed.source).toMatch(/Space Weather Prediction Center/);
    expect(body.kp_observed.fetched_utc).toBeTruthy();
    expect(body.kp_forecast.values.every((p: Json) => p.kind !== "observed")).toBe(true);
    expect(body.kp_forecast.values.length).toBeGreaterThan(0);
    expect(body.aurora.observation_time_utc).toBe("2026-09-25T23:29:00Z");
    expect(body.aurora.near_cell).toMatchObject({ lat: 38.35, lon: -109.95, probability_pct: 0 });
    expect(body.cache).toBe("edge-cache");
  });

  it("omits near_cell without a cell and rejects an off-grid one", async () => {
    const f = fixtureFetch();
    expect((await get("/v1/space-weather", makeDeps(f.fetch))).body.aurora.near_cell).toBeNull();
    expect((await get("/v1/space-weather?lat=38.36&lon=-109.95", makeDeps(f.fetch))).status).toBe(
      400,
    );
  });

  it("caches in KV when bound, and a second call makes no upstream request", async () => {
    const kv = memoryKv();
    await get("/v1/space-weather", makeDeps(fixtureFetch().fetch, { cache: null }), {
      SPACE_WEATHER: kv,
    });
    expect(
      kv
        .keys()
        .filter((k) => k.startsWith("swpc:"))
        .sort(),
    ).toEqual(["swpc:kp", "swpc:kp_forecast", "swpc:ovation"]);
    const again = fixtureFetch();
    const res = await get("/v1/space-weather", makeDeps(again.fetch, { cache: null }), {
      SPACE_WEATHER: kv,
    });
    expect(again.calls).toEqual([]);
    expect(res.body.cache).toBe("kv");
    expect(res.body.kp_observed.status).toBe("ok");
  });

  it("works with neither KV nor the Cache API", async () => {
    const f = fixtureFetch();
    const res = await get("/v1/space-weather", makeDeps(f.fetch, { cache: null }));
    expect(res.status).toBe(200);
    expect(res.body.cache).toBe("none");
  });
});
