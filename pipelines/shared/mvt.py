"""Minimal Mapbox Vector Tile (v2.1) encoder in pure Python.

Encodes layers/features into MVT protobuf wire format using only the
standard library, so golden tests need no compiled dependencies. Callers
pass geometry already projected into tile-local pixel coordinates;
``lonlat_to_tile_coords`` does the Web Mercator projection.
"""

from __future__ import annotations

import math
from collections.abc import Mapping

Extent = int
AttributeValue = str | int | float | bool


def _write_varint(out: bytearray, value: int) -> None:
    value &= (1 << 64) - 1
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return


def _zigzag(value: int) -> int:
    return (value << 1) ^ (value >> 63)


def _tag(field: int, wire_type: int) -> int:
    return (field << 3) | wire_type


def _write_len_delimited(out: bytearray, field: int, payload: bytes) -> None:
    _write_varint(out, _tag(field, 2))
    _write_varint(out, len(payload))
    out.extend(payload)


class GeometryType:
    POINT = 1
    LINESTRING = 2
    POLYGON = 3


GeomPart = tuple[tuple[float, float], ...]
# Points: one part per point. Lines: one part per line. Polygons: one part
# per ring, first ring exterior.
Geometry = list[GeomPart]


def _signed_area(ring: GeomPart) -> float:
    total = 0.0
    for (x0, y0), (x1, y1) in zip(ring, (*ring[1:], ring[0]), strict=True):
        total += x0 * y1 - x1 * y0
    return total / 2.0


def _encode_ring(ring: GeomPart, cursor: tuple[int, int], out: bytearray) -> tuple[int, int]:
    pts = [(round(x), round(y)) for x, y in ring]
    _write_varint(out, (1 << 3) | 1)  # MoveTo, count 1
    cx, cy = cursor
    _write_varint(out, _zigzag(pts[0][0] - cx))
    _write_varint(out, _zigzag(pts[0][1] - cy))
    cx, cy = pts[0]
    if len(pts) > 1:
        _write_varint(out, ((len(pts) - 1) << 3) | 2)  # LineTo
        for px, py in pts[1:]:
            _write_varint(out, _zigzag(px - cx))
            _write_varint(out, _zigzag(py - cy))
            cx, cy = px, py
    _write_varint(out, (1 << 3) | 7)  # ClosePath
    return cx, cy


class _LayerEncoder:
    def __init__(self, name: str, extent: Extent = 4096) -> None:
        self.name = name
        self.extent = extent
        self._keys: list[str] = []
        self._key_index: dict[str, int] = {}
        self._values: list[bytes] = []
        self._value_index: dict[tuple[type, AttributeValue], int] = {}
        self._features: list[bytes] = []

    def add_feature(
        self,
        geometry_type: int,
        geometry: Geometry,
        attributes: Mapping[str, AttributeValue],
        feature_id: int | None = None,
    ) -> None:
        geom_out = bytearray()
        cursor = (0, 0)
        if geometry_type == GeometryType.POLYGON:
            for i, ring in enumerate(geometry):
                # Screen coords are y-down: exterior rings must be clockwise,
                # holes counter-clockwise. Normalize instead of trusting input.
                area = _signed_area(ring)
                if (i == 0) != (area > 0):
                    ring = tuple(reversed(ring))
                cursor = _encode_ring(ring, cursor, geom_out)
        else:
            pts = [(round(x), round(y)) for part in geometry for x, y in part]
            if not pts:
                raise ValueError("empty geometry")
            _write_varint(geom_out, (len(pts) << 3) | 1)
            cx, cy = cursor
            for px, py in pts:
                _write_varint(geom_out, _zigzag(px - cx))
                _write_varint(geom_out, _zigzag(py - cy))
                cx, cy = px, py

        tags_out = bytearray()
        for key, value in sorted(attributes.items()):
            ki = self._key_index.get(key)
            if ki is None:
                ki = len(self._keys)
                self._keys.append(key)
                self._key_index[key] = ki
            vi = self._index_value(value)
            _write_varint(tags_out, ki)
            _write_varint(tags_out, vi)

        feat = bytearray()
        if feature_id is not None:
            _write_varint(feat, _tag(1, 0))
            _write_varint(feat, feature_id)
        _write_len_delimited(feat, 2, bytes(tags_out))
        _write_varint(feat, _tag(3, 0))
        _write_varint(feat, geometry_type)
        _write_len_delimited(feat, 4, bytes(geom_out))
        self._features.append(bytes(feat))

    def _index_value(self, value: AttributeValue) -> int:
        cache_key = (type(value), value)
        idx = self._value_index.get(cache_key)
        if idx is not None:
            return idx
        vb = bytearray()
        match value:
            case bool():
                _write_varint(vb, _tag(7, 0))
                _write_varint(vb, 1 if value else 0)
            case int():
                _write_varint(vb, _tag(6, 0))
                _write_varint(vb, _zigzag(value))
            case float():
                import struct

                _write_varint(vb, _tag(3, 2))
                _write_varint(vb, 8)
                vb.extend(struct.pack("<d", value))
            case str():
                _write_len_delimited(vb, 1, value.encode())
        idx = len(self._values)
        self._values.append(bytes(vb))
        self._value_index[cache_key] = idx
        return idx

    def encode(self) -> bytes:
        out = bytearray()
        _write_varint(out, _tag(15, 0))
        _write_varint(out, 2)  # version
        _write_len_delimited(out, 1, self.name.encode())
        for feature in self._features:
            _write_len_delimited(out, 2, feature)
        for key in self._keys:
            _write_len_delimited(out, 3, key.encode())
        for value in self._values:
            _write_len_delimited(out, 4, value)
        _write_varint(out, _tag(5, 0))
        _write_varint(out, self.extent)
        return bytes(out)


class TileBuilder:
    def __init__(self, extent: Extent = 4096) -> None:
        self.extent = extent
        self._layers: dict[str, _LayerEncoder] = {}

    def layer(self, name: str) -> _LayerEncoder:
        enc = self._layers.get(name)
        if enc is None:
            enc = _LayerEncoder(name, self.extent)
            self._layers[name] = enc
        return enc

    def encode(self) -> bytes:
        out = bytearray()
        for layer in self._layers.values():
            _write_len_delimited(out, 3, layer.encode())
        return bytes(out)


def lonlat_to_tile_coords(
    lon: float, lat: float, z: int, x: int, y: int, extent: Extent = 4096
) -> tuple[float, float]:
    """Project WGS84 lon/lat to pixel coords within tile (z, x, y)."""
    n = 2**z
    world = extent * n
    xt = (lon + 180.0) / 360.0 * world - x * extent
    lat_rad = math.radians(lat)
    yt = (
        1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi
    ) / 2.0 * world - y * extent
    return xt, yt


def tile_bounds(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    """WGS84 bounds of tile (z,x,y): west, south, east, north."""
    n = 2**z
    west = x / n * 360.0 - 180.0
    east = (x + 1) / n * 360.0 - 180.0

    def lat(yv: float) -> float:
        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * yv / n))))

    return west, lat(y + 1), east, lat(y)


def lonlat_to_tile_xy(lon: float, lat: float, z: int) -> tuple[int, int]:
    """XYZ tile index containing the given WGS84 point at zoom z."""
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    clamped = max(-85.05112878, min(85.05112878, lat))
    rad = math.radians(clamped)
    y = int((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))
