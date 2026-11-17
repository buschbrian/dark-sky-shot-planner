"""Online fetch of the Black Marble annual composite. Requires NASA Earthdata creds.

Suomi NPP (VNP46A4) stopped delivering on 2026-11-02; NOAA-20 (VJ146A4) is the
same algorithm on the continuing satellite. blackmarblepy only knows the VNP46
products, so VJ146A4 is read here directly from LAADS (ADR-0012). For each year,
newest first, VNP46A4 is tried and VJ146A4 is the fallback; the staged grid
records which product and year were used so the manifest labels it honestly.

Never used in CI: golden tests run from committed fixtures. This module is
imported lazily by the CLI so the offline path has no heavy dependencies.
"""

from __future__ import annotations

import datetime as dt
import http.cookiejar
import json
import math
import os
import shutil
import tempfile
import urllib.parse
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from pipelines.shared.config import BoundingBox

LAADS_URL = "https://ladsweb.modaps.eosdis.nasa.gov"
COLLECTION = "5200"
VARIABLE = "NearNadir_Composite_Snow_Free"
DATA_FIELDS = "HDFEOS/GRIDS/VIIRS_Grid_DNB_2d/Data Fields"
TILE_DEG = 10
PIXELS_PER_DEG = 240  # 15 arc-second grid, 2400 px per 10-degree tile
DROP_QUALITY = 255  # same default blackmarblepy applies

# Preference order within a year: the product already published, then the fallback.
PRODUCTS = ("VNP46A4", "VJ146A4")


def stage_grid_from_blackmarble(
    year: int, bbox: BoundingBox, years_back: int = 1
) -> dict[str, Any]:
    """Stage the newest available annual composite at or before ``year``.

    The staged dict matches tests/fixtures/radiance-grid.json (regular lat/lon
    grid of radiance in nW/cm2/sr, rows north to south) plus ``product`` and
    ``year`` for the one actually used.
    """
    return choose_and_stage(
        year,
        bbox,
        years_back=years_back,
        list_files=laads_files,
        fetchers={"VNP46A4": _stage_vnp46a4, "VJ146A4": _stage_vj146a4},
    )


def choose_and_stage(
    year: int,
    bbox: BoundingBox,
    *,
    years_back: int,
    list_files: Callable[[str, int, BoundingBox], list[dict[str, Any]]],
    fetchers: dict[str, Callable[[int, BoundingBox, list[dict[str, Any]]], dict[str, Any]]],
) -> dict[str, Any]:
    """Try each year (newest first) and product in order; stage the first complete one."""
    needed = required_tiles(bbox)
    tried: list[str] = []
    for y in range(year, year - years_back - 1, -1):
        for product in PRODUCTS:
            files = list_files(product, y, bbox)
            have = {_tile_id(f["name"]) for f in files}
            if not needed <= have:
                tried.append(f"{product} {y}: {len(needed & have)}/{len(needed)} tiles")
                continue
            print(f"using {product} {y}" + (f" (unavailable: {'; '.join(tried)})" if tried else ""))
            grid = fetchers[product](y, bbox, [f for f in files if _tile_id(f["name"]) in needed])
            return {**grid, "product": product, "year": y}
    raise LookupError("no complete Black Marble annual composite found: " + "; ".join(tried))


def required_tiles(bbox: BoundingBox) -> set[str]:
    """Black Marble tile IDs (hHHvVV, 10-degree grid) covering ``bbox``."""
    eps = 1e-9
    h0 = math.floor((bbox.west + 180) / TILE_DEG)
    h1 = math.floor((bbox.east - eps + 180) / TILE_DEG)
    v0 = math.floor((90 - bbox.north) / TILE_DEG)
    v1 = math.floor((90 - (bbox.south + eps)) / TILE_DEG)
    return {f"h{h:02d}v{v:02d}" for h in range(h0, h1 + 1) for v in range(v0, v1 + 1)}


def tile_window(tile_id: str, tile_px: int, bbox: BoundingBox) -> tuple[slice, slice, slice, slice]:
    """Row/col slices copying one tile's overlap with ``bbox`` into the AOI array.

    Returns (src_rows, src_cols, dst_rows, dst_cols). The AOI array spans the
    pixels whose centres fall inside ``bbox`` on the global 15" grid.
    """
    h, v = int(tile_id[1:3]), int(tile_id[4:6])
    scale = tile_px / TILE_DEG
    aoi_r0, aoi_r1, aoi_c0, aoi_c1 = aoi_pixel_bounds(bbox, scale)
    tile_r0, tile_c0 = v * tile_px, h * tile_px
    r0, r1 = max(aoi_r0, tile_r0), min(aoi_r1, tile_r0 + tile_px)
    c0, c1 = max(aoi_c0, tile_c0), min(aoi_c1, tile_c0 + tile_px)
    r1, c1 = max(r0, r1), max(c0, c1)
    return (
        slice(r0 - tile_r0, r1 - tile_r0),
        slice(c0 - tile_c0, c1 - tile_c0),
        slice(r0 - aoi_r0, r1 - aoi_r0),
        slice(c0 - aoi_c0, c1 - aoi_c0),
    )


def aoi_pixel_bounds(bbox: BoundingBox, px_per_deg: float) -> tuple[int, int, int, int]:
    """Global row/col range (end-exclusive) of pixel centres inside ``bbox``."""
    r0 = math.ceil((90 - bbox.north) * px_per_deg - 0.5)
    r1 = math.floor((90 - bbox.south) * px_per_deg - 0.5) + 1
    c0 = math.ceil((bbox.west + 180) * px_per_deg - 0.5)
    c1 = math.floor((bbox.east + 180) * px_per_deg - 0.5) + 1
    return r0, r1, c0, c1


def laads_files(product: str, year: int, bbox: BoundingBox) -> list[dict[str, Any]]:
    """List LAADS archive files for one annual composite over ``bbox`` (no auth needed)."""
    files: list[dict[str, Any]] = []
    page, pages = 1, 1
    while page <= pages:
        params = urllib.parse.urlencode(
            {
                "products": product,
                "archiveSet": COLLECTION,
                "temporalRanges": f"{year}-01-01..{year}-01-01",
                "regions": f"[BBOX]W{bbox.west} N{bbox.north} E{bbox.east} S{bbox.south}",
                "page": page,
            }
        )
        with urllib.request.urlopen(
            f"{LAADS_URL}/api/v2/content/details?{params}", timeout=60
        ) as r:
            body = json.load(r)
        files.extend(f for f in body.get("content", []) if f["name"].startswith(f"{product}."))
        pages = int(body.get("n_pages", 1))
        page += 1
    return files


def _tile_id(name: str) -> str:
    return name.split(".")[2]


def _stage_vnp46a4(year: int, bbox: BoundingBox, _files: list[dict[str, Any]]) -> dict[str, Any]:
    import geopandas
    from blackmarble import BlackMarble, Product
    from shapely.geometry import box

    aoi = geopandas.GeoDataFrame(
        geometry=[box(bbox.west, bbox.south, bbox.east, bbox.north)], crs="EPSG:4326"
    )
    rasters = BlackMarble().raster(
        aoi,
        product_id=Product.VNP46A4,
        date_range=[dt.date(year, 1, 1)],
        variable=VARIABLE,
    )
    return _rasters_to_grid(rasters, bbox)


def _stage_vj146a4(year: int, bbox: BoundingBox, files: list[dict[str, Any]]) -> dict[str, Any]:
    import numpy as np

    token = os.environ.get("BLACKMARBLE_TOKEN", "").strip()
    if not token:
        raise RuntimeError("BLACKMARBLE_TOKEN is empty: set a NASA Earthdata token")
    r0, r1, c0, c1 = aoi_pixel_bounds(bbox, PIXELS_PER_DEG)
    mosaic: Any = np.full((r1 - r0, c1 - c0), np.nan, dtype="float32")
    with tempfile.TemporaryDirectory() as tmp:
        for f in files:
            path = _download(f["downloadsLink"], Path(tmp), token)
            data = _read_tile(path)
            src_r, src_c, dst_r, dst_c = tile_window(_tile_id(f["name"]), data.shape[0], bbox)
            mosaic[dst_r, dst_c] = data[src_r, src_c]
            path.unlink()
    return _array_to_grid(mosaic, bbox)


def _download(link: str, directory: Path, token: str) -> Path:
    url = link if link.startswith("http") else f"{LAADS_URL}{link}"
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    out = directory / Path(urllib.parse.urlparse(url).path).name
    with opener.open(req, timeout=300) as r:
        if "text/html" in r.headers.get("Content-Type", ""):
            raise RuntimeError("LAADS returned HTML: the Earthdata token is invalid or expired")
        with out.open("wb") as fh:
            shutil.copyfileobj(r, fh, 1 << 20)
    return out


def _read_tile(path: Path) -> Any:
    """Radiance for one tile with fill and quality-255 pixels as NaN, as blackmarblepy does."""
    import h5py
    import numpy as np

    with h5py.File(path, "r") as h5:
        fields = h5[DATA_FIELDS]
        ds = fields[VARIABLE]
        data = ds[:].astype("float32")
        fill = ds.attrs.get("_FillValue")
        if fill is not None:
            data[np.isclose(data, np.asarray(fill).flat[0], equal_nan=True)] = np.nan
        quality = fields.get(f"{VARIABLE}_Quality")
        if quality is not None:
            data[quality[:] == DROP_QUALITY] = np.nan
        scale = float(np.asarray(ds.attrs.get("scale_factor", 1)).flat[0])
        offset = float(np.asarray(ds.attrs.get("offset", 0)).flat[0])
    return data * scale + offset


def _rasters_to_grid(rasters: Any, bbox: BoundingBox) -> dict[str, Any]:
    """Convert the fetched xarray object into the staged grid JSON shape."""
    # blackmarblepy returns an xr.Dataset (data_vars keyed by variable name);
    # tolerate a bare DataArray or a sequence of either for version drift.
    da = rasters
    if isinstance(da, (list, tuple)):
        da = da[0]
    if hasattr(da, "data_vars"):
        da = next(iter(da.data_vars.values()))
    return _array_to_grid(da.values, bbox)


def _array_to_grid(values: Any, bbox: BoundingBox) -> dict[str, Any]:
    import numpy as np

    arr: Any = np.asarray(values)
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
