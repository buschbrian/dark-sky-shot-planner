import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";
import { fixtureName } from "../scripts/fixture-names.ts";
import { manifest } from "./helpers.ts";

const DIR = join(import.meta.dirname, "fixtures");
const files = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? files(join(dir, e.name)) : [join(dir, e.name)],
  );

describe("fixtures", () => {
  it("contain no credentials", () => {
    const patterns = [
      /API_KEY=(?!REDACTED)[^&"\s]+/i,
      /api[_-]?key"\s*:\s*"[^"]+"/i,
      /bearer\s+[a-z0-9._-]{12,}/i,
      /\b[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\b/,
      /token=|secret=|password=/i,
    ];
    for (const f of files(DIR)) {
      const text = readFileSync(f, "utf8");
      for (const p of patterns)
        expect(p.test(text), `${relative(DIR, f)} matches ${p}`).toBe(false);
    }
  });

  it("mark every synthetic file as synthetic", () => {
    for (const f of files(join(DIR, "synthetic"))) {
      expect(f).toMatch(/\.synthetic\.json$/);
      expect(JSON.parse(readFileSync(f, "utf8")).synthetic).toBe(true);
    }
    for (const f of files(join(DIR, "down"))) {
      const fx = JSON.parse(readFileSync(f, "utf8"));
      expect(fx.synthetic === true || /real/.test(fx.note ?? ""), relative(DIR, f)).toBe(true);
    }
  });

  it("cover every recorded upstream the manifest lists", () => {
    for (const [name, meta] of Object.entries(manifest.files)) {
      expect(fixtureName(meta.url)).toBe(name);
      expect(readdirSync(join(DIR, "recorded"))).toContain(`${name}.json`);
    }
  });
});
