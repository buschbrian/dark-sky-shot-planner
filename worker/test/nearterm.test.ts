import { describe, expect, it } from "vitest";
import { MAX_UPSTREAM_FETCHES } from "../src/limits.ts";
import { parseWindow } from "../src/params.ts";
import { NEAR_TERM, nearTermRange } from "../src/sources/openmeteo.ts";
import {
  fixture,
  fixtureFetch,
  get,
  type Json,
  makeDeps,
  memoryCache,
  Q,
  RECORDED,
  recorded,
} from "./helpers.ts";

const NAME = "open-meteo-forecast-minutely_15-ncep_hrrr_conus";
const raw = () => (recorded(NAME).body as Json).minutely_15;
const FIELDS: Record<string, string> = {
  temperature: "temperature_2m",
  dew_point: "dew_point_2m",
  wind_speed: "wind_speed_10m",
  wind_gust: "wind_gusts_10m",
  visibility: "visibility",
};

describe("HRRR 15-minute series", () => {
  it("adds series_15min to the fields HRRR publishes natively every 15 minutes", async () => {
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch));
    for (const [field, om] of Object.entries(FIELDS)) {
      const [s] = body.fields[field].series_15min;
      expect(s, field).toMatchObject({
        model: "hrrr",
        upstream_model: "ncep_hrrr_conus",
        resolution_minutes: 15,
        status: "ok",
        model_run_utc: "2026-09-25T22:00:00Z",
        next_run_expected_utc: "2026-09-26T00:45:21Z",
      });
      expect(
        s.values.map((p: Json) => p.v),
        field,
      ).toEqual(raw()[om]);
      expect(s.values).toHaveLength(57);
      expect(s.values[1].t).toBe("2026-09-26T00:15:00Z");
      expect(s.values.at(-1).t).toBe("2026-09-26T14:00:00Z");
    }
  });

  it("leaves cloud cover and every other field alone", async () => {
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch));
    for (const [name, f] of Object.entries<Json>(body.fields)) {
      if (!(name in FIELDS)) expect(f, name).not.toHaveProperty("series_15min");
    }
    const temp = body.fields.temperature;
    expect(temp.series.map((s: Json) => s.model)).toEqual(["hrrr", "gfs", "icon", "ecmwf"]);
    expect(temp.series[0]).not.toHaveProperty("resolution_minutes");
    expect(temp.series[0].values).toHaveLength(15);
  });

  it("asks only for native variables, over the window, in the same fan-out", async () => {
    const f = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    const urls = f.calls.filter((u) => new URL(u).searchParams.has("minutely_15"));
    expect(urls).toHaveLength(1);
    const p = new URL(urls[0]!).searchParams;
    expect(p.get("minutely_15")!.split(",").sort()).toEqual(Object.values(FIELDS).sort());
    expect(p.get("minutely_15")).not.toMatch(/cloud|humidity/);
    expect(p.get("models")).toBe("ncep_hrrr_conus");
    expect(p.get("start_minutely_15")).toBe("2026-09-26T00:00");
    expect(p.get("end_minutely_15")).toBe("2026-09-26T14:00");
  });

  it("stays inside the per-request budget on a cold cache", async () => {
    const f = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(f.fetch), { AIRNOW_API_KEY: "k" });
    expect(f.calls).toHaveLength(15);
    expect(f.calls.length).toBeLessThanOrEqual(MAX_UPSTREAM_FETCHES);
  });

  it("drops values past the run's 18-hour native range", async () => {
    const fx = recorded(NAME);
    const b = structuredClone(fx.body) as Json;
    for (const t of ["2026-09-26T16:00", "2026-09-26T16:15", "2026-09-26T16:30"]) {
      b.minutely_15.time.push(t);
      for (const k of Object.values(FIELDS)) b.minutely_15[k].push(1);
    }
    const f = fixtureFetch({ [NAME]: { ...fx, body: b } });
    const { body } = await get(
      "/v1/conditions?lat=38.35&lon=-109.95&start=2026-09-26T00:00Z&end=2026-09-26T20:00Z",
      makeDeps(f.fetch),
    );
    const s = body.fields.visibility.series_15min[0];
    // Run 2026-09-25T22Z + 18 h = 16:00Z.
    expect(s.values.at(-1).t).toBe("2026-09-26T16:00:00Z");
    const url = f.calls.find((u) => u.includes("minutely_15"))!;
    // Requested up to the hour of "now" (23Z) + 18 h.
    expect(new URL(url).searchParams.get("end_minutely_15")).toBe("2026-09-26T17:00");
  });

  it("makes no request for a window beyond the range, and says why", async () => {
    const f = fixtureFetch();
    const { body } = await get(
      "/v1/conditions?lat=38.35&lon=-109.95&start=2026-09-27T20:00Z&end=2026-09-28T08:00Z",
      makeDeps(f.fetch),
    );
    expect(f.calls.some((u) => u.includes("minutely_15"))).toBe(false);
    const s = body.fields.wind_gust.series_15min[0];
    expect(s.status).toBe("unavailable");
    expect(s.reason).toMatch(/beyond HRRR's 18-hour 15-minute range/);
    expect(s.values).toEqual([]);
  });

  it("computes the requestable range from the window and the clock", () => {
    const now = new Date("2026-09-26T05:40:00Z");
    const w = (start: string, end: string) => parseWindow(new URLSearchParams({ start, end }), now);
    expect(nearTermRange(w("2026-09-26T04:00Z", "2026-09-26T12:00Z"), now)).toEqual({
      start: new Date("2026-09-26T04:00:00Z"),
      end: new Date("2026-09-26T12:00:00Z"),
    });
    expect(nearTermRange(w("2026-09-26T20:00Z", "2026-09-27T08:00Z"), now)?.end).toEqual(
      new Date(`2026-09-26T${5 + NEAR_TERM.nativeHours}:00:00Z`),
    );
    expect(nearTermRange(w("2026-09-27T00:00Z", "2026-09-27T08:00Z"), now)).toBeNull();
  });

  it("reads upstream down or outside the domain as unavailable, never zero", async () => {
    const down = await get(
      `/v1/conditions?${Q}`,
      makeDeps(fixtureFetch({ [NAME]: fixture("down/open-meteo-forecast.json") }).fetch),
    );
    const s = down.body.fields.visibility.series_15min[0];
    expect(s.status).toBe("unavailable");
    expect(s.reason).toBe("HTTP 502");
    expect(s.values).toEqual([]);
    expect(down.body.fields.visibility.series[0].status).toBe("ok");
    const outside = await get(
      `/v1/conditions?${Q}`,
      makeDeps(fixtureFetch({ [NAME]: fixture("down/open-meteo-forecast-no-data.json") }).fetch),
    );
    expect(outside.body.fields.temperature.series_15min[0].reason).toMatch(/outside/);
  });

  it("serves the last good 15-minute series once the fresh copy is gone", async () => {
    const cache = memoryCache();
    const warm = await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    const f = fixtureFetch({ [NAME]: fixture("down/open-meteo-forecast.json") });
    const { body } = await get(
      `/v1/conditions?${Q}`,
      makeDeps(f.fetch, { cache, now: new Date(RECORDED.getTime() + 7 * 3_600_000) }),
    );
    const s = body.fields.dew_point.series_15min[0];
    expect(s.status).toBe("unavailable");
    expect(s.last_good_utc).toBe(warm.body.generated_utc);
    expect(s.values).toEqual(warm.body.fields.dew_point.series_15min[0].values);
  });
});
