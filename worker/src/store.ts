import { UpstreamError } from "./http.ts";
import { type CacheLike, type Deps, iso, type KvLike, type Timing } from "./types.ts";

/**
 * One entry per key, kept for a week so it can serve as the last good value after its
 * freshness window. Freshness is decided by `fetched_utc` age and, for model products,
 * by the model run: a new run makes the cached entry stale regardless of age.
 */
export interface Entry<T> {
  fetched_utc: string;
  model_run_utc: string | null;
  /**
   * When the source should publish its next run. An entry fetched before this goes stale
   * when it passes; after it (the run is overdue) the entry is re-checked every
   * `overdueTtlSeconds`.
   */
  next_run_expected_utc?: string | null;
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

export interface LoadSpec<T = unknown> {
  store: EntryStore;
  source: string;
  key: string;
  /** Upper bound on an entry's age, whatever the run says. */
  ttlSeconds: number;
  /** When set, a cached entry from a different run is stale. */
  run?: string | null;
  /** Entries fetched before this instant are stale once it has passed (Open-Meteo's sync margin). */
  recheckAfter?: string | null;
  /** Re-check interval once the entry's `next_run_expected_utc` has passed. Default 120 s. */
  overdueTtlSeconds?: number;
  /** The stored entry, when the caller has already read it (null: nothing stored). */
  stored?: Entry<T> | null;
  /** `Server-Timing` name; omitted loads are not timed. */
  timing?: string;
  /** Start of the timed span (epoch ms) when the caller began work before `cachedLoad`. */
  startedMs?: number;
}

const DEFAULT_OVERDUE_SECONDS = 120;

/** Whether a stored entry can answer now without an upstream call. */
export function isFresh<T>(stored: Entry<T>, spec: LoadSpec<T>, now: Date): boolean {
  const nowMs = now.getTime();
  const fetched = Date.parse(stored.fetched_utc);
  const age = (nowMs - fetched) / 1000;
  if (!(age >= 0 && age < spec.ttlSeconds)) return false;
  if (spec.run != null && stored.model_run_utc !== spec.run) return false;
  const boundaries = [spec.recheckAfter, stored.next_run_expected_utc]
    .filter((b): b is string => typeof b === "string")
    .map(Date.parse);
  if (boundaries.some((b) => fetched < b && b <= nowMs)) return false;
  const next = stored.next_run_expected_utc ? Date.parse(stored.next_run_expected_utc) : Number.NaN;
  if (next <= nowMs && age >= (spec.overdueTtlSeconds ?? DEFAULT_OVERDUE_SECONDS)) return false;
  return true;
}

/** Runs a write after the response when the platform allows it, otherwise inline. */
export async function defer(deps: Deps, work: Promise<unknown>): Promise<void> {
  const safe = work.catch(() => {});
  if (deps.waitUntil) deps.waitUntil(safe);
  else await safe;
}

function time(
  deps: Deps,
  spec: { timing?: string; startedMs?: number },
  t0: number,
  desc: Timing["desc"],
): void {
  if (spec.timing && deps.timings) {
    deps.timings.push({ name: spec.timing, ms: Date.now() - (spec.startedMs ?? t0), desc });
  }
}

export async function cachedLoad<T>(
  deps: Deps,
  spec: LoadSpec<T>,
  load: () => Promise<{
    data: T;
    model_run_utc?: string | null;
    next_run_expected_utc?: string | null;
  }>,
): Promise<Loaded<T>> {
  const t0 = Date.now();
  const now = deps.now();
  const stored = spec.stored !== undefined ? spec.stored : await spec.store.get<T>(spec.key);
  if (stored && isFresh(stored, spec, now)) {
    time(deps, spec, t0, "hit");
    return { ok: true, entry: stored, cached: true };
  }
  try {
    const { data, model_run_utc, next_run_expected_utc } = await load();
    const entry: Entry<T> = {
      fetched_utc: iso(now),
      model_run_utc: model_run_utc ?? spec.run ?? null,
      ...(next_run_expected_utc ? { next_run_expected_utc } : {}),
      data,
    };
    await defer(deps, spec.store.put(spec.key, entry));
    await defer(deps, recordHealth(deps, spec.source, null));
    time(deps, spec, t0, "miss");
    return { ok: true, entry, cached: false };
  } catch (err) {
    const reason = err instanceof UpstreamError ? err.message : "upstream parse error";
    await defer(deps, recordHealth(deps, spec.source, reason));
    time(deps, spec, t0, "fail");
    return { ok: false, reason, last_good: stored };
  }
}

export interface HealthRecord {
  last_success_utc: string | null;
  last_failure_utc: string | null;
  last_error: string | null;
}

const memoryHealth = new Map<string, HealthRecord>();

const NO_HEALTH: HealthRecord = {
  last_success_utc: null,
  last_failure_utc: null,
  last_error: null,
};

/** Updates this isolate's record at once; the shared (cache) copy is written in the background. */
function recordHealth(deps: Deps, source: string, error: string | null): Promise<void> {
  const store = edgeStore(deps);
  const key = `health:${source}`;
  const at = iso(deps.now());
  const apply = (prev: HealthRecord): HealthRecord =>
    error === null
      ? { ...prev, last_success_utc: at }
      : { ...prev, last_failure_utc: at, last_error: error };
  const write = (next: HealthRecord) => {
    memoryHealth.set(source, next);
    return store.put(key, { fetched_utc: at, model_run_utc: null, data: next });
  };
  const mem = memoryHealth.get(source);
  if (mem) return write(apply(mem));
  return (async () => {
    const prev = (await store.get<HealthRecord>(key))?.data ?? NO_HEALTH;
    await write(apply(memoryHealth.get(source) ?? prev));
  })();
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
