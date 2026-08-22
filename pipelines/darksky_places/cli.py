"""CLI: build the dark-sky places layer from the curated CSV.

Fully offline — the input is a hand-curated file in this repository and no
network access or credentials are ever involved.
"""

from __future__ import annotations

import datetime as dt
from pathlib import Path

import click

from pipelines.darksky_places.places import emit_geojson, load_places
from pipelines.shared.manifest import Artifact, build_manifest, sha256_file


@click.command()
@click.option("--csv", "csv_path", type=click.Path(exists=True, path_type=Path), required=True)
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True)
def build(csv_path: Path, out_dir: Path) -> None:
    places, report = load_places(csv_path)
    if report.errors:
        for err in report.errors:
            click.echo(f"ERROR: {err}", err=True)
        raise SystemExit(1)

    geojson_path = out_dir / "darksky-places.geojson"
    count = emit_geojson(places, geojson_path)
    csv_copy = out_dir / "darksky-places.source.csv"
    csv_copy.write_text(csv_path.read_text())

    manifest = build_manifest(
        layer_id="darksky_places",
        source_name="International Dark Sky Places (hand-curated)",
        source_url="https://darksky.org/places/",
        license="Factual list; curated by hand with per-row sources",
        license_url="https://darksky.org/places/",
        publication_date=None,
        artifacts=[
            Artifact(
                path=geojson_path.name,
                sha256=sha256_file(geojson_path),
                bytes=geojson_path.stat().st_size,
            ),
            Artifact(
                path=csv_copy.name, sha256=sha256_file(csv_copy), bytes=csv_copy.stat().st_size
            ),
        ],
        counts={"places": count},
        now_utc=dt.datetime.now(dt.UTC),
    )
    manifest.write(out_dir)
    click.echo(f"OK: {count} places -> {geojson_path}")


@click.group()
def cli() -> None:
    """Dark-sky places layer pipeline."""


cli.add_command(build)

if __name__ == "__main__":
    cli()
