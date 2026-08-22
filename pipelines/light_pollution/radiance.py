"""Radiance-to-display mapping for the light-pollution layer.

Pure functions only: numbers in, colors out. The legend in the UI and the
raster tiles are rendered from the same breakpoints in ``config/app-config.json``
so they can never drift apart.
"""

from __future__ import annotations

from pipelines.shared.config import RadianceBreakpoint, RadianceMapping


def _parse_hex(color: str) -> tuple[int, int, int]:
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16)


def _format_rgb(r: int, g: int, b: int) -> str:
    return f"#{r:02x}{g:02x}{b:02x}"


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def classify_radiance(radiance: float, mapping: RadianceMapping) -> str:
    """Return the label for a radiance value (lowest breakpoint >= value wins ties)."""
    label = mapping.breakpoints[0].label
    for bp in mapping.breakpoints:
        if radiance >= bp.radiance:
            label = bp.label
    return label


def radiance_to_color(radiance: float, mapping: RadianceMapping) -> str:
    """Piecewise-linear ramp between breakpoints; clamps at both ends."""
    bps = sorted(mapping.breakpoints, key=lambda bp: bp.radiance)
    if radiance <= bps[0].radiance:
        return bps[0].color
    if radiance >= bps[-1].radiance:
        return bps[-1].color
    for lo, hi in zip(bps, bps[1:], strict=True):
        if lo.radiance <= radiance <= hi.radiance:
            t = (radiance - lo.radiance) / (hi.radiance - lo.radiance)
            r1, g1, b1 = _parse_hex(lo.color)
            r2, g2, b2 = _parse_hex(hi.color)
            return _format_rgb(
                round(_lerp(r1, r2, t)),
                round(_lerp(g1, g2, t)),
                round(_lerp(b1, b2, t)),
            )
    raise AssertionError("unreachable: radiance within breakpoint range")


def radiance_to_rgba_bytes(radiance: float, mapping: RadianceMapping) -> tuple[int, int, int, int]:
    hex_color = radiance_to_color(radiance, mapping)
    r, g, b = _parse_hex(hex_color)
    return (r, g, b, 255)


def legend_stops(mapping: RadianceMapping) -> list[RadianceBreakpoint]:
    """Stops for rendering the UI legend, ascending by radiance."""
    return sorted(mapping.breakpoints, key=lambda bp: bp.radiance)
