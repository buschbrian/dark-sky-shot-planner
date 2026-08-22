import { defineConfig } from "vite";

export default defineConfig({
  root: "app",
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
