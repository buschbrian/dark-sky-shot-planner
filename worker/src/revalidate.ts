/** Cheap revalidation: content ETags, max-age from model runs, and Server-Timing. */
import type { Timing } from "./types.ts";

/** Delivery timestamps: they change on every refetch without the data changing. */
const VOLATILE_KEYS = new Set(["generated_utc", "fetched_utc"]);

/**
 * A strong ETag over the response with its fetch and generation times left out, so it
 * changes when a model run, a value, a status or a reason changes, and not when the Worker
 * merely re-read an upstream. Two responses with one tag differ only in those timestamps.
 */
export async function etagFor(body: unknown): Promise<string> {
  const canonical = JSON.stringify(body, (k, v) => (VOLATILE_KEYS.has(k) ? undefined : v));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  const hex = [...new Uint8Array(digest).slice(0, 16)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `"${hex}"`;
}

/**
 * `If-None-Match` uses the weak comparison (RFC 9110 §13.1.2): a `W/` prefix is ignored.
 * Cloudflare may weaken a strong ETag when it recompresses a response, and clients echo it.
 */
export function matchesEtag(header: string | null, etag: string): boolean {
  if (!header) return false;
  const bare = (t: string) => t.trim().replace(/^W\//, "");
  return header.split(",").some((t) => t.trim() === "*" || bare(t) === bare(etag));
}

/** Bounds on a `/v1/conditions` max-age, which otherwise runs to the soonest expected run. */
export const CONDITIONS_MAX_AGE = { min: 60, max: 1800, unknown: 300 } as const;
export const STALE_WHILE_REVALIDATE_SECONDS = 600;

/** Seconds a client may reuse conditions: until the soonest expected model run, bounded. */
export function conditionsMaxAge(nextUpdateUtc: string | null, now: Date): number {
  const { min, max, unknown } = CONDITIONS_MAX_AGE;
  if (!nextUpdateUtc) return unknown;
  const seconds = Math.floor((Date.parse(nextUpdateUtc) - now.getTime()) / 1000);
  if (!Number.isFinite(seconds)) return unknown;
  return Math.min(max, Math.max(min, seconds));
}

/**
 * One entry per source, e.g. `om-hrrr;dur=182;desc="miss"`, plus `total`. In Workers the
 * clock only advances on I/O, so these are wall times spent waiting on caches and upstreams.
 */
export function serverTiming(timings: Timing[], startedMs?: number): string {
  const entries = timings.map(
    (t) => `${t.name.replace(/[^A-Za-z0-9_-]/g, "-")};dur=${Math.max(0, t.ms)};desc="${t.desc}"`,
  );
  if (startedMs !== undefined) entries.push(`total;dur=${Math.max(0, Date.now() - startedMs)}`);
  return entries.join(", ");
}
