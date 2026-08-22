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
