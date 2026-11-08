import { defineConfig } from "@playwright/test";

const baseURL = process.env.PLAYWRIGHT_BASE_URL;
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;

export default defineConfig({
  testDir: "e2e",
  timeout: 30_000,
  use: {
    baseURL: baseURL ?? "http://localhost:5199",
    browserName: "chromium",
    ...(executablePath ? { launchOptions: { executablePath } } : {}),
  },
  webServer: baseURL ? undefined : {
    command: "npx vite --port 5199",
    port: 5199,
    reuseExistingServer: true,
    root: ".",
  },
});
