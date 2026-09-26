import { assertNoArcgisError, getJson, isRecord, UpstreamError } from "../http.ts";
import type { Bbox } from "../params.ts";
import { cachedLoad, edgeStore } from "../store.ts";
import type { Deps } from "../types.ts";

export const HMS_LAYER =
  "https://services2.arcgis.com/C8EMgrsFcRFL6LrL/arcgis/rest/services/NOAA_Satellite_Smoke_Detection_(v1)/FeatureServer/0";
export const HMS_SOURCE = "NOAA NESDIS Hazard Mapping System (HMS) smoke analysis";
export const HMS_NOTE =
  "Analyst-drawn from daytime satellite imagery; at night it shows the previous afternoon.";

type Ring = [number, number][];

const STATS = encodeURIComponent(
  JSON.stringify([
    { statisticType: "max", onStatisticField: "End_", outStatisticFieldName: "latest_end" },
    { statisticType: "min", onStatisticField: "Start", outStatisticFieldName: "earliest_start" },
  ]),
);
type Geometry =
  | { type: "Polygon"; coordinates: Ring[] }
  | { type: "MultiPolygon"; coordinates: Ring[][] };

export interface SmokeFeature {
  type: "Feature";
  properties: {
    density: string | null;
    satellite: string | null;
    start_utc: string | null;
    end_utc: string | null;
  };
  geometry: Geometry;
}

export interface HmsResult {
  features: SmokeFeature[];
  truncated: boolean;
  /** Latest analysis end across the whole dataset, so an empty bbox still has a time. */
  analysis_end_utc: string | null;
  analysis_start_utc: string | null;
}

/** HMS times are "YYYYDDD HHMM" (day of year), UTC. */
export function hmsTime(x: unknown): string | null {
  const m = typeof x === "string" ? /^(\d{4})(\d{3}) (\d{2})(\d{2})$/.exec(x.trim()) : null;
  if (!m) return null;
  const ms = Date.UTC(Number(m[1]), 0, Number(m[2]), Number(m[3]), Number(m[4]));
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Sutherland–Hodgman against the bbox; the clip region is convex, so one pass per edge. */
export function clipRing(ring: Ring, [w, s, e, n]: Bbox): Ring | null {
  const edges: [
    (p: [number, number]) => boolean,
    (a: [number, number], b: [number, number]) => [number, number],
  ][] = [
    [(p) => p[0] >= w, (a, b) => [w, a[1] + ((b[1] - a[1]) * (w - a[0])) / (b[0] - a[0])]],
    [(p) => p[0] <= e, (a, b) => [e, a[1] + ((b[1] - a[1]) * (e - a[0])) / (b[0] - a[0])]],
    [(p) => p[1] >= s, (a, b) => [a[0] + ((b[0] - a[0]) * (s - a[1])) / (b[1] - a[1]), s]],
    [(p) => p[1] <= n, (a, b) => [a[0] + ((b[0] - a[0]) * (n - a[1])) / (b[1] - a[1]), n]],
  ];
  let pts: [number, number][] = ring.slice(0, -1);
  for (const [inside, cross] of edges) {
    const next: [number, number][] = [];
    pts.forEach((cur, i) => {
      const prev = pts[(i + pts.length - 1) % pts.length]!;
      if (inside(cur)) {
        if (!inside(prev)) next.push(cross(prev, cur));
        next.push(cur);
      } else if (inside(prev)) {
        next.push(cross(prev, cur));
      }
    });
    pts = next;
    if (pts.length === 0) return null;
  }
  const r = (x: number) => Math.round(x * 1e4) / 1e4;
  const out = pts.map(([x, y]) => [r(x), r(y)] as [number, number]);
  if (new Set(out.map((p) => p.join())).size < 3) return null;
  out.push(out[0]!);
  return out;
}

function clipPolygon(rings: Ring[], bbox: Bbox): Ring[] | null {
  const [outer, ...holes] = rings;
  const clippedOuter = outer ? clipRing(outer, bbox) : null;
  if (!clippedOuter) return null;
  const clippedHoles = holes.map((h) => clipRing(h, bbox)).filter((h): h is Ring => h !== null);
  return [clippedOuter, ...clippedHoles];
}

export function clipGeometry(g: unknown, bbox: Bbox): Geometry | null {
  if (!isRecord(g) || !Array.isArray(g.coordinates)) return null;
  if (g.type === "Polygon") {
    const c = clipPolygon(g.coordinates as Ring[], bbox);
    return c ? { type: "Polygon", coordinates: c } : null;
  }
  if (g.type === "MultiPolygon") {
    const parts = (g.coordinates as Ring[][])
      .map((p) => clipPolygon(p, bbox))
      .filter((p): p is Ring[] => p !== null);
    if (parts.length === 0) return null;
    return parts.length === 1
      ? { type: "Polygon", coordinates: parts[0]! }
      : { type: "MultiPolygon", coordinates: parts };
  }
  return null;
}

export function parseHmsStats(body: unknown): { start: string | null; end: string | null } {
  assertNoArcgisError(body);
  const a =
    isRecord(body) && Array.isArray(body.features) && isRecord(body.features[0])
      ? body.features[0].attributes
      : null;
  if (!isRecord(a)) throw new UpstreamError("unexpected statistics shape");
  return { start: hmsTime(a.earliest_start), end: hmsTime(a.latest_end) };
}

export function parseHms(
  body: unknown,
  bbox: Bbox,
): Omit<HmsResult, "analysis_end_utc" | "analysis_start_utc"> {
  assertNoArcgisError(body);
  if (!isRecord(body) || !Array.isArray(body.features)) {
    throw new UpstreamError("unexpected response shape");
  }
  const features: SmokeFeature[] = [];
  for (const f of body.features) {
    if (!isRecord(f)) continue;
    const geometry = clipGeometry(f.geometry, bbox);
    if (!geometry) continue;
    const p = isRecord(f.properties) ? f.properties : {};
    features.push({
      type: "Feature",
      properties: {
        density: typeof p.Density === "string" ? p.Density : null,
        satellite: typeof p.Satellite === "string" ? p.Satellite : null,
        start_utc: hmsTime(p.Start),
        end_utc: hmsTime(p.End_),
      },
      geometry,
    });
  }
  const truncated =
    body.exceededTransferLimit === true ||
    (isRecord(body.properties) && body.properties.exceededTransferLimit === true);
  return { features, truncated };
}

export async function smokePolygons(deps: Deps, bbox: Bbox): Promise<Record<string, unknown>> {
  const url =
    `${HMS_LAYER}/query?where=1%3D1&outFields=Satellite,Start,End_,Density` +
    `&geometry=${bbox.join(",")}&geometryType=esriGeometryEnvelope&inSR=4326` +
    "&spatialRel=esriSpatialRelIntersects&outSR=4326&geometryPrecision=4&f=geojson";
  const loaded = await cachedLoad(
    deps,
    { store: edgeStore(deps), source: "hms", key: `hms:${bbox.join(",")}`, ttlSeconds: 900 },
    async () => {
      const [features, stats] = await Promise.all([
        getJson(deps.fetch, url),
        getJson(deps.fetch, `${HMS_LAYER}/query?where=1%3D1&outStatistics=${STATS}&f=json`),
      ]);
      const { start, end } = parseHmsStats(stats);
      return {
        data: { ...parseHms(features, bbox), analysis_start_utc: start, analysis_end_utc: end },
      };
    },
  );
  const base = { type: "FeatureCollection", bbox, source: HMS_SOURCE, note: HMS_NOTE };
  const analysis = (r: HmsResult) => ({
    analysis_start_utc: r.analysis_start_utc,
    analysis_time_utc: r.analysis_end_utc,
    analysis_date: r.analysis_end_utc?.slice(0, 10) ?? null,
  });
  if (!loaded.ok) {
    const lg = loaded.last_good;
    return {
      ...base,
      status: "unavailable",
      reason: loaded.reason,
      fetched_utc: null,
      last_good_utc: lg?.fetched_utc ?? null,
      ...(lg
        ? analysis(lg.data)
        : { analysis_start_utc: null, analysis_time_utc: null, analysis_date: null }),
      truncated: lg?.data.truncated ?? false,
      features: lg?.data.features ?? [],
    };
  }
  const r = loaded.entry.data;
  return {
    ...base,
    status: "ok",
    fetched_utc: loaded.entry.fetched_utc,
    ...analysis(r),
    truncated: r.truncated,
    features: r.features,
  };
}
