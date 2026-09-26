/**
 * Stateless live-conditions Worker (ADR-0010). No per-user state: coordinates arrive already
 * rounded to the 0.05° grid, and the only storage is upstream data keyed by cell and model run.
 */
import { budgetedFetch } from "./http.ts";
import { MAX_UPSTREAM_FETCHES, RATE_LIMIT_PERIOD_SECONDS } from "./limits.ts";
import { BadRequest } from "./params.ts";
import {
  conditionsMaxAge,
  etagFor,
  matchesEtag,
  STALE_WHILE_REVALIDATE_SECONDS,
  serverTiming,
} from "./revalidate.ts";
import { conditions, health, smoke, spaceWeather } from "./routes.ts";
import type { CacheLike, Deps, Env, Timing } from "./types.ts";

const HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "if-none-match",
  "access-control-expose-headers": "retry-after, etag, server-timing",
  "timing-allow-origin": "*",
};

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...HEADERS, "cache-control": "no-store" },
  });

/**
 * A cacheable JSON answer: a content ETag (fetch times left out), a 304 when the client
 * already holds it, and `Server-Timing` with the per-source timings either way.
 */
async function cacheable(
  request: Request,
  deps: Deps,
  body: unknown,
  maxAge: number,
  swr: number,
): Promise<Response> {
  const etag = await etagFor(body);
  const headers: Record<string, string> = {
    ...HEADERS,
    etag,
    "cache-control": `public, max-age=${maxAge}, stale-while-revalidate=${swr}`,
    "server-timing": serverTiming(deps.timings ?? [], deps.startedMs),
  };
  if (matchesEtag(request.headers.get("if-none-match"), etag)) {
    const { "content-type": _drop, ...rest } = headers;
    return new Response(null, { status: 304, headers: rest });
  }
  return new Response(JSON.stringify(body), { status: 200, headers });
}

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
  const timings: Timing[] = [];
  const deps = {
    ...rawDeps,
    fetch: budgetedFetch(rawDeps.fetch, MAX_UPSTREAM_FETCHES),
    timings,
    startedMs: Date.now(),
  };
  const url = new URL(request.url);
  try {
    switch (url.pathname) {
      case "/health":
        return json(await health(deps, env));
      case "/v1/conditions": {
        const body = await conditions(deps, env, url.searchParams);
        const maxAge = conditionsMaxAge(body.next_update_expected_utc, deps.now());
        return cacheable(request, deps, body, maxAge, STALE_WHILE_REVALIDATE_SECONDS);
      }
      case "/v1/space-weather":
        return cacheable(request, deps, await spaceWeather(deps, env, url.searchParams), 300, 300);
      case "/v1/smoke":
        return cacheable(request, deps, await smoke(deps, url.searchParams), 600, 600);
      default:
        return json({ error: "not found" }, 404);
    }
  } catch (err) {
    if (err instanceof BadRequest) return json({ error: err.message }, 400);
    return json({ error: "internal error" }, 500);
  }
}

interface ContextLike {
  waitUntil(p: Promise<unknown>): void;
}

function defaultDeps(ctx?: ContextLike): Deps {
  const cache = (globalThis as { caches?: { default?: CacheLike } }).caches?.default ?? null;
  return {
    fetch: (input, init) => fetch(input, init),
    now: () => new Date(),
    cache,
    // Not destructured: waitUntil needs its `this`.
    ...(ctx ? { waitUntil: (p: Promise<unknown>) => ctx.waitUntil(p) } : {}),
  };
}

export default {
  fetch(request: Request, env: Env, ctx?: ContextLike): Promise<Response> {
    return handle(request, env, defaultDeps(ctx));
  },
};
