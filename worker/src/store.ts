import { UpstreamError } from "./http.ts";
import { type CacheLike, type Deps, iso, type KvLike } from "./types.ts";

/**
 * One entry per key, kept for a week so it can serve as the last good value after its
 * freshness window. Freshness is decided by `fetched_utc` age and, for model products,
 * by the model run: a new run makes the cached entry stale regardless of age.
 */
export interface Entry<T> {
  fetched_utc: string;
  model_run_utc: string | null;
  data: T;
}

export interface EntryStore {
  get<T>(key: string): Promise<Entry<T> | null>;
  put<T>(key: string, entry: Entry<T>): Promise<void>;
}

const KEEP_SECONDS = 7 * 86_400;
const CACHE_ORIGIN = "https://conditions-cache.invalid/v1/";

export function cacheStore(cache: CacheLike): EntryStore {
  return {
    async get<T>(key: string) {
      try {
        const hit = await cache.match(CACHE_ORIGIN + encodeURIComponent(key));
        return hit ? ((await hit.json()) as Entry<T>) : null;
      } catch {
        return null;
      }
    },
    async put<T>(key: string, entry: Entry<T>) {
      try {
        await cache.put(
          CACHE_ORIGIN + encodeURIComponent(key),
          new Response(JSON.stringify(entry), {
            headers: {
              "content-type": "application/json",
              "cache-control": `public, max-age=${KEEP_SECONDS}`,
            },
          }),
        );
      } catch {
        // Cache writes are best effort.
      }
    },
  };
}

export function kvStore(kv: KvLike): EntryStore {
  return {
    async get<T>(key: string) {
      try {
        const raw = await kv.get(key);
        return raw ? (JSON.parse(raw) as Entry<T>) : null;
      } catch {
        return null;
      }
    },
    async put<T>(key: string, entry: Entry<T>) {
      try {
        await kv.put(key, JSON.stringify(entry), { expirationTtl: KEEP_SECONDS });
      } catch {
        // KV writes are best effort.
      }
    },
  };
}

export const nullStore: EntryStore = {
  get: async () => null,
  put: async () => {},
};

export const edgeStore = (deps: Deps): EntryStore =>
  deps.cache ? cacheStore(deps.cache) : nullStore;

export type Loaded<T> =
  | { ok: true; entry: Entry<T>; cached: boolean }
  | { ok: false; reason: string; last_good: Entry<T> | null };

export interface LoadSpec {
  store: EntryStore;
  source: string;
  key: string;
  ttlSeconds: number;
  /** When set, a cached entry from a different run is stale. */
  run?: string | null;
}

export async function cachedLoad<T>(
  deps: Deps,
  spec: LoadSpec,
  load: () => Promise<{ data: T; model_run_utc?: string | null }>,
): Promise<Loaded<T>> {
  const now = deps.now();
  const stored = await spec.store.get<T>(spec.key);
  if (stored) {
    const age = (now.getTime() - Date.parse(stored.fetched_utc)) / 1000;
    const sameRun = spec.run == null || stored.model_run_utc === spec.run;
    if (age >= 0 && age < spec.ttlSeconds && sameRun) {
      return { ok: true, entry: stored, cached: true };
    }
  }
  try {
    const { data, model_run_utc } = await load();
    const entry: Entry<T> = {
      fetched_utc: iso(now),
      model_run_utc: model_run_utc ?? spec.run ?? null,
      data,
    };
    await spec.store.put(spec.key, entry);
    await recordHealth(deps, spec.source, null);
    return { ok: true, entry, cached: false };
  } catch (err) {
    const reason = err instanceof UpstreamError ? err.message : "upstream parse error";
    await recordHealth(deps, spec.source, reason);
    return { ok: false, reason, last_good: stored };
  }
}

export interface HealthRecord {
  last_success_utc: string | null;
  last_failure_utc: string | null;
  last_error: string | null;
}

const memoryHealth = new Map<string, HealthRecord>();

async function recordHealth(deps: Deps, source: string, error: string | null): Promise<void> {
  const store = edgeStore(deps);
  const key = `health:${source}`;
  const prev = memoryHealth.get(source) ??
    (await store.get<HealthRecord>(key))?.data ?? {
      last_success_utc: null,
      last_failure_utc: null,
      last_error: null,
    };
  const at = iso(deps.now());
  const next: HealthRecord =
    error === null
      ? { ...prev, last_success_utc: at }
      : { ...prev, last_failure_utc: at, last_error: error };
  memoryHealth.set(source, next);
  await store.put(key, { fetched_utc: at, model_run_utc: null, data: next });
}

export async function readHealth(deps: Deps, source: string): Promise<HealthRecord | null> {
  const mem = memoryHealth.get(source);
  const stored = (await edgeStore(deps).get<HealthRecord>(`health:${source}`))?.data ?? null;
  if (!mem) return stored;
  if (!stored) return mem;
  const later = (a: string | null, b: string | null) => ((a ?? "") > (b ?? "") ? a : b);
  const failure = later(mem.last_failure_utc, stored.last_failure_utc);
  return {
    last_success_utc: later(mem.last_success_utc, stored.last_success_utc),
    last_failure_utc: failure,
    last_error: failure === mem.last_failure_utc ? mem.last_error : stored.last_error,
  };
}

export function resetMemoryHealth(): void {
  memoryHealth.clear();
}
