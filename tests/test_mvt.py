from __future__ import annotations

from pipelines.shared.mvt import GeometryType, TileBuilder, lonlat_to_tile_coords, tile_bounds


def test_point_feature_roundtrip() -> None:
    from vt2geojson.tools import vt_bytes_to_geojson

    tb = TileBuilder()
    lay = tb.layer("places")
    lay.add_feature(GeometryType.POINT, [[(2048.0, 2048.0)]], {"name": "Test Butte"}, 7)
    data = tb.encode()
    gj = vt_bytes_to_geojson(data, 0, 0, 1)
    assert len(gj["features"]) == 1
    feat = gj["features"][0]
    assert feat["properties"] == {"name": "Test Butte"}
    # tile (z1, x0, y0) center is (-90, ~66.5)
    lon, lat = feat["geometry"]["coordinates"]
    assert abs(lon - -90.0) < 0.5
    assert abs(lat - 66.51) < 0.5


def test_polygon_winding_normalized() -> None:
    from vt2geojson.tools import vt_bytes_to_geojson

    tb = TileBuilder()
    lay = tb.layer("padus")
    counter_clockwise_screen = [(0, 0), (0, 100), (100, 100), (100, 0)]
    lay.add_feature(GeometryType.POLYGON, [counter_clockwise_screen], {}, 1)
    gj = vt_bytes_to_geojson(tb.encode(), 0, 0, 1)
    ring = gj["features"][0]["geometry"]["coordinates"][0]
    assert ring[0] == ring[-1]  # closed


def test_lonlat_projection_matches_tile_bounds() -> None:
    west, south, east, north = tile_bounds(7, 42, 73)
    x_min, y_max = lonlat_to_tile_coords(west, south, 7, 42, 73)
    x_max, y_min = lonlat_to_tile_coords(east, north, 7, 42, 73)
    assert round(x_min) == 0 and round(x_max) == 4096
    assert round(y_min) == 0 and round(y_max) == 4096
