import { describe, expect, it } from "vitest";

import { dataUrl } from "../src/paths";

describe("dataUrl", () => {
  it("keeps root-relative paths at a root base", () => {
    expect(dataUrl("config.json", "/")).toBe("/config.json");
    expect(dataUrl("/config.json", "/")).toBe("/config.json");
  });

  it("prefixes a project-site base", () => {
    expect(dataUrl("config.json", "/dark-sky-shot-planner/")).toBe(
      "/dark-sky-shot-planner/config.json",
    );
    expect(dataUrl("/padus/padus.pmtiles", "/dark-sky-shot-planner/")).toBe(
      "/dark-sky-shot-planner/padus/padus.pmtiles",
    );
  });

  it("tolerates a base without a trailing slash", () => {
    expect(dataUrl("light_pollution/manifest.json", "/dark-sky-shot-planner")).toBe(
      "/dark-sky-shot-planner/light_pollution/manifest.json",
    );
  });

  it("defaults to Vite's BASE_URL", () => {
    // vitest runs with base "/" — the same value `npm run dev` sees.
    expect(dataUrl("config.json")).toBe("/config.json");
  });
});
