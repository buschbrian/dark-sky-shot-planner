import { describe, expect, it } from "vitest";
import { FORECAST_MODELS } from "../src/sources/openmeteo.ts";
import {
  fixture,
  fixtureFetch,
  get,
  type Json,
  makeDeps,
  memoryCache,
  memoryKv,
  Q,
  RECORDED,
} from "./helpers.ts";

const down = (name: string) => fixture(`down/${name}.json`);
const MODELS = FORECAST_MODELS.map((m) => m.upstream);
const allForecastsDown = Object.fromEntries(
  MODELS.map((m) => [`open-meteo-forecast-${m}`, down("open-meteo-forecast")]),
);
const hoursLater = (h: number) => new Date(RECORDED.getTime() + h * 3_600_000);

function expectUnavailable(field: Json, reason: RegExp) {
  expect(field.status).toBe("unavailable");
  expect(field.reason).toMatch(reason);
  expect("last_good_utc" in field).toBe(true);
  for (const s of field.series) {
    expect(s.status).toBe("unavailable");
    for (const p of s.values) expect(p.v).not.toBe(0);
  }
}

describe("each upstream down, cold cache", () => {
  it("Open-Meteo forecast: every cloud field unavailable, nothing zero-filled", async () => {
    const f = fixtureFetch(allForecastsDown);
    const { status, body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    expect(status).toBe(200);
    expectUnavailable(body.fields.cloud_cover_total, /HTTP 502/);
    expect(body.fields.cloud_cover_total.last_good_utc).toBeNull();
    expect(body.fields.cloud_cover_total.series[0].values).toEqual([]);
    expect(body.fields.aerosol_optical_depth.status).toBe("ok");
  });

  it("Open-Meteo meta.json: forecast still served, run time honestly null", async () => {
    const f = fixtureFetch({ "open-meteo-meta-ncep_hrrr_conus": down("open-meteo-meta") });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    const hrrr = body.fields.cloud_cover_total.series[0];
    expect(hrrr.status).toBe("ok");
    expect(hrrr.model_run_utc).toBeNull();
  });

  it("Open-Meteo Air Quality", async () => {
    const f = fixtureFetch({ "open-meteo-air-quality": down("open-meteo-air-quality") });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    for (const k of ["aerosol_optical_depth", "pm2_5", "dust"]) {
      expectUnavailable(body.fields[k], /HTTP 503/);
    }
  });

  it("NDGD smoke (ArcGIS error inside HTTP 200)", async () => {
    const f = fixtureFetch({
      "ndgd-smoke-sfc-identify": down("ndgd-smoke-identify"),
      "ndgd-smoke-vert-identify": down("ndgd-smoke-identify"),
    });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    expectUnavailable(body.fields.smoke_column, /ArcGIS error 500/);
    expectUnavailable(body.fields.smoke_surface, /ArcGIS error 500/);
  });

  it("AirNow 401 (the real keyless answer)", async () => {
    const f = fixtureFetch({ "airnow-ziplatlong": down("airnow-ziplatlong") });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch), {
      AIRNOW_API_KEY: "test-only",
    });
    expect(body.fields.aqi_observed.status).toBe("unavailable");
    expect(body.fields.aqi_observed.reason).toBe("HTTP 401");
    expect(body.fields.aqi_observed.observations).toEqual([]);
  });

  it("7Timer empty body", async () => {
    const f = fixtureFetch({ "7timer-astro": down("7timer-astro") });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    expectUnavailable(body.fields.transparency, /invalid JSON/);
    expectUnavailable(body.fields.seeing, /invalid JSON/);
  });

  it("network failure is reported without the URL", async () => {
    const f = fixtureFetch({ "airnow-ziplatlong": "throw" });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch), {
      AIRNOW_API_KEY: "secret-value",
    });
    expect(body.fields.aqi_observed.reason).toBe("network error");
    expect(JSON.stringify(body)).not.toContain("secret-value");
  });

  it("SWPC products", async () => {
    const f = fixtureFetch({
      "swpc-kp": down("swpc"),
      "swpc-kp-forecast": down("swpc"),
      "swpc-ovation": down("swpc"),
    });
    const { body } = await get("/v1/space-weather", makeDeps(f.fetch));
    for (const k of ["kp_observed", "kp_forecast", "aurora"]) {
      expect(body[k].status).toBe("unavailable");
      expect(body[k].reason).toBe("HTTP 503");
      expect(body[k].last_good_utc).toBeNull();
    }
    expect(body.kp_observed.values).toEqual([]);
  });

  it("HMS", async () => {
    const f = fixtureFetch({ "hms-query": down("hms-query") });
    const { status, body } = await get("/v1/smoke?bbox=-114,37,-109,42", makeDeps(f.fetch));
    expect(status).toBe(200);
    expect(body.status).toBe("unavailable");
    expect(body.reason).toBe("ArcGIS error 400");
    expect(body.features).toEqual([]);
  });
});

describe("upstream down with a last good value (ADR-0006)", () => {
  it("serves the last good series with its age once the fresh copy expires", async () => {
    const cache = memoryCache();
    const warm = await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    const f = fixtureFetch(allForecastsDown);
    const { body } = await get(
      `/v1/conditions?${Q}`,
      makeDeps(f.fetch, { cache, now: hoursLater(7) }),
    );
    const field = body.fields.cloud_cover_total;
    expect(field.status).toBe("unavailable");
    expect(field.last_good_utc).toBe(warm.body.generated_utc);
    const hrrr = field.series[0];
    expect(hrrr.last_good_utc).toBe(warm.body.generated_utc);
    expect(hrrr.values).toEqual(warm.body.fields.cloud_cover_total.series[0].values);
    expect(hrrr.fetched_utc).toBeNull();
  });

  it("keeps last good smoke polygons and space weather too", async () => {
    const cache = memoryCache();
    const kv = memoryKv();
    const deps0 = makeDeps(fixtureFetch().fetch, { cache });
    const smoke0 = await get("/v1/smoke?bbox=-114,37,-109,42", deps0);
    const sw0 = await get("/v1/space-weather", deps0, { SPACE_WEATHER: kv });
    const f = fixtureFetch({
      "hms-query": down("hms-query"),
      "swpc-kp": down("swpc"),
      "swpc-kp-forecast": down("swpc"),
      "swpc-ovation": down("swpc"),
    });
    const deps1 = makeDeps(f.fetch, { cache, now: hoursLater(2) });
    const smoke1 = await get("/v1/smoke?bbox=-114,37,-109,42", deps1);
    expect(smoke1.body.status).toBe("unavailable");
    expect(smoke1.body.last_good_utc).toBe(smoke0.body.fetched_utc);
    expect(smoke1.body.features).toEqual(smoke0.body.features);
    const sw1 = await get("/v1/space-weather", deps1, { SPACE_WEATHER: kv });
    expect(sw1.body.kp_observed.status).toBe("unavailable");
    expect(sw1.body.kp_observed.last_good_utc).toBe(sw0.body.kp_observed.fetched_utc);
    expect(sw1.body.kp_observed.values).toEqual(sw0.body.kp_observed.values);
  });
});
