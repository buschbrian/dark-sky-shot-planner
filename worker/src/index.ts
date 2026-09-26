/**
 * Stateless live-conditions Worker (ADR-0010). No per-user state: coordinates arrive already
 * rounded to the 0.05° grid, and the only storage is upstream data keyed by cell and model run.
 */
import { budgetedFetch } from "./http.ts";
import { MAX_UPSTREAM_FETCHES, RATE_LIMIT_PERIOD_SECONDS } from "./limits.ts";
import { BadRequest } from "./params.ts";
import { conditions, health, smoke, spaceWeather } from "./routes.ts";
import type { CacheLike, Deps, Env } from "./types.ts";

const HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-expose-headers": "retry-after",
};

const json = (body: unknown, status = 200, maxAge = 0): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...HEADERS, "cache-control": maxAge > 0 ? `public, max-age=${maxAge}` : "no-store" },
  });

/** Keyed on client IP: the API is keyless, so there is no better key. Fails open. */
async function overLimit(request: Request, env: Env): Promise<boolean> {
  if (!env.RATE_LIMITER) return false;
  try {
    const key = request.headers.get("cf-connecting-ip") ?? "unknown";
    return !(await env.RATE_LIMITER.limit({ key })).success;
  } catch {
    return false;
  }
}

export async function handle(request: Request, env: Env, rawDeps: Deps): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: HEADERS });
  if (await overLimit(request, env)) {
    const res = json({ error: "rate limited" }, 429);
    res.headers.set("retry-after", String(RATE_LIMIT_PERIOD_SECONDS));
    return res;
  }
  if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
  const deps = { ...rawDeps, fetch: budgetedFetch(rawDeps.fetch, MAX_UPSTREAM_FETCHES) };
  const url = new URL(request.url);
  try {
    switch (url.pathname) {
      case "/health":
        return json(await health(deps, env));
      case "/v1/conditions":
        return json(await conditions(deps, env, url.searchParams), 200, 300);
      case "/v1/space-weather":
        return json(await spaceWeather(deps, env, url.searchParams), 200, 300);
      case "/v1/smoke":
        return json(await smoke(deps, url.searchParams), 200, 600);
      default:
        return json({ error: "not found" }, 404);
    }
  } catch (err) {
    if (err instanceof BadRequest) return json({ error: err.message }, 400);
    return json({ error: "internal error" }, 500);
  }
}

function defaultDeps(): Deps {
  const cache = (globalThis as { caches?: { default?: CacheLike } }).caches?.default ?? null;
  return { fetch: (input, init) => fetch(input, init), now: () => new Date(), cache };
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, defaultDeps());
  },
};
