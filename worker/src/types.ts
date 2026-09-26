export type Status = "ok" | "unavailable";

export interface Point {
  t: string;
  v: number | null;
}

export interface Series {
  model: string;
  upstream_model?: string;
  /** Minutes between points; only set on sub-hourly series (`series_15min`). */
  resolution_minutes?: number;
  model_run_utc: string | null;
  /** When the next run should be on the source, if the source says enough to estimate it. */
  next_run_expected_utc?: string | null;
  fetched_utc: string | null;
  status: Status;
  reason?: string;
  last_good_utc?: string | null;
  values: Point[];
}

export interface Field {
  unit: string;
  source: string;
  status: Status;
  fetched_utc: string | null;
  series: Series[];
  reason?: string;
  last_good_utc?: string | null;
  [extra: string]: unknown;
}

/** Minimal slice of a KV namespace binding; absent locally unless bound. */
export interface KvLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

/** Minimal slice of `caches.default`. */
export interface CacheLike {
  match(request: Request | string): Promise<Response | undefined>;
  put(request: Request | string, response: Response): Promise<void>;
}

/** Workers Rate Limiting binding; absent locally unless bound, and in tests. */
export interface RateLimiterLike {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  SPACE_WEATHER?: KvLike;
  RATE_LIMITER?: RateLimiterLike;
  AIRNOW_API_KEY?: string;
  SEVENTIMER_ENABLED?: string;
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

/** One `Server-Timing` entry: how long a source took and whether the cache answered. */
export interface Timing {
  name: string;
  ms: number;
  desc: "hit" | "miss" | "fail";
}

/** Everything that touches the outside world, injected so tests never reach the network. */
export interface Deps {
  fetch: FetchLike;
  now: () => Date;
  cache: CacheLike | null;
  /** `ctx.waitUntil` in production: cache and health writes leave the critical path. */
  waitUntil?: (p: Promise<unknown>) => void;
  /** Per-request timings, filled by `cachedLoad` and sent as `Server-Timing`. */
  timings?: Timing[];
}

export const iso = (d: Date): string => d.toISOString().replace(/\.\d{3}Z$/, "Z");
