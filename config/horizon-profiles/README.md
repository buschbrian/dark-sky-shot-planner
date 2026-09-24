# Terrain horizon profiles

Measured skyline profiles for specific observing sites: for each azimuth, how
many degrees above horizontal the terrain rises. The app's astronomy currently
assumes a flat horizon, so **nothing here is wired into the build yet.** These
files are the input a terrain-aware darkness window would need.

## Why this is not in `darksky-places.csv`

That file is the curated list of *DarkSky International certified places*, and
its build contract requires a `source_url` and `verified_on` for every row. A
campsite is not a certified place, and a 360-row profile is not a CSV cell.
Mixing the two would put false entries into the published places layer.

## Format

One file per site. Two columns, 360 rows, one per whole degree:

| column | meaning |
|---|---|
| `azimuth_deg` | geographic azimuth, 0 = true north, increasing clockwise, 0–359 |
| `horizon_alt_deg` | terrain altitude above horizontal at that azimuth, degrees |

Azimuth 360 is omitted; consumers wrap to 0.

## Sites

### `candlestick-camp.csv`

Candlestick Camp, White Rim Road, Canyonlands National Park, Utah. A
reservable NPS backcountry site, so the location is already public.

- **Observer:** 38.374031, -109.965416 (WGS84), ground elevation 1320.3 m
- **Source:** `Skyline` and `Skyline Graph`, ArcGIS Pro 3D Analyst, run
  2026-09-04 against a USGS 3DEP 10 m DEM, projected NAD83(2011) UTM 12N
- **Project:** `Canyonlands26.aprx`, table `skylinefull_angles`
- **Range:** 1.024° at azimuth 326 to 8.700° at azimuth 14
- **Validation:** an independent hand calculation put Candlestick Tower at
  76.03° azimuth and 8.84° altitude; `Skyline` measured 75.50° and 8.62°.

Sampled at 1°. A separate 0.25° run over the sunrise sector gives 4.987° at
azimuth 82.60°, which is the number the 2026-09-06 first-light prediction of
7:18 AM was built on. The 1° file interpolates to 4.91° there, so **read the
finer run for sunrise-critical work**; this file is for whole-sky planning.

## Known discrepancy

The observer latitude above is what the analysis actually used. A separate
field note records the campsite as 38.374222, -109.965417 — about 21 m north.
The angles are insensitive to that at a rim distance near 4.7 km, but the two
records should be reconciled against a GPS pin before either is treated as
authoritative.
