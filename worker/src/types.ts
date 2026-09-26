export type Status = "ok" | "unavailable";

export interface Point {
  t: string;
  v: number | null;
}

export interface Series {
  model: string;
  upstream_model?: string;
  model_run_utc: string | null;
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

/** Everything that touches the outside world, injected so tests never reach the network. */
export interface Deps {
  fetch: FetchLike;
  now: () => Date;
  cache: CacheLike | null;
}

export const iso = (d: Date): string => d.toISOString().replace(/\.\d{3}Z$/, "Z");
