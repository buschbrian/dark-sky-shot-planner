"""Land-manager taxonomy normalization for PAD-US.

PAD-US carries a rich managerial hierarchy (Mang_Type, Mang_Name, Cat_Describe).
We collapse it into a small readable set defined in config so the map and the
answer text stay legible. Pure functions only.
"""

from __future__ import annotations

from pipelines.shared.config import AppConfig

# Substrings are matched case-insensitively against PAD-US Mang_Name /
# Mang_Type fields. Order matters: first match wins.
_BLM_MARKERS = ("BLM", "BUREAU OF LAND MANAGEMENT")
_USFS_MARKERS = ("USFS", "FOREST SERVICE", "US FOREST")
_NPS_MARKERS = ("NPS", "NATIONAL PARK SERVICE")
_FEDERAL_OTHER_MARKERS = (
    "FWS",
    "FISH AND WILDLIFE",
    "BUREAU OF RECLAMATION",
    "DOD",
    "DOD-",
    "ARMY",
    "AIR FORCE",
    "NAVY",
    "TVA",
    "BOR",
    "USBR",
)
_STATE_MARKERS = ("STATE", "ST ", "DIVISION OF WILDLIFE", "DEPT OF NATURAL")
_TRIBAL_MARKERS = ("TRIBAL", "INDIAN", "NATION ", "RESERV")


def normalize_manager(
    *,
    mang_type: str | None,
    mang_name: str | None,
    category: str | None = None,
) -> str:
    """Map raw PAD-US fields to a taxonomy key from ``manager_taxonomy``.

    Never raises: anything unrecognized becomes ``unknown`` (or ``private``
    when PAD-US marks the gap explicitly), because a wrong guess about land
    status is worse than an honest unknown.
    """
    haystack = f"{mang_name or ''} {mang_type or ''} {category or ''}".upper()

    if any(m in haystack for m in _BLM_MARKERS):
        return "federal_blm"
    if any(m in haystack for m in _USFS_MARKERS):
        return "federal_usfs"
    if any(m in haystack for m in _NPS_MARKERS):
        return "federal_nps"
    if any(m in haystack for m in _FEDERAL_OTHER_MARKERS):
        return "federal_other"
    if any(m in haystack for m in _TRIBAL_MARKERS):
        return "tribal"
    if any(m in haystack for m in _STATE_MARKERS):
        return "state"
    if "PRIVATE" in haystack or (category or "").upper() == "PUBG":
        return "private"
    return "unknown"


def validate_taxonomy_keys(app_config: AppConfig, keys: set[str]) -> list[str]:
    """Return any keys not present in the configured taxonomy."""
    known = {c.key for c in app_config.manager_taxonomy}
    return sorted(keys - known)
