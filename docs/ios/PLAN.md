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
- Dew and PM2.5 are advisories, not gates (see the notes in the thresholds file).
- A factor whose thresholds are `null` (HRRR smoke until M3 calibration) is
  shown with its value and source but never rated.
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
Status and license details: see that file's "Proposed for the iOS companion"
section.

Endpoints below were fetched live on 2026-09-25 by the research pass whose
notes are in `docs/data-licensing.md`.

| Need | Source | Via | Notes |
|---|---|---|---|
| Cloud cover total + low/mid/high, hourly | Open-Meteo forecast: `ncep_hrrr_conus` (3 km), `gfs_seamless`, `gem_hrdps_continental`, `ecmwf_ifs025` side by side | Worker (fallback: direct) | Show model disagreement as a band, don't average it away. **Not** `ncep_nam_conus` (NOAA retires NAM 2026-10-14) or `ncep_nbm_conus` (no cloud layers) |
| Model run time | Open-Meteo `/data/{model}/static/meta.json` → `last_run_initialisation_time` | Worker | The forecast response doesn't carry it; the brief requires it |
| Dew point, humidity, wind, gusts, visibility, temperature | Open-Meteo forecast (HRRR has all of them) | Worker | GEM returns no visibility |
| Seeing proxy | Open-Meteo `wind_speed_250hPa` / `200hPa` (jet stream) | Worker | Our own, license-clean seeing indicator |
| Seeing + transparency indices | 7Timer! ASTRO (GFS-based, 3-hourly, indices 1–8) | Worker (no CORS) | **Non-commercial use only**. Fine for personal use, blocks App Store distribution without written permission. Optional, never required |
| Smoke forecast, near-surface + vertically integrated | NOAA HRRR-Smoke via NWS NDGD ImageServers (`air_quality/ndgd_smoke_{sfc,vert}_1hr_avg_time`), `identify` at a point, +48 h, ~2.7 km | Worker | **Primary smoke/transparency signal.** Units must be calibrated first (the service text says µg/m³, the raw values look like kg/m³, kg/m²). The vertically integrated field is what dims the sky |
| AOD, PM2.5, dust | Open-Meteo Air Quality (CAMS Global, ~45 km, 12-hourly) | Worker | Coarse. Use as a fallback and a cross-check for HRRR-Smoke, attributing CAMS + Open-Meteo |
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
    "fields": {
      "cloud_cover_low": {
        "unit": "%",
        "series": [ { "model": "hrrr", "model_run_utc": "…", "values": [ { "t": "…", "v": 12 } ] }, … ],
        "source": "Open-Meteo", "fetched_utc": "…"
      },
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

## Milestones

Each milestone lists what "done" means. "Owner checks" are things only a
real phone at a real dark site can prove. Record their outcome in §Log.

### M0 — SkyCore package (Command Line Tools only, no Xcode yet)
Machine setup: `docs/ios/MAC-SETUP.md`, Phases 1–3. The repo lives on the
external SSD.
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
  each model's `meta.json`, Open-Meteo air quality, HRRR-Smoke point values
  from the NDGD ImageServers, AirNow (new `ziplatLong` path), then 7Timer.
  `/v1/space-weather`; `/v1/smoke`; `/health`.
- **Calibrate HRRR-Smoke units first.** Compare ImageServer `identify` values
  against a raw HRRR GRIB2 `COLMD`/`MASSDEN` read for the same cell and hour,
  and write the conversion and evidence into `docs/methods.md`. Until that
  is done the smoke factor is shown but does not gate.
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
  re-checks, local notification. Be honest that iOS schedules this
  opportunistically, and show "last checked" in the UI.
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
- NPF rule, 500 rule (labelled as the rough one), star-trail length,
  hyperfocal/DoF, stacking count for a target SNR, timelapse interval/frames.
- Pure functions in SkyCore with published worked examples as tests.

### Later (each needs its own decision)
Live Activity during a shoot (countdown to moonrise / GC set / dawn), Apple
Watch complication, HRRR-Smoke via a pipeline, satellite-pass warnings for
long exposures, App Store / TestFlight distribution (re-check every data
source's terms for distribution first).

## Log

Record milestone completions, owner field checks, and verdict-vs-reality
nights here, newest first.

- 2026-09-26: Mac is 256 GB. Added `docs/ios/MAC-SETUP.md` and split the
  scaffold so M0–M1 need only the Command Line Tools (Swift Testing), with
  Xcode arriving at M1b. PRs checked: #9 (this plan) and #8 (docs
  housekeeping) both green and mutually mergeable.
- 2026-09-25: Plan written. Golden vectors for 8 nights exported from the
  web planner to `shared/golden/night-report.json`.
