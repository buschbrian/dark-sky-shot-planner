from __future__ import annotations

import pytest

from pipelines.padus.taxonomy import normalize_manager


@pytest.mark.parametrize(
    ("mang_name", "expected"),
    [
        ("Bureau of Land Management", "federal_blm"),
        ("US Forest Service", "federal_usfs"),
        ("National Park Service", "federal_nps"),
        ("US Fish and Wildlife Service", "federal_other"),
        ("Utah Division of Wildlife Resources", "state"),
        ("Navajo Nation", "tribal"),
        ("The Nature Conservancy", "unknown"),
    ],
)
def test_normalize_manager(mang_name: str, expected: str) -> None:
    assert normalize_manager(mang_type="FED", mang_name=mang_name) == expected


def test_private_gap_is_explicit() -> None:
    assert normalize_manager(mang_type=None, mang_name=None, category="PUBG") == "private"


def test_unknown_never_raises() -> None:
    assert normalize_manager(mang_type=None, mang_name=None) == "unknown"
    assert normalize_manager(mang_type="", mang_name="\xff junk") == "unknown"


def test_all_normalized_keys_exist_in_taxonomy(app_config) -> None:
    from pipelines.padus.taxonomy import validate_taxonomy_keys

    keys = {
        normalize_manager(mang_type="FED", mang_name=n)
        for n in (
            "Bureau of Land Management",
            "US Forest Service",
            "National Park Service",
            "State Park Commission",
            "Cherokee Nation",
            "",
        )
    }
    keys.add("private")
    keys.add("unknown")
    assert validate_taxonomy_keys(app_config, keys) == []
