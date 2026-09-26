import type { FetchLike } from "./types.ts";

export const USER_AGENT =
  "dark-sky-shot-planner-worker (+https://github.com/buschbrian/dark-sky-shot-planner)";

/** Reasons never include the request URL, so a keyed URL cannot leak into a response. */
export class UpstreamError extends Error {}

export async function getText(
  fetch: FetchLike,
  url: string,
  timeoutMs = 8000,
): Promise<{ status: number; text: string }> {
  let res: Response;
  try {
    res = await fetch(url, {
      headers: { "user-agent": USER_AGENT, accept: "application/json" },
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    if (err instanceof UpstreamError) throw err;
    const name = err instanceof Error ? err.name : "";
    throw new UpstreamError(name === "TimeoutError" ? "timeout" : "network error");
  }
  return { status: res.status, text: await res.text() };
}

export async function getJson(fetch: FetchLike, url: string, timeoutMs?: number): Promise<unknown> {
  const { status, text } = await getText(fetch, url, timeoutMs);
  if (status < 200 || status >= 300) throw new UpstreamError(`HTTP ${status}`);
  return parseJson(text);
}

export function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new UpstreamError("invalid JSON");
  }
}

/** ArcGIS REST answers errors with HTTP 200 and an `error` object. */
export function assertNoArcgisError(body: unknown): void {
  if (isRecord(body) && isRecord(body.error)) {
    const code = typeof body.error.code === "number" ? ` ${body.error.code}` : "";
    throw new UpstreamError(`ArcGIS error${code}`);
  }
}

export const isRecord = (x: unknown): x is Record<string, unknown> =>
  typeof x === "object" && x !== null && !Array.isArray(x);

export const num = (x: unknown): number | null => {
  if (typeof x === "number" && Number.isFinite(x)) return x;
  if (typeof x === "string" && x.trim() !== "" && Number.isFinite(Number(x))) return Number(x);
  return null;
};

/** Caps upstream calls for one incoming request; the structural maximum today is 15. */
export function budgetedFetch(fetch: FetchLike, max: number): FetchLike {
  let used = 0;
  return (input, init) => {
    used += 1;
    if (used > max) return Promise.reject(new UpstreamError("per-request upstream budget spent"));
    return fetch(input, init);
  };
}
