import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import type { DataStatusJson } from "../src/config";
import { dataNoticeText, injectDataNotice } from "../src/datanotice";

const status = (layers: DataStatusJson["layers"]): DataStatusJson => ({
  built_utc: "2026-09-29T00:00:00Z",
  layers,
});

const TAIL =
  "an offline fixture, not real coverage. Darkness, moon, and Galactic Center times are computed " +
  "in your browser and are unaffected. See docs/credentials-setup.md to enable the real layers.";

describe("dataNoticeText", () => {
  it("names both fixture layers in data-status order (the default fixture build)", () => {
    expect(
      dataNoticeText(
        status({ light_pollution: "fixture", land_ownership: "fixture", darksky_places: "real" }),
      ),
    ).toBe(`Sample data: the light pollution and land ownership map layers are ${TAIL}`);
  });

  it("uses the singular for one fixture layer", () => {
    expect(
      dataNoticeText(
        status({ light_pollution: "real", land_ownership: "fixture", darksky_places: "real" }),
      ),
    ).toBe(`Sample data: the land ownership map layer is ${TAIL}`);
  });

  it("says nothing when every layer is real or the status is unknown", () => {
    expect(
      dataNoticeText(
        status({ light_pollution: "real", land_ownership: "real", darksky_places: "real" }),
      ),
    ).toBeNull();
    expect(dataNoticeText(null)).toBeNull();
    expect(dataNoticeText(undefined)).toBeNull();
  });
});

describe("injectDataNotice", () => {
  const indexHtml = readFileSync(new URL("../index.html", import.meta.url), "utf8");

  it("fills and reveals the placeholder in app/index.html", () => {
    const text = dataNoticeText(status({ light_pollution: "fixture" }))!;
    const out = injectDataNotice(indexHtml, text);
    expect(out).toContain(`<p id="data-notice" class="notice">${text}</p>`);
    expect(out).not.toMatch(/id="data-notice"[^>]*hidden/);
  });

  it("leaves the hidden placeholder alone when there is nothing to say", () => {
    expect(injectDataNotice(indexHtml, null)).toBe(indexHtml);
  });

  it("escapes markup in the text", () => {
    const html = '<p id="data-notice" class="notice" hidden></p>';
    expect(injectDataNotice(html, 'a<b>&"c"')).toBe(
      '<p id="data-notice" class="notice">a&lt;b&gt;&amp;&quot;c&quot;</p>',
    );
  });
});
