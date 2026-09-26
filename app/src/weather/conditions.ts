/**
 * Optional client for the conditions Worker (ADR-0010). Opt-in only: the
 * build-time `VITE_WORKER_URL` env var selects it; unset, callers should stay
 * on the direct Open-Meteo path in `weather/openmeteo.ts` and behaviour is
 * exactly as before this module existed.
 *
 * Precise coordinates never leave the browser: `roundToGrid` rounds to the
 * Worker's 0.05° grid (same constant as `worker/src/params.ts`, duplicated
 * here rather than imported — the web app and the Worker are separate
 * deploy units) before any request is built.
 *
 * The response shape is the Worker's `Field`/`Series` contract
 * (`worker/src/types.ts`, `shared/golden/conditions-response.json`). This
 * client reads only the fields it knows about and ignores unknown keys, so
 * additions such as `next_run_expected_utc`, an ETag, or a denser series
 * (e.g. 15-minute HRRR) never break parsing.
 */

export const WORKER_GRID_DEG = 0.05;

export type FieldStatus = "ok" | "unavailable";

export interface ConditionsPoint {
  t: string;
  v: number | null;
}

export interface ConditionsSeries {
  model: string;
  upstream_model?: string;
  model_run_utc: string | null;
  fetched_utc: string | null;
  status: FieldStatus;
  reason?: string;
  last_good_utc?: string | null;
  values: ConditionsPoint[];
}

export interface ConditionsField {
  unit: string;
  source: string;
  status: FieldStatus;
  fetched_utc: string | null;
  series: ConditionsSeries[];
  reason?: string;
  last_good_utc?: string | null;
}

export interface ConditionsResponse {
  cell: { lat: number; lon: number; rounding_deg: number };
  window: { start_utc: string; end_utc: string };
  generated_utc: string;
  /** Indexed by field name (e.g. "cloud_cover_total"); unknown fields pass through untouched. */
  fields: Record<string, ConditionsField>;
  attribution?: string[];
}

/** Round a coordinate to the Worker's 0.05° grid. Precise coordinates never leave the browser. */
export function roundToGrid(value: number, step: number = WORKER_GRID_DEG): number {
  const steps = Math.round(value / step);
  return Number((steps * step).toFixed(2));
}

/** The base Worker URL, or null when the feature is not opted into at build time. */
export function workerBaseUrl(): string | null {
  const raw = import.meta.env.VITE_WORKER_URL;
  if (!raw || typeof raw !== "string" || raw.trim() === "") return null;
  return raw.replace(/\/+$/, "");
}

/**
 * Build the `/v1/conditions` request URL for a rounded cell and UTC window.
 * `start`/`end` must already carry a UTC offset once serialized (toISOString
 * always ends in "Z"), matching the Worker's request rules
 * (`docs/ios/PLAN.md` §Worker "Request rules"): coordinates already on the
 * grid, `start`/`end` with a UTC offset, window at most 48 h.
 */
export function buildConditionsUrl(
  base: string,
  lat: number,
  lon: number,
  startUtc: Date,
  endUtc: Date,
): string {
  const params = new URLSearchParams({
    lat: roundToGrid(lat).toFixed(2),
    lon: roundToGrid(lon).toFixed(2),
    start: startUtc.toISOString(),
    end: endUtc.toISOString(),
  });
  return `${base}/v1/conditions?${params.toString()}`;
}

const DEFAULT_TIMEOUT_MS = 6000;

export class ConditionsFetchError extends Error {}

/**
 * Fetch conditions from the Worker. Throws `ConditionsFetchError` on any
 * failure (network error, non-2xx, timeout, or a body that isn't the shape
 * we need) so callers can fall back to the direct Open-Meteo path.
 */
export async function fetchConditions(
  lat: number,
  lon: number,
  startUtc: Date,
  endUtc: Date,
  opts: { base?: string; timeoutMs?: number; fetchImpl?: typeof fetch } = {},
): Promise<ConditionsResponse> {
  const base = opts.base ?? workerBaseUrl();
  if (!base) throw new ConditionsFetchError("worker not configured");
  const doFetch = opts.fetchImpl ?? fetch;
  const url = buildConditionsUrl(base, lat, lon, startUtc, endUtc);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), opts.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  let res: Response;
  try {
    res = await doFetch(url, { signal: controller.signal });
  } catch (err) {
    throw new ConditionsFetchError(`worker unreachable: ${String(err)}`);
  } finally {
    clearTimeout(timeout);
  }
  if (!res.ok) throw new ConditionsFetchError(`worker responded ${res.status}`);
  let body: unknown;
  try {
    body = await res.json();
  } catch (err) {
    throw new ConditionsFetchError(`worker response was not JSON: ${String(err)}`);
  }
  if (!isConditionsResponse(body)) {
    throw new ConditionsFetchError("worker response missing required shape");
  }
  return body;
}

/** Narrow, tolerant shape check: only what this client depends on, nothing more. */
function isConditionsResponse(body: unknown): body is ConditionsResponse {
  if (typeof body !== "object" || body === null) return false;
  const b = body as Record<string, unknown>;
  if (typeof b.fields !== "object" || b.fields === null) return false;
  if (typeof b.cell !== "object" || b.cell === null) return false;
  return true;
}

/** One row per model for a cloud-cover-shaped field: the disagreement, never averaged away. */
export interface ModelCloudRow {
  model: string;
  status: FieldStatus;
  reason: string | null;
  modelRunUtc: string | null;
  /** Average over the values, when any are present and numeric; null otherwise. */
  meanPct: number | null;
}

/**
 * Summarize one field's per-model series into rows for display. Never
 * averages across models — only within a single model's own series, which
 * is what "one line per model" (the brief) needs to show a single number.
 * A model with `status: "unavailable"` gets `meanPct: null`, rendered as the
 * word "unavailable", never 0 (ADR-0006).
 */
export function summarizeFieldByModel(field: ConditionsField | undefined): ModelCloudRow[] {
  if (!field) return [];
  return field.series.map((s) => {
    if (s.status === "unavailable") {
      return {
        model: s.model,
        status: "unavailable",
        reason: s.reason ?? null,
        modelRunUtc: s.model_run_utc,
        meanPct: null,
      };
    }
    const nums = s.values.map((p) => p.v).filter((v): v is number => v !== null && Number.isFinite(v));
    const meanPct = nums.length ? Math.round(nums.reduce((a, v) => a + v, 0) / nums.length) : null;
    return {
      model: s.model,
      status: "ok",
      reason: null,
      modelRunUtc: s.model_run_utc,
      meanPct,
    };
  });
}
