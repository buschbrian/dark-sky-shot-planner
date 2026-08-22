"""Tile assembly helpers shared by raster and vector pipelines.

Wraps the official ``pmtiles`` writer so each pipeline just supplies a dict
of ``{(z, x, y): bytes}`` in final wire format plus metadata.
"""

from __future__ import annotations

import gzip
from pathlib import Path
from typing import TypedDict

from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer

TileKey = tuple[int, int, int]


class Bounds(TypedDict):
    west: float
    south: float
    east: float
    north: float


def write_pmtiles(
    tiles: dict[TileKey, bytes],
    out_path: Path,
    *,
    tile_type: TileType,
    bounds: Bounds,
    attribution: str,
    extra_metadata: dict[str, object] | None = None,
) -> Path:
    """Write a PMTiles v3 archive.

    Vector (MVT) tiles are gzip-compressed here and declared as such; PNG
    raster tiles are stored uncompressed.
    """
    if not tiles:
        raise ValueError("refusing to write an empty tile archive")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    zs = [z for z, _, _ in tiles]
    min_zoom, max_zoom = min(zs), max(zs)

    with out_path.open("wb") as fh:
        writer = Writer(fh)
        for key in sorted(tiles):
            blob = tiles[key]
            if tile_type == TileType.MVT:
                blob = gzip.compress(blob)
            writer.write_tile(zxy_to_tileid(*key), blob)
        header = {
            "spec_version": 3,
            "internal_compression": Compression.GZIP,
            "tile_compression": (
                Compression.GZIP if tile_type == TileType.MVT else Compression.NONE
            ),
            "tile_type": tile_type,
            "min_zoom": min_zoom,
            "max_zoom": max_zoom,
            "min_lon_e7": round(bounds["west"] * 10_000_000),
            "min_lat_e7": round(bounds["south"] * 10_000_000),
            "max_lon_e7": round(bounds["east"] * 10_000_000),
            "max_lat_e7": round(bounds["north"] * 10_000_000),
        }
        metadata = {
            "name": out_path.stem,
            "minzoom": min_zoom,
            "maxzoom": max_zoom,
            "bounds": [bounds["west"], bounds["south"], bounds["east"], bounds["north"]],
            "attribution": attribution,
            **(extra_metadata or {}),
        }
        writer.finalize(header, metadata)
    return out_path


def web_mercator_pixel_bounds(*, z: int, x: int, y: int) -> tuple[float, float, float, float]:
    """Return (west, south, east, north) WGS84 bounds of an XYZ tile."""
    n = 2**z
    west = x / n * 360.0 - 180.0
    east = (x + 1) / n * 360.0 - 180.0

    def _lat(yv: float) -> float:
        import math

        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * yv / n))))

    return west, _lat(y + 1), east, _lat(y)
