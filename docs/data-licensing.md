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

## Proposed for the iOS companion and conditions Worker (not yet fetched)

Verified on 2026-09-25 by fetching each endpoint and reading each source's
terms (ADR-0009, ADR-0010). A row moves up into the table above when code
starts using it. "Personal use" means the owner's own app. "Distribution"
means an App Store or public TestFlight release.

| Layer | Source | License / terms | Personal use | Distribution |
|---|---|---|---|---|
| Cloud layers, dew, wind, visibility, jet-stream winds | [Open-Meteo forecast](https://open-meteo.com/en/docs) (HRRR, GFS, GEM, ECMWF) | Data CC BY 4.0. [Free API is non-commercial](https://open-meteo.com/en/terms) (subscriptions or ads count as commercial) | OK, keyless | Needs a paid API plan; key kept in the Worker |
| AOD, PM2.5, dust | [Open-Meteo Air Quality](https://open-meteo.com/en/docs/air-quality-api) (CAMS Global) | CC BY 4.0; credit CAMS and Open-Meteo | OK | Paid plan, as above |
| Seeing / transparency indices | [7Timer! ASTRO](https://www.7timer.info/doc.php) (Shanghai Astronomical Observatory) | Free for non-commercial use; developers asked to notify | OK | **Blocked** without written permission |
| Smoke forecast | NOAA HRRR-Smoke via [NWS NDGD ImageServers](https://mapservices.weather.noaa.gov/raster/rest/services/air_quality) | U.S. Government work, public domain | OK | OK |
| Smoke polygons | [NOAA NESDIS HMS](https://www.ospo.noaa.gov/products/land/hms.html), via the NESDIS ArcGIS FeatureServer | Public domain (item license CC0) | OK | OK |
| Observed AQI | [EPA AirNow API](https://docs.airnowapi.org/) | Free key. Label data "preliminary", credit the reporting agencies and AirNow, don't alter values, use official AQI colors, notify AirNow | OK | OK, with the display rules |
| Kp, aurora oval | [NOAA SWPC](https://services.swpc.noaa.gov/) JSON | U.S. Government work, public domain (SWPC disclaimer page unreachable when checked) | OK | OK |
| Night cloud imagery | [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/) GOES ABI band 13 | NASA open data; GIBS acknowledgement text required | OK | OK |
| Terrain for horizon profiles | [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) (3DEP/NED, SRTM) and [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) services | Public domain sources; credit per the tiles' attribution file | OK | OK |
| Terrain (alternative) | Mapterhorn hosted tiles | Terms for the hosted tiles not stated | Avoid | Avoid (self-host its PMTiles if ever needed) |

Ephemeris code, not data: the iOS app vendors the astronomy-engine C port
(MIT), the same library and version as the web app (ADR-0009).

## Explicitly forbidden

- **Falchi et al. 2016, "New World Atlas of Artificial Night Sky Brightness"**
  — licensed CC BY-NC. Non-commercial terms would contaminate every derived
  tile and artifact. Not used, not shipped, not linked as a source.
- **Lorenz light-pollution atlas** — no published reuse license. Not used.

A test (`tests/test_forbidden_sources.py`) enforces these exclusions.
