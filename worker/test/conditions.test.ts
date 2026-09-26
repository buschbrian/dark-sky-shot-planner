import { describe, expect, it } from "vitest";
import { FORECAST_MODELS } from "../src/sources/openmeteo.ts";
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

const KEY = "test-only-not-a-real-key";

async function conditions(env = {}) {
  const f = fixtureFetch();
  const res = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch), env);
  expect(res.status).toBe(200);
  return { ...res, calls: f.calls };
}

const runOf = (meta: string) =>
  new Date(
    (recorded(`open-meteo-meta-${meta}`).body as { last_run_initialisation_time: number })
      .last_run_initialisation_time * 1000,
  )
    .toISOString()
    .replace(".000Z", "Z");

describe("GET /v1/conditions", () => {
  it("echoes the cell and the rounded window", async () => {
    const { body } = await conditions();
    expect(body.cell).toEqual({ lat: 38.35, lon: -109.95, rounding_deg: 0.05 });
    expect(body.window).toEqual({
      start_utc: "2026-09-26T00:00:00Z",
      end_utc: "2026-09-26T14:00:00Z",
    });
  });

  it("returns every model as its own series, never averaged", async () => {
    const { body } = await conditions();
    const cloud = body.fields.cloud_cover_total;
    expect(cloud.unit).toBe("%");
    expect(cloud.source).toBe("Open-Meteo");
    expect(cloud.series.map((s: Json) => s.model)).toEqual(["hrrr", "gfs", "icon", "ecmwf"]);
    const hrrr = cloud.series[0];
    const raw = (recorded("open-meteo-forecast-ncep_hrrr_conus").body as Json).hourly.cloud_cover;
    expect(hrrr.values.map((p: Json) => p.v)).toEqual(raw.slice(0, 15));
    expect(hrrr.values[0].t).toBe("2026-09-26T00:00:00Z");
    expect(hrrr.values.at(-1).t).toBe("2026-09-26T14:00:00Z");
    const ecmwf = cloud.series[3];
    const rawE = (recorded("open-meteo-forecast-ecmwf_ifs025").body as Json).hourly.cloud_cover;
    expect(ecmwf.values.map((p: Json) => p.v)).toEqual(rawE.slice(0, 15));
  });

  it("uses gfs_global, not the HRRR-blended gfs_seamless", async () => {
    const { calls } = await conditions();
    const models = calls
      .filter((u) => u.includes("/v1/forecast"))
      .map((u) => new URL(u).searchParams.get("models"));
    expect(models.sort()).toEqual(
      ["ecmwf_ifs025", "gfs_global", "icon_global", "ncep_hrrr_conus"].sort(),
    );
    expect(calls.join()).not.toMatch(/ncep_nam|ncep_nbm|gfs_seamless|gem_hrdps/);
  });

  it("never lists a seamless alias or a stale GEM meta id", () => {
    for (const m of FORECAST_MODELS) {
      expect(m.upstream, m.id).not.toMatch(/seamless|best_match/);
      expect(m.meta, m.id).not.toMatch(/seamless|^cmc_gem_(rdps|gdps)$/);
    }
    expect(FORECAST_MODELS.find((m) => m.id === "icon")).toMatchObject({
      upstream: "icon_global",
      meta: "dwd_icon",
    });
  });

  it("stamps each series with its model run from meta.json", async () => {
    const { body } = await conditions();
    const [hrrr, gfs, icon, ecmwf] = body.fields.cloud_cover_low.series;
    expect(hrrr.model_run_utc).toBe(runOf("ncep_hrrr_conus"));
    expect(gfs.model_run_utc).toBe(runOf("ncep_gfs013"));
    expect(icon.model_run_utc).toBe(runOf("dwd_icon"));
    expect(ecmwf.model_run_utc).toBe(runOf("ecmwf_ifs025"));
    expect(hrrr.fetched_utc).toBe(body.generated_utc);
  });

  it("marks a model outside its domain unavailable, not zero", async () => {
    const f = fixtureFetch({
      "open-meteo-forecast-icon_global": fixture("down/open-meteo-forecast-no-data.json"),
    });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    const icon = body.fields.cloud_cover_total.series[2];
    expect(icon.status).toBe("unavailable");
    expect(icon.reason).toMatch(/outside this model's domain/);
    expect(icon.values).toEqual([]);
    expect(body.fields.cloud_cover_total.status).toBe("ok");
  });

  it("marks a variable a model doesn't publish unavailable (ECMWF visibility)", async () => {
    const { body } = await conditions();
    const vis = body.fields.visibility;
    expect(vis.status).toBe("ok");
    expect(vis.series[3].status).toBe("unavailable");
    expect(vis.series[3].reason).toMatch(/does not publish/);
  });

  it("marks ICON visibility unavailable, not zero, while its clouds are served", async () => {
    const { body } = await conditions();
    const raw = (recorded("open-meteo-forecast-icon_global").body as Json).hourly;
    expect(raw.visibility.every((v: unknown) => v === null)).toBe(true);
    const vis = body.fields.visibility.series[2];
    expect(vis.model).toBe("icon");
    expect(vis.status).toBe("unavailable");
    expect(vis.reason).toMatch(/does not publish/);
    expect(vis.values).toEqual([]);
    const cloud = body.fields.cloud_cover_total.series[2];
    expect(cloud.status).toBe("ok");
    expect(cloud.values.map((p: Json) => p.v)).toEqual(raw.cloud_cover.slice(0, 15));
  });

  it("carries source, status and freshness on every field and series", async () => {
    const { body } = await conditions();
    const expected = [
      "cloud_cover_total",
      "cloud_cover_low",
      "cloud_cover_mid",
      "cloud_cover_high",
      "temperature",
      "dew_point",
      "relative_humidity",
      "wind_speed",
      "wind_gust",
      "visibility",
      "wind_speed_250hpa",
      "wind_speed_200hpa",
      "aerosol_optical_depth",
      "pm2_5",
      "dust",
      "smoke_surface",
      "smoke_column",
      "aqi_observed",
      "seeing",
      "transparency",
    ];
    expect(Object.keys(body.fields).sort()).toEqual(expected.sort());
    for (const [name, field] of Object.entries<Json>(body.fields)) {
      expect(field.source, name).toBeTruthy();
      expect(["ok", "unavailable"], name).toContain(field.status);
      expect("fetched_utc" in field, name).toBe(true);
      if (field.status === "unavailable") expect("last_good_utc" in field, name).toBe(true);
      for (const s of field.series) {
        expect(s.model, name).toBeTruthy();
        expect("model_run_utc" in s && "fetched_utc" in s, name).toBe(true);
        if (s.status === "ok") {
          expect(s.values.length, name).toBeGreaterThan(0);
          expect(s.model_run_utc, name).toBeTruthy();
        } else {
          expect("last_good_utc" in s, name).toBe(true);
        }
      }
    }
  });

  it("reports CAMS air quality with its run and the config's µg/m³", async () => {
    const { body } = await conditions();
    const aod = body.fields.aerosol_optical_depth;
    expect(aod.series[0].model).toBe("cams_global");
    expect(aod.series[0].model_run_utc).toBe(runOf("cams_global"));
    expect(aod.series[0].values).toHaveLength(15);
    expect(body.fields.pm2_5.unit).toBe("µg/m³");
    expect(body.fields.pm2_5.series[0].status).toBe("ok");
  });

  it("calibrates RAP-Smoke and leaves gating to config", async () => {
    const { body } = await conditions();
    const col = body.fields.smoke_column;
    expect(col.source).toBe("NOAA RAP-Smoke via NWS NDGD");
    expect(col.unit).toBe("mg/m²");
    expect(col.calibrated).toBe(true);
    expect(col).not.toHaveProperty("gates_verdict");
    const s = col.series[0];
    expect(s.model).toBe("rap_smoke");
    expect(s.model_run_utc).toBe("2026-09-25T03:00:00Z");
    const raw = recorded("ndgd-smoke-vert-identify").body as Json;
    const i = raw.catalogItems.features.findIndex(
      (f: Json) => f.attributes.idp_validtime === Date.parse("2026-09-26T04:00:00Z"),
    );
    const v4 = s.values.find((p: Json) => p.t === "2026-09-26T04:00:00Z").v;
    expect(v4).toBeCloseTo(Number(raw.properties.Values[i]) * 1e6, 9);
    expect(s.values.map((p: Json) => p.t)).toEqual([...s.values.map((p: Json) => p.t)].sort());
    expect(s.values).toHaveLength(15);
    expect(body.fields.smoke_surface.unit).toBe("µg/m³");
  });

  it("returns AirNow unavailable without a key and never calls it", async () => {
    const { body, calls } = await conditions();
    const aqi = body.fields.aqi_observed;
    expect(aqi.status).toBe("unavailable");
    expect(aqi.reason).toMatch(/key not configured/);
    expect(aqi.last_good_utc).toBeNull();
    expect(calls.some((u) => u.includes("airnowapi"))).toBe(false);
  });

  it("reads AirNow ziplatLong with a key and never echoes the key", async () => {
    const { body, calls } = await conditions({ AIRNOW_API_KEY: KEY });
    const aqi = body.fields.aqi_observed;
    expect(aqi.status).toBe("ok");
    expect(aqi.preliminary).toBe(true);
    expect(aqi.attribution).toMatch(/reporting agencies/);
    expect(aqi.observations[0]).toMatchObject({
      parameter: "PM2.5",
      aqi: 38,
      category: "Good",
      category_number: 1,
      observed_utc: "2026-09-25T23:00:00Z",
    });
    const url = calls.find((u) => u.includes("airnowapi"))!;
    expect(new URL(url).pathname).toBe("/aq/observation/current/ziplatLong/");
    expect(url).not.toMatch(/latLong\/current/);
    expect(JSON.stringify(body)).not.toContain(KEY);
  });

  it("adds 7Timer seeing/transparency, flagged non-commercial and optional", async () => {
    const { body } = await conditions();
    const t = body.fields.transparency;
    expect(t.terms).toMatch(/non-commercial/);
    expect(t.optional).toBe(true);
    expect(t.series[0].model_run_utc).toBe("2026-09-25T18:00:00Z");
    for (const p of t.series[0].values) expect(p.v === null || (p.v >= 1 && p.v <= 8)).toBe(true);
  });

  it("can switch 7Timer off without dropping the field", async () => {
    const f = fixtureFetch();
    const res = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch), {
      SEVENTIMER_ENABLED: "false",
    });
    expect(res.body.fields.seeing.status).toBe("unavailable");
    expect(res.body.fields.seeing.reason).toMatch(/disabled/);
    expect(f.calls.some((u) => u.includes("7timer"))).toBe(false);
  });

  it("serves a repeat request for the same cell and run from cache", async () => {
    const cache = memoryCache();
    const first = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(first.fetch, { cache }));
    const again = fixtureFetch();
    const res = await get(`/v1/conditions?${Q}`, makeDeps(again.fetch, { cache }));
    expect(res.body.fields.cloud_cover_total.series[0].status).toBe("ok");
    expect(again.calls).toEqual([]);
  });

  it("refetches a model's forecast when meta.json shows a new run", async () => {
    const cache = memoryCache();
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    // Past the fixture runs' sync margins (see freshness.test.ts), so only a new run refetches.
    const synced = new Date(RECORDED.getTime() + 10 * 60_000);
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache, now: synced }));
    const meta = recorded("open-meteo-meta-ncep_hrrr_conus");
    const newer = {
      ...meta,
      body: {
        ...(meta.body as object),
        last_run_initialisation_time: (meta.body as Json).last_run_initialisation_time + 3600,
      },
    };
    // Past HRRR's expected next run (00:45Z) and the one-hour meta.json cap. The other
    // models report the same runs, so their cached forecasts still answer.
    const later = new Date(RECORDED.getTime() + 70 * 60_000);
    const f = fixtureFetch({ "open-meteo-meta-ncep_hrrr_conus": newer });
    const res = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch, { cache, now: later }));
    const forecastCalls = f.calls.filter((u) => u.includes("/v1/forecast"));
    expect(forecastCalls.map((u) => new URL(u).searchParams.get("models"))).toEqual([
      "ncep_hrrr_conus",
    ]);
    expect(res.body.fields.cloud_cover_total.series[0].model_run_utc).toBe(
      new Date(newer.body.last_run_initialisation_time * 1000).toISOString().replace(".000Z", "Z"),
    );
  });
});
