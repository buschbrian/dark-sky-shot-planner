import { describe, expect, it } from "vitest";

import { averageCloudCover, type CloudForecast } from "../src/weather/openmeteo";
import { classifyRadiance, sampleRadiance, type LowResGrid } from "../src/radiance";
import type { AppConfigJson } from "../src/config";

const grid: LowResGrid = {
  step_deg: 1,
  west: -112,
  south: 38,
  east: -110,
  north: 40,
  rows: [
    [80, 40, 0],
    [60, 30, 5],
    [20, 10, 2],
  ],
};

describe("sampleRadiance", () => {
  it("returns null outside the grid", () => {
    expect(sampleRadiance(grid, 41, -111)).toBeNull();
    expect(sampleRadiance(grid, 39, -113)).toBeNull();
  });

  it("samples the nearest cell", () => {
    expect(sampleRadiance(grid, 39.9, -111.9)).toBe(80);
    expect(sampleRadiance(grid, 38.1, -110.1)).toBe(2);
  });
});

const config = {
  radiance_mapping: {
    source: "x",
    source_year: 2024,
    unit: "nW",
    breakpoints: [
      { radiance: 0, color: "#000", label: "Pristine" },
      { radiance: 5, color: "#333", label: "Dark" },
      { radiance: 50, color: "#666", label: "Bright" },
    ],
  },
} as unknown as AppConfigJson;

describe("classifyRadiance", () => {
  it("uses the same breakpoints as the legend", () => {
    expect(classifyRadiance(0, config)).toBe("Pristine");
    expect(classifyRadiance(4.99, config)).toBe("Pristine");
    expect(classifyRadiance(5, config)).toBe("Dark");
    expect(classifyRadiance(1000, config)).toBe("Bright");
  });
});

describe("averageCloudCover", () => {
  const forecast: CloudForecast = {
    attribution: "test",
    hourly: [
      { timeUtc: "2026-08-22T03:00:00", cloudCover: 10 },
      { timeUtc: "2026-08-22T04:00:00", cloudCover: 30 },
      { timeUtc: "2026-08-22T05:00:00", cloudCover: 50 },
      { timeUtc: "2026-08-23T04:00:00", cloudCover: 90 },
    ],
  };

  it("averages only hours inside the window", () => {
    const avg = averageCloudCover(
      forecast,
      new Date("2026-08-22T02:30:00Z"),
      new Date("2026-08-22T05:30:00Z"),
    );
    expect(avg).toBe(30);
  });

  it("returns null when data does not cover the window", () => {
    expect(
      averageCloudCover(forecast, new Date("2027-01-01T00:00:00Z"), new Date("2027-01-01T02:00:00Z")),
    ).toBeNull();
  });
});
