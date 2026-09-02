# ADR-0007: Deploy from GitHub Actions; fixtures stand in until real data is committed

**Status:** accepted · **Date:** 2026-09-02

## Decision

The site is published to GitHub Pages by `.github/workflows/deploy-pages.yml`
using the Pages "GitHub Actions" source (`upload-pages-artifact` +
`deploy-pages`), on every push to `main`, on manual dispatch, and after a
successful run of the "Data refresh" workflow. The deploy job does **not**
fetch source data. It runs `scripts/build-data.sh`, which keeps whatever real
artifacts `data-refresh.yml` has committed under `data/out/` and builds
anything missing from the offline fixtures in `tests/fixtures/`. The script
records the origin of each layer in `data/out/data-status.json`, and the
client labels fixture layers as sample data, withholds the sky-brightness
class, and never names a land manager from them.

The Vite `base` is driven by `BASE_PATH` (default `/`), and every artifact
fetch in the client goes through `dataUrl()` so a project site under
`/dark-sky-shot-planner/` resolves its data.

## Alternatives considered

- **Run the real fetch inside the deploy** — couples every deploy to a NASA
  Earthdata token, a 60-minute heavy-geo job that has already hung once, and
  network availability. A docs-only push should not need any of that.
- **Deploy only committed data, no fallback** — the first deploy would ship a
  site that boots into degraded mode with no `config.json`, exactly the failure
  the CI comments warn about. Nothing renders until a refresh succeeds.
- **Fixtures silently** — the fixture radiance grid is a synthetic gradient
  over one small box near Utah Lake. Showing it as "VIIRS 2024" with no
  label would be dishonest, and the answer panel could classify sky brightness
  from it. The project's rule is that every number carries its provenance.
- **`gh-pages` branch push** — a second branch to keep in sync and a
  `contents: write` token where `pages: write` + OIDC suffices.

## Consequences

- The first deploy works with **no secret set**. Real config, real curated
  dark-sky places, and fixture light-pollution / land-ownership layers,
  labelled as such. Astronomy and weather are unaffected — both are computed
  or fetched in the browser.
- Enabling the real light-pollution layer means adding the `BLACKMARBLE_TOKEN`
  secret (`docs/credentials-setup.md`) and running "Data refresh"; its commit
  then triggers a redeploy through `workflow_run`. PAD-US has no fetch step in
  the refresh yet, so land ownership stays a labelled fixture until one exists.
- Enabling Pages with source = "GitHub Actions" is a one-time repository
  setting the maintainer must flip; the workflow cannot do it and the deploy
  job fails until it is done.
- `data-refresh.yml` force-adds `data/out/`, which `.gitignore` excludes for
  local builds. That convention is unchanged: committed data is real data.
