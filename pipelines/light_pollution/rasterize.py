"""Radiance grid -> Web Mercator raster tiles.

The input is a regular lat/lon grid of VNP46A4 radiance values (rows ordered
north to south) covering a WGS84 bounding box. Each output tile pixel is
sampled at its tile-pixel center (nearest neighbor — appropriate because the
display mapping is categorical in appearance, and it is deterministic).

Pure Python: no numpy, no GDAL. The heavy GeoTIFF ingestion lives in
``fetch.py``; this module works from any array you hand it.
"""

from __future__ import annotations

import math
from typing import TypedDict

from pipelines.light_pollution.png import encode_png_rgb
from pipelines.light_pollution.radiance import radiance_to_color
from pipelines.shared.config import AppConfig
from pipelines.shared.tiles import Bounds

TileKey = tuple[int, int, int]
TILE_SIZE = 256


class Grid(TypedDict):
    """A radiance grid: values[row][col], row 0 = north edge."""

    values: list[list[float]]
    west: float
    south: float
    east: float
    north: float


def _lon_to_col(lon: float, grid: Grid) -> float:
    return (lon - grid["west"]) / (grid["east"] - grid["west"]) * len(grid["values"][0])


def _lat_to_row(lat: float, grid: Grid) -> float:
    return (grid["north"] - lat) / (grid["north"] - grid["south"]) * len(grid["values"])


def _tile_pixel_lonlat(z: int, x: int, y: int, px: float, py: float) -> tuple[float, float]:
    """WGS84 lon/lat of a fractional pixel position within an XYZ tile."""
    world_px = TILE_SIZE * 2**z
    lon = ((x * TILE_SIZE + px) / world_px) * 360.0 - 180.0
    n = math.pi * (1 - 2 * (y * TILE_SIZE + py) / world_px)
    lat = math.degrees(math.atan(math.sinh(n)))
    return lon, lat


def render_tile(grid: Grid, key: TileKey, app_config: AppConfig) -> bytes:
    z, x, y = key
    mapping = app_config.radiance_mapping
    pixels: list[list[tuple[int, int, int]]] = []
    step = 0.5
    for row_px in range(TILE_SIZE):
        row_colors: list[tuple[int, int, int]] = []
        for col_px in range(TILE_SIZE):
            lon, lat = _tile_pixel_lonlat(z, x, y, col_px + step, row_px + step)
            col_f = _lon_to_col(lon, grid)
            row_f = _lat_to_row(lat, grid)
            ci = min(max(int(col_f), 0), len(grid["values"][0]) - 1)
            ri = min(max(int(row_f), 0), len(grid["values"]) - 1)
            radiance = grid["values"][ri][ci]
            hex_color = radiance_to_color(radiance, mapping)
            row_colors.append(
                (int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16))
            )
        pixels.append(row_colors)
    return encode_png_rgb(TILE_SIZE, TILE_SIZE, pixels)


def tiles_for_bbox(bbox: Bounds, min_zoom: int, max_zoom: int) -> list[TileKey]:
    """All XYZ keys intersecting the bbox for the zoom range."""
    import math as m

    def lon_to_x(lon: float, z: int) -> int:
        return int(((lon + 180.0) / 360.0) * 2**z)

    def lat_to_y(lat: float, z: int) -> int:
        rad = m.radians(max(min(lat, 85.05112878), -85.05112878))
        return int((1 - m.log(m.tan(rad) + 1 / m.cos(rad)) / m.pi) / 2 * 2**z)

    keys: list[TileKey] = []
    for z in range(min_zoom, max_zoom + 1):
        x0, x1 = lon_to_x(bbox["west"], z), lon_to_x(bbox["east"], z)
        y0, y1 = lat_to_y(bbox["north"], z), lat_to_y(bbox["south"], z)
        n = 2**z - 1
        for x in range(x0, min(x1, n) + 1):
            for y in range(max(y0, 0), min(y1, n) + 1):
                keys.append((z, x, y))
    return keys
