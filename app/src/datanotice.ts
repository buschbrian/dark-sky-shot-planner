import type { DataStatusJson } from "./config";

/**
 * Wording of the "sample data" notice shown under the tagline when a deploy
 * serves offline fixtures for any map layer, or null when every layer is real
 * (or the status is unknown), in which case the notice stays hidden.
 *
 * Pure and DOM-free on purpose: vite.config.ts calls it at build time to bake
 * the notice into index.html (so it paints with the first frame and never
 * shifts the page), and main.ts calls it at runtime with the fetched
 * data-status.json. Both must produce identical text.
 */
export function dataNoticeText(status: DataStatusJson | null | undefined): string | null {
  const fixtures = Object.entries(status?.layers ?? {})
    .filter(([, origin]) => origin === "fixture")
    .map(([layerId]) => layerId.replace("_", " "));
  if (fixtures.length === 0) return null;
  return (
    `Sample data: the ${fixtures.join(" and ")} map layer${fixtures.length > 1 ? "s are" : " is"} ` +
    "an offline fixture, not real coverage. Darkness, moon, and Galactic Center times are computed " +
    "in your browser and are unaffected. See docs/credentials-setup.md to enable the real layers."
  );
}

/**
 * Rewrite the empty, hidden `<p id="data-notice">` placeholder in index.html
 * so it carries `text` and is visible. Returns the HTML unchanged when the
 * placeholder is not found or there is nothing to say.
 */
export function injectDataNotice(html: string, text: string | null): string {
  if (text === null) return html;
  const placeholder = /<p id="data-notice" class="notice" hidden><\/p>/;
  return html.replace(placeholder, `<p id="data-notice" class="notice">${escapeHtml(text)}</p>`);
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
