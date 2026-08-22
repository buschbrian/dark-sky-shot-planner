/**
 * Point lookup against the pipeline-emitted low-res radiance grid, plus the
 * shared color ramp so labels match the legend exactly.
 */

import type { AppConfigJson } from "./config";

export interface LowResGrid {
  step_deg: number;
  west: number;
  south: number;
  east: number;
  north: number;
  rows: number[][];
}

export interface RadianceAtPoint {
  value: number | null;
  label: string;
}

export function sampleRadiance(grid: LowResGrid, lat: number, lon: number): number | null {
  if (
    lat > grid.north ||
    lat < grid.south ||
    lon < grid.west ||
    lon > grid.east ||
    grid.rows.length === 0
  ) {
    return null;
  }
  const nRows = grid.rows.length;
  const nCols = grid.rows[0]!.length;
  const r = Math.round(((grid.north - lat) / (grid.north - grid.south)) * (nRows - 1));
  const c = Math.round(((lon - grid.west) / (grid.east - grid.west)) * (nCols - 1));
  return grid.rows[Math.min(Math.max(r, 0), nRows - 1)]?.[Math.min(Math.max(c, 0), nCols - 1)] ?? null;
}

export function classifyRadiance(radiance: number, config: AppConfigJson): string {
  let label = config.radiance_mapping.breakpoints[0]!.label;
  for (const bp of config.radiance_mapping.breakpoints) {
    if (radiance >= bp.radiance) label = bp.label;
  }
  return label;
}
