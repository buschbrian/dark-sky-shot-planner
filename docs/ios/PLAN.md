# iOS field companion — plan

**Status:** plan, written 2026-09-25 on Windows, to be built on the M4 MacBook.
**Why:** ADR-0009 (scope + native app) and ADR-0010 (stateless Worker).
**How to work:** on the Mac, use the copy-paste prompts in
`docs/ios/MAC-PROMPTS.md`. One milestone at a time, in order. Each ends with the
listed checks passing and a short note in §Log. Do not start a milestone
whose predecessor's checks are not green.

## The job

Replace the six apps opened on every shoot night (PhotoPills, Astrospheric /
Clear Outside, an AQI app, a Kp app, a weather app, notes) with one app
that answers:

> **Should I go shoot tonight — and if so, where, when, and how?**

Answer first, then the evidence. The headline stays what makes this project
different: **minutes of moon-free astronomical darkness**, and from M9 on,
moon-free darkness *above your actual horizon*.

## Screens

| Screen | Answers | First milestone |
|---|---|---|
| **Tonight** | Verdict (go / marginal / no-go) + limiting factor, moon-free minutes, GC window, moon, then a night strip: darkness bands × hourly cloud layers, AOD, transparency, wind, dew | M2 (astronomy), M4 (conditions) |
| **Week** | Next 7 nights for the current spot, one row each: verdict, moon-free minutes, cloud mean | M5 |
| **Map** | Pin → azimuth lines (sun, moon, GC rise/set and at a chosen time), light pollution, land manager, dark-sky places, smoke polygons, GOES IR loop | M6 |
| **Sky (AR)** | Camera view with MW band, GC path by hour, moon, planets, and the terrain horizon | M7 |
| **Spots** | Saved places with their horizon profile, notes, week verdicts; "alert me when" rules | M8 |
| **Tools** | NPF / 500 rule, star trails, hyperfocal, stacking, timelapse, all per saved camera+lens | M10 |

Field mode (all-red UI) is a toggle reachable from every screen, and it is on
by default after civil dusk if the owner opts in.

## Verdict

A **worst-gating-factor** rule, not a weighted score. Each factor is rated
good / marginal / poor against `config/conditions-thresholds.json`, and the
night's verdict is the worst rating among factors with `gates_verdict: true`,
evaluated over the moon-free dark window. The screen always names the
limiting factor ("No-go: smoke, AOD 0.41") and one tap shows every factor
with its source and age.

Why not a 0–100 score: a weighted sum hides the one thing that kills the
night, and invites arguing about weights instead of looking at the sky. A
worst-factor rule is explainable in one sentence and trivially testable.

Rules the verdict must follow:
- A factor with **no data** is "unavailable", never good. If any gating factor
  is unavailable, the verdict is at best "marginal — incomplete data".
- Stale data (ADR-0006) caps the verdict at marginal.
- Aurora (Kp) never lowers a verdict; it adds an "aurora possible" flag.
- Dew, PM2.5, observed AQI and transparency are advisories, not gates (see the
  notes in the thresholds file). Observed AQI is PM2.5-only: ozone rows are
  ignored. Transparency's only source, 7Timer, is optional (owner, 2026-09-26).
- Live conditions age in whole hours, per source (`freshness_hours` in
  `config/app-config.json`): a daily smoke issue is not "stale" every evening.
- A factor whose thresholds are `null` (surface dust) is shown with its value
  and source but never rated.
- Haze thresholds (AOD, RAP-Smoke column, PM2.5, AQI) were researched on
  2026-09-26 against AERONET NEON_MOAB/NEON_ONAQ and Wasatch Front PM2.5
  monitors; each factor's note in the thresholds file gives the evidence.
- The thresholds are proposals. When a real night disagrees with the
  verdict, write it in §Log and adjust the config, not the code.

## Architecture

```
iPhone (SwiftUI)                                   Cloudflare (stateless)
  App target: views, sensors, SwiftData ──────►  worker/  GET /v1/conditions
  Packages/SkyCore (pure Swift + C)                        GET /v1/space-weather
    CAstronomy  ← astronomy-engine C (MIT)                 GET /v1/smoke
    Planner / SkyPositions / Verdict /                     GET /health
    Calculators / Horizon                                    │ fans out, caches by cell+run
  Widgets (WidgetKit)                                        ▼
  BGAppRefreshTask → local notifications           Open-Meteo, 7Timer, SWPC, HMS, AirNow
  Map: MapLibre Native + PMTiles from data/out     (keys = Worker secrets)
  Imagery: NASA GIBS tiles, direct (keyless)
```

- **Shared with the web app:** everything in `config/` (bundled into the app
  at build time), `data/out/` PMTiles (fetched from the Pages site, cached
  for offline), `shared/golden/` test vectors.
- **Persistence:** SwiftData models `Spot`, `Plan`, `Gear`, `ConditionsSnapshot`,
  `HorizonProfile`; CloudKit private-database sync behind a setting.
- **Networking:** one `ConditionsClient` that talks to the Worker and falls
  back to direct Open-Meteo for clouds if the Worker is unreachable. Every
  response is stored as a `ConditionsSnapshot` with `fetched_utc`, so the
  offline view is just "render the newest snapshot, with its age".
- **Project generation:** XcodeGen (`ios/project.yml`). The `.xcodeproj` is
  generated and gitignored, so agents edit YAML instead of `project.pbxproj`.

## Data sources

Every row must also appear in `docs/data-licensing.md` before code fetches it.
Status and license details: see that file's "Used by the conditions Worker"
and "Proposed for the iOS companion" sections.

Endpoints below were fetched live on 2026-09-25 by the research pass whose
notes are in `docs/data-licensing.md`.

| Need | Source | Via | Notes |
|---|---|---|---|
| Cloud cover total + low/mid/high, hourly | Open-Meteo forecast: `ncep_hrrr_conus` (3 km), `gfs_global`, `icon_global` (DWD ICON, ~11 km), `ecmwf_ifs025` side by side | Worker (fallback: direct) | Show model disagreement as a band, don't average it away. Named models only, never a `*_seamless` alias: over Utah `gfs_seamless` serves HRRR for roughly the first 40 h, `gem_seamless` is `gem_regional` and `icon_seamless` is `icon_global`, so an alias would repeat a series and hide the disagreement. Aliases also have no `meta.json`; run times come from `ncep_hrrr_conus`, `ncep_gfs013`, `dwd_icon` and `ecmwf_ifs025`. **ICON replaced GEM HRDPS (2026-09-26):** `gem_hrdps_continental` answers "No data is available for this location" at 38.35, −109.95 and 37.60, −110.00, because its domain misses much of southern Utah. ICON is global, publishes native low/mid/high cloud, runs every 6 h, is independent of NOAA, ECMWF and ECCC, and is CC BY 4.0 via Open-Meteo. It has no `visibility` (served as unavailable). Alternates if ICON fails: `gem_regional` (meta `cmc_gem_rdps_10km`; low/mid/high derived from humidity) or `ukmo_global_deterministic_10km` (CC BY-SA 4.0, share-alike). Never use the stale meta ids `cmc_gem_rdps`/`cmc_gem_gdps` (last run 2026-05-26). Deferred: NWS `api.weather.gov` gridpoint `skyCover` as an "official NWS" reference line (total cover only; NBM plus forecaster edits, so not an independent model). **Not** `ncep_nam_conus` (NOAA retires NAM 2026-10-14) or `ncep_nbm_conus` (no cloud layers) |
| Model run time | Open-Meteo `/data/{model}/static/meta.json` → `last_run_initialisation_time`; next run estimated from `last_run_availability_time` + `update_interval_seconds` ([docs](https://open-meteo.com/en/docs/model-updates)) | Worker | The forecast response doesn't carry it; the brief requires it |
| Dew point, humidity, wind, gusts, visibility, temperature | Open-Meteo forecast (HRRR has all of them) | Worker | ICON and ECMWF return no visibility; those series are unavailable, never zero |
| Seeing proxy | Open-Meteo `wind_speed_250hPa` / `200hPa` (jet stream) | Worker | Our own, license-clean seeing indicator |
| Seeing + transparency indices | 7Timer! ASTRO (GFS-based, 3-hourly, indices 1–8) | Worker (no CORS) | **Non-commercial use only**. Fine for personal use, blocks App Store distribution without written permission. Optional, never required |
| Smoke forecast, near-surface + vertically integrated | NOAA **RAP-Smoke** (not HRRR-Smoke; NWS SCN 22-42) via NWS NDGD ImageServers (`air_quality/ndgd_smoke_{sfc,vert}_1hr_avg_time`), `identify` at a point. 13 km RAP regridded to the 5 km NDGD grid; one 03Z issue a day, 03Z day 1 to 06Z day 3; instantaneous values despite "1hr_avg" | Worker | **Primary smoke/transparency signal.** Units calibrated in `docs/methods.md` §Smoke forecast units (the service's µg/m³ text is wrong: raw kg/m² column, kg/m³ at 8 m). The vertically integrated field is what dims the sky |
| AOD, PM2.5, dust | Open-Meteo Air Quality (CAMS Global, ~45 km, 12-hourly) | Worker | Coarse. Use as a fallback and a cross-check for RAP-Smoke, attributing CAMS + Open-Meteo |
| Observed AQI | EPA AirNow `/aq/observation/current/ziplatLong/` | Worker (key) | The old `latLong/current` path retires 2026-09-30. Must be labelled "preliminary" and credit the reporting agencies |
| Analyst smoke polygons | NOAA HMS via NESDIS ArcGIS FeatureServer (`NOAA_Satellite_Smoke_Detection_(v1)`), GeoJSON + CORS | Direct or Worker | Human analysis, daytime only. At night it shows the previous afternoon, so label its time |
| Kp observed + 3-day forecast | SWPC `products/noaa-planetary-k-index{,-forecast}.json` | Worker (KV cache) | Now arrays of objects, so parse by key |
| Aurora oval | SWPC `json/ovation_aurora_latest.json` (1° grid, ~5 min, ~1 MB) | Worker | Worker reduces it to "aurora % near this cell" |
| Night cloud imagery (IR loop) | NASA GIBS `GOES-{West,East}_ABI_Band13_Clean_Infrared` (Level6, 10-min, ~30–40 min latency) | Direct from app | Get valid times from DescribeDomains, since steps have gaps. GIBS attribution text required |
| Light pollution | VNP46A4 (existing pipeline) | `data/out/` PMTiles | Unchanged |
| Land manager | PAD-US (existing pipeline) | `data/out/` PMTiles | Unchanged, never "you may camp here" |
| Terrain / horizon | Measured profiles in `config/horizon-profiles/`; computed from AWS Terrain Tiles (terrarium, z≤15, keyless) or USGS 3DEP `getSamples` | App (M9) | Validate computed profiles against Candlestick Camp's measured one |

**Distribution caveat:** as a personal app, every source above is usable.
Before any App Store / TestFlight-for-others release, three need action.
Open-Meteo needs a paid API plan (the free tier is non-commercial). 7Timer
needs written permission or has to be dropped in favour of the jet-stream
proxy. The Mapterhorn terrain terms are unstated, so avoid Mapterhorn.

**NOAA model changes:** per NWS SCN 26-48, RRFS v1 goes operational 2026-10-14,
replacing NAM, HREF, SREF and HiresW; HRRR and RAP (so RAP-Smoke) retire with
RRFS v2, around 2027–28. Open-Meteo has no RRFS yet
([open-meteo#1849](https://github.com/open-meteo/open-meteo/issues/1849)).

Deferred and needing a decision first: raw HRRR GRIB2 range-reads from
`noaa-hrrr-bdp-pds` (only if the ImageServers prove unreliable),
satellite/Starlink passes, Apple Watch.

## Worker

`worker/` — TypeScript, Wrangler, Vitest with recorded upstream fixtures
(no network in tests). Structured like the Blaumeux Worker.

```
GET /v1/conditions?lat=38.35&lon=-109.95&start=2026-09-26T00:00Z&end=2026-09-26T14:00Z
→ {
    "cell": { "lat": 38.35, "lon": -109.95, "rounding_deg": 0.05 },
    "next_update_expected_utc": "…",
    "fields": {
      "cloud_cover_low": {
        "unit": "%",
        "series": [ { "model": "hrrr", "model_run_utc": "…", "next_run_expected_utc": "…",
                      "values": [ { "t": "…", "v": 12 } ] }, … ],
        "source": "Open-Meteo", "fetched_utc": "…"
      },
      "visibility": { …, "series": [ … ],
        "series_15min": [ { "model": "hrrr", "resolution_minutes": 15, … } ] },
      "aerosol_optical_depth": { … },
      "transparency": { …, "status": "unavailable", "last_good_utc": null }
    }
  }
GET /v1/space-weather   → Kp observed + forecast, aurora-oval summary (global, KV-cached)
GET /v1/smoke?bbox=…    → HMS polygons clipped to bbox as GeoJSON, with the analysis date
GET /health             → per-upstream status and last success time
```

The Worker rejects coordinates that aren't already rounded to the 0.05° grid,
so the privacy rule is enforced server-side as well as in the client.
Values the Worker cannot get come back as `"status": "unavailable"`, never
dropped and never zero.

### Request rules

Anything outside these answers 400 before any upstream call.

- `lat`, `lon` and every `bbox` corner must already sit on the 0.05° grid.
- `/v1/conditions` needs `start` and `end` with a UTC offset (`Z` or `±hh:mm`).
  Start rounds down and end rounds up to the hour. The window is at most
  48 h, starts no earlier than now − 2 days and ends no later than now + 16 days.
- `/v1/space-weather` takes an optional cell: both `lat` and `lon`, or neither.
- `/v1/smoke?bbox=minLon,minLat,maxLon,maxLat` needs min < max and is capped at
  30° of longitude × 20° of latitude.
- Only `GET` and `OPTIONS` (CORS preflight, origin `*`); other methods get 405.

### Behaviour

- **`/health` makes no upstream calls.** Per upstream it reports the last
  success and last failure (with its error) recorded by real requests in this
  isolate and this data center's cache: `unknown` until one is seen, `failing`
  when the latest failure is newer than the latest success. It also reports
  whether the AirNow key is set (never the key), the KV binding, the edge
  cache and 7Timer.
- **Aurora "% near this cell"** is the maximum OVATION probability over the
  3×3 one-degree grid points around the cell (cell rounded to whole degrees,
  ±1° in latitude and longitude, longitude wrapped to 0–359).
- **RAP-Smoke** uses one `identify` per layer, with `time` spanning the whole
  window, instead of one call per hour. Values are read in catalog order,
  `idp_subset=conus` only, newest issue per valid hour (validated 14/14
  against per-slice calls on 2026-09-25; `docs/methods.md`). The service
  answers 0, not NoData, outside its coverage, so a cell outside a conservative
  lower-48 box (24–50° N, 125–66° W) is unavailable without a request. An issue
  hour other than 03Z, or a forecast hour past 51, marks the series
  unavailable, since the source has probably changed (for example to RRFS).
- **Caching:** upstream results go in the Cache API, keyed by source, cell and
  window; a new model run makes a cached forecast stale. Entries are kept a
  week so they can serve as last-good values. Space
  weather uses KV when `SPACE_WEATHER` is bound, otherwise the Cache API.
  The cache is run-aware (2026-09-26): a model's `meta.json` is kept until
  its next run is expected (capped at 1 h), then re-read every 2 min while
  the run is late. A forecast is kept while `meta.json` reports the same run
  (capped at 6 h). A forecast fetched within 10 min of its run's
  availability is read once more after that, because Open-Meteo asks
  clients to wait 10 min for its servers to sync
  ([model updates](https://open-meteo.com/en/docs/model-updates)).
  RAP-Smoke is kept until its next issue is expected (capped at 6 h,
  re-checked every 15 min while late), not for a fixed 30 min. Cache and
  health writes go through `ctx.waitUntil`, after the response.
- **Refresh times.** Every series carries `next_run_expected_utc`, the
  Worker's estimate of when its source publishes the next run. `null` means
  there is no basis for one, or that the series is being served from a
  last-good copy. The response carries `next_update_expected_utc`, the
  soonest estimate among series served fresh.
  - Open-Meteo models and CAMS: `last_run_availability_time` +
    `update_interval_seconds` + 600 s, all from `meta.json`. This assumes
    the next run is as late as the last. Recorded cadences: HRRR 1 h; GFS,
    ICON and ECMWF 6 h; CAMS 12 h. `temporal_resolution_seconds` (3600;
    ECMWF 10800) is the step between values, not the update cadence.
  - RAP-Smoke: newest issue + 24 h + that issue's delay, from issue time
    to the latest `idp_ingestdate` on the ImageServer catalog (about 83 min
    on 2026-09-25).
  - 7Timer: `null`. It publishes no schedule, and the Worker re-checks it
    every 3 h.
- **Revalidation.** `/v1/conditions`, `/v1/space-weather` and `/v1/smoke`
  send a strong `ETag`: the first 128 bits of the SHA-256 of the JSON, with
  `generated_utc` and `fetched_utc` removed. The tag changes when a run,
  value, status or reason changes, and not when the Worker merely re-reads
  an upstream. A matching `If-None-Match` answers 304 with no body. It uses
  the weak comparison, because Cloudflare may weaken a strong tag when it
  recompresses a response.
  `/v1/conditions` has `Cache-Control: public, max-age=N,
  stale-while-revalidate=600`. N runs to `next_update_expected_utc`,
  bounded to 60–1800 s. It is 60 s when that time has passed (the run is
  late) and 300 s when there is no estimate. Space weather keeps
  `max-age=300`, smoke `max-age=600`. Errors and `/health` are `no-store`.
- **Near term (15 min).** `temperature`, `dew_point`, `wind_speed`,
  `wind_gust` and `visibility` carry `series_15min`: one HRRR series with
  `resolution_minutes: 15`. It covers the part of the window up to the
  current hour + 18 h, and values past the run + 18 h are dropped. HRRR
  publishes 15-minute output only for the first 18 h of each run, and
  beyond that Open-Meteo interpolates. The hourly `series` are unchanged.
  Cloud cover has no 15-minute series: Open-Meteo's `minutely_15` cloud
  cover (all layers) and relative humidity equal a Catmull-Rom
  interpolation of the hourly values at every point checked (2026-09-26,
  from 19 h in the past to 44 h ahead), so they add nothing. The docs list neither as a native
  15-minute variable ([forecast API](https://open-meteo.com/en/docs)).
- **Server-Timing.** Every cacheable answer lists each source's wall time
  and whether the cache answered, for example `om-hrrr;dur=182;desc="miss"`,
  plus `total`. The names are `meta-<id>`, `om-<model>`, `om15-hrrr`,
  `smoke-sfc|vert`, `airnow`, `7timer`, `swpc-*` and `hms`. Workers' clock
  advances only on I/O, so these are waits on caches and upstreams.
  `Timing-Allow-Origin: *` and the exposed headers let the web app read it.

### Abuse protection

- **Rate limit:** the Workers Rate Limiting binding `RATE_LIMITER` (wrangler
  `ratelimits`), keyed on `cf-connecting-ip`, 120 requests per 60 s. Over the
  limit the Worker answers 429 `{"error":"rate limited"}` with `Retry-After: 60`
  before any upstream call. Preflights aren't counted. With no binding (tests)
  or a binding error it fails open. The counter is per Cloudflare location and
  eventually consistent. Cloudflare advises against IP keys because carrier NAT
  shares addresses; a keyless API has no better key, hence the generous limit.
  [Docs](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
  (`period` must be 10 or 60; `namespace_id` is shared account-wide).
- **Fan-out cap:** at most 20 upstream fetches per incoming request
  (`src/limits.ts`). A cold `/v1/conditions` makes 15: four models ×
  (`meta.json` + forecast), HRRR's 15-minute request, air quality × 2, two
  smoke layers, AirNow and 7Timer. All of them start together: the cached
  forecast is read while `meta.json` is in flight, so the fan-out is one
  round trip deep. `wrangler dev` on 2026-09-26 took 0.95 s cold, 13 ms
  warm, and 28 ms for a 304.
  A fetch past the cap is reported as that source being unavailable
  ("per-request upstream budget spent").

### Platform notes (checked 2026-09-25)

- **KV id:** `SPACE_WEATHER` has no `id`. Wrangler's automatic provisioning
  creates the namespace on the first deploy; from Workers Builds the id is not
  written back to the repo, but the binding stays linked. `wrangler dev`
  uses a local namespace.
  [Docs](https://developers.cloudflare.com/workers/wrangler/configuration/#automatic-provisioning)
- **Cache API on `*.workers.dev`: not confirmed.** The
  [Cache API page](https://developers.cloudflare.com/workers/runtime-apis/cache/)
  says Workers on custom domains have functional cache operations, and that
  the dashboard editor and Playground previews have none. It does not list
  `*.workers.dev` as a no-op (earlier versions of the page did), and it
  describes a `.workers.dev` cache-key rule, which suggests `cache.put` works
  there. It never says so outright. After the first deploy, call the same
  `/v1/conditions` twice, a minute apart: if `/health` shows `open-meteo-forecast`
  `last_success_utc` unchanged after the second call, the cache works. If it
  doesn't, every request fans out upstream. Correct, but slower and heavier
  on the sources.

### Pre-deploy decisions (owner)

1. **Route:** `*.workers.dev`, or a custom domain. Use the custom domain if the
   cache check above fails on `workers.dev`.
2. **Rate limit:** keep 120/min, and confirm `namespace_id` `"10010"` is unused
   by the account's other Workers.
3. **KV:** let Workers Builds auto-provision `SPACE_WEATHER`, or create it and
   pin its id in `wrangler.jsonc`.
4. **`AIRNOW_API_KEY` secret.** (The HRDPS replacement is settled: DWD ICON
   Global, see §Data sources.)

## Milestones

Each milestone lists what "done" means. "Owner checks" are things only a
real phone at a real dark site can prove. Record their outcome in §Log.

### M0 — SkyCore package (Command Line Tools only, no Xcode yet)
Machine setup: `docs/ios/MAC-SETUP.md`, Phases 1–3. The repo stays in
`~/Developer`; the SSD holds DerivedData, archives and optionally Xcode.
- `ios/Packages/SkyCore` Swift package with `CAstronomy` (vendored
  `astronomy.c`/`astronomy.h` from cosinekitty/astronomy v2.1.19, the same
  version as the web app's npm package, with LICENSE alongside and version
  recorded) and an empty `SkyCore` target. `heirloomlogic/AstronomyKit`
  (MIT, wraps the same C code) is a useful reference for the Swift wrapper
  shape. Don't depend on it: it has a single maintainer and 7 stars.
- Tests use **Swift Testing** (`import Testing`), never XCTest. XCTest is not
  in the Command Line Tools, and Swift Testing is the current standard anyway.
- `.github/workflows/ios.yml`: macOS runner, `swift test` in SkyCore.
- **Done when:** `swift test` passes locally **and reports a non-zero test
  count** (see the zero-tests trap in MAC-SETUP.md), and passes in CI.
- *Note 2026-09-25:* without Xcode (Command Line Tools only), `swift test`
  needs the `-plugin-path` workaround in SkyCore's `Package.swift` (the
  Phase 1 `-F` flags in MAC-SETUP.md were not enough on this Mac). It is a
  no-op under Xcode (installed 2026-09-26) and stays, so SkyCore still tests
  with the Command Line Tools alone (ios/AGENTS.md). `ios.yml` is deferred by
  the owner until the local build is solid.

### M1 — SkyCore astronomy parity
- Port `planner.ts` (darkness window, moon-up intervals, moon-free windows,
  GC visibility, `planNight`) to Swift over CAstronomy.
- Add what the web app doesn't have yet but AR and the map need: alt/az
  series for sun, moon, GC, planets; Milky Way band as a set of galactic-plane
  points (l = 0…360°, b = 0) converted to alt/az; rise/set/transit azimuths.
- Load `config/app-config.json` (GC threshold) as a bundled resource.
- **Done when:** a SkyCore test reads `shared/golden/night-report.json` and
  every case passes within its tolerances; alt/az spot-checks agree with the
  web app's `gcAltitude`/`gcAzimuth` within 0.1°.

### M1b — App scaffold (needs Xcode, see MAC-SETUP.md Phase 4)
- Xcode 27 (macOS Tahoe 26.6+), iOS platform only, DerivedData on the SSD.
- `brew install xcodegen`; `ios/project.yml` with App, Widgets, and UI-test
  targets that depend on the local SkyCore package; bundle ID and team set in a
  gitignored `Local.xcconfig`.
- Add `maplibre-gl-native-distribution` (SPM, BSD-2, ≥ 6.31; PMTiles
  supported natively since 6.10) now, so the dependency graph is settled early.
- **Done when:** `xcodegen generate && xcodebuild build` pass, and the app
  launches **on the owner's iPhone** to a placeholder (the simulator is optional).

### M2 — Tonight, offline
- Location: GPS, saved spot, or pasted coordinates (also accept the web app's
  share URL so a link opens the same place and date).
- Date picker ("tonight" default; the night containing local midnight).
- Answer-first layout: moon-free minutes (headline), darkness window, moon
  rise/set/illumination, GC peak altitude and time, or "out of season".
- Night strip (Swift Charts): sun/moon altitude, darkness shading, moon-free
  band, GC altitude curve.
- Field mode (red) and dark theme.
- **Done when:** the screen works in airplane mode; UI test covers location
  entry by typing coordinates and switching dates; VoiceOver reads the answer
  in order.
- **Owner checks:** read it in field mode at a dark site. Is anything too
  bright? Is anything unreadable?

### M3 — Worker v1 (can be built on Windows)
- `/v1/conditions`: Open-Meteo forecast (multi-model) with run times from
  each model's `meta.json`, Open-Meteo air quality, RAP-Smoke point values
  from the NDGD ImageServers, AirNow (new `ziplatLong` path), then 7Timer.
  `/v1/space-weather`; `/v1/smoke`; `/health`.
- **Calibrate RAP-Smoke units first.** Compare ImageServer `identify` values
  against the NDGD GRIB2 and a raw RAP `COLMD`/`MASSDEN` read (`noaa-rap-pds`)
  for the same cell and hour, and write the conversion and evidence into
  `docs/methods.md`. Done 2026-09-25; the smoke factor is still shown but does
  not gate until its thresholds are set.
- Fixture-recorded tests for every upstream, including one "upstream down"
  fixture per source.
- Deploy with Workers Builds; the only secrets are upstream keys.
- **Done when:** `npm test` in `worker/` passes offline; deployed `/health`
  green; the web app can optionally call it (one small PR there too).

### M4 — Conditions + verdict on Tonight
- `ConditionsClient` + `ConditionsSnapshot` cache; the night strip gains cloud
  low/mid/high (one row per model), AOD, transparency, wind, dew spread.
- `Verdict` in SkyCore implementing §Verdict, driven by
  `config/conditions-thresholds.json`, with table-driven tests for every rule
  (including unavailable, stale, and aurora flag).
- **Done when:** verdict tests pass; airplane mode shows the last snapshot
  with its age; killing the Worker falls back to direct Open-Meteo for clouds
  and shows everything else as unavailable.
- **Owner checks:** three real nights. Did the verdict match the sky? Log it.

### M5 — Week view + space weather
- Seven-night outlook per spot (verdict, moon-free minutes, cloud mean).
- Kp now/forecast, aurora flag when Kp reaches the visible threshold for the
  spot's latitude.

### M6 — Map planner
- MapLibre Native (`MLNMapView` wrapped in `UIViewRepresentable`; the
  `swiftui-dsl` package is pre-1.0, so only adopt it if it has stabilized),
  PMTiles from `data/out/` (light pollution, PAD-US), dark-sky places, HMS
  smoke polygons (NESDIS FeatureServer, labelled with analysis time), and a
  GOES band-13 loop from GIBS (times from DescribeDomains).
- Pin → azimuth lines for sun/moon/GC rise and set, plus "at time T" with a
  time scrubber (PhotoPills-planner style); line length and label legible
  in field mode.
- Offline region download for saved spots.
- **Done when:** lines match SkyCore azimuths (unit test on the geometry);
  map is never the only way to reach a state (invariant 5 applies on iOS too).

### M7 — Night AR
- CoreMotion attitude in `.xTrueNorthZVertical` + `CLHeading`, drawn over an
  `AVCaptureSession` preview. Not ARKit world tracking: it relies on camera
  features that disappear in the dark, and it samples compass heading once at
  session start. Overlay: MW band, GC with hour ticks across the night, moon,
  bright planets, cardinal points, and the horizon profile when one exists.
- Show `headingAccuracy` and refuse to look confident when it is negative or
  large.
- Heading calibration: align on the moon, a planet, or a known peak, since
  magnetometers near vehicles and tripods lie.
- Time scrubber shared with the map.
- **Done when:** a projection unit test places a known alt/az on the right
  pixel for a fixed camera intrinsics + attitude.
- **Owner checks:** at a site, does the GC overlay land on the real GC
  within a few degrees after calibration?

### M8 — Spots, alerts, widget
- Saved spots with notes, horizon profile, and per-spot week verdicts.
- "Alert me when a night this week is Go at <spot>": BGAppRefreshTask
  re-checks, local notification. **Best-effort by owner decision
  (2026-09-26):** iOS schedules this opportunistically, so the UI says so and
  shows "last checked" / "couldn't check"; no server-side push (that would
  break ADR-0010's statelessness).
- Home Screen / Lock Screen widget: tonight's verdict + moon-free minutes for
  the pinned spot. The astronomy is precomputed into the timeline, so only
  conditions need refreshes (Apple: a frequently viewed widget gets roughly
  40–70 a day).
- CloudKit sync toggle.

### M9 — Terrain-aware darkness
- Horizon profiles from `config/horizon-profiles/` first (Candlestick Camp
  is already measured), then computed on-device for any saved spot by
  ray-marching 360 azimuths over AWS Terrain Tiles (terrarium PNG, z15,
  `elev = R*256 + G + B/256 − 32768`, keyless), with earth curvature and
  refraction. Cache the profile with the spot so it works offline.
- Validation: the computed Candlestick profile must match the ArcGIS Skyline
  measurement (3DEP 10 m) within 0.5° RMS. That's the test that proves the
  DEM path.
- Moon "up" means above the *terrain*, not the mathematical horizon. That
  moves moonrise later behind a ridge and adds real minutes of moon-free
  darkness. The same terrain limits when the GC clears the skyline.
- Port the same change to the web app so both keep one set of numbers
  (extend the golden vectors with a horizon-profile case).
- **Done when:** golden vectors include Candlestick Camp with its measured
  profile, and both web and iOS pass them.

### M10 — Exposure tools
- Gear profiles (camera: sensor size, resolution/pixel pitch; lens: focal
  length, max aperture), entered by the owner, not scraped.
- Curated, cited presets seed these profiles, still editable: ADR-0012, `config/gear-presets.json`.
- NPF rule, 500 rule (labelled as the rough one), star-trail length,
  hyperfocal/DoF, stacking count for a target SNR, timelapse interval/frames.
- Pure functions in SkyCore with published worked examples as tests.

### M11 — Shot window

**Status (2026-09-27):** SkyCore and the views are built and merged, but no
screen instantiates `ShotWindowCard`/`ShotWindowSection`/`ShotTargetPicker`
(`docs/ios/REVIEW-2026-09-27-FABLE.md` B-3) — the shot window is not
reachable in the app yet. Being wired onto Tonight now; see
`docs/deepsky/PLAN-ANY-ASTRO.md` "Before M13" for the fixes that gate both
this wiring and M13.

- One trustworthy answer for one shot: pick a target (GC, Milky Way arch, the
  moon, a planet) at a spot, and Tonight shows when it clears that spot's
  terrain horizon, the moon-free minutes left while it is up, and whether
  clouds or smoke threaten those same minutes, with each model's run time,
  age and disagreement (`docs/ios/ASTRONOMY-APP-RESEARCH-2026-09-26.md`).
- Adopts the Worker's `next_update_expected_utc`, ETag revalidation and
  15-minute HRRR series in `ConditionsClient`.
- **Owner checks:** time a real go/no-go decision against the current
  PhotoPills + weather-app routine at a dark site.

### M12 — Capture (ADR-0011)

**Status (2026-09-27):** built and checked on the owner's iPhone 18 Pro Max
(§Log, 2026-09-27) — capability probe, a 5-frame ProRAW sequence, on-device
stacking, and lifecycle tests all passed indoors. **Not yet done:** an
actual night-sky capture. Indoors, fewer than half the frames aligned on
"stars", so registration on a real star field is unverified; the tripod
stability thresholds, infinity focus and the real UI leave/interrupt path
(Back button, Home, lock) are also unverified (`docs/ios/CAPABILITIES.md`).

- Capability probe on the owner's phone first; its numbers go into
  `docs/ios/`.
- Tripod capture: longest usable frames, locked infinity focus, RAW where
  supported, every frame kept; star-registered, sigma-clipped average (or
  maximum for trails) computed on device. No generative or learned
  enhancement.
- The iPhone's own camera is a gear profile, so NPF and trail limits apply.
- **Owner checks:** a real stack of the Milky Way from a tripod; battery,
  heat and storage over a 10-minute sequence.

### Field validation (owner, before claiming accuracy)
- Terrain horizon at two or three more sites of different relief (the
  Candlestick DEM check passes 0.494° against a 0.5° bound).
- Compass and AR alignment near the car and a metal tripod and away from them.
- Offline forecast age after a day without signal; battery over a night.
- Verdict against the actual sky, logged here.

### Later (each needs its own decision)
Live Activity during a shoot (countdown to moonrise / GC set / dawn), Apple
Watch complication, HRRR-Smoke via a pipeline, satellite-pass warnings for
long exposures, App Store / TestFlight distribution (re-check every data
source's terms for distribution first).

## Log

Record milestone completions, owner field checks, and verdict-vs-reality
nights here, newest first.

- 2026-09-27: **Capture UX (product review §6–§7)**, merged at 6df5573.
  A fixed bottom bar holds Start, "Stop and stack" and Cancel (frames are
  always kept), with progress and heat; settings turn read-only during a
  run. The exposure label gives the chosen value and the maximum ("longest"
  only at the maximum). Explicit 12/48 MP choice with storage estimates.
  Named 44 pt focus steps. "How to shoot" guide: an Apple Camera path
  (Night mode Max, flash and Live Photos off, Apple links) and a Dark Sky
  path (this phone's detected ceiling, four separate times, recommended
  preset). Results view with counts, an unaligned notice, "Save image"
  first and originals separate. Star trails read the Sky design. No AI
  denoise yet: iOS has no on-device model, and one would need a licensed
  model plus night validation. Checks: 7 `CaptureScreenTests` on
  `-CaptureDemo` states (field scans 0 non-red pixels), 9 SkyCore
  `CaptureGuidanceTests`. **Not run on the phone.** Owner checks: the bar
  and guide at night, one-handed Start/Stop, Save image to Photos,
  `-CaptureSelfTest YES -CaptureSelfTestNoPhotos YES`. Known shell issue:
  the field dock overlaps the bottom of screens pushed from Tools; Capture
  pads itself, others (NPF calculator) still need it.

- 2026-09-27: **M12 capture, built and checked on the owner's iPhone 18 Pro
  Max** (branch `local/ios-capture`; indoors, no night-sky test yet).
  - **Probe** (`-CameraProbe YES`, `docs/ios/iphone18promax-camera-probe.json`,
    summary in `docs/ios/CAPTURE-LIMITS.md`): every format of all three back
    cameras stops at 1.0 s. Main camera ISO 55–12,320, f/1.48–4.0; ultra wide
    ISO 15–3,600, f/2.2; telephoto ISO 15–7,680, f/2.8. No Bayer RAW anywhere;
    ProRAW (`l64r` → DNG) only on the 48 MP formats, which the app uses.
  - **Sequence** (`-CaptureSelfTest YES`, the real `CaptureModel` run): 5
    ProRAW DNGs, 4032×3024, EXIF 1.0000 s, ISO 800, f/1.48, 25–28 MB each.
    Sensor timestamps are 1.00 s apart, so each frame is a new exposure. Two
    defects were found and fixed on the phone first: frame 1 at 1/15 s (the
    exposure lock is now awaited), and five "1 s" frames in 0.6 s from the
    zero-shutter-lag ring buffer (ZSL off, requests paced, timestamps
    checked). Stacked on the phone in 2.8 s (decode 1.1, stars 0.4, combine
    1.2 s) into a 16-bit linear-sRGB TIFF, 3024×4032, 73 MB. Peak footprint
    163 MB while shooting, 805 MB while stacking. Thermal stayed nominal and
    the battery was at 85 %. The frames and the stack were added to Photos
    (add-only access granted by the owner): 6 assets, ids in the console log.
    Indoors, fewer than half the frames aligned on "stars", so the stack fell
    back to unaligned and says so in its metadata. EXIF gives the main camera
    6.93 mm (3.46 crop, 2.48 µm pitch), NPF (k = 1) 8.6 s, so the 1 s ceiling
    is the camera's, not the stars'.
  - **Stacking bench** (`-CaptureBench YES -CaptureBenchFrames 20`, optimized
    build): 20 synthetic 12 MP RGB frames with known rotations. Detection
    0.079 s per frame, registration of all 20 in 0.013 s (worst corner error
    0.007 px), sigma-clipped mean 6.77 s, maximum 0.94 s, footprint ≤ 435 MB.
  - **Lifetime** (`-CaptureLifecycleTest YES`, headless `CaptureModel`):
    leaving during the countdown, during acquisition (3 frames drained, run
    ended 0.5–0.8 s later) and during stacking (stopped 0.3–0.7 s after
    leaving). A new screen waits for the old run's cleanup. The saved frames
    are offered again and restack to completion. After each case: no run,
    camera off, idle timer restored. A second session taking the camera
    ended the run with its frames kept; before a fix it raised an
    uncatchable `capturePhoto` exception.
  - **SkyCore:** `swift test` 318 tests (44 new). They cover recall ≥ 95 % at
    SNR 5 (798 synthetic stars), noise detections all fainter than SNR 5,
    shift within 0.1 px and rotation within 0.01°, a satellite streak
    reduced below 1 % of its peak, unbroken trail arcs, and a cancelled
    12 MP stack returning within 1 s.
  - **Not verified:** the Back button, Home and the phone lock driven through
    the real UI. The device UI test (`ios/UITests/CaptureLifecycleTests.swift`)
    cannot be signed: Xcode on this Mac has no account for the xctrunner
    profile. Also unverified: registration on a real star field, the tripod
    stability thresholds (the phone never read "still" off a tripod: gyro
    mean 0.005–0.038 rad/s against a 0.01 limit) and infinity focus.
  - **Owner checks:** a Milky Way stack from a tripod, with focus set on
    stars by the HFR readout; the stability thresholds on a tripod; lock and
    unlock during a run; battery, heat and storage over a 10-minute
    sequence; deleting the 16 indoor test photos in Photos from the three
    self-test runs.
- 2026-09-26: **Worker deployed** (owner decision; the rest stays local):
  `https://dark-sky-conditions.brisk-delta-c382.workers.dev`, from
  `local/ios-integration` with `wrangler deploy`. Pre-deploy decisions:
  workers.dev route; rate limit 120/min, namespace `10010` (the owner's
  western-water Worker uses `1001`); KV `SPACE_WEATHER` auto-provisioned;
  no AirNow key yet (observed AQI unavailable). Checked live: `/health` OK;
  `/v1/conditions` for 38.35, −109.95 returned all 20 fields `ok` except
  AirNow, cold 1.8 s, warm 0.12 s, `If-None-Match` → 304 in 0.12 s, so the
  Cache API does work on `*.workers.dev`. The app reads the URL from the
  gitignored `Local.xcconfig`. Merged into integration today: Sky (M7),
  Week/Tools (M5/M10), Map (M6), Tonight + conditions (M2/M4), Spots,
  alerts and widget (M8/M9), web Worker client (M3), Worker freshness.
  The App Group signs on the owner's team.
- 2026-09-26: **M1b build checks green** (local). Xcode 27.0 (27A266a) on
  macOS 27.2, iOS 27.0 platform + simulator runtime (7.5 GB); DerivedData on
  the internal disk until an SSD is connected. `xcodegen generate` and
  `xcodebuild build` for `generic/platform=iOS` pass with no project warnings
  (widget version now follows the app); `xcodebuild test` on the iPhone 17
  simulator passes (211 SkyCore tests + the launch UI test), and the
  placeholder shows "0 min moon-free darkness" for Canyonlands on the
  2026-09-26 full moon (99.8%, up all night: correct). Free space 31 GB.
  **M1b done:** signed with automatic provisioning (team in the gitignored
  `ios/Config/Local.xcconfig`), installed with `xcrun devicectl` and
  launched on the owner's iPhone 18 Pro Max (app + widget extension
  running). Command-line signing needed a one-time keychain "Always Allow"
  for codesign (`errSecInternalComponent` until then).
- 2026-09-26 (Mac, local only, branch `local/ios-integration`): the owner
  asked to keep all iOS and Worker work local (no push, PRs, CI or deploys)
  until the local build is solid. Merged here: SkyCore M0+M1 and the Worker
  (M3), both rebased from PR #9, plus the SkyCore (logic-only) parts of M4,
  M5, M6/M7, M9 and M10. Nothing needing Xcode (app views, sensors, widgets)
  is built yet. Checks: `swift test` 209 tests; `npx vitest run` 134;
  `worker` `npm run verify` 70; tsc, eslint, ruff, mypy, pytest green.
  - **M4:** port of `freshness.ts`; Worker `Codable` models decoded from the
    new `shared/golden/{conditions,space-weather}-response.json` (written
    offline by `worker/test/golden-response.test.ts`); `ConditionsSnapshot`;
    `Verdict` per §Verdict (worst model per factor, spread kept, not averaged).
  - **M5:** `WeekOutlook`, 7 nights matching the web `planNight` on 28 nights
    (both DST changes, month and year ends); missing cloud hours make a mean
    partial or unavailable, never clear. Aurora flag: Kp against the NOAA
    G-scale geomagnetic latitudes (WMM2025 dipole), table in
    `opportunities.kp_index`; OVATION near-cell deliberately not used.
  - **M6/M7:** WGS84 Vincenty geodesics (1 mm vs Karney 2013 and
    GeographicLib), azimuth line specs, AR projection from a
    `.xTrueNorthZVertical` rotation matrix to portrait pixels, heading
    confidence (`ar_overlay.heading_accuracy_confident_max_deg` = 10°, a
    proposal) and calibration.
  - **M9:** both planners take an optional horizon profile (none ⇒ unchanged);
    `night-report.json` gains `horizon_cases` for Candlestick Camp (+27 and
    +19 moon-free min; the 8 existing cases unchanged). On-device ray march
    over 25 recorded z12 AWS Terrain Tiles matches the measured skyline at
    0.494° RMS (bound 0.5°, thin margin).
  - **M10:** gear profiles, NPF (Michaud/SAH; non-commercial terms), rough
    500 rule, star trails, hyperfocal/DoF, stacking, timelapse, tested on
    published worked examples.
  - **Owner decisions, same day:** transparency is advisory, not a gate;
    live conditions age in hours per source (default 12/24/48 h, CAMS
    24/36/48 h, RAP-Smoke 30/48/72 h, all proposals); the web app's
    "tonight" default now uses the browser's local date instead of the UTC
    date (branch `fix/tonight-local-date`, also merged here). Still open:
    AR frame orientation, the heading threshold and field-mode brightness
    need phone checks. `swift test` 211, `npx vitest run` 139.
- 2026-09-26: Mac is 256 GB. Added `docs/ios/MAC-SETUP.md` and split the
  scaffold so M0–M1 need only the Command Line Tools (Swift Testing), with
  Xcode arriving at M1b. PRs checked: #9 (this plan) and #8 (docs
  housekeeping) both green and mutually mergeable.
- 2026-09-25: **M1 checks green** (SkyCore astronomy parity; started before
  M0's `xcodebuild` check could run, at the owner's direction). `swift test` in
  `ios/Packages/SkyCore`: all 8 golden night-report cases match the web
  planner to within a millisecond (tolerance 60 s), and GC alt/az matches
  `gcAltitude`/`gcAzimuth` to within 0.0001° on the 6 points in the new
  `shared/golden/gc-horizon.json` (written by `app/tests/golden-vectors.test.ts`).
  **GC precession fix:** both planners now rotate the GC's J2000 RA/Dec to
  the equator of date before `Horizon()` (it was ~0.37° off in 2026); golden
  files regenerated, GC peaks moved by up to 0.2° (same peak times), and both
  files now record `astronomy_engine` (checked against npm and `VENDORED.md`).
  The Milky Way band's l = 0 point now sits within 0.1° of the GC. The
  moon-up seed now follows the rise/set rule on both platforms (ADR-0002
  amendment); no golden value moved.
  Adds alt/az series (sun, moon, planets, GC), the Milky Way band, and
  rise/set/transit azimuths. The GC threshold is read from a bundled copy of
  `config/app-config.json` (`ios/scripts/sync-shared.sh`; a test fails if
  the copy drifts). **M0 partial:** the SkyCore package, `project.yml`
  (validated with `xcodegen generate`), and the app/widget/UI-test stubs
  exist, but `xcodebuild` and the simulator launch are unverified until
  Xcode is installed. `ios.yml` CI is deferred by the owner until the local
  build is solid. Deployment target raised to iOS 26 (ADR-0009 §2 amendment).
- 2026-09-25: Plan written. Golden vectors for 8 nights exported from the
  web planner to `shared/golden/night-report.json`.
