"""CLI: build the light-pollution raster layer.

Two paths:
- ``build``: offline. Reads a staged radiance grid (JSON, rows north->south)
  and emits PMTiles + legend + manifest. Golden tests use this path.
- ``fetch-and-build``: online. Downloads VNP46A4 via blackmarblepy (requires
  NASA Earthdata credentials in the environment), stages a grid JSON, then
  delegates to ``build``. Never used by CI.
"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

import click
from pmtiles.tile import TileType

from pipelines.light_pollution.downsample import downsample_grid
from pipelines.light_pollution.radiance import legend_stops
from pipelines.light_pollution.rasterize import Grid, render_tile, tiles_for_bbox
from pipelines.shared.config import load_config
from pipelines.shared.manifest import Artifact, build_manifest, sha256_file
from pipelines.shared.tiles import Bounds, write_pmtiles


@click.command()
@click.option(
    "--grid",
    "grid_path",
    type=click.Path(exists=True, path_type=Path),
    required=True,
    help="Staged radiance grid JSON (see fetch-and-build).",
)
@click.option("--publication-date", type=click.DateTime(["%Y-%m-%d"]), required=True)
@click.option("--min-zoom", default=5, show_default=True)
@click.option("--max-zoom", default=8, show_default=True)
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True)
def build(
    grid_path: Path,
    publication_date: dt.datetime,
    min_zoom: int,
    max_zoom: int,
    out_dir: Path,
) -> None:
    app_config = load_config()
    grid: Grid = json.loads(grid_path.read_text())
    bbox = Bounds(west=grid["west"], south=grid["south"], east=grid["east"], north=grid["north"])

    tiles = {
        key: render_tile(grid, key, app_config) for key in tiles_for_bbox(bbox, min_zoom, max_zoom)
    }
    pmtiles_path = out_dir / "light-pollution.pmtiles"
    write_pmtiles(
        tiles,
        pmtiles_path,
        tile_type=TileType.PNG,
        bounds=bbox,
        attribution=f"VIIRS VNP46A4 ({app_config.radiance_mapping.source_year})",
        extra_metadata={"source_year": app_config.radiance_mapping.source_year},
    )

    legend = [
        {"radiance": bp.radiance, "color": bp.color, "label": bp.label}
        for bp in legend_stops(app_config.radiance_mapping)
    ]
    legend_path = out_dir / "legend.json"
    legend_path.write_text(json.dumps(legend, indent=2))

    # Downsampled radiance grid for client-side point lookups ("how dark is
    # this spot?"). Small enough to ship as JSON; carries the same source
    # year so the UI labels staleness honestly.
    grid_out_path = out_dir / "radiance-grid-lowres.json"
    lowres = downsample_grid(grid, step_deg=0.25)
    grid_out_path.write_text(json.dumps(lowres))

    manifest = build_manifest(
        layer_id="light_pollution",
        source_name="VIIRS VNP46A4 Black Marble annual composite",
        source_url="https://ladsweb.modaps.eosdis.nasa.gov/",
        license="CC0 1.0",
        license_url="https://creativecommons.org/publicdomain/zero/1.0/",
        publication_date=publication_date.date(),
        artifacts=[
            Artifact(
                path=pmtiles_path.name,
                sha256=sha256_file(pmtiles_path),
                bytes=pmtiles_path.stat().st_size,
            ),
            Artifact(
                path=legend_path.name,
                sha256=sha256_file(legend_path),
                bytes=legend_path.stat().st_size,
            ),
            Artifact(
                path=grid_out_path.name,
                sha256=sha256_file(grid_out_path),
                bytes=grid_out_path.stat().st_size,
            ),
        ],
        counts={"tiles": len(tiles), "breakpoints": len(legend)},
        now_utc=dt.datetime.now(dt.UTC),
    )
    manifest.write(out_dir)
    click.echo(f"OK: {len(tiles)} tiles -> {pmtiles_path}")


@click.command()
@click.option("--year", type=int, required=True, help="Composite year, e.g. 2024.")
@click.option("--out", "stage_dir", type=click.Path(path_type=Path), required=True)
def fetch_and_build(year: int, stage_dir: Path) -> None:
    try:
        from pipelines.light_pollution.fetch import stage_grid_from_blackmarble
    except ImportError as exc:
        raise SystemExit(f"fetch extras not installed (pip install .[fetch]): {exc}") from exc
    app_config = load_config()
    grid = stage_grid_from_blackmarble(year, app_config.aoi.bbox)
    stage_dir.mkdir(parents=True, exist_ok=True)
    grid_path = stage_dir / "staged-grid.json"
    grid_path.write_text(json.dumps(grid))
    click.echo(f"staged {grid_path}; now run build --grid {grid_path} ...")


@click.group()
def cli() -> None:
    """Light-pollution layer pipeline."""


cli.add_command(build)
cli.add_command(fetch_and_build)

if __name__ == "__main__":
    cli()
