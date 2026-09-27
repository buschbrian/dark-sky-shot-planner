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
| Tonight — shot window for a specific target (`ShotWindowCard`/`ShotWindowSection`/`ShotTargetPicker`) | Yes | Yes (Tonight, first block under the date; compact line on a spot page) | Yes | No | No | `ios/App/ShotWindow/`. Default target the Galactic Center, remembered; a saved spot's skyline when the place is that spot, else a labelled flat-horizon estimate. Verdict for the selected window, other windows selectable; Save plan (recorded on the phone, no list yet), Show on map (switches tab and night; the Map does not read the target/time yet), Find in sky. `ShotEventsTests.testShotWindowAtCandlestickNamesClearanceAndMinutes`, `testFullMoonNightReadsTheSameEverywhere`, `DesignTourTests.testNightTabTour` (field scan). |
| Tonight — sky events within 30 days (`SkyEventsSection`/`SkyEventsList`) | Yes | Yes (Tonight after the sky facts; Week row badges; "All sky events" pushes the list) | Yes | No | No | `ios/App/Events/`. "Plan this" sets the shot target and night. `ShotEventsTests.testEventsSectionAndWeekBadgeOnAnEventNight`, `DesignTourTests.testNightTabTour` (field scan). |
| Tonight — "tonight" rolls to the coming night after darkness ends | Yes | Yes | Yes (SkyCore `NightDate` tests + `shared/golden/tonight.json` parity) | Yes (installed at 66e0c34) | Unverified | Fixed in 5b4a702/97fceec (review B-2): `NightDate.current`/`currentSpan` drive Tonight, Week, Map, Spots and the widget. Not yet checked after dawn at a site. |
| Week — 7-night outlook per spot | Yes | Yes (inside the Tonight tab) | Yes | Yes | Unverified | `ios/App/Week/WeekScreen.swift`. `WeekToolsTests` pass. Uses the same coming-night rule as Tonight. |
| Map — pin, azimuth lines, scrubber | Yes | Yes | Yes (`MapTests.testScreenshotsBothModes`, `testMapLoadsAndCoordinateSetsPlaceWithoutTheMap`) | Unverified | Unverified | `ios/App/Map/MapScreen.swift`, `PlannerMapView.swift`. |
| Map — basemap (USGS Topo / Imagery / Dark relief) | Yes | Yes | Partial (`MapEngineTests`, opt-in with `TEST_RUNNER_MAP_ENGINE=1`, live tiles) | Yes (installed at 66e0c34) | Unverified | `ios/App/Map/MapStyle.swift` (merged from `local/ios-mapfix`, 0d72dbe). Owner reported the map as poor in the field before that merge; the rework has not been field-checked. |
| Map — light pollution, land ownership (PAD-US) layers | Yes (code); data is fixtures | Yes | Yes | Unverified | No | Public `data-status.json` (checked in the 2026-09-27 product review) reports `light_pollution: fixture`, `land_ownership: fixture`; only `darksky_places` is real. **Sample fixtures, not real coverage** — labelled in the UI, but the app does not yet exclude them from recommendations (product review §4, README "What the site shows" table). |
| Map — offline area download | Yes | Yes | Unverified | Unverified | Unverified | `ios/App/Map/MapOffline.swift`, MapLibre offline packs with a size estimate. Completeness of a downloaded area offline is not yet recorded. |
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
| Widget — tonight's verdict + moon-free minutes | Yes | Yes (Home/Lock Screen, added separately from tabs) | Unverified | Yes (installed and running alongside the app — PLAN.md §Log 2026-09-26) | No | `ios/Widgets/DarkSkyWidgets.swift`. Timeline follows `NightDate.currentSpan` (B-2 fix). |
| Field mode (red UI) + brightness dock | Yes | Yes | Yes (`DesignTourTests.testFieldModeSurvivesRelaunch`) | Yes (installed at 66e0c34) | No | Persisted by `FieldModePreference` (`AppState.fieldMode`). Field-mode readability (contrast) is calculated from sRGB tokens, not measured on a display (product review §3). |
| The Worker (`worker/`) — `/v1/conditions`, `/v1/space-weather`, `/v1/smoke`, `/health` | Yes | Yes (deployed) | Yes (`npm run verify`, offline, fixture-recorded) | Yes (live) | N/A (server-side) | Deployed at `https://dark-sky-conditions.brisk-delta-c382.workers.dev` (PLAN.md §Log 2026-09-26): `/health` OK, `/v1/conditions` returned 20 fields ok except AirNow (no key yet), cold 1.8 s / warm 0.12 s, ETag 304 confirms the Cache API works on `*.workers.dev`. |
| The web client (`app/`) | Yes | Yes (deployed) | Yes (`npx vitest run`, `npx playwright test`) | N/A | N/A | Static site at <https://buschbrian.github.io/dark-sky-shot-planner/>. Reference implementation for the shared astronomy numbers (`shared/golden/`); does not yet read `conditions-thresholds.json` or show a verdict (owner decision D6, `docs/deepsky/OWNER-DECISIONS.md`). |

## Known gaps (plain statement)

- **Shot window and sky events are on Tonight, but not yet everywhere.**
  Both are reachable and simulator-tested (rows above). Still missing: the
  Map does not read the plan's target and time (`AppState.planFocus`), a
  saved plan has no list or Calendar export, and neither has been checked
  on the phone or at a dark site.
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
