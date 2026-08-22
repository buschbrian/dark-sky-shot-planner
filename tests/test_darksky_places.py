from __future__ import annotations

import datetime as dt
from pathlib import Path

from pipelines.darksky_places.places import emit_geojson, load_places

FIXTURES = Path(__file__).parent / "fixtures"


def test_valid_csv_loads() -> None:
    places, report = load_places(FIXTURES / "darksky-places-valid.csv")
    assert report.errors == []
    assert len(places) == 1
    assert places[0].verified_on == dt.date(2026, 1, 15)


def test_missing_source_url_or_verified_on_fails() -> None:
    _, report = load_places(FIXTURES / "darksky-places-invalid.csv")
    assert any("source_url" in e for e in report.errors)
    assert any("verified_on" in e for e in report.errors)


def test_geojson_carries_provenance(tmp_path: Path) -> None:
    places, report = load_places(FIXTURES / "darksky-places-valid.csv")
    assert report.errors == []
    out = tmp_path / "places.geojson"
    count = emit_geojson(places, out)
    data = out.read_text()
    assert count == 1
    assert '"source_url": "https://example.com/place"' in data
    assert "Not exhaustive" in data


def test_real_curated_csv_is_valid() -> None:
    repo_csv = Path(__file__).parents[1] / "config" / "darksky-places.csv"
    places, report = load_places(repo_csv)
    assert not report.errors
    assert len(places) >= 10
