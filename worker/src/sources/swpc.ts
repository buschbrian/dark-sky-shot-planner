import { getJson, isRecord, num, UpstreamError } from "../http.ts";
import type { Cell } from "../params.ts";
import { cachedLoad, type EntryStore, type Loaded } from "../store.ts";
import type { Deps } from "../types.ts";

export const SWPC_BASE = "https://services.swpc.noaa.gov";
export const KP_URL = `${SWPC_BASE}/products/noaa-planetary-k-index.json`;
export const KP_FORECAST_URL = `${SWPC_BASE}/products/noaa-planetary-k-index-forecast.json`;
export const OVATION_URL = `${SWPC_BASE}/json/ovation_aurora_latest.json`;
export const SWPC_SOURCE = "NOAA Space Weather Prediction Center";

export interface KpPoint {
  t: string;
  v: number;
  kind?: string;
  noaa_scale?: string | null;
}

/** SWPC products are arrays of objects now; a header-row array of arrays is also accepted. */
export function rowsByKey(body: unknown): Record<string, unknown>[] {
  if (!Array.isArray(body)) throw new UpstreamError("unexpected response shape");
  if (body.length > 0 && Array.isArray(body[0])) {
    const header = (body[0] as unknown[]).map(String);
    return body
      .slice(1)
      .map((r) =>
        Object.fromEntries(header.map((h, i) => [h, Array.isArray(r) ? r[i] : undefined])),
      );
  }
  return body.filter(isRecord);
}

const timeTag = (x: unknown): string | null => {
  if (typeof x !== "string") return null;
  const t = /(Z|[+-]\d{2}:?\d{2})$/.test(x) ? x : `${x.replace(" ", "T")}Z`;
  const ms = Date.parse(t);
  return Number.isNaN(ms) ? null : new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
};

export function parseKp(body: unknown): KpPoint[] {
  const out: KpPoint[] = [];
  for (const row of rowsByKey(body)) {
    const t = timeTag(row.time_tag);
    const v = num(row.Kp ?? row.kp);
    if (t === null || v === null) continue;
    const point: KpPoint = { t, v };
    if (typeof row.observed === "string") point.kind = row.observed;
    if ("noaa_scale" in row)
      point.noaa_scale = typeof row.noaa_scale === "string" ? row.noaa_scale : null;
    out.push(point);
  }
  if (out.length === 0) throw new UpstreamError("no Kp rows");
  return out;
}

export interface Ovation {
  observation_time_utc: string | null;
  forecast_time_utc: string | null;
  /** Non-zero points only, [lon 0–359, lat, %]. */
  points: [number, number, number][];
}

export function parseOvation(body: unknown): Ovation {
  if (!isRecord(body) || !Array.isArray(body.coordinates)) {
    throw new UpstreamError("unexpected response shape");
  }
  const fmt = String(body["Data Format"] ?? "");
  if (fmt && !/^\[Longitude, Latitude, Aurora\]$/.test(fmt)) {
    throw new UpstreamError("unexpected OVATION data format");
  }
  const points: [number, number, number][] = [];
  for (const c of body.coordinates) {
    if (!Array.isArray(c)) continue;
    const [lon, lat, v] = c.map(num);
    if (lon == null || lat == null || v == null || v <= 0) continue;
    points.push([lon, lat, v]);
  }
  return {
    observation_time_utc: timeTag(body["Observation Time"]),
    forecast_time_utc: timeTag(body["Forecast Time"]),
    points,
  };
}

export const AURORA_METHOD =
  "max OVATION probability over the 1° grid points within ±1° latitude and longitude of the cell";

export function auroraNearCell(ov: Ovation, cell: Cell): number {
  const lon360 = (x: number) => ((Math.round(x) % 360) + 360) % 360;
  const lat0 = Math.round(cell.lat);
  const lon0 = lon360(cell.lon);
  const wanted = new Set<string>();
  for (let dLat = -1; dLat <= 1; dLat++) {
    for (let dLon = -1; dLon <= 1; dLon++) wanted.add(`${lon360(lon0 + dLon)},${lat0 + dLat}`);
  }
  let max = 0;
  for (const [lon, lat, v] of ov.points) if (wanted.has(`${lon},${lat}`) && v > max) max = v;
  return max;
}

const PRODUCTS = {
  kp: { url: KP_URL, source: "swpc-kp", ttl: 900, parse: parseKp },
  kp_forecast: { url: KP_FORECAST_URL, source: "swpc-kp-forecast", ttl: 1800, parse: parseKp },
  ovation: { url: OVATION_URL, source: "swpc-ovation", ttl: 600, parse: parseOvation },
} as const;

export function loadKp(
  deps: Deps,
  store: EntryStore,
  which: "kp" | "kp_forecast",
): Promise<Loaded<KpPoint[]>> {
  const p = PRODUCTS[which];
  return cachedLoad(
    deps,
    { store, source: p.source, key: `swpc:${which}`, ttlSeconds: p.ttl, timing: p.source },
    async () => ({
      data: p.parse(await getJson(deps.fetch, p.url)),
    }),
  );
}

export function loadOvation(deps: Deps, store: EntryStore): Promise<Loaded<Ovation>> {
  const p = PRODUCTS.ovation;
  return cachedLoad(
    deps,
    { store, source: p.source, key: "swpc:ovation", ttlSeconds: p.ttl, timing: p.source },
    async () => ({
      data: p.parse(await getJson(deps.fetch, p.url, 15_000)),
    }),
  );
}
