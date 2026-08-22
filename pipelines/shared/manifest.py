"""Provenance manifests emitted by every pipeline.

The client reads these to render source, date, and freshness for every
displayed number. No number reaches the user without one.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


class Artifact(BaseModel):
    path: str
    sha256: str
    bytes: int


class Manifest(BaseModel):
    layer_id: str
    source_name: str
    source_url: str
    license: str
    license_url: str
    retrieval_utc: dt.datetime = Field(alias="retrieval_utc")
    publication_date: dt.date | None = None
    checksum: str  # sha256 over the artifact list below
    artifacts: list[Artifact]
    counts: dict[str, int]

    def write(self, out_dir: Path) -> Path:
        path = out_dir / "manifest.json"
        path.write_text(json.dumps(self.model_dump(mode="json", by_alias=True), indent=2))
        return path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(
    *,
    layer_id: str,
    source_name: str,
    source_url: str,
    license: str,  # noqa: A002 - JSON field name is "license"
    license_url: str,
    publication_date: dt.date | None,
    artifacts: list[Artifact],
    counts: dict[str, int],
    now_utc: dt.datetime | None = None,
) -> Manifest:
    """Assemble a manifest. ``now_utc`` is injectable for deterministic tests."""
    digest = hashlib.sha256()
    for art in sorted(artifacts, key=lambda a: a.path):
        digest.update(art.path.encode())
        digest.update(art.sha256.encode())
    return Manifest(
        layer_id=layer_id,
        source_name=source_name,
        source_url=source_url,
        license=license,
        license_url=license_url,
        retrieval_utc=now_utc or dt.datetime.now(dt.UTC),
        publication_date=publication_date,
        checksum=digest.hexdigest(),
        artifacts=artifacts,
        counts=counts,
    )


def manifest_freshness(
    publication_date: dt.date | None,
    thresholds_fresh_max_days: int,
    thresholds_aging_max_days: int,
    thresholds_stale_max_days: int,
    today: dt.date | None = None,
) -> str:
    """Apply the uniform fresh/aging/stale/unavailable convention.

    Pure function; the client mirrors this logic from config thresholds.
    """
    if publication_date is None:
        return "unavailable"
    age_days = ((today or dt.date.today()) - publication_date).days
    if age_days <= thresholds_fresh_max_days:
        return "fresh"
    if age_days <= thresholds_aging_max_days:
        return "aging"
    if age_days <= thresholds_stale_max_days:
        return "stale"
    return "stale"


def load_manifest(path: Path) -> dict[str, Any]:
    data: Any = json.loads(path.read_text())
    assert isinstance(data, dict)
    return data
