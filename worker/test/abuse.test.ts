import { describe, expect, it } from "vitest";
import { budgetedFetch, getJson } from "../src/http.ts";
import { handle } from "../src/index.ts";
import { MAX_UPSTREAM_FETCHES, RATE_LIMIT_PERIOD_SECONDS } from "../src/limits.ts";
import type { Env, RateLimiterLike } from "../src/types.ts";
import { fixtureFetch, makeDeps, Q } from "./helpers.ts";

/** Allows `limit` calls per key, then refuses; records every key it saw. */
function limiter(limit: number): RateLimiterLike & { keys: string[] } {
  const counts = new Map<string, number>();
  const keys: string[] = [];
  return {
    keys,
    limit: async ({ key }) => {
      keys.push(key);
      const n = (counts.get(key) ?? 0) + 1;
      counts.set(key, n);
      return { success: n <= limit };
    },
  };
}

const req = (path: string, ip?: string, method = "GET") =>
  new Request(`https://worker.test${path}`, {
    method,
    headers: ip ? { "cf-connecting-ip": ip } : {},
  });

describe("rate limiting", () => {
  it("answers 429 with Retry-After past the limit, per client IP, before any upstream call", async () => {
    const rl = limiter(2);
    const env: Env = { RATE_LIMITER: rl };
    const f = fixtureFetch();
    const deps = makeDeps(f.fetch);
    expect((await handle(req("/health", "203.0.113.7"), env, deps)).status).toBe(200);
    expect((await handle(req("/health", "203.0.113.7"), env, deps)).status).toBe(200);
    const res = await handle(req(`/v1/conditions?${Q}`, "203.0.113.7"), env, deps);
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe(String(RATE_LIMIT_PERIOD_SECONDS));
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(await res.json()).toEqual({ error: "rate limited" });
    expect(f.calls).toEqual([]);
    expect((await handle(req("/health", "198.51.100.2"), env, deps)).status).toBe(200);
    expect(rl.keys).toEqual(["203.0.113.7", "203.0.113.7", "203.0.113.7", "198.51.100.2"]);
  });

  it("serves normally when the binding is absent", async () => {
    const deps = makeDeps(fixtureFetch().fetch);
    for (let i = 0; i < 5; i++) {
      expect((await handle(req("/health", "203.0.113.7"), {}, deps)).status).toBe(200);
    }
  });

  it("fails open when the binding throws", async () => {
    const env: Env = {
      RATE_LIMITER: {
        limit: async () => {
          throw new Error("binding unavailable");
        },
      },
    };
    const res = await handle(req("/health", "203.0.113.7"), env, makeDeps(fixtureFetch().fetch));
    expect(res.status).toBe(200);
  });

  it("does not count CORS preflights", async () => {
    const rl = limiter(0);
    const res = await handle(
      req("/v1/conditions", "203.0.113.7", "OPTIONS"),
      { RATE_LIMITER: rl },
      makeDeps(fixtureFetch().fetch),
    );
    expect(res.status).toBe(204);
    expect(rl.keys).toEqual([]);
  });
});

describe("upstream fan-out cap", () => {
  it("keeps a full conditions request under the per-request budget", async () => {
    const f = fixtureFetch();
    const res = await handle(
      req(`/v1/conditions?${Q}`),
      { AIRNOW_API_KEY: "k" },
      makeDeps(f.fetch),
    );
    expect(res.status).toBe(200);
    expect(f.calls.length).toBeGreaterThan(0);
    expect(f.calls.length).toBeLessThanOrEqual(MAX_UPSTREAM_FETCHES);
  });

  it("refuses calls past the budget with a reason that names it", async () => {
    const f = fixtureFetch();
    const capped = budgetedFetch(f.fetch, 1);
    const url = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json";
    await expect(getJson(capped, url)).resolves.toBeTruthy();
    await expect(getJson(capped, url)).rejects.toThrow("per-request upstream budget spent");
    expect(f.calls).toHaveLength(1);
  });
});
