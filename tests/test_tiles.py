from __future__ import annotations

from pathlib import Path

from pipelines.light_pollution.png import encode_png_rgb
from pipelines.light_pollution.rasterize import render_tile, tiles_for_bbox
from pipelines.shared.tiles import write_pmtiles


def test_tiles_for_bbox_covers_aoi(app_config) -> None:
    bbox = app_config.aoi.bbox.model_dump()
    keys = tiles_for_bbox(bbox, 5, 5)
    assert len(keys) > 0
    # AOI spans multiple states; a single tile at z5 cannot cover it.
    assert len(keys) >= 4
    assert all(k[0] == 5 for k in keys)


def test_render_tile_is_deterministic(radiance_grid, app_config) -> None:
    bbox = {k: radiance_grid[k] for k in ("west", "south", "east", "north")}
    key = tiles_for_bbox(bbox, 6, 6)[0]
    png_a = render_tile(radiance_grid, key, app_config)
    png_b = render_tile(radiance_grid, key, app_config)
    assert png_a == png_b
    assert png_a.startswith(b"\x89PNG")


def test_png_encoder_round_shape() -> None:
    import struct
    import zlib

    pixels = [[(255, 0, 0), (0, 255, 0)]]  # 2x1 image
    data = encode_png_rgb(2, 1, pixels)
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    # walk chunks: length(4) kind(4) payload crc(4)
    pos = 8
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            w, h = struct.unpack(">II", payload[:8])
            assert (w, h) == (2, 1)
        if kind == b"IDAT":
            idat += payload
        pos += 12 + length
    raw = zlib.decompress(idat)
    assert len(raw) == 1 + 6  # filter byte + 2 px * RGB


def test_write_pmtiles_raster(tmp_path: Path, app_config, radiance_grid) -> None:
    from pmtiles.reader import Reader
    from pmtiles.tile import TileType

    bbox = {k: radiance_grid[k] for k in ("west", "south", "east", "north")}
    keys = tiles_for_bbox(bbox, 6, 6)
    tiles = {k: render_tile(radiance_grid, k, app_config) for k in keys}
    out = tmp_path / "test.pmtiles"
    write_pmtiles(
        tiles,
        out,
        tile_type=TileType.PNG,
        bounds=bbox,
        attribution="test",
        extra_metadata={"source_year": 2024},
    )
    reader = Reader(lambda off, ln: out.read_bytes()[off : off + ln])
    z, x, y = keys[0]
    blob = reader.get(z, x, y)
    assert blob == tiles[(z, x, y)]
    meta = reader.metadata()
    assert isinstance(meta, dict)
    assert meta["source_year"] == 2024


def test_mvt_tiles_gzip_and_decode(tmp_path: Path, padus_geojson, app_config) -> None:
    from vt2geojson.tools import vt_bytes_to_geojson

    from pipelines.padus.cli import build_vector_tiles

    tiles = build_vector_tiles(padus_geojson, app_config)
    assert tiles
    (z, x, y), blob = sorted(tiles.items())[0]
    geojson = vt_bytes_to_geojson(blob, x, y, z)
    managers = {f["properties"]["manager"] for f in geojson["features"]}
    assert managers <= {
        "federal_blm",
        "federal_usfs",
        "federal_nps",
        "state",
        "tribal",
        "private",
        "unknown",
        "federal_other",
    }
    assert any(f["geometry"]["type"] == "Polygon" for f in geojson["features"])
