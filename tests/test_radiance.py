from __future__ import annotations

import pytest

from pipelines.light_pollution.radiance import (
    classify_radiance,
    legend_stops,
    radiance_to_color,
)


def test_dark_end_clamps_to_first_breakpoint(app_config) -> None:
    m = app_config.radiance_mapping
    assert radiance_to_color(0.0, m) == "#000005"
    assert radiance_to_color(-5.0, m) == "#000005"


def test_bright_end_clamps_to_last_breakpoint(app_config) -> None:
    m = app_config.radiance_mapping
    assert radiance_to_color(1000.0, m) == "#ffffff"


def test_midpoint_interpolates_linearly(app_config) -> None:
    m = app_config.radiance_mapping
    # halfway between 0.0 (#000005) and 0.25 (#0d1338)
    color = radiance_to_color(0.125, m)
    assert color == "#060a1e"


def test_classification_boundaries(app_config) -> None:
    m = app_config.radiance_mapping
    assert classify_radiance(0.0, m) == "Pristine dark sky"
    assert classify_radiance(0.25, m) == "Dark"
    assert classify_radiance(19.9, m) == "Bright fringe"
    assert classify_radiance(20.0, m) == "Suburban"


def test_legend_is_ascending(app_config) -> None:
    stops = legend_stops(app_config.radiance_mapping)
    radiances = [s.radiance for s in stops]
    assert radiances == sorted(radiances)


@pytest.mark.parametrize(
    ("radiance", "expected"),
    [(0.0625, "#030512"), (2.5, "#374687"), (12.5, "#7796c6")],
)
def test_known_interpolation_points(radiance: float, expected: str, app_config) -> None:
    assert radiance_to_color(radiance, app_config.radiance_mapping) == expected
