"""Validation and GeoJSON emission for the hand-curated dark-sky places CSV.

This list is curated by humans in ``config/darksky-places.csv`` because
DarkSky International publishes no machine-readable dataset. We do not scrape.
Every row MUST carry a source_url and a verified_on date or the build fails —
that is the provenance contract, enforced here.
"""

from __future__ import annotations

import csv
import datetime as dt
import json
from pathlib import Path

from pydantic import BaseModel, Field


class CuratedPlace(BaseModel):
    name: str
    designation: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    source_url: str
    verified_on: dt.date

    def to_feature(self) -> dict[str, object]:
        return {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [self.longitude, self.latitude],
            },
            "properties": {
                "name": self.name,
                "designation": self.designation,
                "source_url": self.source_url,
                "verified_on": self.verified_on.isoformat(),
            },
        }


REQUIRED_COLUMNS = {"name", "designation", "latitude", "longitude", "source_url", "verified_on"}


class ValidationReport(BaseModel):
    row_count: int
    errors: list[str]


def load_places(csv_path: Path) -> tuple[list[CuratedPlace], ValidationReport]:
    """Parse and validate the CSV. Returns rows plus a report of all problems."""
    errors: list[str] = []
    with csv_path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None or not REQUIRED_COLUMNS.issubset(set(reader.fieldnames)):
            missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
            return [], ValidationReport(row_count=0, errors=[f"missing columns: {sorted(missing)}"])
        places: list[CuratedPlace] = []
        for i, row in enumerate(reader, start=2):  # header is line 1
            for col in REQUIRED_COLUMNS:
                if not (row.get(col) or "").strip():
                    errors.append(f"line {i}: empty required column '{col}'")
            try:
                places.append(
                    CuratedPlace(
                        name=(row["name"] or "").strip(),
                        designation=(row["designation"] or "").strip(),
                        latitude=float(row["latitude"]),
                        longitude=float(row["longitude"]),
                        source_url=(row["source_url"] or "").strip(),
                        verified_on=dt.date.fromisoformat((row["verified_on"] or "").strip()),
                    )
                )
            except (ValueError, TypeError) as exc:
                errors.append(f"line {i}: {exc}")
    return places, ValidationReport(row_count=len(places), errors=errors)


def emit_geojson(places: list[CuratedPlace], out_path: Path) -> int:
    fc = {
        "type": "FeatureCollection",
        # The incompleteness notice travels with the data itself.
        "_note": (
            "Manually curated list of International Dark Sky Places in the AOI. "
            "Not exhaustive; see docs/data-licensing.md."
        ),
        "features": [p.to_feature() for p in places],
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(fc))
    return len(places)
