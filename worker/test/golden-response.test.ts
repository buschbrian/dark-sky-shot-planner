/**
 * Contract fixtures for clients: real Worker responses built offline from the recorded
 * upstream fixtures, written to `shared/golden/` and decoded by SkyCore's tests.
 *   UPDATE_GOLDEN=1 npx vitest run test/golden-response.test.ts
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { Env } from "../src/types.ts";
import { fixtureFetch, get, type Json, makeDeps, memoryKv, Q } from "./helpers.ts";

const GOLDEN = join(import.meta.dirname, "../../shared/golden");
// Exercises the AirNow happy path with the synthetic fixture rows; the key is never echoed.
const KEY = "test-only-not-a-real-key";
const ENV: Env = { AIRNOW_API_KEY: KEY };

const CASES: { file: string; path: string; env: Env }[] = [
  { file: "conditions-response.json", path: `/v1/conditions?${Q}`, env: ENV },
  {
    file: "space-weather-response.json",
    path: "/v1/space-weather?lat=38.35&lon=-109.95",
    env: { SPACE_WEATHER: memoryKv() },
  },
];

describe("golden Worker responses", () => {
  it.each(CASES)("$file matches the Worker's current output", async ({ file, path, env }) => {
    const res = await get(path, makeDeps(fixtureFetch().fetch), env);
    expect(res.status).toBe(200);
    const target = join(GOLDEN, file);
    if (process.env.UPDATE_GOLDEN) writeFileSync(target, `${JSON.stringify(res.body, null, 2)}\n`);
    const committed: Json = JSON.parse(readFileSync(target, "utf8"));
    expect(committed).toEqual(res.body);
  });

  it("the conditions contract carries every provenance key and some unavailable series", () => {
    const body: Json = JSON.parse(readFileSync(join(GOLDEN, "conditions-response.json"), "utf8"));
    const series = Object.values(body.fields).flatMap((f: Json) => f.series);
    for (const s of series) {
      expect(Object.keys(s)).toEqual(
        expect.arrayContaining(["model", "model_run_utc", "fetched_utc", "status", "values"]),
      );
    }
    expect(series.some((s: Json) => s.status === "unavailable" && s.reason)).toBe(true);
    expect(body.fields.aqi_observed.observations.length).toBeGreaterThan(0);
  });
});
