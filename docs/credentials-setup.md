# Credentials & API setup — what's needed from you

The app itself needs **zero credentials** to run, test, or deploy: CI is
fixture-based, the site is static on GitHub Pages, weather is fetched
keyless client-side. Exactly **one credential** exists in this project, and
only for the monthly real-data refresh.

## 1. NASA Earthdata personal access token — REQUIRED (one-time)

Needed by `blackmarblepy` to download the VIIRS VNP46A4 annual composite
(light-pollution layer) from the NASA LAADS DAAC archive.

### Steps

1. Register / log in at <https://urs.earthdata.nasa.gov> (free).
2. Generate a personal access token from your profile:
   <https://urs.earthdata.nasa.gov/profile> → *Generate Token*.
3. Accept the LAADS DAAC archive access agreement if prompted on first data
   access (<https://ladsweb.modaps.eosdis.nasa.gov/>).
4. Add it as a GitHub Actions secret:
   - Repo → *Settings* → *Secrets and variables* → *Actions*
   - Name: `BLACKMARBLE_TOKEN`
   - Value: the token from step 2

### Notes

- Tokens expire (~2 months for Earthdata tokens); the monthly refresh will
  fail with an auth error when it does — rotate the secret then.
- This is the only secret in the project. It lives in GitHub Actions
  secrets only, never in code. The `.gitignore` already excludes `.env`,
  `*.pem`, `*.key` defensively.

## Local runs (optional)

To run the real fetch locally instead of waiting for CI:

```bash
uv sync --extra fetch
export BLACKMARBLE_TOKEN="your-token"
uv run python -m pipelines.light_pollution.cli fetch-and-build --year 2025 --out /tmp/stage/lp
```

## What needs NO credentials (for the record)

| Thing | Why not |
|---|---|
| All tests & CI | Golden fixtures committed; no network |
| GitHub Pages hosting | Uses built-in `GITHUB_TOKEN`, no setup |
| Open-Meteo weather | Keyless public API, called from the user's browser |
| PAD-US land ownership | Public domain USGS download, no auth |
| MapLibre GL + PMTiles | Open source; no basemap token (plain background style) |

## Optional future credentials (not needed now)

- **Basemap tiles** (satellite/terrain): only if you later want a richer
  basemap style — e.g., a Stadia/MapTiler key. Current design deliberately
  uses no basemap provider.
- **NWS gridpoint fallback**: keyless, nothing required.
