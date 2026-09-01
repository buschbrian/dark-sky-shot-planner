"""The client cannot boot without config.json, so publishing it is a guarded step.

app/src/main.ts fetches ``/config.json`` during boot and reads thresholds,
radiance breakpoints, and the manager taxonomy from it. Nothing published that
file for the first six weeks of the project's life, which left every CI e2e run
testing an app that had aborted its own initialization. This test keeps the
publisher wired to the shape the client actually reads.
"""

from __future__ import annotations

import json
from pathlib import Path

from click.testing import CliRunner

from pipelines.shared.cli import publish_config
from pipelines.shared.config import AppConfig

# Layer ids the provenance table in app/src/main.ts looks up by name.
CLIENT_FRESHNESS_LAYERS = ["light_pollution", "land_ownership", "darksky_places"]


def publish(tmp_path: Path) -> dict[str, object]:
    result = CliRunner().invoke(publish_config, ["--out", str(tmp_path)])
    assert result.exit_code == 0, result.output
    published = tmp_path / "config.json"
    assert published.exists(), "the client fetches /config.json; it must be published"
    return json.loads(published.read_text())


def test_publishes_config_json(tmp_path: Path) -> None:
    data = publish(tmp_path)
    # Round-trips through the same model the pipelines validate against.
    AppConfig.model_validate(data)


def test_published_config_carries_every_field_the_client_reads(tmp_path: Path) -> None:
    data = publish(tmp_path)
    assert isinstance(data["gc_min_useful_altitude_deg"], (int, float))

    freshness = data["freshness_days"]
    assert isinstance(freshness, dict)
    for layer_id in CLIENT_FRESHNESS_LAYERS:
        assert layer_id in freshness, f"client renders a freshness row for {layer_id}"

    radiance_mapping = data["radiance_mapping"]
    assert isinstance(radiance_mapping, dict)
    assert isinstance(radiance_mapping["source_year"], int)
    breakpoints = radiance_mapping["breakpoints"]
    assert isinstance(breakpoints, list) and breakpoints
    assert all({"radiance", "color", "label"} <= set(bp) for bp in breakpoints)

    taxonomy = data["manager_taxonomy"]
    assert isinstance(taxonomy, list) and taxonomy
    assert all({"key", "label", "color"} <= set(cls) for cls in taxonomy)
