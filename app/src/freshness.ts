/**
 * Freshness convention, mirrored from the pipeline config. One set of
 * thresholds (fresh / aging / stale / unavailable) applied uniformly to
 * every layer; the client reads the same config JSON the pipelines emit.
 */

export interface LayerFreshnessConfig {
  layer_id: string;
  fresh_max_days: number;
  aging_max_days: number;
  stale_max_days: number;
}

export type Freshness = "fresh" | "aging" | "stale" | "unavailable";

export function freshnessOf(
  publicationDate: string | null,
  cfg: LayerFreshnessConfig,
  today: Date = new Date(),
): Freshness {
  if (!publicationDate) return "unavailable";
  const pub = new Date(`${publicationDate}T00:00:00Z`);
  if (Number.isNaN(pub.getTime())) return "unavailable";
  const ageDays = Math.floor((today.getTime() - pub.getTime()) / 86_400_000);
  if (ageDays <= cfg.fresh_max_days) return "fresh";
  if (ageDays <= cfg.aging_max_days) return "aging";
  if (ageDays <= cfg.stale_max_days) return "stale";
  return "stale";
}

export const FRESHNESS_LABEL: Record<Freshness, string> = {
  fresh: "fresh",
  aging: "aging",
  stale: "stale — verify before trusting",
  unavailable: "unavailable",
};

/**
 * Hour-scale freshness for live conditions (`config/app-config.json`'s
 * `freshness_hours`, `docs/ios/PLAN.md` §Verdict). Live feeds age in whole
 * hours, not days: a daily smoke issue is not "stale" every evening.
 */
export interface HourFreshnessConfig {
  layer_id: string;
  fresh_max_hours: number;
  aging_max_hours: number;
  stale_max_hours: number;
}

/**
 * Age in whole hours, given an instant to measure from `now`. Returns null
 * when the timestamp is missing or unparsable (unavailable).
 */
export function ageHours(timestampUtc: string | null, now: Date = new Date()): number | null {
  if (!timestampUtc) return null;
  const t = new Date(timestampUtc);
  if (Number.isNaN(t.getTime())) return null;
  return Math.floor((now.getTime() - t.getTime()) / 3_600_000);
}

/**
 * Freshness of a live-conditions value. Age is the older (larger) of
 * `modelRunUtc` and `fetchedUtc` in whole hours, per PLAN.md; either being
 * absent makes the freshness "unavailable" rather than guessing from the one
 * that is present.
 */
export function hourFreshnessOf(
  modelRunUtc: string | null,
  fetchedUtc: string | null,
  cfg: HourFreshnessConfig,
  now: Date = new Date(),
): Freshness {
  const runAge = ageHours(modelRunUtc, now);
  const fetchAge = ageHours(fetchedUtc, now);
  if (runAge === null || fetchAge === null) return "unavailable";
  const ageH = Math.max(runAge, fetchAge);
  if (ageH <= cfg.fresh_max_hours) return "fresh";
  if (ageH <= cfg.aging_max_hours) return "aging";
  return "stale";
}
