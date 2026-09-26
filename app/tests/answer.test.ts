import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { gcUsability } from "../src/ui/answer";

describe("GC usability against the config threshold", () => {
  it("judges against the configured threshold", () => {
    expect(gcUsability(22.6, 12)).toBe("usable (threshold 12°)");
    expect(gcUsability(11.9, 12)).toBe("below the 12° useful-photography threshold");
    expect(gcUsability(null, 12)).toBe("below the 12° useful-photography threshold");
  });

  it("says unavailable, never usable, when config.json is missing", () => {
    for (const peak of [45, 12, 3, null]) {
      const text = gcUsability(peak, null);
      expect(text).toContain("unavailable");
      expect(text).not.toMatch(/usable \(|below the|\d+°/);
    }
  });

  it("main.ts passes the config value through with no numeric fallback", () => {
    const main = readFileSync(resolve(__dirname, "../src/main.ts"), "utf8");
    expect(main).toContain("gc_min_useful_altitude_deg ?? null");
    expect(main).not.toMatch(/gc_min_useful_altitude_deg\s*\?\?\s*\d/);
  });
});
