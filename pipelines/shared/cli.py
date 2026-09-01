"""CLI: publish the client-facing app config.

The browser reads every threshold, breakpoint, and taxonomy label from
``config.json`` instead of hardcoding them (ADR 0004, 0005, 0006). That file
is derived from ``config/app-config.json`` and has to be published next to the
layer artifacts: the client fetches it during boot, so a site without it is a
site that cannot start.
"""

from __future__ import annotations

import json
from pathlib import Path

import click

from pipelines.shared.config import load_config


@click.command()
@click.option(
    "--config",
    "config_path",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    default=None,
    help="Source config; defaults to config/app-config.json.",
)
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True)
def publish_config(config_path: Path | None, out_dir: Path) -> None:
    """Validate config/app-config.json and write it to ``<out>/config.json``."""
    app_config = load_config(config_path)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "config.json"
    out_path.write_text(json.dumps(app_config.to_client_json(), indent=2) + "\n")
    click.echo(f"OK: client config -> {out_path}")


if __name__ == "__main__":
    publish_config()
