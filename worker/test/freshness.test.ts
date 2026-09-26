import { describe, expect, it } from "vitest";
import { nextSmokeIssue, parseIdentify } from "../src/sources/ndgdsmoke.ts";
import { parseMeta, SYNC_MARGIN_SECONDS } from "../src/sources/openmeteo.ts";
import { type Entry, isFresh, nullStore } from "../src/store.ts";
import type { FetchLike } from "../src/types.ts";
import {
  fixtureFetch,
  get,
  type Json,
  makeDeps,
  memoryCache,
  Q,
  RECORDED,
  recorded,
} from "./helpers.ts";

const at = (ms: number) => new Date(ms).toISOString().replace(".000Z", "Z");
const later = (minutes: number) => new Date(RECORDED.getTime() + minutes * 60_000);
const metaBody = (id: string) => recorded(`open-meteo-meta-${id}`).body as Json;
const META_IDS = ["ncep_hrrr_conus", "ncep_gfs013", "dwd_icon", "ecmwf_ifs025", "cams_global"];

describe("next-run estimates", () => {
  it.each(META_IDS)("%s: last availability + update interval + sync margin", (id) => {
    const b = metaBody(id);
    const m = parseMeta(b);
    expect(m.run_utc).toBe(at(b.last_run_initialisation_time * 1000));
    expect(m.available_utc).toBe(at(b.last_run_availability_time * 1000));
    expect(m.next_run_expected_utc).toBe(
      at((b.last_run_availability_time + b.update_interval_seconds + SYNC_MARGIN_SECONDS) * 1000),
    );
  });

  it("gives no estimate when meta.json lacks the interval or availability", () => {
    const b = metaBody("ncep_hrrr_conus");
    expect(
      parseMeta({ ...b, update_interval_seconds: undefined }).next_run_expected_utc,
    ).toBeNull();
    expect(parseMeta({ ...b, last_run_availability_time: null }).next_run_expected_utc).toBeNull();
  });

  it("RAP-Smoke: newest issue + 24 h + that issue's ingest delay", () => {
    const pts = parseIdentify(recorded("ndgd-smoke-vert-identify").body);
    // Issued 2026-09-25T03:00Z, on the service by 04:23:01Z (idp_ingestdate).
    expect(nextSmokeIssue(pts)).toBe("2026-09-26T04:23:01Z");
    expect(nextSmokeIssue(pts.map((p) => ({ ...p, ingested_utc: null })))).toBeNull();
    expect(nextSmokeIssue([])).toBeNull();
  });

  it("stamps every series and the response with the estimates", async () => {
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch));
    const expected = (id: string) => parseMeta(metaBody(id)).next_run_expected_utc;
    const [hrrr, gfs, icon, ecmwf] = body.fields.cloud_cover_total.series;
    expect(hrrr.next_run_expected_utc).toBe(expected("ncep_hrrr_conus"));
    expect(gfs.next_run_expected_utc).toBe(expected("ncep_gfs013"));
    expect(icon.next_run_expected_utc).toBe(expected("dwd_icon"));
    expect(ecmwf.next_run_expected_utc).toBe(expected("ecmwf_ifs025"));
    expect(body.fields.pm2_5.series[0].next_run_expected_utc).toBe(expected("cams_global"));
    expect(body.fields.smoke_column.series[0].next_run_expected_utc).toBe("2026-09-26T04:23:01Z");
    expect(body.fields.seeing.series[0].next_run_expected_utc).toBeNull();
    // HRRR is hourly, so it is the soonest.
    expect(body.next_update_expected_utc).toBe("2026-09-26T00:45:21Z");
  });

  it("ignores series that are down when picking the soonest update", async () => {
    const down = recorded("open-meteo-meta-ncep_hrrr_conus");
    const hrrrDown = { ...down, status: 502, body: { error: true } };
    const f = fixtureFetch({
      "open-meteo-forecast-ncep_hrrr_conus": hrrrDown,
      "open-meteo-forecast-minutely_15-ncep_hrrr_conus": hrrrDown,
    });
    const { body } = await get(`/v1/conditions?${Q}`, makeDeps(f.fetch));
    expect(body.fields.cloud_cover_total.series[0].next_run_expected_utc).toBeNull();
    const others = ["ncep_gfs013", "dwd_icon", "ecmwf_ifs025", "cams_global"].map(
      (id) => parseMeta(metaBody(id)).next_run_expected_utc,
    );
    // ECMWF's 01:57Z estimate is the soonest once HRRR is out.
    expect(body.next_update_expected_utc).toBe([...others, "2026-09-26T04:23:01Z"].sort()[0]);
    expect(body.next_update_expected_utc).toBe("2026-09-26T01:57:13Z");
  });
});

describe("run-aware cache", () => {
  const entry = (fetched: string, next?: string): Entry<number> => ({
    fetched_utc: fetched,
    model_run_utc: "R1",
    ...(next ? { next_run_expected_utc: next } : {}),
    data: 1,
  });
  const spec = { store: nullStore, source: "x", key: "k", ttlSeconds: 3600 };
  const t = (hhmm: string) => new Date(`2026-09-26T${hhmm}:00Z`);

  it("keeps an entry until its next run is due, then re-checks it", () => {
    const e = entry("2026-09-26T00:00:00Z", "2026-09-26T00:40:00Z");
    expect(isFresh(e, spec, t("00:39"))).toBe(true);
    expect(isFresh(e, spec, t("00:40"))).toBe(false);
  });

  it("re-checks an overdue source every overdueTtlSeconds", () => {
    // Fetched after the expected time: the run is late.
    const e = entry("2026-09-26T00:41:00Z", "2026-09-26T00:40:00Z");
    expect(isFresh(e, { ...spec, overdueTtlSeconds: 120 }, t("00:42"))).toBe(true);
    expect(isFresh(e, { ...spec, overdueTtlSeconds: 120 }, t("00:43"))).toBe(false);
  });

  it("never outlives ttlSeconds, a new run, or a recheck boundary", () => {
    const e = entry("2026-09-26T00:00:00Z", "2026-09-26T05:00:00Z");
    expect(isFresh(e, spec, t("01:00"))).toBe(false);
    expect(isFresh(e, { ...spec, run: "R2" }, t("00:10"))).toBe(false);
    const recheck = { ...spec, recheckAfter: "2026-09-26T00:05:00Z" };
    expect(isFresh(e, recheck, t("00:04"))).toBe(true);
    expect(isFresh(e, recheck, t("00:06"))).toBe(false);
  });

  it("makes no upstream call until something is due to change", async () => {
    const cache = memoryCache();
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    // The fixtures' HRRR and GFS runs went live at 23:35Z and 23:38Z, minutes before they were
    // recorded, so both forecasts are read again once the 10-minute sync margin has passed.
    const synced = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(synced.fetch, { cache, now: later(10) }));
    const models = synced.calls.map((u) => new URL(u).searchParams.get("models"));
    expect([...new Set(models)].sort()).toEqual(["gfs_global", "ncep_hrrr_conus"]);
    // 50 min: before the 00:45Z HRRR estimate and inside the one-hour meta.json cap.
    // RAP-Smoke is kept until its next issue (04:23Z) instead of for 30 minutes.
    const f = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(f.fetch, { cache, now: later(50) }));
    expect(f.calls).toEqual([]);
  });

  it("polls an overdue model's meta.json every two minutes, and only that one", async () => {
    const cache = memoryCache();
    const metaCalls = async (minutes: number) => {
      const f = fixtureFetch();
      await get(`/v1/conditions?${Q}`, makeDeps(f.fetch, { cache, now: later(minutes) }));
      return f.calls
        .filter((u) => u.includes("meta.json"))
        .map((u) => /data\/([^/]+)\//.exec(u)?.[1])
        .sort();
    };
    expect(await metaCalls(0)).toHaveLength(5);
    // 00:47Z: every meta.json has hit the one-hour cap; HRRR's run (due 00:45Z) is late.
    expect(await metaCalls(68)).toHaveLength(5);
    expect(await metaCalls(69)).toEqual([]);
    expect(await metaCalls(70.5)).toEqual(["ncep_hrrr_conus"]);
  });

  it("re-reads a forecast fetched during Open-Meteo's post-run sync window", async () => {
    const meta = recorded("open-meteo-meta-ncep_hrrr_conus");
    // The run went live two minutes before the first request.
    const fresh = {
      ...meta,
      body: {
        ...(meta.body as object),
        last_run_availability_time: Math.floor(RECORDED.getTime() / 1000) - 120,
      },
    };
    const cache = memoryCache();
    const over = { "open-meteo-meta-ncep_hrrr_conus": fresh };
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch(over).fetch, { cache }));
    const inside = fixtureFetch(over);
    await get(`/v1/conditions?${Q}`, makeDeps(inside.fetch, { cache, now: later(7) }));
    expect(inside.calls).toEqual([]);
    // 8.5 min: past this run's sync margin, still inside GFS's (23:48:35Z).
    const after = fixtureFetch(over);
    await get(`/v1/conditions?${Q}`, makeDeps(after.fetch, { cache, now: later(8.5) }));
    // HRRR's hourly and 15-minute entries both predate the end of the sync margin.
    expect(after.calls.map((u) => new URL(u).searchParams.get("models"))).toEqual([
      "ncep_hrrr_conus",
      "ncep_hrrr_conus",
    ]);
  });

  it("keeps RAP-Smoke until the next issue is due", async () => {
    const cache = memoryCache();
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    const before = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(before.fetch, { cache, now: later(4 * 60) }));
    expect(before.calls.some((u) => u.includes("ndgd_smoke"))).toBe(false);
    // 04:24Z is past the 04:23:01Z estimate.
    const after = fixtureFetch();
    await get(`/v1/conditions?${Q}`, makeDeps(after.fetch, { cache, now: later(4 * 60 + 45) }));
    expect(after.calls.filter((u) => u.includes("ndgd_smoke"))).toHaveLength(2);
  });
});

describe("fan-out", () => {
  // Four hourly models, HRRR's 15-minute request and CAMS.
  const FORECASTS = 6;

  it("starts every forecast before any meta.json has answered (cold cache)", async () => {
    const inner = fixtureFetch();
    let release: () => void = () => {};
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const timedOut = setTimeout(release, 500);
    let forecasts = 0;
    let metaAnsweredBeforeForecasts = false;
    const fetch: FetchLike = async (url, init) => {
      if (url.includes("meta.json")) {
        await gate;
        if (forecasts < FORECASTS) metaAnsweredBeforeForecasts = true;
        return inner.fetch(url, init);
      }
      if (url.includes("/v1/forecast") || url.includes("/v1/air-quality")) {
        forecasts += 1;
        if (forecasts === FORECASTS) release();
      }
      return inner.fetch(url, init);
    };
    const { status } = await get(`/v1/conditions?${Q}`, makeDeps(fetch));
    clearTimeout(timedOut);
    expect(status).toBe(200);
    expect(forecasts).toBe(FORECASTS);
    expect(metaAnsweredBeforeForecasts).toBe(false);
  });
});
