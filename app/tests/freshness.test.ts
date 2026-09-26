import { describe, expect, it } from "vitest";

import { ageHours, freshnessOf, FRESHNESS_LABEL, hourFreshnessOf } from "../src/freshness";
import type { HourFreshnessConfig, LayerFreshnessConfig } from "../src/freshness";

const cfg: LayerFreshnessConfig = {
  layer_id: "test",
  fresh_max_days: 400,
  aging_max_days: 550,
  stale_max_days: 800,
};

describe("freshness", () => {
  const today = new Date("2026-08-22T00:00:00Z");

  it("classifies fresh/aging/stale uniformly with pipeline logic", () => {
    expect(freshnessOf("2026-01-01", cfg, today)).toBe("fresh"); // ~233 days
    expect(freshnessOf("2025-03-01", cfg, today)).toBe("aging"); // ~539 days
    expect(freshnessOf("2024-06-01", cfg, today)).toBe("stale"); // ~812 days
    expect(freshnessOf(null, cfg, today)).toBe("unavailable");
    expect(freshnessOf("garbage", cfg, today)).toBe("unavailable");
  });

  it("labels match the documented convention", () => {
    expect(FRESHNESS_LABEL.stale).toContain("verify");
    expect(FRESHNESS_LABEL.unavailable).toBe("unavailable");
  });
});

describe("hour-scale freshness for live conditions (PLAN.md §Verdict)", () => {
  const now = new Date("2026-09-26T00:00:00Z");
  const cfg: HourFreshnessConfig = {
    layer_id: "weather_forecast",
    fresh_max_hours: 12,
    aging_max_hours: 24,
    stale_max_hours: 48,
  };

  it("computes whole-hour age", () => {
    expect(ageHours("2026-09-25T22:00:00Z", now)).toBe(2);
    expect(ageHours("2026-09-25T00:00:00Z", now)).toBe(24);
    expect(ageHours(null, now)).toBeNull();
    expect(ageHours("garbage", now)).toBeNull();
  });

  it("uses the older of model_run_utc and fetched_utc", () => {
    // run 2h old, fetched just now: age is 2h (older of the two by hours, not by exact ms).
    expect(hourFreshnessOf("2026-09-25T22:00:00Z", "2026-09-26T00:00:00Z", cfg, now)).toBe("fresh");
    // run 30h old (stale) even though fetched a moment ago.
    expect(hourFreshnessOf("2026-09-24T18:00:00Z", "2026-09-26T00:00:00Z", cfg, now)).toBe("stale");
  });

  it("is unavailable, never a guess, when either timestamp is missing", () => {
    expect(hourFreshnessOf(null, "2026-09-26T00:00:00Z", cfg, now)).toBe("unavailable");
    expect(hourFreshnessOf("2026-09-25T22:00:00Z", null, cfg, now)).toBe("unavailable");
  });

  it("classifies fresh/aging/stale at the configured boundaries", () => {
    const at = (h: number) => new Date(now.getTime() - h * 3_600_000).toISOString();
    expect(hourFreshnessOf(at(12), at(0), cfg, now)).toBe("fresh");
    expect(hourFreshnessOf(at(13), at(0), cfg, now)).toBe("aging");
    expect(hourFreshnessOf(at(24), at(0), cfg, now)).toBe("aging");
    expect(hourFreshnessOf(at(25), at(0), cfg, now)).toBe("stale");
  });
});
