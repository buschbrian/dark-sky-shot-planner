import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  buildConditionsUrl,
  ConditionsFetchError,
  fetchConditions,
  roundToGrid,
  summarizeFieldByModel,
  workerBaseUrl,
  type ConditionsResponse,
} from "../src/weather/conditions";

const golden: ConditionsResponse = JSON.parse(
  readFileSync(resolve(__dirname, "../../shared/golden/conditions-response.json"), "utf8"),
);

describe("roundToGrid", () => {
  it("rounds to the Worker's 0.05° grid", () => {
    expect(roundToGrid(38.37)).toBeCloseTo(38.35, 5);
    expect(roundToGrid(38.38)).toBeCloseTo(38.4, 5);
    expect(roundToGrid(-109.973)).toBeCloseTo(-109.95, 5);
  });

  it("leaves an already-rounded coordinate unchanged", () => {
    expect(roundToGrid(38.35)).toBeCloseTo(38.35, 5);
    expect(roundToGrid(-109.95)).toBeCloseTo(-109.95, 5);
  });
});

describe("buildConditionsUrl", () => {
  it("builds a request with a rounded cell and a UTC-offset window", () => {
    const url = buildConditionsUrl(
      "https://conditions.example.workers.dev",
      38.37,
      -109.973,
      new Date("2026-09-26T00:00:00Z"),
      new Date("2026-09-26T14:00:00Z"),
    );
    const parsed = new URL(url);
    expect(parsed.pathname).toBe("/v1/conditions");
    expect(parsed.searchParams.get("lat")).toBe("38.35");
    expect(parsed.searchParams.get("lon")).toBe("-109.95");
    // toISOString() always ends in "Z" — a UTC offset, satisfying the Worker's request rule.
    expect(parsed.searchParams.get("start")).toMatch(/Z$/);
    expect(parsed.searchParams.get("end")).toMatch(/Z$/);
  });

  it("never leaks a precise coordinate into the request", () => {
    const url = buildConditionsUrl(
      "https://conditions.example.workers.dev",
      38.351234,
      -109.949876,
      new Date("2026-09-26T00:00:00Z"),
      new Date("2026-09-26T14:00:00Z"),
    );
    expect(url).not.toContain("38.351234");
    expect(url).not.toContain("109.949876");
  });
});

describe("workerBaseUrl", () => {
  it("is null when VITE_WORKER_URL is unset (default, opt-in feature)", () => {
    // import.meta.env.VITE_WORKER_URL is unset in the test environment (no .env.* provides it),
    // matching production behaviour when the build-time var is not set.
    expect(workerBaseUrl()).toBeNull();
  });
});

describe("summarizeFieldByModel against the golden fixture", () => {
  it("produces one row per model with a mean, never averaging across models", () => {
    const rows = summarizeFieldByModel(golden.fields.cloud_cover_total);
    expect(rows.map((r) => r.model)).toEqual(["hrrr", "gfs", "icon", "ecmwf"]);
    for (const row of rows) {
      expect(row.status).toBe("ok");
      expect(row.meanPct).not.toBeNull();
      expect(row.modelRunUtc).toMatch(/Z$/);
    }
    // Models disagree in the fixture; summarizing must not collapse that into one number.
    const means = new Set(rows.map((r) => r.meanPct));
    expect(means.size).toBeGreaterThan(1);
  });

  it("marks an unavailable model's series as unavailable, never 0", () => {
    const rows = summarizeFieldByModel(golden.fields.visibility);
    const icon = rows.find((r) => r.model === "icon");
    const ecmwf = rows.find((r) => r.model === "ecmwf");
    expect(icon?.status).toBe("unavailable");
    expect(icon?.meanPct).toBeNull();
    expect(icon?.reason).toBeTruthy();
    expect(ecmwf?.status).toBe("unavailable");
    expect(ecmwf?.meanPct).toBeNull();
    // hrrr and gfs do publish visibility in the fixture.
    const hrrr = rows.find((r) => r.model === "hrrr");
    expect(hrrr?.status).toBe("ok");
    expect(hrrr?.meanPct).not.toBeNull();
  });

  it("returns no rows for a missing field rather than throwing", () => {
    expect(summarizeFieldByModel(undefined)).toEqual([]);
  });
});

describe("fetchConditions", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("throws ConditionsFetchError when no base is configured (opt-out default)", async () => {
    await expect(
      fetchConditions(38.35, -109.95, new Date("2026-09-26T00:00:00Z"), new Date("2026-09-26T14:00:00Z"), {
        base: undefined,
        fetchImpl: vi.fn(),
      }),
    ).rejects.toBeInstanceOf(ConditionsFetchError);
  });

  it("resolves with the parsed golden fixture on success (no real network)", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify(golden), { status: 200 }));
    const result = await fetchConditions(
      38.35,
      -109.95,
      new Date("2026-09-26T00:00:00Z"),
      new Date("2026-09-26T14:00:00Z"),
      { base: "https://conditions.example.workers.dev", fetchImpl: fetchImpl as unknown as typeof fetch },
    );
    expect(result.cell.lat).toBe(38.35);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("tolerates unknown extra fields in the response (forward compatibility)", async () => {
    const withExtras = {
      ...golden,
      next_run_expected_utc: "2026-09-26T06:00:00Z",
      etag: "W/\"abc123\"",
      fields: {
        ...golden.fields,
        cloud_cover_total: {
          ...golden.fields.cloud_cover_total,
          some_future_field: "ignored",
        },
      },
    };
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify(withExtras), { status: 200 }));
    const result = await fetchConditions(
      38.35,
      -109.95,
      new Date("2026-09-26T00:00:00Z"),
      new Date("2026-09-26T14:00:00Z"),
      { base: "https://conditions.example.workers.dev", fetchImpl: fetchImpl as unknown as typeof fetch },
    );
    expect(result.fields.cloud_cover_total?.status).toBe("ok");
    const rows = summarizeFieldByModel(result.fields.cloud_cover_total);
    expect(rows.length).toBeGreaterThan(0);
  });

  it("throws ConditionsFetchError on a non-2xx response (falls back)", async () => {
    const fetchImpl = vi.fn(async () => new Response("nope", { status: 503 }));
    await expect(
      fetchConditions(
        38.35,
        -109.95,
        new Date("2026-09-26T00:00:00Z"),
        new Date("2026-09-26T14:00:00Z"),
        { base: "https://conditions.example.workers.dev", fetchImpl: fetchImpl as unknown as typeof fetch },
      ),
    ).rejects.toBeInstanceOf(ConditionsFetchError);
  });

  it("throws ConditionsFetchError on a network failure (falls back)", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("network down");
    });
    await expect(
      fetchConditions(
        38.35,
        -109.95,
        new Date("2026-09-26T00:00:00Z"),
        new Date("2026-09-26T14:00:00Z"),
        { base: "https://conditions.example.workers.dev", fetchImpl: fetchImpl as unknown as typeof fetch },
      ),
    ).rejects.toBeInstanceOf(ConditionsFetchError);
  });

  it("throws ConditionsFetchError on a malformed body (falls back)", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ nope: true }), { status: 200 }));
    await expect(
      fetchConditions(
        38.35,
        -109.95,
        new Date("2026-09-26T00:00:00Z"),
        new Date("2026-09-26T14:00:00Z"),
        { base: "https://conditions.example.workers.dev", fetchImpl: fetchImpl as unknown as typeof fetch },
      ),
    ).rejects.toBeInstanceOf(ConditionsFetchError);
  });
});

describe("main.ts wires the Worker path with a fallback, opt-in by config", () => {
  it("gates the Worker call on VITE_WORKER_URL and never on a code branch alone", () => {
    const main = readFileSync(resolve(__dirname, "../src/main.ts"), "utf8");
    expect(main).toContain("workerBaseUrl()");
    expect(main).toContain("fetchConditionsAndRender");
    expect(main).toContain("renderConditionsFallback");
  });
});
