import { assertNoArcgisError, getJson, isRecord, num, UpstreamError } from "../http.ts";
import { type Cell, cellKey, inWindow, type Window } from "../params.ts";
import { cachedLoad, edgeStore, type Loaded } from "../store.ts";
import { type Deps, type Field, iso, type Point, type Series } from "../types.ts";
import { assembleField } from "./openmeteo.ts";

export const NDGD_BASE = "https://mapservices.weather.noaa.gov/raster/rest/services/air_quality";
/** The NDGD smoke services carry RAP-Smoke (NWS SCN 22-42), not HRRR-Smoke. */
export const SMOKE_SOURCE = "NOAA RAP-Smoke via NWS NDGD";

export type SmokeLayer = "sfc" | "vert";

export interface Calibration {
  unit: string;
  factor: number;
  note: string;
}

/**
 * The single conversion hook. The service's own unit text (µg/m³) is stale HYSPLIT wording;
 * the raw values are SI. Evidence: docs/methods.md (calibration section).
 */
export const SMOKE_CALIBRATION: Record<SmokeLayer, Calibration | null> = {
  sfc: { unit: "µg/m³", factor: 1e9, note: "raw kg/m³ at 8 m AGL × 1e9" },
  vert: { unit: "mg/m²", factor: 1e6, note: "raw kg/m² column × 1e6" },
};

/** RAP-Smoke is issued once a day at 03Z and runs to 06Z on day 3 (forecast hour 51). */
export const EXPECTED_ISSUE_HOUR_UTC = 3;
export const MAX_FORECAST_HOUR = 51;

/** Conservative lower-48 box: CONUS slices return 0, not NoData, beyond their coverage. */
const CONUS_BOX = { west: -125, south: 24, east: -66, north: 50 };

const LAYERS: Record<SmokeLayer, { field: string; service: string; label: string }> = {
  sfc: {
    field: "smoke_surface",
    service: "ndgd_smoke_sfc_1hr_avg_time",
    label: "near-surface smoke (8 m AGL)",
  },
  vert: {
    field: "smoke_column",
    service: "ndgd_smoke_vert_1hr_avg_time",
    label: "vertically integrated smoke",
  },
};

export interface SmokePoint {
  t: string;
  v: number;
  issued_utc: string;
  fcst_hour: number | null;
  /** When the slice reached the ImageServer (`idp_ingestdate`). */
  ingested_utc?: string | null;
}

const DAY_MS = 86_400_000;
const SMOKE_MAX_TTL_SECONDS = 6 * 3600;
const SMOKE_UNKNOWN_RUN_TTL_SECONDS = 1800;

/**
 * One issue a day (03Z, NWS SCN 22-42), so the next is expected 24 h after the newest one,
 * delayed as much as the newest one was (its latest `idp_ingestdate` minus its issue time).
 */
export function nextSmokeIssue(points: SmokePoint[]): string | null {
  const latest = points
    .map((p) => p.issued_utc)
    .sort()
    .at(-1);
  if (!latest) return null;
  const ingested = points
    .filter((p) => p.issued_utc === latest && p.ingested_utc)
    .map((p) => Date.parse(p.ingested_utc!))
    .sort((a, b) => a - b)
    .at(-1);
  if (ingested === undefined) return null;
  const issued = Date.parse(latest);
  return iso(new Date(issued + DAY_MS + Math.max(0, ingested - issued)));
}

export const insideConus = (c: Cell): boolean =>
  c.lat >= CONUS_BOX.south &&
  c.lat <= CONUS_BOX.north &&
  c.lon >= CONUS_BOX.west &&
  c.lon <= CONUS_BOX.east;

/**
 * A time-range identify returns `properties.Values` in the same order as its catalog items
 * (checked 2026-09-25 against per-slice identifies at slice start + 30 min: 14/14 equal), so
 * one call covers the window. Alaska slices come back too and are dropped.
 */
export function parseIdentify(body: unknown): SmokePoint[] {
  assertNoArcgisError(body);
  if (!isRecord(body)) throw new UpstreamError("unexpected response shape");
  const values =
    isRecord(body.properties) && Array.isArray(body.properties.Values)
      ? body.properties.Values
      : [];
  const features =
    isRecord(body.catalogItems) && Array.isArray(body.catalogItems.features)
      ? body.catalogItems.features
      : [];
  if (values.length !== features.length)
    throw new UpstreamError("identify values/catalog mismatch");
  const byTime = new Map<number, SmokePoint & { issued: number }>();
  features.forEach((f, i) => {
    const a = isRecord(f) && isRecord(f.attributes) ? f.attributes : {};
    if (a.idp_subset !== "conus") return;
    const valid = num(a.idp_validtime);
    const issued = num(a.idp_issueddate);
    const v = num(values[i]);
    if (valid === null || issued === null || v === null || v < 0) return;
    const prev = byTime.get(valid);
    if (prev && prev.issued >= issued) return;
    const ingested = num(a.idp_ingestdate);
    byTime.set(valid, {
      t: iso(new Date(valid)),
      v,
      issued,
      issued_utc: iso(new Date(issued)),
      fcst_hour: num(a.idp_fcst_hour),
      ingested_utc: ingested === null ? null : iso(new Date(ingested)),
    });
  });
  return [...byTime.values()]
    .sort((a, b) => a.t.localeCompare(b.t))
    .map(({ issued: _issued, ...p }) => p);
}

export function applySmokeCalibration(
  raw: number,
  cal: Calibration | null,
): { v: number; unit: string } {
  return cal
    ? { v: Number((raw * cal.factor).toPrecision(6)), unit: cal.unit }
    : { v: raw, unit: "uncalibrated" };
}

/** Flags an issuance that doesn't look like RAP-Smoke, e.g. once RRFS replaces RAP. */
export function issuanceProblem(points: SmokePoint[]): string | null {
  const latest = points
    .map((p) => p.issued_utc)
    .sort()
    .at(-1);
  if (latest && new Date(latest).getUTCHours() !== EXPECTED_ISSUE_HOUR_UTC) {
    return `unexpected issue hour ${latest.slice(11, 16)}Z (expected 03Z); the source may have changed`;
  }
  if (points.some((p) => p.fcst_hour !== null && p.fcst_hour > MAX_FORECAST_HOUR)) {
    return `forecast hour beyond ${MAX_FORECAST_HOUR}; the source may have changed`;
  }
  return null;
}

function toSmokeSeries(loaded: Loaded<SmokePoint[]>, layer: SmokeLayer, window: Window): Series {
  const base = { model: "rap_smoke", upstream_model: LAYERS[layer].service };
  const cal = SMOKE_CALIBRATION[layer];
  const within = (pts: SmokePoint[]) => pts.filter((p) => inWindow(p.t, window));
  const convert = (pts: SmokePoint[]): Point[] =>
    pts.map((p) => ({ t: p.t, v: applySmokeCalibration(p.v, cal).v }));
  // The oldest issuance among the chosen hours is the honest age of the series.
  const run = (pts: SmokePoint[]) => pts.map((p) => p.issued_utc).sort()[0] ?? null;
  if (!loaded.ok) {
    const pts = loaded.last_good ? within(loaded.last_good.data) : [];
    return {
      ...base,
      model_run_utc: run(pts),
      next_run_expected_utc: null,
      fetched_utc: null,
      status: "unavailable",
      reason: loaded.reason,
      last_good_utc: loaded.last_good?.fetched_utc ?? null,
      values: convert(pts),
    };
  }
  const pts = within(loaded.entry.data);
  const common = {
    ...base,
    model_run_utc: run(pts),
    next_run_expected_utc: loaded.entry.next_run_expected_utc ?? null,
    fetched_utc: loaded.entry.fetched_utc,
  };
  if (pts.length === 0) {
    return {
      ...common,
      status: "unavailable",
      reason: "no CONUS RAP-Smoke slice covers this window",
      last_good_utc: null,
      values: [],
    };
  }
  const problem = issuanceProblem(pts);
  if (problem) {
    return {
      ...common,
      status: "unavailable",
      reason: problem,
      last_good_utc: null,
      values: convert(pts),
    };
  }
  return { ...common, status: "ok", values: convert(pts) };
}

export async function smokeFields(
  deps: Deps,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const out: Record<string, Field> = {};
  await Promise.all(
    (Object.keys(LAYERS) as SmokeLayer[]).map(async (layer) => {
      const spec = LAYERS[layer];
      const cal = SMOKE_CALIBRATION[layer];
      const extra = {
        description: spec.label,
        value_kind: "instantaneous at the start of each hourly slice (despite '1hr_avg')",
        calibrated: cal !== null,
        calibration: cal?.note ?? null,
      };
      if (!insideConus(cell)) {
        out[spec.field] = assembleField(
          cal?.unit ?? "uncalibrated",
          SMOKE_SOURCE,
          [
            {
              model: "rap_smoke",
              upstream_model: spec.service,
              model_run_utc: null,
              next_run_expected_utc: null,
              fetched_utc: null,
              status: "unavailable",
              reason: "cell is outside the NDGD CONUS smoke coverage",
              last_good_utc: null,
              values: [],
            },
          ],
          extra,
        );
        return;
      }
      const geometry = encodeURIComponent(
        JSON.stringify({ x: cell.lon, y: cell.lat, spatialReference: { wkid: 4326 } }),
      );
      // Always pass `time`: without it identify answers from an arbitrary slice.
      const url =
        `${NDGD_BASE}/${spec.service}/ImageServer/identify?geometry=${geometry}` +
        `&geometryType=esriGeometryPoint&time=${window.start.getTime()},${window.end.getTime()}` +
        "&returnGeometry=false&returnCatalogItems=true&f=json";
      const store = edgeStore(deps);
      const key = `ndgd-smoke:${layer}:${cellKey(cell)}:${window.start.getTime()}:${window.end.getTime()}`;
      const stored = await store.get<SmokePoint[]>(key);
      const loaded = await cachedLoad(
        deps,
        {
          store,
          key,
          stored,
          source: "ndgd-smoke",
          // Run-aware: an entry that knows its next issue is kept until then, else 30 min.
          ttlSeconds: stored?.next_run_expected_utc
            ? SMOKE_MAX_TTL_SECONDS
            : SMOKE_UNKNOWN_RUN_TTL_SECONDS,
          overdueTtlSeconds: 900,
          timing: `smoke-${layer}`,
        },
        async () => {
          const data = parseIdentify(await getJson(deps.fetch, url));
          return { data, next_run_expected_utc: nextSmokeIssue(data) };
        },
      );
      out[spec.field] = assembleField(
        cal?.unit ?? "uncalibrated",
        SMOKE_SOURCE,
        [toSmokeSeries(loaded, layer, window)],
        extra,
      );
    }),
  );
  return out;
}
