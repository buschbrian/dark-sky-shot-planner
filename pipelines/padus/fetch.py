"""Online fetch of PAD-US, clipped to the AOI. Public domain data.

Never used in CI: golden tests run from committed fixtures.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pipelines.shared.config import BoundingBox

PADUS_GEOPACKAGE_URL = (
    "https://www.sciencebase.gov/catalog/file/get/"
    "5f62a57982ce38aaa2449128?f=__disk__padus3_0_geopackage"
)


def stage_geojson_from_padus(year: int, bbox: BoundingBox, stage_dir: Path) -> Path:
    """Download PAD-US, clip to the AOI bbox, stage simplified GeoJSON.

    Only polygonal protected areas with a known manager are retained; rings
    are lightened with shapely simplify() at 0.001 degrees (~100 m), which is
    appropriate for zooms <= 9 (see docs/methods.md).
    """
    import geopandas as gpd

    gdf = gpd.read_file(PADUS_GEOPACKAGE_URL, layer="PADUS3_0Combined_Proclamation_Marine")
    gdf = gdf.to_crs("EPSG:4326")
    gdf = gdf.clip((bbox.west, bbox.south, bbox.east, bbox.north))
    keep = ["Mang_Name", "Mang_Type", "Cat_Describe", "geometry"]
    gdf = gdf[[c for c in keep if c in gdf.columns]]
    gdf["geometry"] = gdf.geometry.simplify(0.001, preserve_topology=True)
    out_path = stage_dir / f"staged-padus-{year}.geojson"
    fc = json.loads(gdf.to_json())
    out_path.write_text(json.dumps(fc))
    return out_path
