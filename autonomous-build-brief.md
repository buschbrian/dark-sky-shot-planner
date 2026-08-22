# Dark-Sky Shot Planner — Autonomous Build Brief

> Working doc for [[Dark-Sky Shot Planner]]. Written 2026-08-22 as a single
> self-contained prompt to hand a frontier coding model with a long budget.
> Everything below is intended to be pasted as one message into a fresh
> session in an empty repo directory. It deliberately repeats context that
> lives elsewhere in the vault, because the model reading it will not have
> the vault.

---

## The prompt

You are building a complete, production-quality open-source web application
from scratch, in an empty repository, working autonomously. Read this entire
brief before writing any code. Plan first, then build, then verify, then
write the docs. Do not stop to ask permission for ordinary implementation
decisions — make the call, record it in an ADR, and keep going.

### 1. The product, in one sentence

**Dark-Sky Shot Planner answers one question: "is this spot dark, legal, and
clear tonight?"** for Milky Way photography in the U.S. Mountain West.

That sentence is the scope contract. Darkness, legal access, and sky
conditions for a specific place on a specific night. It is not a trip
planner, not a route planner, not a social network, not a photo gallery, not
a general astronomy app. If a feature does not help answer that one
question, it does not ship in v1. When you are tempted to add something,
re-read this paragraph.

### 2. Why it exists

Existing tools each solve one piece. Light-pollution map sites show darkness
but not land ownership or weather. PhotoPills does ephemeris but not
darkness or access. Land-ownership viewers exist but are not built for
"can I legally stand here at 2 a.m." The gap is the *combination*, presented
as a plan-the-weekend answer rather than three separate lookups.

### 3. Architecture — non-negotiable

**Zero server.** A static site on GitHub Pages plus Python data pipelines
that run in GitHub Actions and publish static assets. No backend, no
database, no API keys in the client, no per-user state on any server.
Hosting cost approaches zero and the app cannot go down because a server
went down.

```
GitHub Actions (scheduled + manual)
  Python pipelines
    fetch source data -> clip to AOI -> normalize -> emit PMTiles / JSON
                                                        |
                                                        v
                                            committed or released artifacts
                                                        |
GitHub Pages  <---- static site build (Vite) ---------- +
    MapLibre GL JS + PMTiles protocol
    client-side astronomy (no API)
    client-side weather fetch on demand (keyless public API)
```

Stack:

- **Client:** TypeScript, Vite, MapLibre GL JS, `pmtiles` protocol adapter.
  No React unless you can justify it in an ADR; prefer small, explicit
  modules and plain DOM with a tiny reactive helper. Whatever you choose,
  choose once and be consistent.
- **Pipelines:** Python 3.11+, `uv` for dependency management, `ruff` and
  `mypy --strict` clean. Each pipeline is a module with a CLI entry point
  and is independently runnable locally.
- **Tiles:** PMTiles v3. Raster tiles for light pollution, vector tiles for
  land ownership.
- **CI:** GitHub Actions — lint, typecheck, unit tests, browser tests, and a
  scheduled data-refresh workflow. CI must pass with **no credentials of any
  kind**.

### 4. Data sources, and the licensing rules you must obey

This section is the single most important part of the brief. Get it wrong
and the project is unusable.

| Layer | Source | License | Status |
|---|---|---|---|
| Light pollution | VIIRS **VNP46A4** (Black Marble annual composite), via `blackmarblepy` | **CC0** | **Use this.** Safe to self-host and to derive tiles from, including for commercial use. |
| Land ownership / manager | **PAD-US** (USGS Protected Areas Database of the United States) | Public domain (U.S. Government work) | **Use this.** |
| Certified dark-sky places | DarkSky International | **No official machine-readable dataset exists** | Hand-curate a small CSV in the repo with a `source_url` and `verified_on` column per row. Do **not** scrape their site. Treat the list as incomplete and say so in the UI. |
| Cloud / sky cover forecast | **Open-Meteo** (primary) and/or **NWS gridpoint API** (CONUS fallback) | Open, keyless | Fetch client-side, on demand, for a clicked point only. No key, no proxy. |
| Elevation / terrain (optional) | USGS 3DEP or an open terrain tile source | Public domain / open | Only if it earns its place. |

**Explicitly forbidden:**

- The **Falchi 2016 World Atlas of Artificial Night Sky Brightness** is
  **CC BY-NC**. Do not use it, do not derive tiles from it, do not ship it.
  Non-commercial licensing would contaminate the project.
- The **Lorenz** light-pollution atlas has **no published license at all**.
  Do not use it.
- Do not scrape any site that does not publish a reuse license.

Ship a `docs/data-licensing.md` that reproduces this table with links, and a
CI test that fails if a forbidden source name appears anywhere in the
pipeline code or configuration.

**Area of interest for v1:** the Mountain West — Utah, Nevada, Idaho,
Wyoming, Colorado, Arizona, New Mexico, Montana. Make the AOI a config
value, not a hardcoded constant, so extending it later is a config change.

### 5. The astronomy — compute it client-side, correctly

No astronomy API. Use `astronomy-engine` (evaluate against SunCalc first and
record the choice in an ADR; `astronomy-engine` is the better default for
accuracy and for Galactic Center work).

For a given latitude, longitude, and date, compute and display:

- **Astronomical darkness window** — sun below −18°. Show start and end in
  local time, and handle the case where astronomical night never occurs
  (high latitude, summer). Do not silently show an empty window; say
  "no astronomical darkness on this date at this location."
- **Moon rise, moon set, and illuminated fraction.** The photographically
  meaningful quantity is *moon-free astronomical darkness* — the intersection
  of the sun-below-−18° window with the moon-below-horizon window. Compute
  that intersection explicitly and make it the headline number, in minutes.
  That single number is the thing nobody else surfaces well.
- **Galactic Center visibility.** GC at RA 17h 45m 40.04s, Dec −29° 00′ 28.1″
  (Sgr A*). Compute altitude and azimuth across the night; report the maximum
  altitude during the moon-free dark window and the time it occurs. Below
  about 10–15° altitude the GC is not usefully photographable — encode that
  as a configurable threshold, not a magic number, and explain it in the UI.
- **Season awareness.** The GC is below the horizon at night for much of
  winter in the Mountain West. If the user picks a date where it never rises
  during darkness, say so plainly rather than showing a chart of nothing.

Every one of these functions is pure — location and time in, numbers out.
Unit-test all of them against known values (a handful of hand-verified
ephemeris results, plus edge cases: summer solstice at 49°N, new moon, full
moon, a date where moonset falls inside the dark window, and a date where it
does not).

### 6. The interface — the map is not the interface

Build this text-first. The answer is text; the map is an enhancement.

```
Location entry (search, click map, or paste coordinates)
        |
        v
Date / night selector  ------->  The Answer (text, above the fold)
        |                          - X minutes of moon-free darkness
        |                          - Bortle-equivalent / radiance at this point
        |                          - Land manager: <name>, <access note>
        |                          - GC max altitude XX° at HH:MM
        |                          - Cloud cover forecast, if within range
        v
    Map (secondary)              Details / provenance (expandable)
```

Hard requirements:

- Every state is reachable and completable **without the map ever receiving
  focus.** A keyboard-only user and a screen-reader user must be able to get
  the full answer. Test this, do not assume it.
- **WCAG 2.1 AA.** Run `axe-core` in CI. Also write explicit Playwright tests
  for the GIS-specific interactions generic scanners miss: search by keyboard,
  toggle a layer, open and close a detail panel with focus returning to the
  trigger, and the whole flow at 200% and 400% zoom.
- **Shareable URL state.** Location, date, and active layers all live in the
  URL. A pasted link reopens exactly the same view and the same answer. Write
  a test that round-trips every piece of state through the URL.
- Mobile-first layout. The real user is standing in a parking lot on cell
  data at 9 p.m. deciding whether to drive another 40 minutes.
- Light and dark themes, with dark as the default, and a genuinely red-shifted
  "field mode" that does not destroy night vision. This is a real requirement
  for the actual use case, not decoration.

### 7. Provenance discipline — the rule that makes it trustworthy

Every number the app displays carries a visible source and a date. Nothing is
presented as authoritative when it is derived or estimated.

- Light pollution comes from an **annual composite** — label the year. A 2024
  composite shown in 2026 is two years stale and the user must be able to see
  that.
- Land ownership from PAD-US is a **boundary dataset, not a permission
  system.** The app says who manages the land and links to the managing
  agency; it never says "you may camp here." Write that disclaimer into the
  UI, not just the docs.
- Weather forecasts carry the model run time.
- The dark-sky places list carries "manually curated, last verified <date>,
  not exhaustive."
- Adopt a consistent freshness convention across all layers: fresh, aging,
  stale, unavailable — with thresholds defined once in config and applied
  uniformly.

If a feed fails, show the last known good value **with its age**, and never a
blank or a zero. A blank reads as "no light pollution here," which is a lie.

### 8. Pipelines — the data build

Each pipeline is idempotent, re-runnable, and diffable.

1. `pipelines/light_pollution/` — fetch VNP46A4 via `blackmarblepy`, clip to
   AOI, reproject to Web Mercator, apply a documented radiance-to-display
   mapping, emit raster PMTiles. Publish the color ramp and its breakpoints as
   data, and render the legend from the same source of truth as the tiles.
2. `pipelines/padus/` — fetch PAD-US, extract the AOI, simplify geometry at
   tile-appropriate zoom levels, normalize the manager taxonomy into a small
   readable set (Federal – BLM, Federal – USFS, Federal – NPS, State, Tribal,
   Private, Unknown …), emit vector PMTiles plus a manager color scheme file.
3. `pipelines/darksky_places/` — validate the hand-curated CSV, emit GeoJSON.
   Fail the build on a missing `source_url` or `verified_on`.

Every pipeline emits a **manifest**: source URL, retrieval timestamp, source
publication date, checksum, output artifact list, and row/pixel counts. The
client reads the manifests to render provenance and freshness. Golden-test the
pipelines against small committed fixtures so CI runs with no network and no
credentials.

Scheduled refresh runs monthly (annual composites do not change often) with
manual dispatch available. Open a GitHub issue automatically if a source is
unreachable or a checksum changes unexpectedly.

### 9. Quality bar

- Unit tests for all astronomy math, URL state, freshness logic, and the
  radiance mapping.
- Golden tests for every pipeline against fixtures.
- Playwright tests for the interaction flows and for accessibility.
- `ruff`, `mypy --strict`, `tsc --noEmit`, and ESLint all clean.
- Lighthouse performance budget enforced in CI; the app must be usable on a
  throttled 3G connection.
- No secret, key, token, or credential anywhere in the repository, in any
  form, at any point. There is no legitimate reason for one to exist here.

### 10. Documentation you must write

- `README.md` — what it answers, a screenshot generated from the real build,
  quickstart, and architecture diagram.
- `docs/data-licensing.md` — the table from section 4, with links.
- `docs/methods.md` — exactly how every displayed number is computed,
  written for a skeptical reader. Plain language, no forecasts, no claims the
  math does not support.
- `docs/adr/` — one numbered ADR per real decision: framework choice,
  astronomy library, tile format, manager taxonomy, radiance mapping,
  freshness thresholds. Each records the decision, alternatives considered,
  and the reasoning.
- `CONTRIBUTING.md` — how to run the pipelines locally and how to extend the
  AOI.
- MIT license.

### 11. How to work

1. Plan the whole build first and write it down as a task list.
2. Build in the order: pipelines → data contracts → astronomy module →
   text-first UI → map → polish. The map comes late deliberately; if the
   answer is not right in text it will not be right on a map.
3. Commit in small, coherent commits with real messages.
4. Verify your own work by running it — pipelines against fixtures, the site
   in a real browser, the accessibility tests for real. Do not report
   completion on anything you have not run.
5. When you make a judgment call, write the ADR and continue.
6. At the end, produce a short written report: what shipped, what you chose
   and why, what you deliberately left out, and what you could not verify.

Build it.

---

## Notes for Brian (not part of the prompt)

- Name is still a placeholder — run it through the domain gauntlet before the
  repo goes public.
- The moon-free-darkness intersection is the genuinely differentiated number.
  If only one thing survives contact with reality, keep that.
- The Falchi/Lorenz exclusions are the trap most likely to be tripped by a
  model reaching for "the" light pollution dataset. That is why they are
  called out twice.
