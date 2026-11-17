"""Product/year fallback and tile mosaicking for the Black Marble fetch (ADR-0012).

Offline: the LAADS listing and the per-product fetchers are stubbed, and the
mosaic window math is pure integer arithmetic.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from click.testing import CliRunner

from pipelines.light_pollution.cli import build
from pipelines.light_pollution.fetch import (
    aoi_pixel_bounds,
    choose_and_stage,
    required_tiles,
    tile_window,
)
from pipelines.shared.config import BoundingBox

AOI = BoundingBox(west=-120.0, south=31.3, east=-102.0, north=49.1)
AOI_TILES = {"h06v04", "h06v05", "h07v04", "h07v05"}


def _listing(available: dict[tuple[str, int], set[str]]) -> Any:
    def list_files(product: str, year: int, _bbox: BoundingBox) -> list[dict[str, Any]]:
        return [
            {"name": f"{product}.A{year}001.{t}.002.2026072180242.h5", "downloadsLink": t}
            for t in sorted(available.get((product, year), set()))
        ]

    return list_files


def _fetchers(calls: list[tuple[str, int, int]]) -> dict[str, Any]:
    def make(product: str) -> Any:
        def fetch(year: int, _bbox: BoundingBox, files: list[dict[str, Any]]) -> dict[str, Any]:
            calls.append((product, year, len(files)))
            return {"values": [[0.0]]}

        return fetch

    return {p: make(p) for p in ("VNP46A4", "VJ146A4")}


def test_required_tiles_cover_the_mountain_west() -> None:
    assert required_tiles(AOI) == AOI_TILES


def test_required_tiles_exclude_a_tile_the_bbox_only_touches() -> None:
    bbox = BoundingBox(west=-120.0, south=40.0, east=-110.0, north=50.0)
    assert required_tiles(bbox) == {"h06v04"}


def test_prefers_vnp46a4_when_complete() -> None:
    calls: list[tuple[str, int, int]] = []
    listing = _listing({("VNP46A4", 2025): AOI_TILES, ("VJ146A4", 2025): AOI_TILES})
    grid = choose_and_stage(2025, AOI, years_back=1, list_files=listing, fetchers=_fetchers(calls))
    assert (grid["product"], grid["year"]) == ("VNP46A4", 2025)
    assert calls == [("VNP46A4", 2025, 4)]


def test_falls_back_to_vj146a4_when_vnp46a4_is_missing_or_partial() -> None:
    calls: list[tuple[str, int, int]] = []
    listing = _listing({("VNP46A4", 2026): {"h06v04"}, ("VJ146A4", 2026): AOI_TILES})
    grid = choose_and_stage(2026, AOI, years_back=1, list_files=listing, fetchers=_fetchers(calls))
    assert (grid["product"], grid["year"]) == ("VJ146A4", 2026)
    assert calls == [("VJ146A4", 2026, 4)]


def test_falls_back_to_previous_year_when_neither_product_has_the_year() -> None:
    calls: list[tuple[str, int, int]] = []
    listing = _listing({("VJ146A4", 2025): AOI_TILES})
    grid = choose_and_stage(2026, AOI, years_back=1, list_files=listing, fetchers=_fetchers(calls))
    assert (grid["product"], grid["year"]) == ("VJ146A4", 2025)


def test_raises_when_nothing_is_complete_within_the_window() -> None:
    listing = _listing({("VNP46A4", 2024): AOI_TILES})
    with pytest.raises(LookupError, match="VJ146A4 2025: 0/4"):
        choose_and_stage(2026, AOI, years_back=1, list_files=listing, fetchers=_fetchers([]))


def test_tile_windows_tile_the_aoi_exactly_once() -> None:
    r0, r1, c0, c1 = aoi_pixel_bounds(AOI, 240)
    covered = [[0] * (c1 - c0) for _ in range(r1 - r0)]
    for tile in AOI_TILES:
        src_r, src_c, dst_r, dst_c = tile_window(tile, 2400, AOI)
        assert src_r.stop - src_r.start == dst_r.stop - dst_r.start
        assert src_c.stop - src_c.start == dst_c.stop - dst_c.start
        assert 0 <= src_r.start <= src_r.stop <= 2400
        assert 0 <= src_c.start <= src_c.stop <= 2400
        for r in range(dst_r.start, dst_r.stop):
            row = covered[r]
            for c in range(dst_c.start, dst_c.stop):
                row[c] += 1
    assert all(v == 1 for row in covered for v in row)


def test_aoi_pixel_bounds_match_the_15_arcsecond_grid() -> None:
    r0, r1, c0, c1 = aoi_pixel_bounds(AOI, 240)
    assert (c1 - c0, r1 - r0) == (18 * 240, round(17.8 * 240))
    # West edge -120 sits on the h06 tile boundary: first AOI column is the tile's first.
    assert tile_window("h06v04", 2400, AOI)[1].start == 0


def test_build_labels_the_product_and_year_actually_staged(
    tmp_path: Path, radiance_grid: dict[str, Any]
) -> None:
    grid_path = tmp_path / "staged-grid.json"
    grid_path.write_text(json.dumps({**radiance_grid, "product": "VJ146A4", "year": 2025}))
    result = CliRunner().invoke(
        build, ["--grid", str(grid_path), "--max-zoom", "5", "--out", str(tmp_path / "out")]
    )
    assert result.exit_code == 0, result.output
    manifest = json.loads((tmp_path / "out" / "manifest.json").read_text())
    assert manifest["source_name"] == "VIIRS VJ146A4 Black Marble annual composite (NOAA-20)"
    assert manifest["publication_date"] == "2025-12-01"


def test_build_requires_a_date_for_a_grid_without_a_year(
    tmp_path: Path, radiance_grid: dict[str, Any]
) -> None:
    grid_path = tmp_path / "grid.json"
    grid_path.write_text(json.dumps(radiance_grid))
    result = CliRunner().invoke(build, ["--grid", str(grid_path), "--out", str(tmp_path)])
    assert result.exit_code != 0
    assert "--publication-date is required" in result.output
