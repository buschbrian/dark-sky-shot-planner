import { describe, expect, it } from "vitest";

import { freshnessOf, FRESHNESS_LABEL } from "../src/freshness";
import type { LayerFreshnessConfig } from "../src/freshness";

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
