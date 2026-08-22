from __future__ import annotations

import datetime as dt

from pipelines.shared.manifest import build_manifest, manifest_freshness


def test_freshness_thresholds_uniform() -> None:
    today = dt.date(2026, 8, 22)

    def pub(age_days: int) -> dt.date:
        return today - dt.timedelta(days=age_days)

    assert manifest_freshness(pub(100), 400, 550, 800, today=today) == "fresh"
    assert manifest_freshness(pub(500), 400, 550, 800, today=today) == "aging"
    assert manifest_freshness(pub(700), 400, 550, 800, today=today) == "stale"
    assert manifest_freshness(pub(900), 400, 550, 800, today=today) == "stale"
    assert manifest_freshness(None, 400, 550, 800, today=today) == "unavailable"


def test_manifest_checksum_depends_on_artifacts() -> None:
    from pipelines.shared.manifest import Artifact

    art = Artifact(path="a.png", sha256="deadbeef", bytes=10)
    m1 = build_manifest(
        layer_id="x",
        source_name="s",
        source_url="u",
        license="CC0",
        license_url="u",
        publication_date=None,
        artifacts=[art],
        counts={},
        now_utc=dt.datetime(2026, 1, 1, tzinfo=dt.UTC),
    )
    art2 = Artifact(path="a.png", sha256="feedface", bytes=10)
    m2 = build_manifest(
        layer_id="x",
        source_name="s",
        source_url="u",
        license="CC0",
        license_url="u",
        publication_date=None,
        artifacts=[art2],
        counts={},
        now_utc=dt.datetime(2026, 1, 1, tzinfo=dt.UTC),
    )
    assert m1.checksum != m2.checksum
