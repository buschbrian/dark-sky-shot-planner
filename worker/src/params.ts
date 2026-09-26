/** Request validation. ADR-0010 point 2: coordinates must already be on the 0.05° grid. */

export const GRID_DEG = 0.05;
export const MAX_WINDOW_HOURS = 48;
const HOUR_MS = 3_600_000;

export class BadRequest extends Error {}

export interface Cell {
  lat: number;
  lon: number;
  rounding_deg: number;
}

export interface Window {
  start: Date;
  end: Date;
  /** UTC calendar dates the window touches, for date-keyed upstream requests. */
  startDate: string;
  endDate: string;
}

export function gridCoord(raw: string | null, name: string, limit: number): number {
  if (raw === null || raw.trim() === "") throw new BadRequest(`${name} is required`);
  const x = Number(raw);
  if (!Number.isFinite(x) || Math.abs(x) > limit) throw new BadRequest(`${name} is out of range`);
  const steps = Math.round(x / GRID_DEG);
  if (Math.abs(steps * GRID_DEG - x) > 1e-9) {
    throw new BadRequest(
      `${name} must be rounded to the ${GRID_DEG}° grid before it leaves the device (ADR-0010)`,
    );
  }
  return Number((steps * GRID_DEG).toFixed(2));
}

export function parseCell(params: URLSearchParams): Cell {
  return {
    lat: gridCoord(params.get("lat"), "lat", 90),
    lon: gridCoord(params.get("lon"), "lon", 180),
    rounding_deg: GRID_DEG,
  };
}

/** Optional cell: both or neither. */
export function parseOptionalCell(params: URLSearchParams): Cell | null {
  if (!params.has("lat") && !params.has("lon")) return null;
  return parseCell(params);
}

function parseInstant(raw: string | null, name: string): Date {
  if (!raw) throw new BadRequest(`${name} is required`);
  if (!/(Z|[+-]\d{2}:?\d{2})$/.test(raw)) throw new BadRequest(`${name} must carry a UTC offset`);
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) throw new BadRequest(`${name} is not a valid time`);
  return d;
}

export function parseWindow(params: URLSearchParams, now: Date): Window {
  const rawStart = parseInstant(params.get("start"), "start");
  const rawEnd = parseInstant(params.get("end"), "end");
  const start = new Date(Math.floor(rawStart.getTime() / HOUR_MS) * HOUR_MS);
  const end = new Date(Math.ceil(rawEnd.getTime() / HOUR_MS) * HOUR_MS);
  if (end <= start) throw new BadRequest("end must be after start");
  if (end.getTime() - start.getTime() > MAX_WINDOW_HOURS * HOUR_MS) {
    throw new BadRequest(`window is limited to ${MAX_WINDOW_HOURS} hours`);
  }
  if (start.getTime() < now.getTime() - 2 * 86_400_000) {
    throw new BadRequest("start is more than 2 days in the past");
  }
  if (end.getTime() > now.getTime() + 16 * 86_400_000) {
    throw new BadRequest("end is beyond the 16-day forecast horizon");
  }
  const day = (d: Date) => d.toISOString().slice(0, 10);
  return { start, end, startDate: day(start), endDate: day(new Date(end.getTime() - 1)) };
}

export type Bbox = [number, number, number, number];

export function parseBbox(params: URLSearchParams): Bbox {
  const raw = params.get("bbox");
  if (!raw) throw new BadRequest("bbox is required (minLon,minLat,maxLon,maxLat)");
  const parts = raw.split(",");
  if (parts.length !== 4) throw new BadRequest("bbox must have four numbers");
  const [w, s, e, n] = [
    gridCoord(parts[0] ?? null, "bbox minLon", 180),
    gridCoord(parts[1] ?? null, "bbox minLat", 90),
    gridCoord(parts[2] ?? null, "bbox maxLon", 180),
    gridCoord(parts[3] ?? null, "bbox maxLat", 90),
  ];
  if (e <= w || n <= s) throw new BadRequest("bbox must have min < max");
  if (e - w > 30 || n - s > 20) throw new BadRequest("bbox is limited to 30° × 20°");
  return [w, s, e, n];
}

export const cellKey = (c: Cell): string => `${c.lat.toFixed(2)},${c.lon.toFixed(2)}`;

export function inWindow(t: string, w: Window): boolean {
  const ms = Date.parse(t);
  return ms >= w.start.getTime() && ms <= w.end.getTime();
}
