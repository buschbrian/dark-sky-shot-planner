import { parseBbox, parseCell, parseOptionalCell, parseWindow } from "./params.ts";
import { AIRNOW_ATTRIBUTION, airnowField } from "./sources/airnow.ts";
import { smokePolygons } from "./sources/hms.ts";
import { smokeFields } from "./sources/ndgdsmoke.ts";
import { airQualityFields, forecastFields } from "./sources/openmeteo.ts";
import { sevenTimerFields } from "./sources/seventimer.ts";
import {
  AURORA_METHOD,
  auroraNearCell,
  type KpPoint,
  loadKp,
  loadOvation,
  SWPC_SOURCE,
} from "./sources/swpc.ts";
import { edgeStore, kvStore, type Loaded, readHealth } from "./store.ts";
import { type Deps, type Env, iso } from "./types.ts";

export const ATTRIBUTION = [
  "Weather data by Open-Meteo.com (CC BY 4.0)",
  "Air quality: Copernicus Atmosphere Monitoring Service (CAMS) via Open-Meteo",
  "Smoke forecast: NOAA RAP-Smoke via NWS NDGD; smoke polygons: NOAA NESDIS HMS",
  AIRNOW_ATTRIBUTION,
  "Seeing and transparency: 7Timer! (non-commercial use)",
  "Space weather: NOAA SWPC",
];

export async function conditions(deps: Deps, env: Env, params: URLSearchParams) {
  const cell = parseCell(params);
  const window = parseWindow(params, deps.now());
  const [forecast, aq, smoke, aqi, astro] = await Promise.all([
    forecastFields(deps, cell, window),
    airQualityFields(deps, cell, window),
    smokeFields(deps, cell, window),
    airnowField(deps, env, cell),
    sevenTimerFields(deps, env, cell, window),
  ]);
  return {
    cell,
    window: { start_utc: iso(window.start), end_utc: iso(window.end) },
    generated_utc: iso(deps.now()),
    fields: { ...forecast, ...aq, ...smoke, aqi_observed: aqi, ...astro },
    attribution: ATTRIBUTION,
  };
}

function kpBlock(loaded: Loaded<KpPoint[]>, keep: (p: KpPoint) => boolean) {
  const base = { source: SWPC_SOURCE, unit: "Kp" };
  if (!loaded.ok) {
    return {
      ...base,
      status: "unavailable",
      reason: loaded.reason,
      fetched_utc: null,
      last_good_utc: loaded.last_good?.fetched_utc ?? null,
      values: (loaded.last_good?.data ?? []).filter(keep),
    };
  }
  return {
    ...base,
    status: "ok",
    fetched_utc: loaded.entry.fetched_utc,
    values: loaded.entry.data.filter(keep),
  };
}

export async function spaceWeather(deps: Deps, env: Env, params: URLSearchParams) {
  const cell = parseOptionalCell(params);
  const store = env.SPACE_WEATHER ? kvStore(env.SPACE_WEATHER) : edgeStore(deps);
  const [kp, kpf, ov] = await Promise.all([
    loadKp(deps, store, "kp"),
    loadKp(deps, store, "kp_forecast"),
    loadOvation(deps, store),
  ]);
  const entry = ov.ok ? ov.entry : ov.last_good;
  const aurora = {
    source: `${SWPC_SOURCE} OVATION aurora model`,
    status: ov.ok ? "ok" : "unavailable",
    fetched_utc: ov.ok ? ov.entry.fetched_utc : null,
    ...(ov.ok ? {} : { reason: ov.reason, last_good_utc: ov.last_good?.fetched_utc ?? null }),
    observation_time_utc: entry?.data.observation_time_utc ?? null,
    forecast_time_utc: entry?.data.forecast_time_utc ?? null,
    near_cell:
      cell && entry
        ? {
            lat: cell.lat,
            lon: cell.lon,
            probability_pct: auroraNearCell(entry.data, cell),
            method: AURORA_METHOD,
          }
        : null,
  };
  return {
    generated_utc: iso(deps.now()),
    cache: env.SPACE_WEATHER ? "kv" : deps.cache ? "edge-cache" : "none",
    kp_observed: kpBlock(kp, () => true),
    kp_forecast: kpBlock(kpf, (p) => p.kind !== "observed"),
    aurora,
  };
}

export async function smoke(deps: Deps, params: URLSearchParams) {
  return smokePolygons(deps, parseBbox(params));
}

export const UPSTREAMS = [
  "open-meteo-meta",
  "open-meteo-forecast",
  "open-meteo-air-quality",
  "ndgd-smoke",
  "airnow",
  "7timer",
  "swpc-kp",
  "swpc-kp-forecast",
  "swpc-ovation",
  "hms",
] as const;

export async function health(deps: Deps, env: Env) {
  const upstreams: Record<string, unknown> = {};
  for (const id of UPSTREAMS) {
    const h = await readHealth(deps, id);
    const failing = h?.last_failure_utc != null && (h.last_success_utc ?? "") < h.last_failure_utc;
    upstreams[id] = {
      status: !h ? "unknown" : failing ? "failing" : "ok",
      last_success_utc: h?.last_success_utc ?? null,
      last_failure_utc: h?.last_failure_utc ?? null,
      last_error: h?.last_error ?? null,
    };
  }
  return {
    status: "ok",
    time_utc: iso(deps.now()),
    config: {
      airnow_key_configured: Boolean(env.AIRNOW_API_KEY?.trim()),
      space_weather_kv_bound: Boolean(env.SPACE_WEATHER),
      edge_cache_available: deps.cache !== null,
      seventimer_enabled: (env.SEVENTIMER_ENABLED ?? "true").toLowerCase() !== "false",
    },
    note: "Upstream status reflects the last real upstream call seen by this data center; unknown means none yet.",
    upstreams,
  };
}
