# Contributing

## Prerequisites

- Python 3.11+ with [uv](https://docs.astral.sh/uv/)
- Node 22+

## Quickstart

```bash
# Python side
uv sync --group dev            # base deps + pytest/ruff/mypy
uv run python -m pytest tests/ # golden + unit tests, fully offline

# Frontend
npm install
npm run dev                    # http://localhost:5173
npx vitest run                 # client unit tests
npx playwright install chromium && npm run test:e2e
```

The dev server reads pipeline artifacts from `data/out/`. That directory is
gitignored for local builds (only `data-refresh.yml` commits real artifacts
there), so build it before `npm run dev` or `npm run test:e2e`, or the client
boots into an empty page:

```bash
scripts/build-data.sh
```

That runs, in order, the four pipeline commands below — keeping any real
artifact already committed under `data/out/` and using the offline fixtures
for the rest — and writes `data/out/data-status.json` so the UI can label
fixture layers. The individual commands, if you need just one:

```bash
uv run python -m pipelines.shared.cli --out data/out
uv run python -m pipelines.light_pollution.cli build --grid tests/fixtures/radiance-grid.json --publication-date 2024-12-01 --out data/out/light_pollution
uv run python -m pipelines.padus.cli --input tests/fixtures/padus-sample.geojson --publication-date 2024-06-01 --out data/out/padus
uv run python -m pipelines.darksky_places.cli build --csv config/darksky-places.csv --out data/out/darksky_places
```

The first command is not optional. `config.json` carries the AOI, freshness
thresholds, radiance breakpoints, and the manager taxonomy, and the client
fetches it during boot — without it the app runs in a degraded mode where
sky-brightness classes, land-manager labels, and freshness are all
unavailable.

## Extending the area of interest

1. Edit `config/app-config.json` → `aoi` (states list and bbox).
2. Re-run the pipelines. Tile coverage, the low-res grid, and the client's
   default map view all derive from that one config value.

No code changes are required; if something breaks when you only changed
config, that is a bug.

## Real (networked) data builds

```bash
uv sync --extra fetch   # heavy geo deps
export EARTHDATA_USER=... EARTHDATA_PASS=...   # NASA Earthdata, never committed
uv run python -m pipelines.light_pollution.cli fetch-and-build --year 2024 --out /tmp/stage/lp
```

CI never runs these paths — it is fixture-based by design.

## Ground rules

- Every PR must keep `ruff`, `mypy --strict`, `tsc --noEmit`, ESLint,
  `pytest`, `vitest`, and Playwright green.
- No secrets, keys, or tokens anywhere, ever. There is no legitimate reason
  for one to exist in this repo.
- New data sources must pass the licensing guard: check `docs/data-licensing.md`
  before reaching for "the" dataset you know.
- Displayed numbers carry provenance. If you add a number, add its source,
  date, and freshness handling.
