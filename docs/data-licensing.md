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

## Explicitly forbidden

- **Falchi et al. 2016, "New World Atlas of Artificial Night Sky Brightness"**
  — licensed CC BY-NC. Non-commercial terms would contaminate every derived
  tile and artifact. Not used, not shipped, not linked as a source.
- **Lorenz light-pollution atlas** — no published reuse license. Not used.

A test (`tests/test_forbidden_sources.py`) enforces these exclusions.
