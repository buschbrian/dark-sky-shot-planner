"""Single source of truth for pipeline configuration.

Everything a maintainer might want to change without touching code lives
here: the area of interest, freshness thresholds, radiance display mapping,
and the land-manager taxonomy. The client reads the emitted manifests and
config JSON; it must never hardcode these values itself.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


class BoundingBox(BaseModel):
    """WGS84 bounding box: west, south, east, north."""

    west: float = Field(ge=-180, le=180)
    south: float = Field(ge=-90, le=90)
    east: float = Field(ge=-180, le=180)
    north: float = Field(ge=-90, le=90)


class Aoi(BaseModel):
    """Area of interest. Extending coverage later is an edit here, not code."""

    name: str
    states: list[str]
    bbox: BoundingBox


class FreshnessThresholds(BaseModel):
    """Uniform freshness convention applied to every layer.

    fresh / aging / stale / unavailable — defined once here and used by both
    pipelines (when stamping manifests) and the client (when rendering age).
    Values are in days relative to the source publication date.
    """

    fresh_max_days: int
    aging_max_days: int
    stale_max_days: int  # beyond this -> "stale"; missing data -> "unavailable"


class LayerFreshness(FreshnessThresholds):
    layer_id: str


class RadianceBreakpoint(BaseModel):
    """A stop in the radiance-to-display mapping.

    ``radiance`` is VNP46A4 radiance in nW/cm2/sr. ``color`` is the legend /
    tile color at that point, ``label`` is the human-readable class name.
    """

    radiance: float
    color: str
    label: str


class RadianceMapping(BaseModel):
    """Documented radiance-to-display mapping shared by tiles and legend.

    Breakpoints are in ascending radiance order. The ramp is piecewise-linear
    between breakpoints; values below the first breakpoint clamp to it.
    """

    source: str
    source_year: int
    unit: str
    breakpoints: list[RadianceBreakpoint]


class ManagerClass(BaseModel):
    """One normalized land-manager category for the PAD-US taxonomy."""

    key: str
    label: str
    color: str


class AppConfig(BaseModel):
    version: int
    aoi: Aoi
    gc_min_useful_altitude_deg: float
    freshness_days: dict[str, FreshnessThresholds]
    radiance_mapping: RadianceMapping
    manager_taxonomy: list[ManagerClass]

    def to_client_json(self) -> dict[str, Any]:
        """The exact JSON shape published as ``data/config.json``."""
        return self.model_dump(mode="json")


def load_config(path: Path | None = None) -> AppConfig:
    if path is None:
        path = Path(__file__).resolve().parents[2] / "config" / "app-config.json"
    return AppConfig.model_validate(json.loads(path.read_text()))
