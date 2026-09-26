import { describe, expect, it } from "vitest";
import { handle } from "../src/index.ts";
import { CONDITIONS_MAX_AGE, conditionsMaxAge, etagFor, matchesEtag } from "../src/revalidate.ts";
import type { Deps, Env } from "../src/types.ts";
import {
  fixture,
  fixtureFetch,
  type Json,
  makeDeps,
  memoryCache,
  Q,
  RECORDED,
  recorded,
} from "./helpers.ts";

const later = (minutes: number) => new Date(RECORDED.getTime() + minutes * 60_000);
const COND = `/v1/conditions?${Q}`;

async function call(path: string, deps: Deps, headers: Record<string, string> = {}, env: Env = {}) {
  return handle(new Request(`https://worker.test${path}`, { headers }), env, deps);
}

describe("ETag", () => {
  it("is a strong, quoted content hash", async () => {
    const res = await call(COND, makeDeps(fixtureFetch().fetch));
    expect(res.status).toBe(200);
    expect(res.headers.get("etag")).toMatch(/^"[0-9a-f]{32}"$/);
    expect(res.headers.get("access-control-expose-headers")).toMatch(/etag/);
  });

  it("stays the same when only fetch and generation times differ", async () => {
    const a = await call(COND, makeDeps(fixtureFetch().fetch));
    const b = await call(COND, makeDeps(fixtureFetch().fetch, { now: later(1) }));
    const [ba, bb]: Json[] = [await a.json(), await b.json()];
    expect(ba.generated_utc).not.toBe(bb.generated_utc);
    expect(ba.fields.cloud_cover_total.series[0].fetched_utc).not.toBe(
      bb.fields.cloud_cover_total.series[0].fetched_utc,
    );
    expect(a.headers.get("etag")).toBe(b.headers.get("etag"));
  });

  it("changes when a value or a model run changes", async () => {
    const base = (await call(COND, makeDeps(fixtureFetch().fetch))).headers.get("etag");
    const hrrr = recorded("open-meteo-forecast-ncep_hrrr_conus");
    const body = structuredClone(hrrr.body) as Json;
    body.hourly.cloud_cover[3] += 1;
    const valueChanged = await call(
      COND,
      makeDeps(fixtureFetch({ "open-meteo-forecast-ncep_hrrr_conus": { ...hrrr, body } }).fetch),
    );
    expect(valueChanged.headers.get("etag")).not.toBe(base);
    const meta = recorded("open-meteo-meta-ncep_gfs013");
    const newRun = {
      ...meta,
      body: {
        ...(meta.body as Json),
        last_run_initialisation_time: (meta.body as Json).last_run_initialisation_time + 21600,
      },
    };
    const runChanged = await call(
      COND,
      makeDeps(fixtureFetch({ "open-meteo-meta-ncep_gfs013": newRun }).fetch),
    );
    expect(runChanged.headers.get("etag")).not.toBe(base);
  });

  it("leaves out the delivery timestamps and nothing else", async () => {
    expect(await etagFor({ a: 1, fetched_utc: "x" })).toBe(
      await etagFor({ a: 1, fetched_utc: "y" }),
    );
    expect(await etagFor({ a: 1 })).not.toBe(await etagFor({ a: 2 }));
  });
});

describe("If-None-Match", () => {
  it("answers 304 with no body and the same validators", async () => {
    const cache = memoryCache();
    const first = await call(COND, makeDeps(fixtureFetch().fetch, { cache }));
    const etag = first.headers.get("etag")!;
    const f = fixtureFetch();
    const res = await call(COND, makeDeps(f.fetch, { cache }), { "if-none-match": etag });
    expect(res.status).toBe(304);
    expect(await res.text()).toBe("");
    expect(res.headers.get("etag")).toBe(etag);
    expect(res.headers.get("cache-control")).toBe(first.headers.get("cache-control"));
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("content-type")).toBeNull();
    expect(f.calls).toEqual([]);
  });

  it("uses the weak comparison: W/ tags and lists match, others don't", () => {
    const tag = '"abc"';
    expect(matchesEtag('W/"abc"', tag)).toBe(true);
    expect(matchesEtag('"x", W/"abc"', tag)).toBe(true);
    expect(matchesEtag("*", tag)).toBe(true);
    expect(matchesEtag('"abd"', tag)).toBe(false);
    expect(matchesEtag(null, tag)).toBe(false);
  });

  it("answers 200 with the new body once the data has changed", async () => {
    const old = await call(COND, makeDeps(fixtureFetch().fetch));
    const hrrr = recorded("open-meteo-forecast-ncep_hrrr_conus");
    const body = structuredClone(hrrr.body) as Json;
    body.hourly.visibility[0] = 1000;
    const f = fixtureFetch({ "open-meteo-forecast-ncep_hrrr_conus": { ...hrrr, body } });
    const res = await call(COND, makeDeps(f.fetch), { "if-none-match": old.headers.get("etag")! });
    expect(res.status).toBe(200);
    expect(((await res.json()) as Json).fields.visibility.series[0].values[0].v).toBe(1000);
  });

  it("revalidates space weather and smoke too", async () => {
    for (const path of [
      "/v1/space-weather?lat=38.35&lon=-109.95",
      "/v1/smoke?bbox=-114,37,-109,42",
    ]) {
      const cache = memoryCache();
      const first = await call(path, makeDeps(fixtureFetch().fetch, { cache }));
      const etag = first.headers.get("etag")!;
      expect(etag, path).toMatch(/^"[0-9a-f]{32}"$/);
      const again = await call(path, makeDeps(fixtureFetch().fetch, { cache, now: later(1) }), {
        "if-none-match": etag,
      });
      expect(again.status, path).toBe(304);
    }
  });

  it("never tags errors or health", async () => {
    const deps = makeDeps(fixtureFetch().fetch);
    const bad = await call("/v1/conditions?lat=38.351&lon=-109.95", deps);
    expect(bad.status).toBe(400);
    expect(bad.headers.get("etag")).toBeNull();
    expect(bad.headers.get("cache-control")).toBe("no-store");
    const health = await call("/health", deps);
    expect(health.headers.get("etag")).toBeNull();
    expect(health.headers.get("cache-control")).toBe("no-store");
  });
});

describe("Cache-Control", () => {
  const maxAge = (res: Response) =>
    Number(/max-age=(\d+)/.exec(res.headers.get("cache-control") ?? "")?.[1]);

  it("runs to the soonest expected model run, capped", async () => {
    // 23:39Z: HRRR's next run is expected 00:45Z, over an hour away, so the cap applies.
    const now = await call(COND, makeDeps(fixtureFetch().fetch));
    expect(now.headers.get("cache-control")).toBe(
      `public, max-age=${CONDITIONS_MAX_AGE.max}, stale-while-revalidate=600`,
    );
    // 00:29:36.069Z: 944.9 s to 00:45:21Z, rounded down.
    const cache = memoryCache();
    await call(COND, makeDeps(fixtureFetch().fetch, { cache }));
    const res = await call(COND, makeDeps(fixtureFetch().fetch, { cache, now: later(50) }));
    expect(maxAge(res)).toBe(944);
  });

  it("stays within its bounds", () => {
    const t0 = new Date("2026-09-26T00:00:00Z");
    expect(conditionsMaxAge("2026-09-26T00:10:00Z", t0)).toBe(600);
    expect(conditionsMaxAge("2026-09-26T00:00:30Z", t0)).toBe(CONDITIONS_MAX_AGE.min);
    // Overdue: the run is late, so check again soon.
    expect(conditionsMaxAge("2026-09-25T23:00:00Z", t0)).toBe(CONDITIONS_MAX_AGE.min);
    expect(conditionsMaxAge("2026-09-26T06:00:00Z", t0)).toBe(CONDITIONS_MAX_AGE.max);
    expect(conditionsMaxAge(null, t0)).toBe(CONDITIONS_MAX_AGE.unknown);
    expect(conditionsMaxAge("garbage", t0)).toBe(CONDITIONS_MAX_AGE.unknown);
  });
});

describe("upstream down", () => {
  it("still reads as unavailable, with its own tag and a bounded max-age", async () => {
    const down = fixture("down/open-meteo-forecast.json");
    const f = fixtureFetch({
      "open-meteo-forecast-ncep_hrrr_conus": down,
      "open-meteo-forecast-gfs_global": down,
      "open-meteo-forecast-icon_global": down,
      "open-meteo-forecast-ecmwf_ifs025": down,
      "open-meteo-forecast-minutely_15-ncep_hrrr_conus": down,
      "open-meteo-air-quality": fixture("down/open-meteo-air-quality.json"),
      "ndgd-smoke-sfc-identify": fixture("down/ndgd-smoke-identify.json"),
      "ndgd-smoke-vert-identify": fixture("down/ndgd-smoke-identify.json"),
      "7timer-astro": fixture("down/7timer-astro.json"),
    });
    const healthy = await call(COND, makeDeps(fixtureFetch().fetch));
    const res = await call(COND, makeDeps(f.fetch));
    expect(res.status).toBe(200);
    const body = (await res.json()) as Json;
    for (const field of Object.values<Json>(body.fields)) expect(field.status).toBe("unavailable");
    expect(body.next_update_expected_utc).toBeNull();
    expect(res.headers.get("etag")).not.toBe(healthy.headers.get("etag"));
    expect(res.headers.get("cache-control")).toBe(
      `public, max-age=${CONDITIONS_MAX_AGE.unknown}, stale-while-revalidate=600`,
    );
  });
});

describe("Server-Timing", () => {
  const entries = (res: Response) =>
    Object.fromEntries(
      (res.headers.get("server-timing") ?? "").split(", ").map((e) => {
        const [name, ...params] = e.split(";");
        return [name, params.join(";")];
      }),
    );

  it("names every source, whether the cache answered, and the total", async () => {
    const cache = memoryCache();
    const cold = entries(await call(COND, makeDeps(fixtureFetch().fetch, { cache })));
    for (const name of [
      "meta-ncep_hrrr_conus",
      "om-hrrr",
      "om-gfs",
      "om-icon",
      "om-ecmwf",
      "meta-cams_global",
      "om-cams_global",
      "smoke-sfc",
      "smoke-vert",
      "7timer",
      "total",
    ]) {
      expect(cold[name], name).toMatch(/dur=\d+/);
    }
    expect(cold["om-hrrr"]).toMatch(/desc="miss"/);
    const warm = entries(await call(COND, makeDeps(fixtureFetch().fetch, { cache })));
    expect(warm["om-hrrr"]).toMatch(/desc="hit"/);
    const failed = entries(
      await call(
        COND,
        makeDeps(fixtureFetch({ "7timer-astro": fixture("down/7timer-astro.json") }).fetch),
      ),
    );
    expect(failed["7timer"]).toMatch(/desc="fail"/);
  });
});

describe("waitUntil", () => {
  it("moves cache writes off the response path", async () => {
    const cache = memoryCache();
    const pending: Promise<unknown>[] = [];
    const deps = {
      ...makeDeps(fixtureFetch().fetch, { cache }),
      waitUntil: (p: Promise<unknown>) => pending.push(p),
    };
    expect((await call(COND, deps)).status).toBe(200);
    expect(pending.length).toBeGreaterThan(0);
    await Promise.all(pending);
    const f = fixtureFetch();
    await call(COND, makeDeps(f.fetch, { cache }));
    expect(f.calls).toEqual([]);
  });
});
