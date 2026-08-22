"""CLI: build the land-ownership vector layer from PAD-US.

- ``build``: offline. Reads staged GeoJSON (already clipped to the AOI),
  normalizes manager taxonomy, emits vector PMTiles + taxonomy file + manifest.
  Golden tests use this path.
- ``fetch-and-build``: online; downloads and clips PAD-US via geopandas.
  Never used by CI.
"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any

import click
from pmtiles.tile import TileType

from pipelines.padus.taxonomy import normalize_manager, validate_taxonomy_keys
from pipelines.shared.config import AppConfig, load_config
from pipelines.shared.manifest import Artifact, build_manifest, sha256_file
from pipelines.shared.mvt import (
    GeometryType,
    TileBuilder,
    lonlat_to_tile_coords,
    lonlat_to_tile_xy,
    tile_bounds,
)
from pipelines.shared.tiles import Bounds, write_pmtiles

MIN_ZOOM = 6
MAX_ZOOM = 9


def _manager_of(props: dict[str, Any]) -> tuple[str, str]:
    """Return (taxonomy_key, raw_manager_label) for one PAD-US feature."""
    raw = str(props.get("Mang_Name") or props.get("raw_manager") or "Unknown")
    key = normalize_manager(
        mang_type=props.get("Mang_Type"),
        mang_name=props.get("Mang_Name"),
        category=props.get("Cat_Describe"),
    )
    return key, raw


def _bbox_of(geometry: dict[str, Any]) -> tuple[float, float, float, float]:
    xs: list[float] = []
    ys: list[float] = []

    def walk(obj: Any) -> None:
        if isinstance(obj, (list, tuple)):
            if len(obj) == 2 and all(isinstance(v, (int, float)) for v in obj):
                x, y = obj
                xs.append(float(x))
                ys.append(float(y))
                return
            for item in obj:
                walk(item)

    walk(geometry["coordinates"])
    return min(xs), min(ys), max(xs), max(ys)


def _overlaps(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def build_vector_tiles(
    geojson: dict[str, Any], app_config: AppConfig
) -> dict[tuple[int, int, int], bytes]:
    """Tile every polygon feature into XYZ tiles across the configured zooms.

    Features are emitted whole into any tile their bbox touches; coordinates
    outside a tile's 4096-unit extent are valid MVT and clipped at render
    time by MapLibre. This keeps tiling deterministic and dependency-free;
    true per-tile simplification is a documented v1 trade-off (see
    docs/methods.md).
    """
    unknown = validate_taxonomy_keys(
        app_config, {_manager_of(f["properties"])[0] for f in geojson["features"]}
    )
    if unknown:
        raise SystemExit(f"taxonomy keys missing from config: {unknown}")

    tiles: dict[tuple[int, int, int], bytes] = {}
    west, south, east, north = (
        app_config.aoi.bbox.west,
        app_config.aoi.bbox.south,
        app_config.aoi.bbox.east,
        app_config.aoi.bbox.north,
    )
    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x0, y0 = lonlat_to_tile_xy(west, north, z)
        x1, y1 = lonlat_to_tile_xy(east, south, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                tb = tile_bounds(z, x, y)
                builder = TileBuilder()
                layer = builder.layer("padus")
                fid = 0
                for feature in geojson["features"]:
                    if feature["geometry"].get("type") != "Polygon":
                        continue
                    fbox = _bbox_of(feature["geometry"])
                    if not _overlaps(fbox, tb):
                        continue
                    key, raw = _manager_of(feature["properties"])
                    rings = [
                        tuple(lonlat_to_tile_coords(lon, lat, z, x, y) for lon, lat in ring)
                        for ring in feature["geometry"]["coordinates"]
                    ]
                    layer.add_feature(
                        GeometryType.POLYGON, rings, {"manager": key, "raw": raw}, fid
                    )
                    fid += 1
                if fid:
                    tiles[(z, x, y)] = builder.encode()
    return tiles


@click.command()
@click.option("--input", "input_path", type=click.Path(exists=True, path_type=Path), required=True)
@click.option("--publication-date", type=click.DateTime(["%Y-%m-%d"]), required=True)
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True)
def build(input_path: Path, publication_date: dt.datetime, out_dir: Path) -> None:
    app_config = load_config()
    geojson: dict[str, Any] = json.loads(input_path.read_text())
    tiles = build_vector_tiles(geojson, app_config)
    if not tiles:
        raise SystemExit("no features tiled; check input coverage")

    bbox = Bounds(
        west=app_config.aoi.bbox.west,
        south=app_config.aoi.bbox.south,
        east=app_config.aoi.bbox.east,
        north=app_config.aoi.bbox.north,
    )
    pmtiles_path = out_dir / "padus.pmtiles"
    write_pmtiles(
        tiles,
        pmtiles_path,
        tile_type=TileType.MVT,
        bounds=bbox,
        attribution="PAD-US, USGS. Public domain.",
        extra_metadata={
            "vector_layers": [{"id": "padus", "fields": {"manager": "String", "raw": "String"}}]
        },
    )

    taxonomy_path = out_dir / "managers.json"
    taxonomy_path.write_text(
        json.dumps([c.model_dump() for c in app_config.manager_taxonomy], indent=2)
    )

    managers = {_manager_of(f["properties"])[0] for f in geojson["features"]}
    manifest = build_manifest(
        layer_id="land_ownership",
        source_name="USGS Protected Areas Database (PAD-US)",
        source_url="https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download",
        license="Public domain (U.S. Government work)",
        license_url="https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits",
        publication_date=publication_date.date(),
        artifacts=[
            Artifact(
                path=pmtiles_path.name,
                sha256=sha256_file(pmtiles_path),
                bytes=pmtiles_path.stat().st_size,
            ),
            Artifact(
                path=taxonomy_path.name,
                sha256=sha256_file(taxonomy_path),
                bytes=taxonomy_path.stat().st_size,
            ),
        ],
        counts={
            "tiles": len(tiles),
            "features": len(geojson["features"]),
            "manager_classes": len(managers),
        },
        now_utc=dt.datetime.now(dt.UTC),
    )
    manifest.write(out_dir)
    click.echo(f"OK: {len(tiles)} tiles -> {pmtiles_path}")


if __name__ == "__main__":
    build()
