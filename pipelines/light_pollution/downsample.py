"""Downsample a staged radiance grid to a fixed lat/lon step.

The low-resolution grid is what the client samples to answer "how dark is
this spot?" without pulling raster tiles. Nearest-neighbor sampling keeps it
deterministic and dependency-free.
"""

from __future__ import annotations

import math
from typing import Any

from pipelines.light_pollution.rasterize import Grid


def downsample_grid(grid: Grid, step_deg: float = 0.25) -> dict[str, Any]:
    """Resample onto a regular ``step_deg`` lattice covering the grid bbox."""
    values = grid["values"]
    n_rows, n_cols = len(values), len(values[0])
    lon0, lon1 = grid["west"], grid["east"]
    lat0, lat1 = grid["south"], grid["north"]

    n_out_cols = max(2, int(math.floor((lon1 - lon0) / step_deg)) + 1)
    n_out_rows = max(2, int(math.floor((lat1 - lat0) / step_deg)) + 1)

    out: list[list[float]] = []
    for r in range(n_out_rows):
        lat = lat1 - r * (lat1 - lat0) / (n_out_rows - 1)
        src_r = min(n_rows - 1, max(0, int((lat1 - lat) / (lat1 - lat0) * n_rows)))
        row: list[float] = []
        for c in range(n_out_cols):
            lon = lon0 + c * (lon1 - lon0) / (n_out_cols - 1)
            src_c = min(n_cols - 1, max(0, int((lon - lon0) / (lon1 - lon0) * n_cols)))
            row.append(round(values[src_r][src_c], 4))
        out.append(row)

    return {
        "step_deg": step_deg,
        "west": lon0,
        "south": lat0,
        "east": lon1,
        "north": lat1,
        "rows": out,
    }
