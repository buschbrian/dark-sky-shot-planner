import { expect, test } from "@playwright/test";

test.describe("MapLibre runtime", () => {
  test("loads its worker and both PMTiles sources", async ({ page, baseURL }, testInfo) => {
    const errors: string[] = [];
    const workers: string[] = [];
    const tiles = new Set<string>();
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });
    page.on("worker", (worker) => workers.push(worker.url()));
    page.on("response", (response) => {
      const path = new URL(response.url()).pathname;
      if (path.endsWith(".pmtiles") && response.ok()) tiles.add(path);
    });
    await page.route("https://api.open-meteo.com/**", (route) =>
      route.fulfill({ json: { hourly: { time: [], cloud_cover: [] } } }),
    );
    await page.goto("./#lat=40.687&lon=-111.824&date=2026-08-22&layers=lp,land,places");
    await page.locator("#map").scrollIntoViewIfNeeded();
    await expect(page.locator("#map canvas")).toBeVisible({ timeout: 15_000 });
    await expect.poll(() => tiles.size).toBe(2);
    await expect.poll(() => workers.length).toBeGreaterThan(0);
    await page.waitForLoadState("networkidle");
    const prefix = new URL(baseURL!).pathname;
    expect([...tiles].every((path) => path.startsWith(prefix))).toBe(true);
    expect(workers.every((url) => new URL(url).pathname.startsWith(prefix))).toBe(true);
    expect(errors).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath("map-runtime.png"), fullPage: true });
  });

  test("keeps the text answer usable without WebGL", async ({ page }) => {
    await page.addInitScript(() => {
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (...args) {
        if (args[0] === "webgl" || args[0] === "webgl2") {
          document.documentElement.dataset.webglDenied = "true";
          return null;
        }
        return getContext.apply(this, args);
      } as typeof getContext;
    });
    await page.goto("./#lat=38.53&lon=-109.90&date=2026-08-22");
    await page.locator("#map").scrollIntoViewIfNeeded();
    await expect(page.locator("html")).toHaveAttribute("data-webgl-denied", "true");
    await expect(page.locator("#answer")).toContainText(/moon-free darkness/i);
    await expect(page.locator("#date-input")).toHaveValue("2026-08-22");
    await page.fill("#date-input", "2026-08-23");
    await page.click("#coord-apply");
    await expect(page.locator("#location-status")).toContainText("2026-08-23");
    await expect(page.locator("#answer")).toContainText(/moon-free darkness/i);
  });
});
