import { getJson, getText, isRecord, num, parseJson, UpstreamError } from "../http.ts";
import { type Cell, cellKey, inWindow, type Window } from "../params.ts";
import { cachedLoad, edgeStore, type Loaded } from "../store.ts";
import { type Deps, type Field, iso, type Point, type Series } from "../types.ts";

export const FORECAST_HOST = "https://api.open-meteo.com";
export const AQ_HOST = "https://air-quality-api.open-meteo.com";

export interface ModelSpec {
  id: string;
  /** `models=` value for the forecast API. */
  upstream: string;
  /** `/data/{meta}/static/meta.json` id; seamless/alias models have no meta of their own. */
  meta: string;
  label: string;
}

/**
 * Named models only, never `*_seamless` aliases: over Utah `gfs_seamless` serves HRRR for the
 * first ~40 h and `icon_seamless` is `icon_global`, so a blend would repeat a series and hide
 * the disagreement; aliases also have no meta.json. HRDPS was dropped: its domain misses much
 * of southern Utah (docs/ios/PLAN.md §Data sources).
 */
export const FORECAST_MODELS: ModelSpec[] = [
  { id: "hrrr", upstream: "ncep_hrrr_conus", meta: "ncep_hrrr_conus", label: "NOAA HRRR CONUS" },
  { id: "gfs", upstream: "gfs_global", meta: "ncep_gfs013", label: "NOAA GFS" },
  { id: "icon", upstream: "icon_global", meta: "dwd_icon", label: "DWD ICON Global" },
  { id: "ecmwf", upstream: "ecmwf_ifs025", meta: "ecmwf_ifs025", label: "ECMWF IFS 0.25°" },
];

export const AQ_MODEL: ModelSpec = {
  id: "cams_global",
  upstream: "cams_global",
  meta: "cams_global",
  label: "CAMS Global",
};

export interface VariableSpec {
  field: string;
  om: string;
  unit: string;
}

export const FORECAST_VARIABLES: VariableSpec[] = [
  { field: "cloud_cover_total", om: "cloud_cover", unit: "%" },
  { field: "cloud_cover_low", om: "cloud_cover_low", unit: "%" },
  { field: "cloud_cover_mid", om: "cloud_cover_mid", unit: "%" },
  { field: "cloud_cover_high", om: "cloud_cover_high", unit: "%" },
  { field: "temperature", om: "temperature_2m", unit: "°C" },
  { field: "dew_point", om: "dew_point_2m", unit: "°C" },
  { field: "relative_humidity", om: "relative_humidity_2m", unit: "%" },
  { field: "wind_speed", om: "wind_speed_10m", unit: "km/h" },
  { field: "wind_gust", om: "wind_gusts_10m", unit: "km/h" },
  { field: "visibility", om: "visibility", unit: "m" },
  { field: "wind_speed_250hpa", om: "wind_speed_250hPa", unit: "km/h" },
  { field: "wind_speed_200hpa", om: "wind_speed_200hPa", unit: "km/h" },
];

export const AQ_VARIABLES: VariableSpec[] = [
  { field: "aerosol_optical_depth", om: "aerosol_optical_depth", unit: "" },
  { field: "pm2_5", om: "pm2_5", unit: "µg/m³" },
  { field: "dust", om: "dust", unit: "µg/m³" },
];

export const FORECAST_SOURCE = "Open-Meteo";
export const AQ_SOURCE = "Open-Meteo Air Quality (CAMS Global; © ECMWF Copernicus)";

export interface Hourly {
  outside_domain: boolean;
  units: Record<string, string>;
  time: string[];
  vars: Record<string, (number | null)[]>;
}

export function parseMeta(body: unknown): string {
  if (!isRecord(body) || body.error === true) throw new UpstreamError("meta.json error");
  const t = num(body.last_run_initialisation_time);
  if (t === null) throw new UpstreamError("meta.json has no run time");
  return iso(new Date(t * 1000));
}

export function parseHourly(status: number, text: string): Hourly {
  if (status === 400) {
    const body = parseJson(text);
    if (
      isRecord(body) &&
      typeof body.reason === "string" &&
      /no data is available/i.test(body.reason)
    ) {
      return { outside_domain: true, units: {}, time: [], vars: {} };
    }
  }
  if (status < 200 || status >= 300) throw new UpstreamError(`HTTP ${status}`);
  const body = parseJson(text);
  if (!isRecord(body) || body.error === true || !isRecord(body.hourly)) {
    throw new UpstreamError("unexpected response shape");
  }
  const { time, ...rest } = body.hourly;
  if (!Array.isArray(time)) throw new UpstreamError("hourly.time missing");
  const times = time.map((t) => {
    if (typeof t !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(t)) {
      throw new UpstreamError("unexpected time format");
    }
    return `${t}:00Z`;
  });
  const vars: Record<string, (number | null)[]> = {};
  for (const [k, v] of Object.entries(rest)) if (Array.isArray(v)) vars[k] = v.map(num);
  const units: Record<string, string> = {};
  if (isRecord(body.hourly_units)) {
    for (const [k, v] of Object.entries(body.hourly_units)) if (typeof v === "string") units[k] = v;
  }
  return { outside_domain: false, units, time: times, vars };
}

async function modelRun(deps: Deps, host: string, metaId: string): Promise<string | null> {
  const loaded = await cachedLoad(
    deps,
    {
      store: edgeStore(deps),
      source: "open-meteo-meta",
      key: `om-meta:${host}:${metaId}`,
      ttlSeconds: 300,
    },
    async () => ({
      data: parseMeta(await getJson(deps.fetch, `${host}/data/${metaId}/static/meta.json`)),
    }),
  );
  return loaded.ok ? loaded.entry.data : null;
}

async function loadModel(
  deps: Deps,
  opts: {
    host: string;
    path: string;
    source: string;
    model: ModelSpec;
    query: string;
    cell: Cell;
    window: Window;
  },
): Promise<Loaded<Hourly>> {
  const { host, path, source, model, query, cell, window } = opts;
  const run = await modelRun(deps, host, model.meta);
  const url =
    `${host}${path}?latitude=${cell.lat}&longitude=${cell.lon}&${query}` +
    `&timezone=GMT&timeformat=iso8601&start_date=${window.startDate}&end_date=${window.endDate}`;
  return cachedLoad(
    deps,
    {
      store: edgeStore(deps),
      source,
      key: `${source}:${model.upstream}:${cellKey(cell)}:${window.startDate}:${window.endDate}`,
      // A known run pins the entry until the next run appears; an unknown run falls back to age.
      ttlSeconds: run ? 6 * 3600 : 900,
      run,
    },
    async () => {
      const { status, text } = await getText(deps.fetch, url);
      return { data: parseHourly(status, text), model_run_utc: run };
    },
  );
}

/** Open-Meteo writes µ as Greek mu (U+03BC); the thresholds config uses the micro sign. */
const sameUnit = (u: string) => u.replace(/\u03bc/g, "\u00b5");

function pick(h: Hourly, v: VariableSpec, model: ModelSpec, window: Window): Point[] | string {
  if (h.outside_domain) return "cell is outside this model's domain";
  const key = v.om in h.vars ? v.om : `${v.om}_${model.upstream}`;
  const vals = h.vars[key];
  const unit = h.units[key];
  if (!vals || vals.every((x) => x === null)) return "model does not publish this variable here";
  if (unit !== undefined && sameUnit(unit) !== sameUnit(v.unit)) {
    return `unexpected upstream unit "${unit}"`;
  }
  return h.time.map((t, i) => ({ t, v: vals[i] ?? null })).filter((p) => inWindow(p.t, window));
}

export function toSeries(
  loaded: Loaded<Hourly>,
  v: VariableSpec,
  model: ModelSpec,
  window: Window,
): Series {
  const base = { model: model.id, upstream_model: model.upstream };
  if (!loaded.ok) {
    const lg = loaded.last_good;
    const values = lg ? pick(lg.data, v, model, window) : [];
    return {
      ...base,
      model_run_utc: lg?.model_run_utc ?? null,
      fetched_utc: null,
      status: "unavailable",
      reason: loaded.reason,
      last_good_utc: lg?.fetched_utc ?? null,
      values: typeof values === "string" ? [] : values,
    };
  }
  const { entry } = loaded;
  const values = pick(entry.data, v, model, window);
  if (typeof values === "string") {
    return {
      ...base,
      model_run_utc: entry.model_run_utc,
      fetched_utc: entry.fetched_utc,
      status: "unavailable",
      reason: values,
      last_good_utc: null,
      values: [],
    };
  }
  return {
    ...base,
    model_run_utc: entry.model_run_utc,
    fetched_utc: entry.fetched_utc,
    status: "ok",
    values,
  };
}

/** Series stay separate: disagreement between models is shown, never averaged (ADR-0010). */
export function assembleField(
  unit: string,
  source: string,
  series: Series[],
  extra: Record<string, unknown> = {},
): Field {
  const ok = series.filter((s) => s.status === "ok");
  const latest = (xs: (string | null | undefined)[]) =>
    xs
      .filter((x): x is string => typeof x === "string")
      .sort()
      .at(-1) ?? null;
  const field: Field = {
    unit,
    source,
    status: ok.length > 0 ? "ok" : "unavailable",
    fetched_utc: latest(ok.map((s) => s.fetched_utc)),
    series,
    ...extra,
  };
  if (field.status === "unavailable") {
    field.reason = series.map((s) => `${s.model}: ${s.reason ?? "unavailable"}`).join("; ");
    field.last_good_utc = latest(series.map((s) => s.last_good_utc));
  }
  return field;
}

export async function forecastFields(
  deps: Deps,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const hourly = FORECAST_VARIABLES.map((v) => v.om).join(",");
  const loaded = await Promise.all(
    FORECAST_MODELS.map((model) =>
      loadModel(deps, {
        host: FORECAST_HOST,
        path: "/v1/forecast",
        source: "open-meteo-forecast",
        model,
        query: `hourly=${hourly}&models=${model.upstream}`,
        cell,
        window,
      }),
    ),
  );
  const out: Record<string, Field> = {};
  for (const v of FORECAST_VARIABLES) {
    const series = FORECAST_MODELS.map((m, i) => toSeries(loaded[i]!, v, m, window));
    out[v.field] = assembleField(v.unit, FORECAST_SOURCE, series);
  }
  return out;
}

export async function airQualityFields(
  deps: Deps,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const loaded = await loadModel(deps, {
    host: AQ_HOST,
    path: "/v1/air-quality",
    source: "open-meteo-air-quality",
    model: AQ_MODEL,
    query: `hourly=${AQ_VARIABLES.map((v) => v.om).join(",")}&domains=cams_global`,
    cell,
    window,
  });
  const out: Record<string, Field> = {};
  for (const v of AQ_VARIABLES) {
    out[v.field] = assembleField(v.unit, AQ_SOURCE, [toSeries(loaded, v, AQ_MODEL, window)], {
      resolution_note: "CAMS Global is ~45 km; use as a cross-check for RAP-Smoke",
    });
  }
  return out;
}
