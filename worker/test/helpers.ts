import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type Fixture, fixtureName } from "../scripts/fixture-names.ts";
import { handle } from "../src/index.ts";
import type { CacheLike, Deps, Env, FetchLike, KvLike } from "../src/types.ts";

const DIR = join(import.meta.dirname, "fixtures");

export const manifest = JSON.parse(readFileSync(join(DIR, "manifest.json"), "utf8")) as {
  recorded_utc: string;
  files: Record<string, { url: string }>;
};

/** Fixed "now": the moment the fixtures were recorded. */
export const RECORDED = new Date(manifest.recorded_utc);
export const Q = "lat=38.35&lon=-109.95&start=2026-09-26T00:00Z&end=2026-09-26T14:00Z";

export function fixture(path: string): Fixture {
  return JSON.parse(readFileSync(join(DIR, path), "utf8")) as Fixture;
}

export const recorded = (name: string): Fixture => fixture(`recorded/${name}.json`);

export function toResponse(f: Fixture): Response {
  const text = f.body_format === "json" ? JSON.stringify(f.body) : String(f.body);
  return new Response(text, { status: f.status, headers: { "content-type": f.content_type } });
}

type Override = Fixture | "throw" | ((url: string) => Fixture);

/** Routes upstream URLs to fixtures; anything unmapped throws, so no request can escape. */
export function fixtureFetch(overrides: Record<string, Override> = {}) {
  const calls: string[] = [];
  const fetch: FetchLike = async (url) => {
    calls.push(url);
    const name = fixtureName(url);
    const o = overrides[name];
    if (o === "throw") throw new TypeError("fetch failed");
    if (typeof o === "function") return toResponse(o(url));
    if (o) return toResponse(o);
    if (name === "airnow-ziplatlong") {
      return toResponse(fixture("synthetic/airnow-ziplatlong.synthetic.json"));
    }
    return toResponse(recorded(name));
  };
  return { fetch, calls };
}

export function memoryCache(): CacheLike & { size: () => number } {
  const m = new Map<string, string>();
  const key = (r: Request | string) => (typeof r === "string" ? r : r.url);
  return {
    match: async (r) => {
      const hit = m.get(key(r));
      return hit === undefined ? undefined : new Response(hit);
    },
    put: async (r, res) => {
      m.set(key(r), await res.text());
    },
    size: () => m.size,
  };
}

export function memoryKv(): KvLike & { keys: () => string[] } {
  const m = new Map<string, string>();
  return {
    get: async (k) => m.get(k) ?? null,
    put: async (k, v) => {
      m.set(k, v);
    },
    keys: () => [...m.keys()],
  };
}

export function makeDeps(
  fetch: FetchLike,
  opts: { now?: Date; cache?: CacheLike | null } = {},
): Deps {
  const now = opts.now ?? RECORDED;
  return { fetch, now: () => now, cache: opts.cache === undefined ? memoryCache() : opts.cache };
}

// biome-ignore lint/suspicious/noExplicitAny: tests read loosely typed JSON responses
export type Json = any;

export async function get(
  path: string,
  deps: Deps,
  env: Env = {},
): Promise<{ status: number; body: Json; headers: Headers }> {
  const res = await handle(new Request(`https://worker.test${path}`), env, deps);
  return { status: res.status, body: await res.json(), headers: res.headers };
}

export const withStatus = (f: Fixture, status: number, body: unknown = f.body): Fixture => ({
  ...f,
  status,
  body,
});
