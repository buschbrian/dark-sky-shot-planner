# Dark-Sky Shot Planner

**One question: is this spot dark, legal, and clear tonight?** — for Milky
Way photography in the U.S. Mountain West.

Darkness, legal access, and sky conditions for one place on one night,
answered text-first:

- **X minutes of moon-free astronomical darkness** — the intersection of the
  sun-below-−18° window with the moon-down window. The number nobody else
  surfaces well.
- Galactic Center peak altitude and time, with an honest "out of season"
  answer in winter.
- Land manager from USGS PAD-US — who manages it, never "you may camp here."
- Cloud-cover forecast over the moon-free window (Open-Meteo, keyless).
- **Sky events within 30 days** of the chosen night, for the chosen spot: moon
  phases, oppositions and elongations, Moon–planet pairings (with a
  topocentric occultation test), zodiacal-light windows, equinoxes and
  solstices — all computed — plus hand-curated meteor showers and festivals
  from `config/sky-events.json`, each judged at your location: does the
  radiant clear 10° in darkness, and is the Moon in the way?
- Every number carries its source and its age.

Zero server: a static site (MapLibre + PMTiles on GitHub Pages) plus Python
pipelines that run in GitHub Actions and publish static artifacts. All
astronomy is computed client-side; weather is fetched client-side on demand.

## Quickstart

```bash
uv sync --group dev && uv run python -m pytest tests/   # pipelines + tests (offline)
scripts/build-data.sh                                   # data/out — required first, or the app boots empty
npm install && npm run dev                              # http://localhost:5173
```

Requires Python 3.11+ with [uv](https://docs.astral.sh/uv/) and Node 22+.

See [CONTRIBUTING.md](CONTRIBUTING.md) for real data builds and AOI extension.

## Architecture

```
GitHub Actions (scheduled + manual)
  Python pipelines
    fetch source data -> clip to AOI -> normalize -> emit PMTiles / JSON
                                                        |
                                        committed artifacts (data/out/)
                                                        |
GitHub Pages  <---- static site build (Vite) ---------- +
    MapLibre GL JS + PMTiles protocol
    client-side astronomy (astronomy-engine, no API)
    client-side weather fetch on demand (Open-Meteo, keyless)
```

## Deploying

The site is published to <https://buschbrian.github.io/dark-sky-shot-planner/>
by `.github/workflows/deploy-pages.yml` on every push to `main` (and on manual
dispatch, and after a successful data refresh).

**One-time setup, by the repo maintainer:** Settings → Pages → Build and
deployment → Source = **GitHub Actions**. The workflow cannot flip this and
its deploy job fails until it is done. No secret is needed to deploy.

**What the site shows** depends on what is committed under `data/out/`
(force-added there only by `data-refresh.yml`):

| Layer | With nothing committed (first deploy) | After a successful refresh |
|---|---|---|
| Moon-free darkness, moon, Galactic Center | real — computed in your browser | real |
| Sky events (computed + curated file) | real — computed in your browser | real |
| Cloud forecast | real — Open-Meteo, keyless | real |
| Dark-sky places | real — `config/darksky-places.csv` | real |
| Light pollution | **sample fixture**, labelled in the UI | real VIIRS VNP46A4 |
| Land ownership (PAD-US) | **sample fixture**, labelled in the UI | still a fixture — the refresh has no PAD-US fetch step yet |

A fixture layer shows a notice under the tagline and "SAMPLE FIXTURE" in the
provenance table; the app withholds sky-brightness and land-manager answers
rather than derive them from sample tiles.

**Enabling real light-pollution data:** add the `BLACKMARBLE_TOKEN` Actions
secret (a NASA Earthdata token — steps in
[`docs/credentials-setup.md`](docs/credentials-setup.md)), then run the
"Data refresh" workflow. Its commit redeploys the site automatically.
See [ADR-0007](docs/adr/0007-github-pages-deploy.md) for the reasoning.

To build the production site locally exactly as the workflow does:

```bash
scripts/build-data.sh                                   # data/out, fixtures where no real data is committed
BASE_PATH=/dark-sky-shot-planner/ npm run build         # dist/
npx vite preview                                        # http://localhost:4173/dark-sky-shot-planner/
```

## Coming next: the iOS field companion

A native SwiftUI app (`ios/`, planned) that puts the whole shoot-night
routine in one place: this planner's numbers plus cloud layers from several
models, smoke and haze, seeing, dew and wind, aurora, Night AR, map
planner lines, and exposure tools. It gives one go / marginal / no-go
verdict that always names its limiting factor. A small stateless Cloudflare
Worker (`worker/`, planned) serves the live conditions. Plan and build
order: [`docs/ios/PLAN.md`](docs/ios/PLAN.md). Why: ADR-0009 and ADR-0010.

## Documentation

- [`docs/data-licensing.md`](docs/data-licensing.md) — every source, its
  license, and the sources we refuse to use (Falchi 2016, Lorenz).
- [`docs/methods.md`](docs/methods.md) — exactly how each displayed number is
  computed.
- [`docs/adr/`](docs/adr/) — architecture decision records.
- [`docs/credentials-setup.md`](docs/credentials-setup.md) — the one secret,
  and what needs none.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — local pipelines, extending the AOI.
- [`config/horizon-profiles/`](config/horizon-profiles/README.md) — measured
  terrain horizons for specific sites; not wired into the app yet.
- [`autonomous-build-brief.md`](autonomous-build-brief.md) — the original
  scope contract.

## License

MIT — see [LICENSE](LICENSE).
