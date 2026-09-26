import { describe, expect, it } from "vitest";
import { fixture, fixtureFetch, get, makeDeps, memoryCache, memoryKv, Q } from "./helpers.ts";

describe("GET /health", () => {
  it("reports config and unknown upstreams before any call, without a network probe", async () => {
    const f = fixtureFetch();
    const { status, body } = await get("/health", makeDeps(f.fetch), {
      AIRNOW_API_KEY: "k-secret",
    });
    expect(status).toBe(200);
    expect(body.status).toBe("ok");
    expect(body.config).toEqual({
      airnow_key_configured: true,
      space_weather_kv_bound: false,
      edge_cache_available: true,
      seventimer_enabled: true,
    });
    expect(body.upstreams["open-meteo-forecast"].status).toBe("unknown");
    expect(JSON.stringify(body)).not.toContain("k-secret");
    expect(f.calls).toEqual([]);
  });

  it("records last success and failure per upstream", async () => {
    const cache = memoryCache();
    await get(`/v1/conditions?${Q}`, makeDeps(fixtureFetch().fetch, { cache }));
    await get("/v1/space-weather", makeDeps(fixtureFetch().fetch, { cache }), {
      SPACE_WEATHER: memoryKv(),
    });
    const { body } = await get("/health", makeDeps(fixtureFetch().fetch, { cache }));
    expect(body.upstreams["open-meteo-forecast"].status).toBe("ok");
    expect(body.upstreams["open-meteo-forecast"].last_success_utc).toBeTruthy();
    expect(body.upstreams["swpc-ovation"].status).toBe("ok");
    expect(body.upstreams.hms.status).toBe("unknown");
  });

  it("shows a failing upstream with its error", async () => {
    const f = fixtureFetch({ "7timer-astro": fixture("down/7timer-astro.json") });
    const deps = makeDeps(f.fetch);
    await get(`/v1/conditions?${Q}`, deps);
    const { body } = await get("/health", deps);
    expect(body.upstreams["7timer"]).toMatchObject({
      status: "failing",
      last_error: "invalid JSON",
    });
  });
});

describe("routing", () => {
  it("404s unknown paths, 405s writes, answers CORS preflight", async () => {
    const deps = makeDeps(fixtureFetch().fetch);
    expect((await get("/v2/anything", deps)).status).toBe(404);
    const { handle } = await import("../src/index.ts");
    expect(
      (await handle(new Request("https://w.test/health", { method: "POST" }), {}, deps)).status,
    ).toBe(405);
    const pre = await handle(
      new Request("https://w.test/v1/conditions", { method: "OPTIONS" }),
      {},
      deps,
    );
    expect(pre.status).toBe(204);
    expect(pre.headers.get("access-control-allow-origin")).toBe("*");
  });
});
