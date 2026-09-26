import { getJson, isRecord, num, UpstreamError } from "../http.ts";
import { type Cell, cellKey } from "../params.ts";
import { cachedLoad, edgeStore } from "../store.ts";
import type { Deps, Env, Field } from "../types.ts";

export const AIRNOW_BASE = "https://www.airnowapi.org/aq/observation/current/ziplatLong/";
export const AIRNOW_SOURCE = "EPA AirNow";
export const AIRNOW_ATTRIBUTION =
  "Preliminary data from EPA AirNow and its participating reporting agencies; not verified.";
const DISTANCE_MILES = 50;

export interface Observation {
  parameter: string;
  aqi: number;
  category: string;
  category_number: number;
  reporting_area: string | null;
  site_name: string | null;
  reporting_agency: string | null;
  observed_local: string;
  local_time_zone: string | null;
  observed_utc: string | null;
}

const TZ_OFFSET_HOURS: Record<string, number> = {
  EST: -5,
  EDT: -4,
  CST: -6,
  CDT: -5,
  MST: -7,
  MDT: -6,
  PST: -8,
  PDT: -7,
  AKST: -9,
  AKDT: -8,
  HST: -10,
};

const CATEGORIES: [number, string][] = [
  [50, "Good"],
  [100, "Moderate"],
  [150, "Unhealthy for Sensitive Groups"],
  [200, "Unhealthy"],
  [300, "Very Unhealthy"],
];

export function aqiCategory(aqi: number): { number: number; name: string } {
  const i = CATEGORIES.findIndex(([max]) => aqi <= max);
  return i === -1 ? { number: 6, name: "Hazardous" } : { number: i + 1, name: CATEGORIES[i]![1] };
}

const str = (x: unknown): string | null =>
  typeof x === "string" && x.trim() !== "" ? x.trim() : null;

/**
 * Reads the replacement `ziplatLong` rows (camelCase: `nowcastAQI`, `aqiCategoryName`) and,
 * defensively, the retired `latLong/current` rows (`AQI`, `Category.Name`).
 */
export function parseObservations(body: unknown): Observation[] {
  if (isRecord(body) && body.WebServiceError) throw new UpstreamError("AirNow service error");
  if (!Array.isArray(body)) throw new UpstreamError("unexpected response shape");
  const out: Observation[] = [];
  for (const row of body) {
    if (!isRecord(row)) continue;
    const aqi = num(row.nowcastAQI ?? row.AQI);
    const parameter = str(row.parameterName ?? row.ParameterName);
    if (aqi === null || aqi < 0 || parameter === null) continue;
    const legacyCat = isRecord(row.Category) ? row.Category : {};
    const cat = aqiCategory(aqi);
    const date = str(row.dateObserved ?? row.DateObserved) ?? "";
    const hourRaw = row.hourObserved ?? row.HourObserved;
    const hour = typeof hourRaw === "number" ? hourRaw : num(String(hourRaw ?? "").split(":")[0]);
    const tz = str(row.localTimeZone ?? row.LocalTimeZone);
    const local = hour === null ? date : `${date}T${String(hour).padStart(2, "0")}:00`;
    const offset = tz ? TZ_OFFSET_HOURS[tz.toUpperCase()] : undefined;
    let observed_utc: string | null = null;
    if (hour !== null && offset !== undefined && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
      const ms = Date.parse(`${date}T00:00:00Z`) + (hour - offset) * 3_600_000;
      observed_utc = new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
    }
    out.push({
      parameter,
      aqi,
      category: str(row.aqiCategoryName) ?? str(legacyCat.Name) ?? cat.name,
      category_number: num(legacyCat.Number) ?? cat.number,
      reporting_area: str(row.reportingAreaName ?? row.ReportingArea),
      site_name: str(row.siteName),
      reporting_agency: str(row.reportingAgency),
      observed_local: local,
      local_time_zone: tz,
      observed_utc,
    });
  }
  return out;
}

export async function airnowField(deps: Deps, env: Env, cell: Cell): Promise<Field> {
  const base = {
    unit: "AQI",
    source: AIRNOW_SOURCE,
    series: [],
    preliminary: true,
    attribution: AIRNOW_ATTRIBUTION,
  };
  const key = env.AIRNOW_API_KEY?.trim();
  if (!key) {
    return {
      ...base,
      status: "unavailable",
      fetched_utc: null,
      reason: "AirNow API key not configured",
      last_good_utc: null,
      observations: [],
    };
  }
  const url =
    `${AIRNOW_BASE}?format=application/json&latitude=${cell.lat}&longitude=${cell.lon}` +
    `&distance=${DISTANCE_MILES}&API_KEY=${encodeURIComponent(key)}`;
  const loaded = await cachedLoad(
    deps,
    { store: edgeStore(deps), source: "airnow", key: `airnow:${cellKey(cell)}`, ttlSeconds: 1200 },
    async () => ({ data: parseObservations(await getJson(deps.fetch, url)) }),
  );
  if (!loaded.ok) {
    return {
      ...base,
      status: "unavailable",
      fetched_utc: null,
      reason: loaded.reason,
      last_good_utc: loaded.last_good?.fetched_utc ?? null,
      observations: loaded.last_good?.data ?? [],
    };
  }
  const observations = loaded.entry.data;
  if (observations.length === 0) {
    return {
      ...base,
      status: "unavailable",
      fetched_utc: loaded.entry.fetched_utc,
      reason: `no reporting monitor within ${DISTANCE_MILES} miles`,
      last_good_utc: null,
      observations: [],
    };
  }
  return { ...base, status: "ok", fetched_utc: loaded.entry.fetched_utc, observations };
}
