import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";
import { dataNoticeText, injectDataNotice } from "./app/src/datanotice";
import type { DataStatusJson } from "./app/src/config";

// Public path the site is served from. GitHub Pages hosts a project site under
// "/<repo>/", so the deploy workflow sets BASE_PATH="/dark-sky-shot-planner/".
// Locally it stays "/" and `npm run dev` is unchanged. Every data fetch in the
// client goes through app/src/paths.ts, which reads this back as
// import.meta.env.BASE_URL — nothing else may hardcode a leading "/".
const base = process.env.BASE_PATH ?? "/";

const DATA_STATUS = fileURLToPath(new URL("./data/out/data-status.json", import.meta.url));

/**
 * Bake the "sample data" notice into index.html from data/out/data-status.json
 * (written by scripts/build-data.sh before every build). Revealed at runtime
 * only after five fetches, the notice pushed <main> down (layout shift) and
 * became the late LCP element. main.ts still renders it from the fetched
 * status with the same wording (app/src/datanotice.ts), so nothing moves.
 * With no data-status.json the placeholder stays hidden, as before.
 */
function staticDataNotice(): Plugin {
  return {
    name: "static-data-notice",
    transformIndexHtml(html) {
      if (!existsSync(DATA_STATUS)) return html;
      let status: DataStatusJson;
      try {
        status = JSON.parse(readFileSync(DATA_STATUS, "utf8")) as DataStatusJson;
      } catch {
        return html;
      }
      return injectDataNotice(html, dataNoticeText(status));
    },
  };
}

export default defineConfig({
  root: "app",
  base,
  publicDir: "../data/out",
  plugins: [staticDataNotice()],
  build: {
    outDir: "../dist",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
  },
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
});
