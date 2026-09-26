import { beforeEach } from "vitest";
import { resetMemoryHealth } from "../src/store.ts";

// Any code path that reaches the real network fails the test run.
globalThis.fetch = async () => {
  throw new Error("network access attempted in tests");
};

beforeEach(() => resetMemoryHealth());
