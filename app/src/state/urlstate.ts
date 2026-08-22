/**
 * Shareable URL state. Location, date, and active layers all live in the
 * hash so a pasted link reopens exactly the same view and answer.
 *
 * Format: #lat=38.53&lon=-109.90&date=2026-08-22&layers=lp,land,places
 */

export interface UrlState {
  lat: number | null;
  lon: number | null;
  /** ISO date of the local evening being planned. */
  date: string | null;
  layers: string[];
}

const LAYER_IDS = new Set(["lp", "land", "places"]);

export function parseUrlState(hash: string): UrlState {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const lat = numOrNull(params.get("lat"), -90, 90);
  const lon = numOrNull(params.get("lon"), -180, 180);
  const date = isoDateOrNull(params.get("date"));
  const layersRaw = params.get("layers") ?? "";
  const layers = layersRaw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => LAYER_IDS.has(s));
  return { lat, lon, date, layers };
}

function numOrNull(raw: string | null, min: number, max: number): number | null {
  if (raw === null) return null;
  const v = Number(raw);
  if (!Number.isFinite(v) || v < min || v > max) return null;
  return Math.round(v * 1e5) / 1e5;
}

function isoDateOrNull(raw: string | null): string | null {
  if (!raw || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const d = new Date(`${raw}T12:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : raw;
}

export function serializeUrlState(state: UrlState): string {
  const params = new URLSearchParams();
  if (state.lat !== null && state.lon !== null) {
    params.set("lat", String(state.lat));
    params.set("lon", String(state.lon));
  }
  if (state.date) params.set("date", state.date);
  if (state.layers.length) params.set("layers", [...new Set(state.layers)].join(","));
  const s = params.toString();
  return s ? `#${s}` : "#";
}

export function updateUrlState(state: UrlState): void {
  history.replaceState(null, "", serializeUrlState(state));
}
