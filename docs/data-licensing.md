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

## Proposed for the iOS companion (not yet fetched)

Verified on 2026-09-25, as above. A row moves up when code starts using it.

| Layer | Source | License / terms | Personal use | Distribution |
|---|---|---|---|---|
| Night cloud imagery | [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/) GOES ABI band 13 | NASA open data; GIBS acknowledgement text required | OK | OK |
| Terrain for horizon profiles | [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) (3DEP/NED, SRTM) and [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) services | Public domain sources; credit per the tiles' attribution file | OK | OK |
| Terrain (alternative) | Mapterhorn hosted tiles | Terms for the hosted tiles not stated | Avoid | Avoid (self-host its PMTiles if ever needed) |

SkyCore's horizon ray march reads terrarium tiles through a protocol and does
not fetch them yet. Its test suite commits 25 unmodified z12 AWS Terrain Tiles
around Candlestick Camp as an offline fixture, with the required attribution
in `ios/Packages/SkyCore/Tests/Fixtures/terrarium-candlestick/README.md`.

Ephemeris code, not data: the iOS app vendors the astronomy-engine C port
(MIT), the same library and version as the web app (ADR-0009).

## Sky view catalogs (bundled in the iOS app)

Checked 2026-09-26. Built by `ios/scripts/build-sky-catalogs.py` into
`ios/Packages/SkyCore/Sources/SkyCore/Resources/sky/` (about 350 KB in
total), with credits and the BSD notice in that folder's `SOURCES.md`.

| Data | Source | License / terms | Personal use | Distribution |
|---|---|---|---|---|
| Stars to V 6.5 (8,404: J2000 position, proper motion, V, B−V) | Bright Star Catalogue, 5th Revised Ed. (Preliminary), Hoffleit & Warren 1991, as NASA HEASARC table [`bsc5p`](https://heasarc.gsfc.nasa.gov/W3Browse/star-catalog/bsc5p.html), file `https://heasarc.gsfc.nasa.gov/FTP/heasarc/dbase/tdat_files/heasarc_bsc5p.tdat.gz` (sha256 `122628cd…3931`, table modified 2022-02-03) | [data.gov lists it](https://catalog.data.gov/dataset/bright-star-catalog) with license "U.S. Government Works" (public domain), access level public. The HEASARC page and the CDS ReadMe (V/50) state no terms; CDS's own VizieR terms ("free of usage in a scientific context") cover its copy, so the HEASARC copy is the one used | OK | OK; credit Hoffleit & Warren and HEASARC |
| Constellation stick figures (88) and label positions | [d3-celestial](https://github.com/ofrohn/d3-celestial) `data/constellations.lines.json` and `constellations.json` at commit `7e720a3d`, by Olaf Frohn; the figures follow the [IAU / Sky & Telescope charts](https://www.iau.org/IAU/IAU/Astronomy-FAQs/Constellations.aspx) (Roger Sinnott, Rick Fienberg) | d3-celestial: BSD 3-Clause (notice kept in `SOURCES.md`). IAU charts: CC BY 4.0 | OK | OK with both credits |
| Star names (125) | IAU Working Group on Star Names approved names | Names are facts; the short list was typed by hand and matched to HR numbers by Bayer designation | OK | OK |
| Constellation membership (tests only) | astronomy-engine `Constellation()` (IAU boundaries, Roman 1987), already vendored | MIT | OK | OK |

Considered and not used: **HYG** (CC BY-SA 4.0, share-alike would bind the
bundled file), **Hipparcos** (listed on data.gov as a NASA table, but ESA
states no licence for the 1997 catalogue and ESA's own open data is
CC BY-SA 3.0 IGO), **Stellarium** sky cultures (licences vary per culture),
and survey images of the Milky Way (the Sky view models it analytically,
`MilkyWayModel.swift`, so no image data is bundled).

## Explicitly forbidden

- **Falchi et al. 2016, "New World Atlas of Artificial Night Sky Brightness"**
  — licensed CC BY-NC. Non-commercial terms would contaminate every derived
  tile and artifact. Not used, not shipped, not linked as a source.
- **Lorenz light-pollution atlas** — no published reuse license. Not used.

A test (`tests/test_forbidden_sources.py`) enforces these exclusions.
