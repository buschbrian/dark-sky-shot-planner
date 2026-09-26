import { getJson, getText, isRecord, num, parseJson, UpstreamError } from "../http.ts";
import { type Cell, cellKey, inWindow, type Window } from "../params.ts";
import { cachedLoad, edgeStore, isFresh, type Loaded } from "../store.ts";
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

/**
 * HRRR's native 15-minute output (`minutely_15`), served by Open-Meteo for the first 18 h of
 * each run. Cloud cover is left out on purpose: Open-Meteo's `minutely_15` cloud cover is a
 * Catmull-Rom interpolation of the hourly values (checked point by point on 2026-09-26), so
 * it would add no information. Relative humidity is interpolated too.
 */
export const NEAR_TERM = {
  modelId: "hrrr",
  resolutionMinutes: 15,
  nativeHours: 18,
  fields: ["temperature", "dew_point", "wind_speed", "wind_gust", "visibility"],
} as const;

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

/**
 * Open-Meteo asks clients to wait 10 minutes after `last_run_availability_time` so every API
 * server has the run (https://open-meteo.com/en/docs/model-updates).
 */
export const SYNC_MARGIN_SECONDS = 600;

export interface ModelMeta {
  run_utc: string;
  /** When the run was on the API; null if meta.json doesn't say. */
  available_utc: string | null;
  /** `available_utc` + the sync margin: before this, some servers may still serve the old run. */
  synced_utc: string | null;
  /** Last availability + `update_interval_seconds` + the sync margin. */
  next_run_expected_utc: string | null;
  update_interval_seconds: number | null;
}

const unix = (s: number) => iso(new Date(s * 1000));

/**
 * The next run is estimated as the last run's availability time plus the model's update
 * interval, i.e. it assumes the next run is published with the same delay as the last one.
 */
export function parseMeta(body: unknown): ModelMeta {
  if (!isRecord(body) || body.error === true) throw new UpstreamError("meta.json error");
  const t = num(body.last_run_initialisation_time);
  if (t === null) throw new UpstreamError("meta.json has no run time");
  const available = num(body.last_run_availability_time);
  const interval = num(body.update_interval_seconds);
  const okInterval = interval !== null && interval > 0 ? interval : null;
  return {
    run_utc: unix(t),
    available_utc: available === null ? null : unix(available),
    synced_utc: available === null ? null : unix(available + SYNC_MARGIN_SECONDS),
    next_run_expected_utc:
      available === null || okInterval === null
        ? null
        : unix(available + okInterval + SYNC_MARGIN_SECONDS),
    update_interval_seconds: okInterval,
  };
}

export function parseHourly(status: number, text: string): Hourly {
  return parseTimeBlock(status, text, "hourly");
}

/** Reads `hourly` or `minutely_15`; both carry `time` plus one array per variable. */
export function parseTimeBlock(
  status: number,
  text: string,
  block: "hourly" | "minutely_15",
): Hourly {
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
  const data = isRecord(body) ? body[block] : undefined;
  if (!isRecord(body) || body.error === true || !isRecord(data)) {
    throw new UpstreamError("unexpected response shape");
  }
  const { time, ...rest } = data;
  if (!Array.isArray(time)) throw new UpstreamError(`${block}.time missing`);
  const times = time.map((t) => {
    if (typeof t !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(t)) {
      throw new UpstreamError("unexpected time format");
    }
    return `${t}:00Z`;
  });
  const vars: Record<string, (number | null)[]> = {};
  for (const [k, v] of Object.entries(rest)) if (Array.isArray(v)) vars[k] = v.map(num);
  const units: Record<string, string> = {};
  const unitBlock = body[`${block}_units`];
  if (isRecord(unitBlock)) {
    for (const [k, v] of Object.entries(unitBlock)) if (typeof v === "string") units[k] = v;
  }
  return { outside_domain: false, units, time: times, vars };
}

const META_MAX_TTL_SECONDS = 3600;
const FORECAST_MAX_TTL_SECONDS = 6 * 3600;

/**
 * Run-aware: a cached meta.json stays good until the next run is expected, then is re-checked
 * every two minutes until the run appears. At most an hour either way.
 */
export async function modelMeta(
  deps: Deps,
  host: string,
  metaId: string,
): Promise<ModelMeta | null> {
  const loaded = await cachedLoad<ModelMeta>(
    deps,
    {
      store: edgeStore(deps),
      source: "open-meteo-meta",
      key: `om-meta2:${host}:${metaId}`,
      ttlSeconds: META_MAX_TTL_SECONDS,
      overdueTtlSeconds: 120,
      timing: `meta-${metaId}`,
    },
    async () => {
      const meta = parseMeta(await getJson(deps.fetch, `${host}/data/${metaId}/static/meta.json`));
      return {
        data: meta,
        model_run_utc: meta.run_utc,
        next_run_expected_utc: meta.next_run_expected_utc,
      };
    },
  );
  return loaded.ok ? loaded.entry.data : null;
}

export interface ModelLoad {
  loaded: Loaded<Hourly>;
  meta: ModelMeta | null;
}

/**
 * Reads the cached forecast while meta.json is in flight. With nothing usable cached, the
 * forecast is fetched at once instead of after meta.json, so a cold request costs one
 * round trip, not two.
 */
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
    meta: Promise<ModelMeta | null>;
    /** Key and timing suffix for a second request against the same model (15-minute data). */
    variant?: string;
    block?: "hourly" | "minutely_15";
    /** Replaces the date range (`start_date`/`end_date`) in the URL. */
    range?: string;
  },
): Promise<ModelLoad> {
  const { host, path, source, model, query, cell, window } = opts;
  const t0 = Date.now();
  const store = edgeStore(deps);
  const range = opts.range ?? `start_date=${window.startDate}&end_date=${window.endDate}`;
  const url =
    `${host}${path}?latitude=${cell.lat}&longitude=${cell.lon}&${query}` +
    `&timezone=GMT&timeformat=iso8601&${range}`;
  const key =
    `${source}${opts.variant ? `-${opts.variant}` : ""}:${model.upstream}:${cellKey(cell)}:` +
    range.replace(/[a-z0-9_]+=/g, "").replace("&", ":");
  const fetchIt = async () => {
    const { status, text } = await getText(deps.fetch, url);
    return parseTimeBlock(status, text, opts.block ?? "hourly");
  };
  const stored = await store.get<Hourly>(key);
  const couldBeFresh =
    stored !== null &&
    isFresh(stored, { store, source, key, ttlSeconds: FORECAST_MAX_TTL_SECONDS }, deps.now());
  const early = couldBeFresh ? null : fetchIt();
  early?.catch(() => {});
  const meta = await opts.meta;
  const run = meta?.run_utc ?? null;
  const loaded = await cachedLoad(
    deps,
    {
      store,
      source,
      key,
      // A known run pins the entry until the next run appears; an unknown run falls back to age.
      ttlSeconds: run ? FORECAST_MAX_TTL_SECONDS : 900,
      run,
      // Right after a run appears some API servers may still serve the previous one, so an
      // entry fetched before the sync margin ends is read again once it has.
      recheckAfter: meta?.synced_utc ?? null,
      stored,
      timing: `om${opts.variant ?? ""}-${model.id}`,
      startedMs: t0,
    },
    async () => ({ data: await (early ?? fetchIt()), model_run_utc: run }),
  );
  return { loaded, meta };
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
  { loaded, meta }: ModelLoad,
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
      next_run_expected_utc: null,
      fetched_utc: null,
      status: "unavailable",
      reason: loaded.reason,
      last_good_utc: lg?.fetched_utc ?? null,
      values: typeof values === "string" ? [] : values,
    };
  }
  const { entry } = loaded;
  const common = {
    ...base,
    model_run_utc: entry.model_run_utc,
    // Only a meta.json that describes this entry's run can say when the next one comes.
    next_run_expected_utc:
      meta && meta.run_utc === entry.model_run_utc ? meta.next_run_expected_utc : null,
    fetched_utc: entry.fetched_utc,
  };
  const values = pick(entry.data, v, model, window);
  if (typeof values === "string") {
    return { ...common, status: "unavailable", reason: values, last_good_utc: null, values: [] };
  }
  return { ...common, status: "ok", values };
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

const HOUR_MS = 3_600_000;
const minuteStamp = (d: Date) => d.toISOString().slice(0, 16);

/** The part of the window HRRR can cover at 15 minutes, or null when none of it can. */
export function nearTermRange(window: Window, now: Date): { start: Date; end: Date } | null {
  const horizon = Math.floor(now.getTime() / HOUR_MS) * HOUR_MS + NEAR_TERM.nativeHours * HOUR_MS;
  const end = Math.min(window.end.getTime(), horizon);
  return end < window.start.getTime() ? null : { start: window.start, end: new Date(end) };
}

function nearTermSeries(
  load: ModelLoad | null,
  v: VariableSpec,
  model: ModelSpec,
  window: Window,
): Series {
  const head = {
    model: model.id,
    upstream_model: model.upstream,
    resolution_minutes: NEAR_TERM.resolutionMinutes,
  };
  const none = (reason: string): Series => ({
    ...head,
    model_run_utc: null,
    next_run_expected_utc: null,
    fetched_utc: null,
    status: "unavailable",
    reason,
    last_good_utc: null,
    values: [],
  });
  if (!load)
    return none(`window starts beyond HRRR's ${NEAR_TERM.nativeHours}-hour 15-minute range`);
  const { model: _m, upstream_model: _u, ...rest } = toSeries(load, v, model, window);
  // Past run + 18 h Open-Meteo interpolates from hourly: not native, so not served.
  const run = rest.model_run_utc ? Date.parse(rest.model_run_utc) : Number.NaN;
  const limit = run + NEAR_TERM.nativeHours * HOUR_MS;
  const values = Number.isFinite(limit)
    ? rest.values.filter((p) => Date.parse(p.t) <= limit)
    : rest.values;
  if (rest.status === "ok" && values.length === 0) {
    return {
      ...none("no native 15-minute values in this window"),
      model_run_utc: rest.model_run_utc,
    };
  }
  return { ...head, ...rest, values };
}

export async function forecastFields(
  deps: Deps,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const hourly = FORECAST_VARIABLES.map((v) => v.om).join(",");
  const metas = new Map(
    FORECAST_MODELS.map((m) => [m.id, modelMeta(deps, FORECAST_HOST, m.meta)] as const),
  );
  const nearModel = FORECAST_MODELS.find((m) => m.id === NEAR_TERM.modelId)!;
  const nearVars = FORECAST_VARIABLES.filter((v) =>
    (NEAR_TERM.fields as readonly string[]).includes(v.field),
  );
  const range = nearTermRange(window, deps.now());
  // Every model's meta.json and forecast, and HRRR's 15-minute request, start together: the
  // fan-out is one round trip deep.
  const [loaded, near] = await Promise.all([
    Promise.all(
      FORECAST_MODELS.map((model) =>
        loadModel(deps, {
          meta: metas.get(model.id)!,
          host: FORECAST_HOST,
          path: "/v1/forecast",
          source: "open-meteo-forecast",
          model,
          query: `hourly=${hourly}&models=${model.upstream}`,
          cell,
          window,
        }),
      ),
    ),
    range
      ? loadModel(deps, {
          meta: metas.get(nearModel.id)!,
          host: FORECAST_HOST,
          path: "/v1/forecast",
          source: "open-meteo-forecast",
          model: nearModel,
          query: `minutely_15=${nearVars.map((v) => v.om).join(",")}&models=${nearModel.upstream}`,
          cell,
          window,
          variant: "15",
          block: "minutely_15",
          range: `start_minutely_15=${minuteStamp(range.start)}&end_minutely_15=${minuteStamp(range.end)}`,
        })
      : Promise.resolve(null),
  ]);
  const out: Record<string, Field> = {};
  for (const v of FORECAST_VARIABLES) {
    const series = FORECAST_MODELS.map((m, i) => toSeries(loaded[i]!, v, m, window));
    const extra = nearVars.includes(v)
      ? { series_15min: [nearTermSeries(near, v, nearModel, window)] }
      : {};
    out[v.field] = assembleField(v.unit, FORECAST_SOURCE, series, extra);
  }
  return out;
}

export async function airQualityFields(
  deps: Deps,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const loaded = await loadModel(deps, {
    meta: modelMeta(deps, AQ_HOST, AQ_MODEL.meta),
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
