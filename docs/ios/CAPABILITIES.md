# iOS app capabilities

One row per capability. This table exists because the 2026-09-27 product
review found documentation describing implemented work as planned (§10),
and it should replace that habit going forward: update this table, not a
narrative status paragraph, when a capability's state changes.

**Columns.** *Implemented*: the code exists. *Reachable*: a user can get to
it from a tab, with no Xcode or debug flag. *Simulator-tested*: a UI or unit
test covers it, run in the simulator. *Phone-tested*: `docs/ios/PLAN.md`
§Log or a review records an on-device run. *Field-tested*: recorded at a
dark site specifically — a lit backyard or indoor test does not count.
"Unverified" means no such record was found; it is not a claim that the
capability is broken.

| Capability | Implemented | Reachable | Simulator-tested | Phone-tested | Field-tested | Notes |
|---|---|---|---|---|---|---|
| Tonight — verdict, moon-free minutes, GC window | Yes | Yes (default tab) | Yes | Yes | Unverified | `ios/App/Tonight/TonightScreen.swift`. `TonightTests.testOfflineConditionsAreUnavailableNeverGood`, `testScreenshotTour` pass (REVIEW-2026-09-27-FABLE.md §F). No dark-site verdict-vs-sky log found in PLAN.md §Log. |
| Tonight — shot window for a specific target (`ShotWindowCard`/`ShotWindowSection`/`ShotTargetPicker`) | Yes | **No** | No | No | No | `ios/App/ShotWindow/`. Grep for these three types outside `ios/App/ShotWindow/` returns nothing — no screen instantiates them (REVIEW-2026-09-27-FABLE.md B-3, product review §1). Being wired onto Tonight now; not a user-facing capability yet. |
| Tonight — sky events within 30 days (`SkyEventsSection`/`SkyEventsList`) | Yes | **No** | No | No | No | `ios/App/Events/`. Same dead-code pattern as the shot window: unreferenced outside `ios/App/Events/` (REVIEW-2026-09-27-FABLE.md B-3). Being wired now. |
| Tonight — "tonight" rolls to the coming night after darkness ends | Unverified | Partial | No | No | No | REVIEW-2026-09-27-FABLE.md B-2: before local noon, Tonight/Week/Map/Spots/widget all still show the night that just ended. PLAN-ANY-ASTRO.md lists this fix (B-2) as a precondition for M13. |
| Week — 7-night outlook per spot | Yes | Yes | Yes | Yes | Unverified | `ios/App/Week/WeekScreen.swift`. `WeekToolsTests` pass. Inherits the before-noon issue above (B-2). |
| Map — pin, azimuth lines, scrubber | Yes | Yes | Yes (`MapTests.testScreenshotsBothModes`, `testMapLoadsAndCoordinateSetsPlaceWithoutTheMap`) | Unverified | Unverified | `ios/App/Map/MapScreen.swift`, `PlannerMapView.swift`. |
| Map — basemap (USGS Topo / Imagery / Dark relief) | Yes, on `local/ios-mapfix` only | No (not merged to this integration branch) | Partial (mapfix's own `MapEngineTests`, opt-in, live-tile) | No | No | Integration's `MapStyle.swift` draws a background layer only — no basemap (REVIEW-2026-09-27-FABLE.md B-1). Basemap work exists but is unmerged. |
| Map — light pollution, land ownership (PAD-US) layers | Yes (code); data is fixtures | Yes | Yes | Unverified | No | Public `data-status.json` (checked in the 2026-09-27 product review) reports `light_pollution: fixture`, `land_ownership: fixture`; only `darksky_places` is real. **Sample fixtures, not real coverage** — labelled in the UI, but the app does not yet exclude them from recommendations (product review §4, README "What the site shows" table). |
| Map — offline area download | Yes | Yes | Unverified | Unverified | Unverified | `ios/App/Map/MapOffline.swift`; mapfix branch adds MapLibre offline packs with a size estimate (REVIEW-2026-09-27-FABLE.md §C). |
| Map — long-press sets planning location | Yes | Yes | Unverified | Unverified | No | Currently changes the app-wide place immediately with no confirmation and does not persist through the same path as the location chooser (REVIEW-2026-09-27-FABLE.md B-9, product review §4). Fix pending. |
| Sky — simulated view (no sensors) | Yes | Yes | Yes | Unverified | No | `ios/App/Sky/SkyScreen.swift`. Honestly labelled "The Simulator has no camera or motion sensors" (REVIEW-2026-09-27-FABLE.md §D). |
| Sky — live camera + compass overlay | Yes | Yes | N/A (needs real sensors) | Unverified | **Unverified — untested in the field** | Live Sky uses `state.place`, which can be a remote planning site rather than the sensor's GPS location, with no mismatch warning yet (product review §8). Compass/AR accuracy at a real site is explicitly unproven. |
| Sky — figure-8 compass calibration, align on Moon/star | Yes | Yes | Unverified | Unverified | **Unverified — untested in the field** | `ios/App/Sky/SkyCalibrationGuide.swift` ("Wave the phone in a slow figure 8 … away from the car and tripod"), `SkyControls.swift` (`CalibrationPanel`, calibrate on Moon/planet/star/saved peak). No on-device or dark-site alignment check recorded. |
| Spots — saved places, horizon profile, week verdicts | Yes | Yes | Yes (`SpotsTests`, incl. `testMeasuredCandlestickProfile`) | Unverified | Unverified | `ios/App/Spots/SpotDetail.swift`. Measured Candlestick Camp profile matches computed terrain-ray-march within 0.494° RMS (bound 0.5°) — PLAN.md §Log 2026-09-26. |
| Spots — alerts ("Go this week") | Yes | Yes | Unverified | Unverified | No | `ios/App/Alerts/SpotRefresh.swift`. Best-effort by design (`BGAppRefreshTask`, no server push — ADR-0010). Background reliability at a dark site is **untested in the field**. |
| Tools — NPF/500 rule, DoF, stacking, timelapse calculators | Yes | Yes | Yes (`WeekToolsTests.testGearAndNPFCalculatorWalkthrough`) | Unverified | Unverified | `ios/App/Tools/ToolsScreen.swift`. Pure SkyCore functions with published worked-example tests. |
| Tools — gear profile entry (manual) | Yes | Yes | Unverified | Unverified | No | `ios/App/Tools/GearEditor.swift`: sensor width/height, resolution, pixel pitch, focal length, aperture, typed by hand. |
| Tools — curated gear presets (search/select, "This iPhone") | Yes (catalog + tests), **No** (no UI) | **No** | Unverified | No | No | `config/gear-presets.json`, ADR-0012, `GearPresetsTests`. No app view references `GearPresets` (product review §9) — the catalog exists but nothing in `GearEditor` or `ToolsScreen` lets a user pick from it. |
| Capture — tripod capture, stacking, two-path guidance | Yes | Yes | Yes (SkyCore unit tests: 318+ tests, recall/registration/trail checks) | Yes (indoors, on the owner's iPhone 18 Pro Max) | **No — indoors only, no night-sky test yet** | `ios/App/Capture/CaptureScreen.swift`, `CaptureModel.swift`. PLAN.md §Log 2026-09-27: 5 ProRAW DNGs captured and stacked on-device; fewer than half the frames aligned on "stars" indoors, so the stack fell back to unaligned. Outdoor faint-star detection, real registration, and hour-long thermal reliability are explicitly not established (product review §7, PLAN.md §Log "Not verified"). |
| Capture — leave/interrupt/recover a run | Yes | Yes | Unverified (UI test cannot be signed on this Mac — no xctrunner account) | Partial (headless lifecycle test passed) | No | `-CaptureLifecycleTest` headless run passed (PLAN.md §Log 2026-09-27); the real UI path (Back button, Home, phone lock) is explicitly unverified. |
| Widget — tonight's verdict + moon-free minutes | Yes | Yes (Home/Lock Screen, added separately from tabs) | Unverified | Yes (installed and running alongside the app — PLAN.md §Log 2026-09-26) | No | `ios/Widgets/DarkSkyWidgets.swift`. Inherits the before-noon "tonight" issue (B-2) via its "from local noon" timeline. |
| Field mode (red UI) + brightness dock | Yes | Yes | Yes (`DesignTourTests.testFieldModeSurvivesRelaunch`, on the design branch) | Unverified | No | Persists across relaunch on `local/ios-design`; **still resets on relaunch on the integration branch actually reviewed** (REVIEW-2026-09-27-FABLE.md B-8) until that branch merges. Field-mode readability (contrast) is calculated from sRGB tokens, not measured on a display (product review §3). |
| The Worker (`worker/`) — `/v1/conditions`, `/v1/space-weather`, `/v1/smoke`, `/health` | Yes | Yes (deployed) | Yes (`npm run verify`, offline, fixture-recorded) | Yes (live) | N/A (server-side) | Deployed at `https://dark-sky-conditions.brisk-delta-c382.workers.dev` (PLAN.md §Log 2026-09-26): `/health` OK, `/v1/conditions` returned 20 fields ok except AirNow (no key yet), cold 1.8 s / warm 0.12 s, ETag 304 confirms the Cache API works on `*.workers.dev`. |
| The web client (`app/`) | Yes | Yes (deployed) | Yes (`npx vitest run`, `npx playwright test`) | N/A | N/A | Static site at <https://buschbrian.github.io/dark-sky-shot-planner/>. Reference implementation for the shared astronomy numbers (`shared/golden/`); does not yet read `conditions-thresholds.json` or show a verdict (owner decision D6, `docs/deepsky/OWNER-DECISIONS.md`). |

## Known gaps (plain statement)

- **Shot window and sky events are not on Tonight.** The code for both
  exists (`ios/App/ShotWindow/`, `ios/App/Events/`) but no screen wires
  them in. This is being connected now (REVIEW-2026-09-27-FABLE.md B-3,
  product review §1).
- **Light pollution and PAD-US land-ownership map layers are sample
  fixtures**, not real data, on every build until `data-refresh.yml` runs
  with a NASA Earthdata token (README "What the site shows"; product
  review §4). The UI labels them as fixtures but does not yet exclude them
  from site recommendations.
- **Compass/AR alignment is untested in the field.** The figure-8
  calibration guide and Moon/star alignment exist and are exercised in the
  simulator (no real sensors there); no dark-site accuracy check is
  recorded.
- **Capture of the actual night sky is untested in the field.** The only
  on-device sequence so far was indoors, with fewer than half the frames
  aligning on "stars" (PLAN.md §Log 2026-09-27). A real Milky Way stack
  from a tripod remains an owner check.
- **Background alerts are untested in the field.** `BGAppRefreshTask` is
  best-effort by iOS design (ADR-0010's stateless Worker means no
  server-side push); whether it actually fires reliably at a dark site with
  weak signal has not been recorded.
