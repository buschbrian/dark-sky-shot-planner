"""Online fetch of VNP46A4 via blackmarblepy. Requires NASA Earthdata creds.

Never used in CI: golden tests run from committed fixtures. This module is
imported lazily by the CLI so the offline path has no heavy dependencies.
"""

from __future__ import annotations

import datetime as dt
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from pipelines.shared.config import BoundingBox


def stage_grid_from_blackmarble(year: int, bbox: BoundingBox) -> dict[str, Any]:
    """Download VNP46A4 for ``year``, clip to AOI, return a staged grid dict.

    The staged dict matches tests/fixtures/radiance-grid.json: regular lat/lon
    grid of radiance values in nW/cm2/sr, rows ordered north to south.
    """
    import geopandas
    from blackmarble import BlackMarble, Product
    from shapely.geometry import box

    aoi = geopandas.GeoDataFrame(
        geometry=[box(bbox.west, bbox.south, bbox.east, bbox.north)], crs="EPSG:4326"
    )
    bm = BlackMarble()
    rasters = bm.raster(
        aoi,
        product_id=Product.VNP46A4,
        date_range=[dt.date(year, 1, 1)],
        variable="Gap_Filled_DNB_BRDF-Corrected_NTL",
    )
    return _rasters_to_grid(rasters, bbox)


def _rasters_to_grid(rasters: Any, bbox: BoundingBox) -> dict[str, Any]:
    """Convert the fetched xarray object into the staged grid JSON shape."""
    import numpy as np

    values_da = rasters if hasattr(rasters, "dims") else rasters[0]
    arr: Any = np.asarray(values_da.values)
    if arr.ndim == 3:  # (time, y, x) -> first band
        arr = arr[0]
    step_lon = (bbox.east - bbox.west) / arr.shape[1]
    step_lat = (bbox.north - bbox.south) / arr.shape[0]
    lons = [bbox.west + i * step_lon for i in range(arr.shape[1])]
    lats = [bbox.north - j * step_lat for j in range(arr.shape[0])]
    return {
        "lons": [round(v, 6) for v in lons],
        "lats": [round(v, 6) for v in lats],
        "values": [[float(v) for v in row] for row in arr],
        "west": bbox.west,
        "south": bbox.south,
        "east": bbox.east,
        "north": bbox.north,
    }
