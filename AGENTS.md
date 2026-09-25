# Dark-Sky Shot Planner — Agent Routing

Shared context for coding agents (Codex reads this; CLAUDE.md points here).
This file ROUTES; rules live in scoped files. Keep it under 80 lines.

"Should I go shoot tonight — where, when, how?" for Milky Way photography in
the Mountain West (scope: ADR-0009, amending `autonomous-build-brief.md`).
Python pipelines publish PMTiles/JSON to `data/out/`; a Vite + TypeScript +
MapLibre static site (no framework, ADR-0001) computes astronomy client-side;
a native SwiftUI app lives in `ios/`; one stateless Worker in `worker/` serves
live conditions (ADR-0010). Live status: `README.md`.

## Working on X → read Y

| Working on | Read first |
|---|---|
| Python pipelines (`pipelines/`) | `CONTRIBUTING.md`, `pipelines/shared/` |
| Client (`app/src/`) | ADR-0001, `app/src/config.ts` |
| Astronomy math (`app/src/astronomy/`) | ADR-0002, brief §5 |
| Tiles / pipeline output | ADR-0003, ADR-0005, `pipelines/shared/manifest.py` |
| Land-manager taxonomy | ADR-0004 |
| Freshness / provenance labels | ADR-0006, `app/src/freshness.ts` |
| Sky events (computed or curated) | ADR-0008, `config/sky-events.json` |
| Deploy / Pages / data-refresh | ADR-0007, `.github/workflows/`, `scripts/build-data.sh` |
| iOS app (`ios/`) | `ios/AGENTS.md`, ADR-0009, `docs/ios/PLAN.md` |
| Conditions Worker (`worker/`) | ADR-0010, `docs/ios/PLAN.md` §Worker |
| Numbers shared across web/iOS | `shared/golden/`, `app/tests/golden-vectors.test.ts` |
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

`data/out/` is gitignored. **Never run `npx playwright install`** (standing rule): use system Chrome via
`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`. CI's own `--with-deps chromium` install
is CI-only, not a local pattern to copy. Name the target you ran before calling
work complete; label pre-existing failures as pre-existing.

## Data refresh (what it publishes)

`data-refresh.yml` (monthly + manual) fetches VNP46A4 via `blackmarblepy` (the
`BLACKMARBLE_TOKEN` Actions secret), rebuilds places/config, force-commits
`data/out/`, opens an issue on failure, then retriggers `deploy-pages.yml`.
Until it runs, light pollution and land ownership are fixtures (ADR-0007).

## Invariants (from tests/ and ADRs)

1. **Forbidden sources never appear** — Falchi 2016 (CC BY-NC) and Lorenz (no
   license); `tests/test_forbidden_sources.py` fails the build on either name.
2. **No credential anywhere in the repo** — Actions or Worker secrets only
   (`BLACKMARBLE_TOKEN`; Worker keys per ADR-0010); CI greps for
   credentials and runs a full-history gitleaks scan.
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

- Add a UI framework without an ADR (ADR-0001), or ship Falchi 2016 / Lorenz.
- Scrape DarkSky International or an events calendar; `darksky-places.csv` and
  `sky-events.json` are curated, `source_url` + `verified_on` per row.
- Run `npx playwright install`, or hardcode the AOI (`config/app-config.json` → `aoi`).
- Commit to `data/out/` yourself — only `data-refresh.yml` does.
