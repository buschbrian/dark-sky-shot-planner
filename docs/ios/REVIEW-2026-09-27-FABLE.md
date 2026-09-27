# Independent review of the Dark Sky iOS app, 2026-09-27 (Fable)

Reviewed `local/ios-integration` at **3094aeb** (built in a detached checkout under `/private/tmp/fable-review/integration`, `Local.xcconfig` pointing at the deployed Worker), read-only against `local/ios-mapfix` 24b0b9e, `local/ios-design` 7f80c2f, `local/ios-capture` 2f926a2, `local/ios-events` 4df8af1, `local/ios-skyreal` eb8083c. Simulator: iPhone 18 Pro Max, iOS 27.0, location 38.3740, -109.9654 (Candlestick Camp), live Worker `https://dark-sky-conditions.brisk-delta-c382.workers.dev` (healthy; `/v1/conditions` for the Candlestick cell answered in 1.6 s cold with 20 fields, HRRR 11Z run). Screenshots: `/private/tmp/fable-review/shots/` (`A*` map, `B*` Tonight/Week, `C*` Sky/Spots/Tools, `D*` Accessibility L, `E*` offline, `focused/` the repo's own tour tests). No source in any git worktree was changed; the UI driver that produced `A*`-`E*` lives only in a non-git copy (`/private/tmp/fable-review/drive/ios/UITests/FableDriveTests.swift`).

**Headline.** The map is black because it has no basemap *and* because the live Pages site still publishes 5 KB fixture layers; `local/ios-mapfix` fixes the first and nothing in iOS can fix the second (B-1). Every screen plans for the wrong night before local noon (B-2). The M11 shot-window card, the feature the research says should be the headline, is merged but shown nowhere (B-3). The Codex findings are mostly fixed on integration; the two that are not (field-mode persistence and the shot verdict's consumers) sit on unmerged branches.

## A. Codex findings: status on `local/ios-integration` (3094aeb)

| # | Finding | Source | Status | Evidence |
|---|---|---|---|---|
| 1 | Spots background checks defaulted to `UnavailableConditions`, so alerts could never go Go | Codex #1 (chat) | **Fixed** | `ios/App/DarkSkyApp.swift:8,24` builds one `ConditionsClient.live()` and passes it to `SpotRefresh.runInBackground(container, conditions:)`; commit 792a360 |
| 2 | Map provenance: missing `data-status.json` read as "not a fixture"; PAD-US answer shown without confirmed real data | Codex #1 | **Fixed** | `MapData.origin` returns `PagesOrigin` real/fixture/unknown (`MapData.swift:104-107`, empty status ⇒ `.unknown`); `MapScreen.landAtPin` withholds unless `.real` (`MapScreen.swift:226-231`); tapped PAD-US likewise (`:266-270`); commits fea54ce, 93d3f07 |
| 3 | Map hardcoded the AOI | Codex #1 | **Fixed** | `MapData.refreshSmoke` reads `AppConfig.bundled().aoi.bbox` (`MapData.swift:159`); no literal bbox remains in `ios/App/Map` |
| 4 | Integrate one UI branch at a time, full simulator suite after each | Codex #1 | **Partly followed** | Merges landed one branch per commit (36b0754, 20ab5c3, b0b73ac, 25df3c2, 3094aeb) but PLAN.md §Log records no full simulator run after any of them; Codex's two attempts stalled; this review ran the suite (§F) |
| 5 | Bound the 7 concurrent per-spot requests in `SpotWeekPlanner` | Codex #1 | **Fixed** | `RequestLimiter` with `SpotRefresh.globalRequests = 3` across spots (`SpotRefresh.swift:18,65`) and `perSpotRequests` in `SpotWeekPlanner.compute` (`:82-100`); nights are also merged two-per-request (`requests(_:)`); commit 974d4ca |
| 6 | P1 15-minute HRRR series not in the shot verdict (gust 90 km/h read as 8) | PERIODIC-REVIEW §1 | **Fixed in SkyCore, not yet on any screen** | `ForecastCadence.select`/`timeWeightedMean` used in `Verdict.swift:273-275,366,428-438`; `ForecastCadenceTests`; Codex's own re-check: 321 SkyCore tests pass (`/private/tmp/darksky-review-2026-09-27-core.log`); commit acb60f9. But `ShotWindowCard` is referenced by no screen (grep `ShotWindowCard|ShotWindowSection|ShotTargetPicker` in `ios/App` outside `ShotWindow/` returns nothing), so the M11 shot verdict is dead code in the integrated app (see B-3) |
| 7 | P1 Capture: leaving mid-run has no owner/cleanup; Stop still stacks, stacking not cancellable | PERIODIC-REVIEW §2 | **Fixed on `local/ios-capture`, not merged** | 92ab50e "one explicit run lifetime; Stop and stack / Cancel / Stop stacking; interruptions and background handled", fcc6d20 cancellable stacking, 2f926a2 interruption guards; `CaptureScreen.swift:66` observes `scenePhase`; `CaptureModel` `.leftScreen/.background/.interrupted` end reasons. Device-only proof still owed |
| 8 | P2 Field mode resets on relaunch; no one-hand brightness control | PERIODIC-REVIEW §3 | **Still open on integration; fixed on `local/ios-design`** | Integration `AppState.swift:30` reads `FieldMode` once and never writes it; `FieldModeToggle` is a system `.toggleStyle(.button)`. Design 15797c3 adds `FieldModePreference.save` in `AppState.fieldMode.didSet`, `BrightnessSession`, `FieldDock`/`BrightnessControl`, and `DesignTourTests.testFieldModeSurvivesRelaunch` |
| 9 | P2 Measured skyline applied within 1 000 m | PERIODIC-REVIEW "earlier" | **Fixed** | `MeasuredHorizons.observerMatchMeters = 30` for the RMS comparison; 1 000 m only *offers* the profile and the source line says "reused N m from its surveyed observer" (`TerrainHorizon.swift:277-305`); commit 5a9d2a4; `AppTests/SpotsReviewFixTests.swift` |
| 10 | P2 Go alerts can describe an elapsed window | PERIODIC-REVIEW "earlier" | **Fixed for alerts only** | `SpotRefresh.eligibleGoNights` requires `usableUntil > now` (`SpotRefresh.swift:96-100`); commit 5a9d2a4. The same before-noon rule still mislabels the *screens* (B-2) |
| 11 | Optional: `ShotWindow.best` shows the longest window while `nightForVerdict` judges all | PERIODIC-REVIEW optional | **Open (moot until M11 is wired)** | `ShotWindow.swift` unchanged in intent; no UI shows it yet |
| 12 | CAPTURE-LIMITS.md cites an M12 log that is not in integration's PLAN.md | PERIODIC-REVIEW optional | **Still open** | integration `docs/ios/PLAN.md` §Log has no M12 entry; capture branch 025f094 adds the probe doc |
| 13 | Incomplete simulator checks: Tonight offline, Tonight screenshot tour, Spots measured profile | PERIODIC-REVIEW verification | **Done here** | `TonightTests.testOfflineConditionsAreUnavailableNeverGood` passed (206.7 s), `testScreenshotTour` passed (142.0 s), `MapTests.testScreenshotsBothModes` passed (73.1 s), `testMapLoadsAndCoordinateSetsPlaceWithoutTheMap` passed (225.1 s); log `/private/tmp/fable-review/focused.log`, bundle `focused.xcresult`; Spots in the full suite (§F) |
| 14 | iOS 27: launch screen required with the 27 SDK | RESEARCH | **Satisfied** | `ios/project.yml:71` `INFOPLIST_KEY_UILaunchScreen_Generation: YES`; the built `Info.plist` carries `UILaunchScreen` (checked with `plutil`) |
| 15 | iOS 27: `TabView` selection to a hidden tab can crash | RESEARCH | **Not applicable** | `RootView` (`DarkSkyApp.swift:39-45`) always installs all five `Tab`s; nothing hides one. Re-check if a tab ever becomes conditional (e.g. Capture) |
| 16 | Product: make one site-and-shot usable window the headline; expose model, run, coverage, missing | RESEARCH | **Partly built, not shown** | M11 `ShotWindowCard` implements exactly this ("Core clears the ridge 23:40, 1 h 55 min moon-free, clouds 10-25 % across 4 models") but is unreferenced (B-3) |
| 17 | Word BGAppRefresh as best-effort; scope red guarantee to app-drawn surfaces | RESEARCH #3 | **Fixed** | `AlertSection.swift:79` footer says iOS chooses when and "never after you swipe the app away"; ADR-0011/ios/AGENTS.md invariant 5 rescoped (1f2a47e) |
| 18 | Second Codex review (this morning): verify 5a9d2a4/acb60f9, capture and design fixes; found ShotWindow card and refresh APIs unwired in Tonight/Week/background | Codex session 2026-09-27 12:26-12:30Z; artefacts `/private/tmp/darksky-review-2026-09-27-{build,core}.log`, `darksky-review-{derived,swift,clang}` | **It ran `build-for-testing` (succeeded 06:34) and SkyCore `swift test` (321/46 passed 06:33) and stopped before any simulator test or written prompt** | The unwired-card finding is confirmed above (#6, B-3). The simulator half is completed by §F |

## B. Must-fix before the next field session

Priorities: P0 = will mislead in the field or block the map from being usable; P1 = will cost the owner real time or trust on the night.

### B-1 (P0, mapfix + coordinator/pipeline) The map has nothing on it: no basemap, and the two content layers on the phone are 5 KB / 3 KB fixtures

- **Repro:** Map tab, set `38.3740, -109.9654`, any zoom. Screenshots `shots/A03-map-camp-z8-standard.png`, `A06-map-camp-zoomin3.png`, `focused/map-standard.png`: a black canvas with a pin, azimuth lines and label cards. Zooming in three times (`A04`-`A06`) reveals no ground, no roads, no relief, no place names. The badge reads "Sample fixture: light pollution · Sample fixture: PAD-US".
- **Why:** (a) `MapStyle.json` (`ios/App/Map/MapStyle.swift:84-91`) draws only a `background` layer; the comment says "the web app uses no basemap". (b) The live Pages site publishes fixtures: `https://buschbrian.github.io/dark-sky-shot-planner/data-status.json` = `{light_pollution: "fixture", land_ownership: "fixture", darksky_places: "real"}` (built 2026-09-26T17:51Z); `light-pollution.pmtiles` is 5 231 bytes, `padus.pmtiles` 2 550 bytes. The Offline panel proudly says "On this phone, 5 KB" (`shots/A15-map-standard-panel-bottom.png`). `data-refresh.yml` has never run with `BLACKMARBLE_TOKEN` (AGENTS.md "Data refresh"), so the phone can never show real radiance or PAD-US until it does.
- **Fix:** (a) merge `local/ios-mapfix` (see §C: USGS Topo/Imagery/Dark relief basemaps, public domain, keyless) after it passes its own `MapEngineTests` on the simulator; (b) the owner runs `data-refresh.yml` manually with the token so `data/out/` carries the real VNP46A4 composite and PAD-US clip (repo-level, not iOS). Until (b) lands, the map should say once, plainly, in the Place card: "Light pollution and land manager are sample data on this build" instead of a three-line badge that overlaps the label cards.
- **Owner:** mapfix (a); coordinator + owner (b).

### B-2 (P0, coordinator; SkyCore `NightDate` + web `app/src/state/tonight.ts:9`) Before local noon, Tonight, Week, Map and Spots all plan for the night that has already ended

- **Repro:** at 07:26 MDT on Sunday 27 Sep, Tonight's date row says "Night of Sat, Sep 26 · tonight" (`shots/B04-tonight-top.png`; driver label `tonight.date: Night of Saturday, September 26, tonight`), darkness "8:38 PM-5:43 AM" (over 1 h 43 min ago), and the map scrubber runs 20:00-06:00 of last night with the "at time" lines drawn for 07:20 (`A03`). Week's first row is "Tonight, Saturday, Sep 26" (`B13`), the Spots strip starts "Sat" (`C07`), and the widget timeline is built "from local noon" (`DarkSkyWidgets.swift:13`).
- **Why:** `NightDate.containing` (`ios/Packages/SkyCore/Sources/SkyCore/NightDate.swift:72-78`) rolls to the previous evening for any instant before 12:00 local, mirroring the web app. That is right at 02:00, wrong at 07:30: a morning check before driving out plans for a night that is over, and a Go alert would already be filtered (B-10 fixed) while the screens still show it.
- **Fix:** define "tonight" as the coming night once the current night's darkness has ended (astronomical dawn + a margin, or sunrise), and only fall back to the previous evening while it is still dark. Implement once in SkyCore (`NightDate.containing(_:in:)` gains an `after darknessEnd:` rule fed by `Planner.darknessWindow`), mirror it in `app/src/state/tonight.ts`, add a golden case at 07:30 local and one at 03:00 local, and make the label say "last night (ended 5:43 AM)" if a user steps back to it. Web and iOS must change together (invariant 1).
- **Owner:** coordinator (SkyCore + web), then every screen inherits it.

### B-3 (P1, coordinator) The M11 shot window (the product's headline per the Codex research) is built but shown nowhere

- **Repro:** grep `ShotWindowCard|ShotWindowSection|ShotTargetPicker` in `ios/App` outside `ios/App/ShotWindow/`: no references. Tonight (`TonightScreen.swift:104-124`) still stacks `AnswerCard` + `VerdictCard` + `AstronomyDetails` + charts; Week and Spots use `Verdict.weekRater`.
- **Why:** `local/ios-shot` merged its views (b2c5bf4) and SkyCore, but no screen adopted the card; the second Codex pass found the same and stopped before writing the prompt.
- **Fix:** put `ShotWindowCard(place:night:horizon:plan:snapshot:status:now:)` under the headline on Tonight when the place has a skyline (a saved spot in use) and default `ShotPlan` to the Galactic Center; on `SpotDetail` beneath the week strip. Feed `status` from `ConditionsFetch.status` (B-4). Add a UI test that the card names the target and a clearance time at Candlestick with the measured profile.
- **Owner:** coordinator (integration), with skyreal for the target picker if it shares the Sky target list.

### B-4 (P1, coordinator; `ios/App/Tonight/TonightModel.swift:112`, `VerdictViews.swift:84-95`) A successful live refresh reads "Conditions: offline, showing the copy fetched just now"

- **Repro:** with the Worker reachable, choose a place whose 0.05° cell was fetched minutes earlier (the Candlestick GPS fix after the 38.35,-109.95 cell): the origin line says "Conditions: offline, showing the copy fetched just now" (`shots/B04-tonight-top.png`, driver label `tonight.conditionsOrigin`). Ten seconds earlier the same screen for the typed place said "from the conditions Worker, fetched 7:25 AM" (`B01`).
- **Why:** `TonightModel.loadConditions` marks the snapshot `cached` when `snapshot.fetchedUTC < asked - 5 s`. A Worker `304` deliberately keeps the old `fetchedUTC` (`ConditionsClient.swift:296-300`, `ConditionsSnapshot.fetchedUTC` doc), so every revalidated answer is labelled offline. `ConditionsStatus.liveWorker(confirmedAt:revalidated:)` already carries the right words ("Live conditions, checked 12 s ago and unchanged") but `TonightModel` uses `provider.conditions(for:)`, which drops the status.
- **Fix:** call `fetch(for:window:)` (returns `ConditionsFetch.status`) from `TonightModel` and render `status.summary(now:)`; keep "offline" for `.offlineCache` only. Same in Week (`WeekPlanner.fetch`) and `SpotWeekPlanner`. This is also the "Worker unreachable" wording fix: `VerdictViews.swift:93` should use `ConditionsStatus.workerSilentDirect` / design's `Voice.reason`.
- **Owner:** coordinator now (three-line change), design branch for the words.

### B-5 (P1, design) "No-go · incomplete data" when the only problem is that the moon is up all night

- **Repro:** full moon night (any night this week at Candlestick): verdict "No-go incomplete data / Limited by Moon-free darkness: 0 min" (`B04`, `B16`, `D01`); Every factor lists eight factors as "unavailable ... no moon-free darkness" (`B08`).
- **Why:** with no moon-free window every conditions factor is `.unavailable(reason: "no moon-free darkness")`, which sets `Verdict.Flag.incompleteData` (`Verdict.swift:176-195`), though nothing is missing.
- **Fix:** when `night.moonFreeWindows.isEmpty`, rate conditions as `.notApplicable` (a new `FactorAssessment.Status`) and drop the flag; headline the verdict as "No-go: the moon is up all through darkness" and hide the factor list behind "Conditions don't matter tonight". The M11 card already words this ("no moon-free minutes"), which is another reason for B-3.
- **Owner:** design (`VerdictViews`), SkyCore flag rule by coordinator.

### B-6 (P1, mapfix) The map is one third of the screen with a permanent three-line provenance badge and label cards on top of the pin

- **Repro:** `A03`, `A04`, `focused/map-standard.png`: map area is a fixed 340 pt (`MapScreen.swift:44`); the age badge ("Smoke unavailable / Sample fixture: light pollution / Sample fixture: PAD-US") sits over the map's top-left and collides with the "Sun set" card; at z8 the six event cards and three at-time cards overlap each other and the pin ("Mo|Sun transit 34" is two cards on top of each other); the "Long-press to move the pin" hint overlaps "GC transit 18:43". At Accessibility L (`D04`) the cards cover the whole map and the "Moon 275° · 8° up" card is clipped.
- **Fix:** (a) let the map fill the screen with the panel as a bottom sheet (`.presentationDetents`), or at least a "expand" button; (b) move provenance out of the map into the Place card and keep on-map badges to one line (IR age); (c) declutter: mapfix's `declutter()` hides overlapping label views by priority, which is right, but it should also reserve the top-left badge rect and the bottom-left hint, cap label font at `.xLarge` (DESIGN.md rule 7), and place event labels at the far end of their line rather than 92 %.
- **Owner:** mapfix (already in flight for c), design for a/b.

### B-7 (P1, design; `ios/App/Spots/SpotDetail.swift:66-71`) Field mode cannot be toggled from a pushed spot page, and the Spots list hides the toggle on the left

- **Repro:** open a spot; the toolbar shows back + "Edit" only (`C07`-`C12`). My driver's `Field mode` tap failed there (`drive.log` line "Failed to tap Field mode"); the user must pop back to the list. On Spots the toggle is top-left (`C03`), on every other tab top-right.
- **Fix:** `screenChrome(pushed: true)` from the design branch puts the toggle last on the right on every screen; adopt it in `SpotDetail`, `CalculatorView` and `GearEditor`.
- **Owner:** design (already has `ScreenChrome`, needs applying to SpotDetail).

### B-8 (P1, coordinator, `local/ios-design` merge) Field mode is forgotten on relaunch on the build that will be installed

- Still true on integration (`AppState.swift:30`); fixed on design (15797c3). If the design branch is not merged before the outing, the owner must re-enable red mode after any relaunch. Merge design's `FieldModePreference`, `BrightnessSession` and `FieldDock` first; the `DesignTourTests.testFieldModeSurvivesRelaunch` proves it.

### B-9 (P1, coordinator) A long-press on the map silently rewrites the app-wide place

- **Repro:** long-press anywhere on the map: `map.placeLabel` becomes "38.4529, -109.9785 · night of 2026-09-26" (`A16`), Tonight and Week now plan for "Dropped pin" 9 km from camp with no confirmation, and the remembered place (`RememberedPlace`) is not updated, so a relaunch snaps back to the old one. Two different "current places" after a relaunch.
- **Fix:** either confirm ("Plan for this point?") or show a dismissible "Planning for dropped pin · Undo" bar; and route through the same `apply(LocationChoice)` that Tonight uses so the remembered place stays consistent.
- **Owner:** coordinator (`MapScreen.dropPin` → shared `AppState.setPlace`).

## C. Map

### What is broken on integration (3094aeb), seen at Candlestick in the simulator

| Area | Observation | Evidence |
|---|---|---|
| Basemap | None. Pure black canvas; zooming in reveals nothing. | `A03`, `A06`, `MapStyle.swift:84-91` |
| Content layers | Light pollution and PAD-US are 5 KB / 3 KB fixtures from the live Pages site; dark-sky places (21 points, real) draw as green circles; nothing else. | `data-status.json`, `A15` |
| Gestures | Pinch zoom works and line lengths rescale (5 % steps); the panel below never receives map gestures (good). Double-tap zoom not tested. No "zoom to pin" control; after `Set` the camera animates to `max(zoom, 8)` only. | `A04`-`A06`, `PlannerMapView.swift:106-110` |
| Pin placement | Long-press drops a pin and re-centres. It also changes the app-wide place with no confirmation (B-9). The pin view is a 22 pt ring; the label cards cover it at z8. | `A16`, `A03` |
| Azimuth lines | Correct objects (sun, moon, GC), rise/transit/set plus at-time; halo under lines; dashed moon and GC. Lines are drawn for last night before noon (B-2). Labels cards: two-line, monospaced, clear individually, but nine of them overlap at z8-z9 and cover the pin. | `A03`, `A08`, `MapPlanner.label` |
| Scrubber | Works; ± buttons and drag; snapped 5 min; accessibility adjustable. The clock is large and readable in field mode. | `A08`, `A12` |
| Layer toggles | Five toggles in the panel; IR loop plays at 800 ms; provenance under each. Toggling IR made the whole map a mosaic of GOES 2 km grey blocks at z8-z9 with no coastline or ground beneath to read them against. | `A09`-`A11` |
| Fixture labelling | Honest, but a permanent three-line badge on the map, plus "Land manager: withheld, the PAD-US layer is a sample fixture" in the Place card and "SAMPLE FIXTURE, not real coverage" under each toggle: the same fact three times, none of them saying what to do about it. | `A03`, `A15` |
| IR / smoke | IR frames: 6 frames, 20 min spacing, ages shown ("IR 13:00Z · 24 min old") and refreshed on the 5-min cadence. Smoke: "Smoke unavailable" is what the app says when the HMS feed legitimately holds zero polygons (the live `outStatistics` query returned `latest_end: null` and the AOI count is 0). Should read "No smoke polygons in the current HMS analysis (checked 3 min ago)". | driver labels, `MapData.refreshSmoke`, live curl |
| Offline | `-DarkSkyOffline` relaunch: map draws the cached fixture layers and lines, IR badge absent, timing 424 ms / 2 026 ms. Fine given how little there is to cache. | `E04` |
| Speed | Tab appear → first frame 424-1 112 ms, fully rendered 2.0-2.3 s (6.4 s on the first cold run under the test runner); set place → lines 4.4 s (time-zone lookup + replan); app launch → tab bar 14-31 s under XCTest on this loaded Mac (not representative), `launch-to-headline` 9.8-17 s in the perf log, screen-appear-to-headline 285-939 ms. | `map.timing` labels, `log show` |
| Field mode | Everything multiplies to red; the map's white scale bar becomes full-brightness red (mapfix dims it); the IR raster becomes near-invisible dark red (`A12`). Legend swatches are luminance-mapped to red (good). | `A12`, `A13`, `focused/map-field.png` |
| Legibility | Label cards are legible at default type; at Accessibility L the cards swallow the map (`D04`). The bottom-left hint and the top-left badge are caption2 white-on-80 %-black: fine. Layer provenance lines under each toggle wrap to three lines in orange ("stale · verify before trusting") and dominate the panel. | `D04`, `A15` |

### Will `local/ios-mapfix` (24b0b9e, based on 3f6835d) fix it?

Read-only review of the three commits (+1 569 / -12 lines, 13 files).

**Yes, for the blank canvas.** `MapBasemap.swift` defines three keyless public-domain sources (USGS Topo, USGS ImageryTopo, AWS terrarium DEM) and three basemaps (Topo, Imagery, Dark relief = Topo inverted and dimmed under a MapLibre hillshade); `MapStyle.basemapLayers` adds them hidden and the coordinator shows the chosen one; licences and refresh dates are in `docs/data-licensing.md` with the rejected alternatives (OpenFreeMap's terms, USGSShadedReliefOnly 404s above z12). Field mode gets its own remembered basemap (Dark relief), a `raster-brightness-max: 0.5` cap and `MapColors.fieldCap = 0.6` on every palette colour the map draws. Attribution is drawn on the map. This is the right direction and consistent with the project's data-licensing rules.

**Yes, for three things the owner will feel:** a palette-drawn location puck with heading wedge and accuracy halo (`MapUserPuck.swift`), follow / follow-with-heading / off cycling and "pin me here" buttons bottom-right (thumb reach), and offline basemap areas as MapLibre offline packs with a size estimate before download (150 MB cap, view or 10 × 10 km per spot), plus `-DarkSkyOffline` and `-clearMapAmbientCache` so a test can prove the pack drew the map. `MapEngineTests` measure luma stddev to catch a blank basemap and run an offline-pack round trip.

**Partly, for label clutter.** `declutter()` hides lower-priority label views that overlap a higher one, the pin, the puck or the button column, and re-runs while the region changes. It does not reserve the top-left badge or the bottom-left hint, does not move labels, and keeps the at-time labels at 50 % of the line, which is still on top of the pin at z8.

**Not at all, for:** the fixture content layers (B-1b, pipeline); the fixed 340 pt map height and the panel-first layout (B-6a); the before-noon night (B-2); the silent place rewrite (B-9); provenance repeated three times; "Smoke unavailable" wording; the missing "centre on pin / spot" action (there is centre-on-me only); the IR mosaic having nothing to read against at z8 is improved by the basemap but the loop still has no coastline/state outline on Dark relief at z5-z6 (untested here).

**Risks to check before merging mapfix:** (1) it is 12 commits behind integration and both it and `local/ios-design` rewrite `ios/App/Map/MapScreen.swift` (design: 246 lines changed; mapfix: +6 hooks) and design also rewrites `MapControls.swift`; merge mapfix first (small MapScreen delta), then design; (2) `MapEngineTests` need live USGS and AWS tiles and download a pack: mark them opt-in like `testLiveConditionsTour`, or they will stall the suite the way Codex's runs stalled; (3) Dark relief inverts a raster designed for paper: contour numbers and road casings invert too; judge on the phone at z13-z15 before making it the field default; (4) `MapController.launchCamera` reads `UserDefaults "MapCamera"` on every launch: harmless, but make sure a stale value cannot survive from a test run (it is a launch-argument default, so it should not); (5) `OfflineAreas.maxBytes = 150 MB` and `bytesPerTile` sampled at Candlestick only: estimates will be off elsewhere, say "about"; (6) the WIP commit (24b0b9e) is uncommitted-looking work: ask its agent for the field-legibility screenshots (`testFieldModeDarkReliefIsRedAndDim` thresholds `maxGB ≤ 12`, `p999Red < 160`) before merging.

## D. Clunky tabs, per tab (simulator, iPhone 18 Pro Max, iOS 27.0; screenshots in `/private/tmp/fable-review/shots/`)

Timings are from my driver run on a heavily loaded Mac; treat ratios, not absolutes.

### Tonight (`B01`-`B11`, `B16`-`B18`, `D01`-`D02`, `E01`)
1. **Wrong night before noon** (B-2). The first thing on screen at 07:26 is "Night of Sat, Sep 26 · tonight" for a night that ended.
2. **Origin line lies after a 304** (B-4): "offline, showing the copy fetched just now" while online.
3. **"No-go · incomplete data" on a full-moon night** (B-5) and an eight-item factor sheet all saying "unavailable · no moon-free darkness" (`B08`): alarming, and nothing to act on.
4. **Three taps to the first answer for a new user:** "Choose a location" → "Use my location" → system permission alert → back. Good copy on the empty state ("Where are you shooting?"). Acceptable, but the sheet could ask for location immediately when nothing is saved.
5. **Layout jump:** the headline appears first, then the verdict card, then charts join a frame later (by design, `showDetails`); the conditions strip then repaints from "fetching…" to loaded (`B03` → `B04`). Reserve the strip's height so the page does not grow twice.
6. **"Conditions by hour" strip is a 16-row grey heat map with 6-pt labels** (`B06`): "Low cloud · HRRR / GFS / ICON / ECMWF" × 4, AOD, transparency, gust, dew: unreadable on a phone and worse in red. Collapse to the four factors (worst model shaded, tap for models), and put model disagreement in the factor sheet, which already lists it (`B08`).
7. **Large type** (`D01`, `D02`): survives; the headline number stays whole, but "Night of Sat, Sep 26" wraps to two lines between the chevrons, and the verdict card's "Every factor / Refresh" buttons overflow the card. Design's `StatusBadge` fix (d9133d5) addresses part of this.
8. **Field mode** (`B16`-`B18`, `focused/field-*`): red, status bar hidden; the segmented "Tonight | Week" picker keeps its system tint (dim red, fine); calendar and in-app keypad are red (`field-5`, `field-6`). No leaks found on this tab.
9. **VoiceOver order** (existing test `testVoiceOverReadsTheAnswerInOrder`, passing): place, date, headline, verdict, then details. Good.

### Week (`B12`-`B15`, `D03`, `E03`)
1. First row is last night (B-2).
2. **Rows are four lines each plus a two-line provenance footer**; seven rows need three screens. A "No-go" capsule with "Limited by Moon-free darkness 0 min" and "Cloud: no moon-free darkness to average" is the same fact three ways. Collapse a no-moon-free night to one line.
3. "Conditions received just now." then rows reflow when the fetch lands 4-8 s later (week tab → status 4.2 s, conditions done 7.9 s); no placeholder height.
4. Header repeats the place name ("My location") and instructions ("Tap a night to open it in Tonight") on every visit: move to a footer after first use.
5. Large type (`D03`): fine, one row per screen.
6. Field mode (`B15`): the ↻ refresh button is a bare system glyph on black: OK. No leaks.

### Map (`A*`, `D04`-`D05`, `E04`) — see §C. Summary of friction: the map is one third of the screen; the coordinate field brings up the system keyboard (white, not red-able; `A02`); the fixture warnings appear three times; long-press rewrites the place silently; no "centre on pin"; layer provenance lines are the loudest text on the panel.

### Sky (`C01`, `C02`, `D09`)
1. Simulated view is honestly labelled ("The Simulator has no camera or motion sensors") and the overlay summary is VoiceOver-ready (`sky.overlay` value in the driver log).
2. **The header is a different component from every other tab**: a large "Sky" title with a plain "Field mode" text button instead of the moon-stars toggle; at Accessibility L the "Simulated compass ±3°" chip and "Calibrate" button wrap awkwardly (`D09`). Design's `screenChrome` should be applied here too (design branch has not touched Sky).
3. Sky tab → overlay 6.4 s in the simulator (model computed for the night). On the phone this is the tab opened in the dark: cache the night model from Tonight (same place/night) instead of recomputing.
4. Field mode (`C02`): red, but the sky gradient renders as a dark-red wash and the horizon line/compass letters are dim; the "Preview 8:38 PM" scrubber label loses its blue accent (correct).
5. Live-sensor behaviour (heading accuracy, calibration on the Moon) is device-only; `local/ios-skyreal` (7 commits) adds the calibration guide and star field and is not in this build.

### Spots (`C03`-`C15`, `D06`-`D07`, `E05`)
1. **Adding a spot is 6 fields and the system keyboard** (`C04`); "Fill from current place" helps once a place exists. Fine for a personal app.
2. **The week strip's day letters are Sat…Fri starting with last night** (B-2), and 0-minute nights show a red ✕ with "0" beneath: seven red crosses read as an error (`C07`, `D06`). Show "moon" glyphs for moon-limited nights and reserve ✕ for weather no-go.
3. **The measured Candlestick profile changes the strip from 0/0/0/2/49/106/172 to 0/0/6/35/84/142/208** (`C07` → `C10`): the terrain-aware headline works and is labelled "above the skyline · flat horizon 0 min (+0)". Good; but the "+0" for a 0-minute night is noise.
4. Spot detail has no field-mode toggle (B-7) and the horizon chart's y-axis label "10°" is clipped at the card edge (`C09`).
5. The Horizon card is four stacked full-width buttons ("Use the measured Candlestick Camp profile", "Recompute from terrain", "Import CSV…", "Remove profile") plus a five-line explanation (`C11`): a menu would do.
6. Alert section copy is honest and long (`C11`); fine.
7. Large type (`D07`): the strip's seven columns still fit; "0 min above the skyline · flat horizon 0 min (+0)" wraps into an unreadable tangle.
8. Spots list at Accessibility L: "Candlestick Camp" row shows the mini strip and age; good (`D06`).
9. "Sync spots with iCloud" is a disabled toggle with a five-line footer on every visit (`C06`): move to Settings/About until it exists.

### Tools (`D08`; the gear/NPF walk is covered by the passing `WeekToolsTests.testGearAndNPFCalculatorWalkthrough`, 97 s, not by my driver, whose Tools leg did not run)
1. Empty state is clear ("No gear yet"). Calculators are hidden until gear exists, which is correct but the "Calculators" header with "Add or pick a camera and lens" reads as an error.
2. Gear entry uses the in-app keypad for numbers (red-safe) and the system keyboard for names (not red-safe); the design branch keeps that split (DESIGN.md rule 5).
3. The field-mode toggle hides "Add camera and lens" (`editingAllowed = !state.fieldMode`), which is the right call, but nothing on screen says why the button vanished.

### Location sheet (`B02`, `focused/normal-6-location`, `field-6-location`)
1. Good: one tap to GPS, paste button, saved spots, privacy line. Field mode swaps the text field for an in-app keypad (`field-6`). The "Use" button is a bright accent capsule in field mode: full-red on black, the brightest thing on the page; dim it to `secondary`.
2. The GPS path leaves the place named "My location" forever; Tonight then shows "My location / 38.3740, -109.9654" in two lines. Name it after the nearest saved spot when within 1 km (Candlestick here).

### Alerts (`C11`)
1. Toggle → system notification prompt (white, unavoidable, documented). "Check now" and "Send a test notification" are useful. The footer explains the iOS budget honestly.

### Cross-tab inconsistencies
- Three different field-mode toggles: `FieldModeToggle` (system `.button` toggle: Tonight, Week, Tools, Spots), `MapScreen.fieldToggle` (custom circle), Sky's text button. Three toggle styles: `PaletteToggleStyle` (Spots/Alerts), `MapToggleStyle` (Map), `.switch` nowhere. Two section-header styles (`MapSection` uppercase caption vs `SectionHeader`). Design's `DESIGN.md` unifies all three, so the design merge is the fix; mapfix must then adopt `PaletteToggleStyle` for its new "Include imagery" toggle (it uses `MapToggleStyle`).
- Age wording: "fetched just now", "received just now", "Checked just now (in app)", "24 min old", "3 min ago": design's `Voice.age/ago` fixes it.


## E. Should-fix (P2) and nice-to-have

**P2**
1. **"Smoke unavailable" when HMS has no polygons** (`MapScreen.swift:172-173`, `LayerProvenance.swift:27-38`): the polygons request succeeded with an empty collection and the stats query returns `latest_end: null` when the layer is empty. Say "No smoke polygons in the current HMS analysis (checked N min ago)" and keep "unavailable" for a failed fetch (`failed.contains("hms/smoke.geojson")`). Owner: mapfix.
2. **`MapTests` are order-dependent**: they launch with `-resetMapState` only, so a remembered place from any earlier launch makes `testBadCoordinatesAreRejected` fail (`MapTests.swift:65`, seen in §F). Launch with `-DarkSkyUITest` (which clears `RememberedPlace`) like the other suites, or assert on the specific label text. Owner: coordinator.
3. **UI tests leave state behind**: `TonightScreen.restore()` removes `RememberedPlace` at launch under `-DarkSkyUITest` but `apply()` saves one during the test, so the next real launch opens on the test's place (`B01` showed 38.3500, -109.9500 from `TonightTests`). Skip `RememberedPlace.save` when `uiTesting`. Owner: coordinator.
4. **`ShotWindow` longest-vs-all windows** (Codex optional): decide and document before B-3 ships the card. Owner: coordinator.
5. **Provenance repeated three times on the map** (badge, Place card, per-toggle): once in the Place card, once on the toggle; the on-map badge only for live layers (IR age). Owner: mapfix/design.
6. **Sky tab recomputes the night model** (6.4 s in the simulator) that Tonight already holds: share `TonightModel`'s cache by place+night. Owner: skyreal.
7. **Conditions-by-hour strip**: 16 rows of 6-pt labels (`B06`). Collapse to factor rows with worst-model shading. Owner: design.
8. **Spots week strip glyphs**: ✕ for moon-limited nights reads as failure; a moon glyph and the minutes are enough (`C07`, `D06`). Owner: design.
9. **Accessibility L**: date row wraps between chevrons, "Every factor / Refresh" overflow the card (`D01`); "0 min above the skyline · flat horizon 0 min (+0)" tangles (`D07`); map cards swallow the map (`D04`). Design's `testAccessibilityXL` covers the headline only; extend it to these. Owner: design.
10. **GPS place naming**: "My location" stays the place name forever (`B04`); rename to the nearest saved spot within 1 km or the coordinates. Owner: coordinator.
11. **Field mode "Use" button and accent capsules** are full-red on black, the brightest element on the page (`field-6-location`, `A13` buttons); cap accent at `primary` brightness in field mode, as mapfix does for the map (`MapColors.fieldCap`). Owner: design.
12. **`SyncSection`** disabled toggle + five-line footer on every Spots visit (`C06`): move to an About/Settings screen. Owner: design.
13. **Widget "from local noon" timeline** inherits B-2; fix together. Owner: coordinator.
14. **No app icon** (placeholder grid on the home screen): trivial, but the owner will notice in the field. Owner: design.

**Nice-to-have**
- A "centre on pin / spot" button beside mapfix's centre-on-me.
- A map "expand" affordance or bottom-sheet panel (B-6a) rather than a fixed 340 pt map.
- Show the measured/computed skyline on the map as a shaded horizon ring at the pin.
- Week: one-line rows for moon-limited nights; tap to expand.
- Tools: keep calculators visible with "needs gear" placeholders so the tab is not empty on first visit.
- Log `launch-to-headline` to the Debug gallery so the owner can read it without `log show`.


## F. Test results

All commands from `/private/tmp/fable-review/integration` after `cd ios && xcodegen generate`, DerivedData `/private/tmp/fable-review/DerivedData`, destination `platform=iOS Simulator,name=iPhone 18 Pro Max`. The Mac was heavily loaded (seven sibling agents); runner start-up dominated the per-test times.

1. `xcodebuild build-for-testing …` — **TEST BUILD SUCCEEDED**, 0 errors (`/private/tmp/fable-review/build.log`).
2. Focused re-run of the checks Codex left incomplete: `xcodebuild test-without-building … -only-testing:DarkSkyUITests/TonightTests/testOfflineConditionsAreUnavailableNeverGood -only-testing:…/testScreenshotTour -only-testing:DarkSkyUITests/MapTests/testScreenshotsBothModes -only-testing:…/testMapLoadsAndCoordinateSetsPlaceWithoutTheMap` with `TEST_RUNNER_MAP_SCREENSHOTS=1 TEST_RUNNER_MAP_PLACE="38.3740, -109.9654" TEST_RUNNER_MAP_IR=1` — **4 passed, 0 failed** (225.1 s, 73.1 s, 206.7 s, 142.0 s); `MAP_TIMING tab to map: first frame 675 ms; fully rendered 6433 ms`. Log `focused.log`, bundle `focused.xcresult`, screenshots `shots/focused/`.
3. **Full suite:** `xcodebuild test -project ios/DarkSky.xcodeproj -scheme DarkSky -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath /private/tmp/fable-review/DerivedData -resultBundlePath /private/tmp/fable-review/full.xcresult` (1 624 s wall):
   - `SkyCoreTests` (Swift Testing): **321 tests in 46 suites passed** (3.5 s). Same count as Codex's 06:33 run.
   - `DarkSkyTests` (app-hosted, Swift Testing): **14 tests in 2 suites passed** (0.4 s).
   - `DarkSkyUITests` (XCTest): **29 executed, 25 passed, 2 failed, 2 skipped** (`testLiveConditionsTour`, `testScreenshotsBothModes`, both opt-in), 961 s.
     - **FAIL** `MapTests.testBadCoordinatesAreRejected` (`ios/UITests/MapTests.swift:65`, `XCTAssertFalse(app.staticTexts["map.placeLabel"].exists)`): the Map already had a place because `MapTests` launch with `-resetMapState` only and an earlier test's `RememberedPlace` survived (`TonightScreen.apply` saves it even under `-DarkSkyUITest`). Order-dependent, not a product bug (E #2, #3). Passes alone.
     - **FAIL** `SkyTests.testSimulatedViewListsTargetsForVoiceOver` (`SkyTests.swift:48`): overlay read "Facing south, 20° up, at 11:00 PM. On screen: Galactic Center 22° up in the south. Milky Way band on screen." with no "Terrain horizon shown", because `SimulatedSky.place(state.place)` used the leaked remembered place (no skyline) instead of the Candlestick demo place. Same root cause; Codex's isolated run of this test on a fresh simulator passed (80.4 s), as did the driver's Sky check here.
   - Per-suite: LaunchTests 1/1, MapTests 4/5 (+1 skipped), SkyTests 3/4, SpotsTests 7/7 (including `testMeasuredCandlestickProfile` 32.9 s and `testComputedCandlestickMatchesMeasured` 28.9 s, the latter downloading real terrain tiles), TonightTests 6/6 (+1 skipped), WeekToolsTests 5/5.
   - Log `/private/tmp/fable-review/full.log`; bundle `/private/tmp/fable-review/full.xcresult`.
4. Review driver (non-git copy, DerivedData `/private/tmp/fable-review/DerivedData-drive`): 5 tests, 4 passed; `testC_SkySpotsTools` failed at *my* tap of a field-mode toggle on the pushed Spot page, which does not exist (B-7). Timings from its log: launch→tab bar 13.8-31.3 s (XCTest attach, not representative); Map tab→first frame 424-1 112 ms, fully rendered 2.0-2.3 s; set place→azimuth lines 4.4 s; GPS tap→headline 13.1 s (includes the system permission alert); conditions loaded 3.9 s; Week tab→rows 4.2 s, conditions 7.9 s; Sky tab→overlay 6.4 s; Spot open→night minutes 5.3 s. Perf log (`log show`, subsystem `DarkSky`): `launch-to-headline` 9 785-17 064 ms with `screen-appear-to-headline` 285-939 ms in interactive launches (41-49 s under the test runner).
5. Not run: `swift test` in `ios/Packages/SkyCore` separately (covered by 3), the web/Worker suites (unchanged by the iOS branches), mapfix's `MapEngineTests` (would need a second app build and live tile downloads; disk was at 16-19 GB free).

## G. Field checklist for the owner's next outing

Build to install: `local/ios-integration` at 3094aeb **plus** the design branch merged (field mode persistence, brightness) or, failing that, expect to re-enable red mode after every relaunch. Do not rely on the Map for anything but azimuths until mapfix is merged and `data-refresh.yml` has run.

Before leaving (with signal):
1. Tonight → Choose a location → Use my location; confirm the coordinates match the truck/camp within 100 m and the time zone line says `America/Denver`.
2. If it is before noon, step "Next night" once and confirm the date is the coming night (B-2); note which night the Week and Spots screens show.
3. Spots → the saved spot → "Use the measured Candlestick Camp profile" (only at the surveyed point; elsewhere "Recompute from terrain" while online, ~36 tiles); note the "above the skyline" minutes versus "flat horizon".
4. Map → set the spot → note the GC rise azimuth and time; write down what the "at time" line says for the planned shot time.
5. Tonight → Refresh → the origin line should say "from the conditions Worker" (if it says "offline, showing the copy fetched just now" while online, that is B-4, not a real outage); open Every factor and note model run ages.
6. Toggle field mode, force-quit, relaunch: is it still red? (P2 #8 / B-8.)
7. Airplane mode → Tonight should show "offline, showing the copy fetched N min ago" with the same verdict; Map should still draw the lines; Spots should show "Checked N min ago".

At the site (no signal):
8. Compare the Spot's skyline clearance for the GC azimuth with the visible ridge; record the azimuth where they differ by more than about 2°.
9. Sky: note "Compass ±N°" before and after walking 20 m from the vehicle and tripod; calibrate on the Moon if offered; record whether the GC marker sits on the real core within a hand's width.
10. Use the Map scrubber to the planned shot time; confirm the GC line points where the core actually is.
11. Watch screen brightness in red mode; note whether the brightest element (accent buttons) is too bright at full dark (P2 #11).
12. At the end, note battery %, and whether any white surface appeared (permission prompt, notification, keyboard).

Back with signal:
13. Compare the cloud forecast (model, run) against what happened during the window; put it in PLAN.md §Log with the build hash.
