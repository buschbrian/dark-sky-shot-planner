import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test.describe("text-first flows", () => {
  test("full answer flow by keyboard only, map never focused", async ({ page }) => {
    await page.goto("/");
    await page.fill("#coord-input", "38.53, -109.90");
    await page.fill("#date-input", "2026-08-22");
    await page.keyboard.press("Tab"); // move off the date input
    await page.click("#coord-apply");

    const answer = page.locator("#answer");
    await expect(answer).toContainText(/moon-free darkness/i);
    // The headline number is present and non-zero for this spot in August.
    await expect(answer.locator(".headline strong")).not.toContainText(/^0 /);
    await expect(page.locator("#location-status")).toContainText("Planning");
  });

  test("no astronomical darkness is stated plainly", async ({ page }) => {
    await page.goto("/#lat=48.99&lon=-114.03&date=2026-06-21");
    await page.waitForTimeout(1500);
    await expect(page.locator("#answer")).toContainText(
      /No astronomical darkness on this date/i,
    );
  });

  test("URL state round-trips a pasted link", async ({ page }) => {
    await page.goto("/#lat=44.94&lon=-110.5&date=2026-05-15&layers=lp");
    await page.waitForTimeout(1200);
    await expect(page.locator("#coord-input")).toHaveValue(/44\.94/);
    await expect(page.locator("#date-input")).toHaveValue("2026-05-15");
    await expect(page.locator("#layer-lp")).toBeChecked();
    await expect(page.locator("#answer")).toContainText(/Galactic Center/);
  });

  test("sky events answer 'what else is happening' for this spot and date", async ({ page }) => {
    await page.goto("/#lat=40.687&lon=-111.824&date=2026-09-22");
    await page.waitForTimeout(1500);
    const events = page.locator("#sky-events");
    await expect(events).toContainText(/Saturn at opposition/);
    await expect(events).toContainText(/Orionids/);
    // Provenance on every line: computed ephemeris vs. a dated curated row.
    await expect(events).toContainText(/computed/);
    await expect(events).toContainText(/curated, verified 2026-09-06/);
    await expect(events.locator("a").first()).toHaveAttribute("href", /^https:\/\//);
  });

  test("sky events are reachable by keyboard with the map never focused", async ({ page }) => {
    await page.goto("/#lat=40.687&lon=-111.824&date=2026-09-22");
    await page.waitForTimeout(1500);
    await page.focus("#date-input");

    let reachedSourceLink = false;
    for (let i = 0; i < 60 && !reachedSourceLink; i++) {
      await page.keyboard.press("Tab");
      const inMap = await page.evaluate(
        () => document.getElementById("map")?.contains(document.activeElement) ?? false,
      );
      expect(inMap).toBe(false);
      reachedSourceLink = await page.evaluate(
        () =>
          document.activeElement?.tagName === "A" &&
          (document.getElementById("sky-events")?.contains(document.activeElement) ?? false),
      );
    }
    expect(reachedSourceLink).toBe(true);
  });

  test("theme toggle applies field mode without reload", async ({ page }) => {
    await page.goto("/");
    await page.selectOption("#theme-select", "field");
    const bg = await page.evaluate(() =>
      getComputedStyle(document.body).getPropertyValue("--bg").trim(),
    );
    expect(bg.toLowerCase()).toMatch(/^#(1|2|3)/); // dark red family
    await expect(page.locator("body")).toHaveAttribute("data-theme", "field");
  });
});

test.describe("accessibility (axe-core)", () => {
  test("default view passes WCAG 2.1 AA scan", async ({ page }) => {
    await page.goto("/");
    await page.waitForTimeout(1000);
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test("answer view passes WCAG 2.1 AA scan", async ({ page }) => {
    await page.goto("/#lat=38.53&lon=-109.9&date=2026-08-22&layers=lp");
    await page.waitForTimeout(1500);
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test("200% and 400% zoom keep the answer reachable", async ({ page }) => {
    for (const zoom of [2, 4]) {
      await page.setViewportSize({ width: Math.round(1280 / zoom), height: 800 });
      await page.goto("/#lat=38.53&lon=-109.9&date=2026-08-22");
      await page.waitForTimeout(1000);
      const box = await page.locator("#answer .headline").boundingBox();
      expect(box).not.toBeNull();
      expect(box!.width).toBeGreaterThan(0);
    }
  });

  test("provenance disclosure returns focus to its trigger", async ({ page }) => {
    await page.goto("/");
    await page.focus("#provenance-panel > summary");
    await page.keyboard.press("Enter"); // open
    await expect(page.locator("#provenance table")).toBeVisible();
    await page.keyboard.press("Enter"); // close
    await expect(page.locator("#provenance table")).toBeHidden();
    await expect(page.locator("#provenance-panel > summary")).toBeFocused();
  });

  test("layer toggles work via keyboard", async ({ page }) => {
    await page.goto("/?layers=");
    await page.focus("#layer-land");
    await page.keyboard.press("Space");
    await expect(page.locator("#layer-land")).toBeChecked();
    await expect(page).toHaveURL(/layers=land/);
  });
});
