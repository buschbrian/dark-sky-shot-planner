import { defineConfig } from "vite";

// Public path the site is served from. GitHub Pages hosts a project site under
// "/<repo>/", so the deploy workflow sets BASE_PATH="/dark-sky-shot-planner/".
// Locally it stays "/" and `npm run dev` is unchanged. Every data fetch in the
// client goes through app/src/paths.ts, which reads this back as
// import.meta.env.BASE_URL — nothing else may hardcode a leading "/".
const base = process.env.BASE_PATH ?? "/";

export default defineConfig({
  root: "app",
  base,
  publicDir: "../data/out",
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
