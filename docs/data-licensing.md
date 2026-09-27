# Data licensing

The license status of every data source is a hard constraint, not a
preference. Sources below are used **because** their licenses permit
redistribution and derivation. The CI suite fails the build if a forbidden
source is referenced in pipeline code or configuration.

| Layer | Source | License | Status |
|---|---|---|---|
| Light pollution | VIIRS **VNP46A4** (Black Marble annual composite) via [`blackmarblepy`](https://github.com/nasa/blackmarblepy), [LP DAAC](https://ladsweb.modaps.eosdis.nasa.gov/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | **Used.** Safe to self-host and derive tiles from. |
| Land ownership / manager | USGS **PAD-US** ([Gap Analysis Project](https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download)) | Public domain (U.S. Government work) | **Used.** |
| Certified dark-sky places | DarkSky International place pages (e.g. <https://darksky.org/places/>) | No machine-readable dataset published | **Hand-curated CSV** in `config/darksky-places.csv` with per-row `source_url` and `verified_on`. Their site is not scraped. The list is explicitly labeled incomplete. |
| Meteor showers, festivals, other sky events | IMO Meteor Shower Calendar, In-The-Sky.org, EarthSky, arXiv preprints, NPS park pages (cited per row) | Facts, not datasets; no bulk reuse claimed | **Hand-curated JSON** in `config/sky-events.json` with per-row `source_url` and `verified_on`. Nothing is fetched or scraped at build or run time; rows that could not be verified carry a null `verified_on` and are labelled unverified in the UI. See ADR-0008. |
| Cloud / sky-cover forecast | [Open-Meteo](https://open-meteo.com/) | Free, keyless API; attribution required | **Used**, fetched client-side on demand for one clicked point at a time. |

## Used by the conditions Worker

Verified on 2026-09-25 by fetching each endpoint and reading each source's
terms (ADR-0009, ADR-0010). `worker/` fetches these rows; it is built and tested
locally and is not deployed yet. "Personal use" means the owner's own app.
"Distribution" means an App Store or public TestFlight release.

| Layer | Source | License / terms | Personal use | Distribution |
|---|---|---|---|---|
| Cloud layers, dew, wind, visibility, jet-stream winds | [Open-Meteo forecast](https://open-meteo.com/en/docs) (HRRR, GFS, DWD ICON Global, ECMWF; run times from each model's `/data/{model}/static/meta.json`). GEM HRDPS is **not used**: its domain misses much of southern Utah | Data CC BY 4.0. [Free API is non-commercial](https://open-meteo.com/en/terms) (subscriptions or ads count as commercial) | OK, keyless | Needs a paid API plan; key kept in the Worker |
| Cloud layers (ICON series) | [DWD ICON Global](https://open-meteo.com/en/docs/dwd-api) via Open-Meteo (`icon_global`) | CC BY 4.0: Open-Meteo's [licence page](https://open-meteo.com/en/licence) lists DWD forecasts as CC BY (its link there points at ECMWF's page by mistake). DWD's [open-data server](https://opendata.dwd.de/README.txt) defers to its [legal notice](https://www.dwd.de/EN/service/legal_notice/legal_notice_node.html): re-use under CC BY 4.0 with the source acknowledged. Credit "Deutscher Wetterdienst (DWD)" and Open-Meteo. Checked 2026-09-26 | OK | Paid Open-Meteo plan, as above; the DWD credit stays |
| AOD, PM2.5, dust | [Open-Meteo Air Quality](https://open-meteo.com/en/docs/air-quality-api) (CAMS Global) | CC BY 4.0; credit CAMS and Open-Meteo | OK | Paid plan, as above |
| Seeing / transparency indices | [7Timer! ASTRO](https://www.7timer.info/doc.php) (Shanghai Astronomical Observatory) | Free for non-commercial use; developers asked to notify | OK | **Blocked** without written permission |
| Smoke forecast | NOAA **RAP-Smoke** (not HRRR-Smoke, NWS SCN 22-42) via [NWS NDGD ImageServers](https://mapservices.weather.noaa.gov/raster/rest/services/air_quality) | U.S. Government work, public domain | OK | OK |
| Smoke polygons | [NOAA NESDIS HMS](https://www.ospo.noaa.gov/products/land/hms.html), via the NESDIS ArcGIS FeatureServer | Public domain (item license CC0) | OK | OK |
| Observed AQI | [EPA AirNow API](https://docs.airnowapi.org/) `/aq/observation/current/ziplatLong/` (the replacement schema's docs are behind a login; request parameter names unverified) | Free key. Label data "preliminary", credit the reporting agencies and AirNow, don't alter values, use official AQI colors, notify AirNow | OK | OK, with the display rules |
| Kp, aurora oval | [NOAA SWPC](https://services.swpc.noaa.gov/) JSON | U.S. Government work, public domain (SWPC disclaimer page unreachable when checked) | OK | OK |

## Basemaps on the iOS map

Checked on 2026-09-26 by fetching each service's description and sample tiles
at Candlestick Camp (38.3740, −109.9654), and reading the publisher's terms.
All are keyless. The iOS map draws the credit in its corner and names each
source, license and "Data refreshed" date in the Map panel. Offline areas use
MapLibre offline packs of these same tile URLs.

| Basemap | Source | License / terms | Credit shown | Offline packs |
|---|---|---|---|---|
| Topo; Dark relief (the same tiles inverted and dimmed by MapLibre paint properties) | USGS The National Map [USGSTopo](https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer) cached tiles, `…/tile/{z}/{y}/{x}`, z0–16. Its `copyrightText` lists TNM datasets, Census TIGER/Line, USFS roads, Natural Earth, NOAA NCEI; "Data refreshed September 4, 2026" | Public domain: "USGS-authored or produced data and information are considered to be in the U.S. public domain and can be freely used without permission" ([USGS copyright FAQ](https://www.usgs.gov/faqs/are-usgs-reportspublications-copyrighted)); credit requested | "USGS The National Map" | Allowed: the service reports `exportTilesAllowed: true` (`maxExportTilesCount` 100 000) |
| Imagery | USGS The National Map [USGSImageryTopo](https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer) (orthoimagery, NAIP-class, with US Topo labels), z0–16; "Data refreshed April, 2026" | Public domain (as above) | "USGS The National Map: imagery" | Allowed (`exportTilesAllowed: true`); optional per area, about doubles the size |
| Dark relief hillshade | [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) terrarium PNG, `s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`, used to z12 (overzoomed above) | Public-domain sources (USGS 3DEP/NED, SRTM, GMTED2010); credit per the tiles' [attribution file](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) | "terrain Mapzen/AWS, USGS" | AWS Open Data registry, no terms against bulk use |

Rejected on 2026-09-26: **OpenFreeMap** vector tiles (OpenStreetMap, ODbL,
keyless) — its [terms](https://openfreemap.org/tos/) forbid collecting data
"in automated ways without permission", which an offline-pack download is.
**USGSShadedReliefOnly** returns 404 above z12 at Candlestick. The dynamic
`carto.nationalmap.gov` transportation/geonames exports returned empty images
there and would cut labels at tile edges. No Google, Apple, Esri World
Imagery or competitor tiles are used.

## Proposed for the iOS companion (not yet fetched)

Verified on 2026-09-25, as above. A row moves up when code starts using it.

| Layer | Source | License / terms | Personal use | Distribution |
|---|---|---|---|---|
| Night cloud imagery | [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/) GOES ABI band 13 | NASA open data; GIBS acknowledgement text required | OK | OK |
| Terrain for horizon profiles | [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) (3DEP/NED, SRTM) and [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) services | Public domain sources; credit per the tiles' attribution file. Now also drawn as the map's Dark relief hillshade (above) | OK | OK |
| Terrain (alternative) | Mapterhorn hosted tiles | Terms for the hosted tiles not stated | Avoid | Avoid (self-host its PMTiles if ever needed) |

SkyCore's horizon ray march reads terrarium tiles through a protocol and does
not fetch them yet. Its test suite commits 25 unmodified z12 AWS Terrain Tiles
around Candlestick Camp as an offline fixture, with the required attribution
in `ios/Packages/SkyCore/Tests/Fixtures/terrarium-candlestick/README.md`.

Ephemeris code, not data: the iOS app vendors the astronomy-engine C port
(MIT), the same library and version as the web app (ADR-0009).

## Explicitly forbidden

- **Falchi et al. 2016, "New World Atlas of Artificial Night Sky Brightness"**
  — licensed CC BY-NC. Non-commercial terms would contaminate every derived
  tile and artifact. Not used, not shipped, not linked as a source.
- **Lorenz light-pollution atlas** — no published reuse license. Not used.

A test (`tests/test_forbidden_sources.py`) enforces these exclusions.
