"""Shared pytest fixtures."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from pipelines.shared.config import AppConfig, load_config

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture()
def app_config() -> AppConfig:
    return load_config()


@pytest.fixture()
def radiance_grid() -> dict[str, Any]:
    return json.loads((FIXTURES / "radiance-grid.json").read_text())


@pytest.fixture()
def padus_geojson() -> dict[str, Any]:
    return json.loads((FIXTURES / "padus-sample.geojson").read_text())
