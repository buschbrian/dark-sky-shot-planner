# Dark-Sky Shot Planner — Agent Routing

Shared context for coding agents (Codex reads this directly; CLAUDE.md points
here). This file ROUTES; the rules live in scoped files. Keep it under 80 lines.

Zero-server static site answering "is this spot dark, legal, and clear
tonight?" for Milky Way photography in the Mountain West. Python pipelines
(GitHub Actions) fetch/clip/normalize source data into committed PMTiles/JSON
under `data/out/`; a Vite + TypeScript + MapLibre client (no framework, see
ADR-0001) reads those artifacts and computes astronomy client-side. Full scope
contract and non-negotiables: `autonomous-build-brief.md`. Live status: `README.md`.

## Working on X → read Y

| Working on | Read first |
|---|---|
| Python pipelines (`pipelines/`) | `CONTRIBUTING.md`, `pipelines/shared/` |
| Client (`app/src/`) | ADR-0001, `app/src/config.ts` |
| Astronomy math (`app/src/astronomy/`) | ADR-0002, brief §5 |
| Tiles / pipeline output | ADR-0003, ADR-0005, `pipelines/shared/manifest.py` |
| Land-manager taxonomy | ADR-0004 |
| Freshness / provenance labels | ADR-0006, `app/src/freshness.ts` |
| Deploy / Pages / data-refresh | ADR-0007, `.github/workflows/`, `scripts/build-data.sh` |
| Allowed data sources | `docs/data-licensing.md` |
| A decision that felt settled | `docs/adr/` — do not re-litigate |

## Verify

```bash
uv run ruff check . && uv run ruff format --check .   # Python lint
uv run mypy --strict pipelines                        # Python types
uv run python -m pytest tests/                         # Python tests (offline, fixtures)
npx tsc --noEmit                                        # client types
npx vitest run                                          # client unit tests
scripts/build-data.sh                                   # populate data/out (required before dev/e2e)
npx playwright test                                      # e2e + axe WCAG 2.1 AA
```

`data/out/` is gitignored; the client boots into an empty/degraded page
without it — always run `scripts/build-data.sh` first for `npm run dev` or e2e.

**Never run `npx playwright install`** (standing rule): use system Chrome via
`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` instead. CI's own `--with-deps chromium`
install is CI-only, not a local pattern to copy. Name the target you ran
before calling work complete; label pre-existing failures as pre-existing.

## Data refresh (what it publishes)

`.github/workflows/data-refresh.yml` runs monthly (4th, 07:17 UTC) plus
manual dispatch: fetches VNP46A4 light pollution via `blackmarblepy` (needs
the `BLACKMARBLE_TOKEN` Actions secret, the only credential in the repo),
rebuilds dark-sky places and client config offline, force-commits the result
to `data/out/`, and opens a GitHub issue on failure. A successful run
retriggers `deploy-pages.yml`. Until a refresh runs, light-pollution and
land-ownership layers serve labeled sample fixtures (ADR-0007).

## Invariants (from tests/ and ADRs)

1. **Forbidden sources never appear** — Falchi 2016 (CC BY-NC) and Lorenz (no
   license); `tests/test_forbidden_sources.py` fails the build on either name.
2. **No credential anywhere in the repo** — `BLACKMARBLE_TOKEN` is an Actions
   secret only; CI runs a no-credentials grep plus a full-history gitleaks scan.
3. **Every displayed number carries source + freshness** (fresh/aging/stale/
   unavailable, ADR-0006); a failed feed shows the last good value with its
   age, never a blank.
4. **Pipelines are fixture-driven and offline in CI** — no network, no
   credentials; golden tests compare against `tests/fixtures/`.
5. **The map is secondary** — every state (location, date, layers) is
   reachable without the map receiving focus, and round-trips through the URL.
6. **PAD-US is a boundary dataset, not a permission system** — never assert
   "you may camp here," only who manages the land.

## Don't

- Add a UI framework without an ADR (ADR-0001), or ship/derive tiles from
  Falchi 2016 or Lorenz.
- Scrape DarkSky International; the places list is hand-curated CSV with
  `source_url` + `verified_on` per row.
- Run `npx playwright install`, or hardcode the AOI (`config/app-config.json` → `aoi`).
- Commit to `data/out/` yourself — only `data-refresh.yml` does.
