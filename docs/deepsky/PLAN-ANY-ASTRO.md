# Any astrophotography: plan

**Status:** Accepted, 2026-09-27. ADR-0013 is accepted and owner decisions
D1–D9 are recorded in `docs/deepsky/OWNER-DECISIONS.md`. M13 has not started
yet: `docs/ios/PLAN.md`'s M13 precondition (its "Before M13" list below) is
still open, per owner decision D9.
**Why:** ADR-0013 (activity profiles, catalog targets; amends ADR-0009 §1).
**How to work:** as in `docs/ios/PLAN.md`. Work one milestone at a time, in
order. Each milestone ends with its checks green and a §Log note. SkyCore
stays pure, thresholds live in `config/`, and every number shows its source
and age (ADR-0006).
**Research cited below:** `docs/deepsky/research/{gear.md,gear.json,planning.md,apps.md}`,
`docs/gear/research/{opensource.md,iphone-techstack.md}`, `docs/ios/CAPTURE-LIMITS.md`.

## The job

> **Should I go shoot tonight, and if so, what, where, when and how?**

The nightscape profile is the default and keeps its headline, moon-free
minutes. Every other profile has its own headline (ADR-0013 §2). For deep
sky, the differentiator is one ranked list: tonight's targets for *my*
gear, from *this* spot, above *my* terrain, away from the Moon, under the
forecast. No surveyed tool joins all four (apps.md §5).

## Before M13: fix the foundations it stands on

M13 extends the M11 shot window and the verdict. The 2026-09-27 review
found both unfinished (`docs/ios/REVIEW-2026-09-27-FABLE.md`). Merge
these, with checks green, first:

- **B-2:** "tonight" rolls over once darkness ends (SkyCore and web);
  every per-target window inherits it.
- **B-3:** `ShotWindowCard` is wired into Tonight; the profile headline
  lives on it. **B-4:** the origin line reads "live" after a 304.
- **B-5:** a `.notApplicable` factor status replaces "incomplete data" on
  a moon-up night. Lunar and narrowband need this status.
- **P2 #4:** the owner decides between the longest window and all
  windows. The ranking inherits the rule.
- **B-8:** field mode persists (design branch). New screens use
  `screenChrome` and the palette.

## Cross-cutting rules for M13–M19

- **Nightscape is untouched.** A fresh install opens on nightscape. Every
  current verdict, headline and golden value is unchanged, and each
  milestone re-runs the existing suites to prove it.
- **Deterministic only.** Every window, ranking and recommendation is a
  cited formula with a worked-example test. Nothing is generative
  (ADR-0011 as amended). There are no weighted scores: a target ranks
  only if it passes its profile's verdict, then by usable minutes.
- **Rules of thumb are labelled.** The 30° floor, the tracked-sub ceiling
  and integration hours are community practice (planning.md §2.1, §4.2,
  §4.3).
- **Sources first.** A new data source gets a `docs/data-licensing.md`
  row before code reads it. Gear values come from the owner or a source,
  never a guess: a `null` in `gear.json` reads "not published".

## Milestones

### M13 — Activity profiles and generalized targets

- **Profiles.** `ActivityProfile` in SkyCore: nightscape, star trails,
  meteors & aurora, lunar, planetary, deep-sky broadband and deep-sky
  narrowband, plus solar if D2 approves it. Each profile carries its
  window, headline, targets and tools (ADR-0013 §2).
- **Config v2.** `config/conditions-thresholds.json` gains an
  `activities` section with per-factor `overrides`. Its top-level
  `factors` block is nightscape's, byte for byte. `ConditionsThresholds`
  accepts the `moon_free_darkness`, `astronomical_darkness`,
  `moon_tolerant` and `target_up` windows, and `daylight` if D2 approves
  solar.
- **Seeing.** A new factor, `jet_stream_250hpa`, reads the Worker's
  existing `wind_speed_250hpa` field (`worker/src/sources/openmeteo.ts`;
  already in `shared/golden/conditions-response.json`). The proposed edges
  are 111 and 185 km/h (60 and 100 kt, planning.md §5.1). It gates only
  in lunar and planetary. The Worker needs no change.
- **Transparency.** Deep-sky transparency uses the `when_available` gate,
  if D7 approves it.
- **Targets.** `ShotTarget` gains `case catalog(SkyTarget)` (ADR-0013 §3),
  and `needsMoonFree` moves to the profile. Until M14, the deep-sky
  profiles use the M31, M45 and M42 already in `FixedTarget.catalog`.
- **Verdict.** `Verdict.evaluate(…, activity:)` replaces
  `galacticCoreIsTarget:`. A nightscape GC shot keeps the
  `gc_max_altitude` gate.
- **Floor.** The profile passes its floor to the existing
  `ShotWindow.compute(minAltitudeDeg:)`: 30° for deep sky (§2.1), and an
  owner setting of 20–30° for planetary (§5.4). The higher of the floor
  and the terrain wins, as now.
- **Lunar.** The Moon is positive. Its window is the Moon above the
  terrain and the floor, from sunset to sunrise. Moon-free minutes is not
  applicable, seeing gates, and AOD and smoke advise (§5.4, §6.3). The
  headline is well-placed minutes and illumination.
- **Planetary.** Seeing and the target floor gate, and AOD and smoke
  advise (§5.4, §6.2).
- **UI.** A profile switch at the top of Tonight (D4), remembered across
  launches. Week, Spots, the widget and alerts follow it. The limiting
  factor stays beside the verdict (ios/AGENTS.md).
- **Done when:**
  - `swift test`: every existing Verdict, ShotWindow, WeekOutlook and
    golden-parity test passes **unmodified**. A parity test runs the 8
    `night-report.json` nights and the conditions golden response under
    v1 and v2-nightscape and gets identical verdicts.
  - Table tests: lunar on the 2026-09-26 full moon at Canyonlands (99.8 %,
    up all night; PLAN.md §Log) is not limited by the Moon; a 200 km/h jet
    is a planetary no-go on seeing and 80 km/h is good; narrowband loses
    only the minutes inside the Lorentzian while broadband loses every
    moon-up minute; an unavailable `when_available` factor raises no
    `incompleteData`; an override naming an unknown factor fails to load.
  - UI test: a fresh install shows nightscape. Lunar on a full-moon night
    changes the headline, and switching back restores it exactly. The
    profile survives a relaunch. VoiceOver reads the profile, the
    headline, then the verdict.
- **Owner checks:** nightscape reads as before. On one lunar or planetary
  night, did the seeing verdict match the eyepiece or the video? Log it.

### M14 — Target catalog and "tonight's best targets for my gear"

- **Data.** `pipelines/targets/` (Python, offline, fixture-tested) writes
  `config/targets/` from pinned inputs:
  - Messier, which is public domain (planning.md §1.1).
  - Caldwell, recompiled as C-number → NGC/IC (§1.2).
  - OpenNGC sizes, magnitudes and names at a pinned commit (§1.3), subject
    to D1.
  - Narrowband NGC/IC favourites such as NGC 281 and IC 1396 (§1.9).

  Sharpless, Abell, Arp, LDN and LBN wait until their VizieR terms are
  verified (§1.4–1.7). The catalog holds 150–300 rows (D5), with the
  fields in §1.9. `best_season` and the focal range are derived from RA
  and size, not tagged (§1.9, §2.5).
- **Ranking.** Each target gets a usable window: astronomical darkness
  (§2.4), intersected with the target above both the terrain and the
  floor (§2.1), intersected with the profile's moon rule. Broadband
  requires moon-free darkness. Narrowband uses the Lorentzian
  `distance / (1 + ((age/29.5 − 0.5)/(width/29.5))²)` with NINA's
  narrowband preset (60°, 7 d), scaled by Moon altitude (§2.3). No
  broadband Lorentzian values are researched. Next comes the profile's
  verdict over the window (transparency, AOD and smoke; §5.1). Last is
  framing fit against the gear's FOV: a mosaic hint when too big (M15),
  and a pixels-across floor when too small. The list shows targets that
  pass, by usable minutes, with framing fit as the tie-break. Each row
  names its limiting factor.
- **Browser.** Search by id or name. Filter by type and by broadband or
  narrowband (§5.2). Open any target in the shot-window card. Every
  catalog is credited, with the OpenNGC license if D1 bundles it.
- **Done when:**
  - Pipeline tests in `tests/` run on fixtures: row count, required
    fields, unique ids, and one object per Caldwell number.
    `tests/test_forbidden_sources.py` passes, and
    `docs/data-licensing.md` has a row per catalog.
  - `swift test`: the Lorentzian gives NINA's example, 60° at full moon
    and about 30° at quarter (§2.3); a synthetic skyline, floor and moon
    interval intersect to the expected minutes; the ranking is stable and
    never lists a failing target; persisted `fixed:` ids still decode.
  - Ranking the whole set for one night is timed on the owner's phone and
    logged. The proposed budget is 2 s, off the main thread and cached by
    place and night (review §E P2 #6).
  - UI test: searching "M31" opens its card. Offline, the list renders
    from cache with its age.
- **Owner checks:** compare tonight's top 10 against Telescopius for the
  same site and date (apps.md §1). Differences should trace to the terrain
  or the forecast.

### M15 — Framing and gear for telescopes

- **Gear profiles** (SwiftData, beside M10's camera and lens): telescope
  (with a reducer or Barlow factor); tracker or mount (payload, tracked or
  guided); astro camera (sensor, pixels, and a **user-entered** read
  noise, which `gear.json` lacks); smart telescope (fixed optics,
  published FOV, maximum sub, alt-az or EQ mode). Presets come from `gear.json` (11 smart telescopes, 5 trackers, 6
  refractors, 5 astro cameras, 5 mounts), with `source_url` and
  `verified_on`.
- **FOV and scale.** FOV = 57.3 × sensor mm / focal mm. Image scale =
  206.265 × pixel µm / focal mm. Sampling is judged against the
  well-sampled band of 0.7–2.0″/px for 2–3″ seeing (planning.md §3).
  Seeing FWHM is an owner setting, because no research maps the jet-stream
  proxy to arcseconds.
- **Field rotation.** On alt-az smart telescopes, the preset's maximum sub
  caps the advisor, and the UI explains EQ mode (gear.md §1). Examples: a
  Seestar S50 in alt-az gets about 10 s (approximate). An S50 Pro or
  DWARF 3 in EQ mode gets 60 s.
- **Framing preview.** The FOV rectangle and the target's ellipse (catalog
  size and PA) over the Sky view's `StarCatalog` (BSC5), with a rotation
  slider (§3). NINA's Framing Assistant is the UX reference (apps.md §1).
  At telescope fields (Stellina 1.0° × 0.7°, S50 Pro 2.8°; gear.md) BSC5
  shows few stars, and the preview says so. Survey imagery stays out,
  because its licensing is unresearched.
- **Mosaics.** Panels per axis = ⌈target / (frame × (1 − overlap))⌉, with
  10–20 % overlap and each panel's centre listed (§3).
- **iPhone as camera.** The 1 s ceiling holds on any mount
  (CAPTURE-LIMITS.md). On a tracker, the telephoto (19°) or main camera
  (70.7°) is a gear profile, and the app says plainly that iPhone-only
  deep sky is limited (gear.md §4).
- **Done when:**
  - `swift test`: an ASI533MC Pro (11.1 mm, 3.76 µm) on a RedCat 51
    (250 mm) gives 2.54° square and 3.10″/px (hand-computed from gear.md);
    a 3° target in a 2.54° frame at 15 % overlap needs 2 panels; sampling
    classes switch at their edges; every `gear.json` preset decodes with
    nulls kept.
  - UI test: a smart-telescope preset on M31 shows the FOV and a mosaic
    hint. Gear numbers use the in-app keypad in field mode (ios/AGENTS.md
    invariant 5).
- **Owner checks:** the framing matches Telescopius's simulator for the
  same gear and target (apps.md §1).

### M16 — Imaging window and integration planner

- **Per-target chart.** On the night strip's axes: astronomical darkness,
  floor crossings, transit, the moon-tolerance window and the terrain
  (planning.md §7.3). A GEM mount adds "meridian flip near HH:MM" (§2.2).
- **Sub-exposure advisor** (§4.3), in three tiers, and it names the tier
  that applies:
  1. The NPF ceiling, untracked (M10).
  2. Tracked and unguided: 30 s–2 min, less at long focal lengths,
     labelled a rule of thumb.
  3. Glover's `sub = C × RN² / sky rate` (SharpCap forums; §4.1), with C
     of 5, 10 (the default) or 25.

  It also shows the ratios: OSC needs about 3× mono, and narrowband
  allows about 25× broadband (§4.1).
- **Sky rate.** The owner enters either a measured e⁻/px/s (as SharpCap
  measures it) or an SQM or Bortle value. The SQM or Bortle →
  electron-rate conversion is **unresearched**, Bortle ↔ SQM is only
  approximate (§5.2), and the light-pollution layer is upward radiance,
  not sky brightness. So the SQM path waits for a cited method in
  `docs/methods.md`.
- **Integration.** Labelled heuristics (§4.2), with SNR ∝ √N: 1–2 h for
  bright targets, 3–6 h broadband at Bortle 1–4, 8–20+ h for faint
  targets, and more under brighter skies.
- **Multi-night.** Usable minutes per target across the week and the
  season, with transit about 4 min earlier each day (§2.5), set against
  the goal. Achieved time comes from M19.
- **Done when:**
  - `swift test`: Glover with C = 10, RN = 1.5 e⁻ and 0.5 e⁻/px/s gives
    45 s (hand-computed); the tier follows the mount; transit drifts about
    4 min a night over 30 nights; season minutes sum across a lunar cycle.
  - UI test: M31's chart at Candlestick marks the ridge crossing from the
    measured profile.
- **Owner checks:** plan one target for a week, then compare its clear
  and drop times with the real ridge.

### M17 — Smart-telescope handoff over ASCOM Alpaca

- **Copy coordinates, always.** J2000 RA/Dec, name and framing, for any
  app. Vaonis Singularity takes manual RA/Dec. The Seestar app reportedly
  takes catalog targets only, which is unverified (apps.md §2).
- **Alpaca client.** Plain HTTP/JSON on the local network (apps.md §2),
  as SkySafari 8 Pro does. It sends a target, slews and reads status. It
  does no sequencing, guiding or focusing (ADR-0013 §1). It honours the
  device's declared equatorial system (`ShotTarget.equatorOfDate`). No new
  package is needed.
- **What the owner would run:**
  - **Seestar:** `smart-underworld/seestar_alp` (Python, 292 stars) on a
    Mac, PC or Raspberry Pi, on the same network as the scope and the
    phone. Its Alpaca API is described in "Seestar Alpaca API.json"
    (apps.md §2).
  - **DWARF:** `acocalypso/dwarfAlp` (license and activity **unverified**,
    so check first), or DWARF's documented Stellarium remote control.
  - **Network:** the field setup (the scope's hotspot or a travel router)
    is confirmed on the owner's hardware.
- **Licenses.**
  - seestar_alp mixes MIT, BSD-3-Clause and GPL-3.0 (gear.md §1, apps.md
    §2). The app links none of it: it speaks the open protocol to a
    process the owner runs.
  - INDI's GPL parts, and INDIGO's no-GPL design, matter only if a driver
    is ever embedded.
  - No reverse-engineering of ASIAIR, Unistellar or Vaonis: none has a
    public API, and ASIAIR raises a ToS concern (apps.md §2).
- **Privacy.** Traffic stays local, and the Worker is not involved
  (ADR-0010). The local-network prompt is a system surface, so it is asked
  outside field mode (ios/AGENTS.md invariant 5).
- **Done when:**
  - Client tests run offline on fixtures recorded from seestar_alp's
    published spec (accepted, slewing, tracking, error). An unreachable
    bridge reads "unavailable", never "sent".
  - A localhost stub drives a send → status UI test. Each bridge's license
    and `verified_on` are recorded in `docs/data-licensing.md`.
- **Owner checks:** one real slew through the owner's bridge (D3). Record
  the bridge version and the firmware.

### M18 — Lunar and planetary helpers

- **Oppositions** come from the vendored `Astronomy_SearchRelativeLongitude`
  (`CAstronomy/astronomy.c` documents it for this). A planet
  `ShotWindow` runs over the planetary floor. A planet that transits low
  even at opposition says so (planning.md §6.2).
- **Verdict.** The seeing verdict comes from M13. The headline names the
  jet-stream value and its model run.
- **Terminator.** Its position and the illumination per night, from the
  Moon's phase geometry (§6.3). The **feature finder** needs a
  lunar-feature table that no research covers, so it waits for that
  source's licensing row.
- **Lucky imaging, iPhone** (afocal with a NexYZ-class adapter, or the
  telephoto on the Moon; gear.md §4):
  1. Record short-exposure video: 14 µs minimum, 1–30 fps in the best
     astro format (CAPTURE-LIMITS.md).
  2. Keep the sharpest 5–20 % of thousands of frames (§6.1).
  3. Register on the disk or limb, a new mode beside star registration,
     and stack.
  4. Export SER for PlanetarySystemStacker (GPL, macOS) or AutoStakkert!
     (§6.1).

  ProRes RAW is not confirmed as a third-party path (iphone-techstack.md
  §Video path).
- **Lucky imaging, telescope + planetary camera.** Guidance only
  (gear.md §5): a Barlow, an ADC when the target is low (best above f/15),
  and a high frame rate.
- **Done when:**
  - `swift test`: Saturn's opposition is found on 2026-10-04 ± 1 day
    (EarthSky, via §6.2); a planet window respects the terrain and the
    floor; frame selection keeps the sharpest of a synthetic blurred
    sequence; a SER file round-trips its header and frames (ser-player
    README).
  - A phone video run is logged with its fps, exposure and size.
- **Owner checks:** a Moon stack through the telephoto against a single
  frame. Optionally, afocal Jupiter or Saturn.

### M19 — Session log

- **Plan.** Spot, profile, targets and gear, with the planned window and
  verdict frozen with every factor's provenance.
- **Actuals.** Entered with the in-app keypad: sky, seeing and
  transparency (1–5), integration achieved, frames kept.
- **Calibration reminders.** Flats after any optical-train change, and
  dark-library validity by gain, temperature and exposure (planning.md
  §4.4).
- **Forecast vs actual,** per target and per profile, as the evidence the
  thresholds file asks for before tuning. Disagreements go to §Log, and
  the config is never auto-tuned.
- **Storage.** SwiftData with optional iCloud (ADR-0009 §4). The CSV
  export is for the owner, and nothing goes to a server.
- **Done when:**
  - Tests: a logged plan stays unchanged by later forecasts, the CSV
    export round-trips, and integration sums feed M16.
  - UI test: log a session in field mode without the system keyboard.
- **Owner checks:** three logged nights across two profiles. Record any
  threshold change and why.

## Plate solving (capture roadmap, not a milestone here)

One on-device solver serves **AR calibration** (solve a 1 s frame to
correct the Sky view's compass and attitude; iphone-techstack.md item 10)
and **deep-sky framing** (confirm an iPhone-on-tracker frame points where
M15's rectangle says; later, check a smart telescope's exported frame).
Research notes (opensource.md §3):

- No Swift port exists. The references are tetra3 and cedar-solve
  (Apache-2.0), OpenStartracker (MIT) and ASTAP (MPL-2.0).
- tetra3's default database covers 10–30° fields to magnitude 7. A
  database for the phone's 19–104° fields is estimated at tens of MB,
  unbenchmarked.
- Telescope fields of 1–3° (gear.md) need a catalog deeper than BSC5, a
  new data and licensing question, so phone fields come first.

Measure before designing (ADR-0011 §1).

## Log

- 2026-09-27: proposal written (ADR-0013, this plan, OWNER-DECISIONS.md).
  Documents only.
