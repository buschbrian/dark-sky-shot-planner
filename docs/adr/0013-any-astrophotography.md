# ADR-0013: Any astrophotography: activity profiles and catalog targets

**Status:** Accepted (owner decisions D1–D9 recorded in `docs/deepsky/OWNER-DECISIONS.md`, 2026-09-27) · **Date:** 2026-09-27 · **Amends:** ADR-0009 §1

## Context

The app is built around the Milky Way core. The headline is moon-free
darkness, `gc_max_altitude` is the one target-specific factor in
`config/conditions-thresholds.json`, and `ShotTarget` (SkyCore) knows the GC,
two Milky Way arches, the Moon, five planets and eleven fixed stars and
objects. The owner asked for "any sort of astrophotography", deep sky with
ordinary telescopes in particular. The deep-sky research (`docs/deepsky/research/`)
finds that the verdict architecture carries over. The worst gating factor,
the moon-free window and the terrain-aware shot window all still hold. What
changes by activity is which factors gate, which window counts, and which
number is the headline (planning.md §5.4, §7.1). It also finds a gap no
surveyed tool fills: one ranked list of tonight's targets that combines the
terrain horizon, a multi-model forecast, the user's gear and moon avoidance
(apps.md §5).

## Decision

### 1. Scope contract, amended again

> **Should I go shoot tonight, and if so, what, where, when and how?**

ADR-0009 §1 stands. The new word *what* admits one family of features:

| Word | Admits |
|---|---|
| *what* | An **activity profile** (§2); photographic targets from a bundled catalog (§3); gear classes: camera + lens (M10), star tracker, telescope, astro camera, smart telescope |

The existing words widen only as far as the profile needs. *When* gains
per-target imaging windows. *How* gains framing (FOV, image scale, mosaics,
rotation), sub-exposure and integration guidance, lucky-imaging guidance,
and handing a target to a smart telescope on the local network.

**Still out:** general planetarium browsing beyond photographic targets;
social features and galleries; desktop-class processing (calibration-frame
pipelines, gradient removal, narrowband channel combination: Siril,
PixInsight and PlanetarySystemStacker cover these, apps.md §3 and
planning.md §6.1); sequencing, guiding, autofocus and full mount or camera
control; and everything ADR-0009 already excluded. Generative AI stays out
under ADR-0011 as amended. Anything the app computes is deterministic.

### 2. The activity profile is the key design move

One setting chooses the headline metric, the verdict window, which factors
gate and which advise, the target types and the tools. The worst-gating-factor
rule (PLAN.md §Verdict) holds *within* each profile. Profiles never average.

| Profile | Window | Headline | Gating vs nightscape | Targets | Tools |
|---|---|---|---|---|---|
| **Nightscape** (default) | Moon-free astronomical darkness | Moon-free minutes above the terrain | **Unchanged** | Today's `ShotTarget.presets` | NPF/500, DoF, stacking, timelapse, capture (M10, M12) |
| **Star trails** | Astronomical darkness, Moon allowed | Dark minutes | Moon-free minutes becomes advisory (planning.md §5.4) | Celestial pole, bright stars | Trail length, max-stack capture (CAPTURE-LIMITS.md) |
| **Meteors & aurora** | Moon-free darkness | Shower active, radiant altitude / Kp against the spot's visible Kp | Unchanged: the research has no row for it, so this is a proposal. Aurora still never lowers a verdict | Radiants (ADR-0008), north horizon | As nightscape |
| **Lunar** | Moon above terrain and floor, sunset to sunrise | Moon well-placed minutes, illumination, terminator | Moon presence is **positive**: moon-free minutes not applicable; seeing gates; AOD and smoke advise (§5.4, §6.3) | Moon, terminator features | Lucky imaging (M18), telephoto (CAPTURE-LIMITS.md) |
| **Planetary** | Planet above a 20–30° floor | Minutes above the floor under good seeing | **Seeing dominates and gates**; AOD and smoke advise; target altitude gates (§5.4, §6.2) | Planets, oppositions | Lucky imaging, sampling |
| **Deep-sky broadband** | Moon-free darkness ∩ target ≥ 30° ∩ terrain | Usable imaging minutes on the target | Target altitude gates (30°, §2.1); transparency gates *when available*; GC altitude not applicable | Galaxies, reflection nebulae, clusters | FOV, image scale, Glover subs, integration |
| **Deep-sky narrowband** | Darkness ∩ Lorentzian moon tolerance ∩ target ≥ 30° ∩ terrain | Usable narrowband minutes | Moon-free minutes is **replaced** by the Lorentzian window (60°, 7 d; planning.md §2.3) | Emission nebulae, SNRs, PNe | As broadband |
| **Solar** (only if the owner approves, OWNER-DECISIONS D2) | Daylight | Not designed yet | A safety acknowledgement gates everything; no filter recommendations until sourced (gear.md §6) | Sun | None yet |

For the deep-sky profiles, aurora also becomes a caution: it can ruin
faint-target backgrounds (planning.md §5.4).

**Config.** `conditions-thresholds.json` gains an `activities` section
(version 2). Each activity names its `window`, `headline`,
`min_target_altitude_deg`, optional `moon_avoidance {distance_deg, width_days}`,
and per-factor `overrides` of `gates_verdict`, `good` and `marginal`. The
top-level `factors` block is the nightscape profile, byte for byte, and
`nightscape` has no overrides, so every current verdict is unchanged.
Seeing gets a license-clean factor built on the Worker's existing
`wind_speed_250hpa` field. The research reads ≥ 60 kt as average-to-poor
seeing and ≥ 100 kt as poor (planning.md §5.1), so the proposed edges are
111 and 185 km/h. The 7Timer `seeing` factor stays advisory. The research
calls for stricter AOD and wind edges for telescopes but gives no numbers
(§5.3, §5.4). Those overrides start equal to nightscape and are tuned from
logged nights, the way the thresholds file already says. A new gate mode,
`when_available`, gates on a value when it exists, and a missing value does
not cap the night at "incomplete data". It is proposed for deep-sky
transparency only (§5.4 departure 1) and needs the owner's approval
(OWNER-DECISIONS D7), because it reverses the 2026-09-26 "transparency is
advisory" decision for those profiles.

### 3. Targets: generalize `ShotTarget` to catalog objects

`ShotTarget.fixed(FixedTarget)` already precesses a J2000 RA/Dec and runs
it through `ShotWindow.compute(…, minAltitudeDeg:)`, which already takes
the terrain skyline. Add `case catalog(SkyTarget)`. `SkyTarget` is a
catalog row with `id`, `common_name`, J2000 RA/Dec, `type`, size (major ×
minor, PA), magnitude, surface brightness, `broadband_or_narrowband` and
`license_source` (planning.md §1.9). `best_season` and the recommended
focal range are derived, not tagged. `needsMoonFree` moves from the target
to the profile, where the Moon stays the one target exempt from moon-free
darkness. Persisted `fixed:` ids keep decoding. The position math is
reused, not rewritten.

### 4. Data and licensing

| Catalog | License | Decision |
|---|---|---|
| Messier (110) | Public domain (planning.md §1.1) | Bundle |
| Caldwell (109) | Moore/S&T copyright on the published list; objects are facts (§1.2) | Recompile C-number → NGC/IC from public identities; credit Moore/S&T for the numbering |
| OpenNGC (NGC/IC) | **CC BY-SA 4.0** (§1.3) | Supplies sizes, magnitudes and names. Share-alike binds the derived data file, not app code. Whether to bundle it is **owner decision D1** |
| Sharpless, Arp, LDN/LBN, Abell | VizieR/CDS terms **unverified** (§1.4–1.7) | Deferred until each terms page is read and a `docs/data-licensing.md` row exists |

The starter set is 150–300 targets, well under 1 MB (planning.md §7.2),
built by an offline, fixture-tested pipeline from a pinned source commit
(AGENTS.md invariant 4).

## Alternatives considered

- **A separate deep-sky app.** It would duplicate SkyCore, the Worker, the
  terrain horizon and the verdict. Those are exactly the parts no
  competitor has together (apps.md §5).
- **A weighted "target score".** PLAN.md §Verdict rejects weighted sums
  because they hide the factor that kills the night. The ranking is instead
  a per-target verdict, then usable minutes.
- **Relaxing thresholds per activity with no window change.** This fails
  for narrowband, which needs a different window (the Lorentzian), not a
  looser number (planning.md §5.4 departure 3).
- **Bundling the full 13k-row NGC/IC.** It turns the app into a
  planetarium, which is out of scope. A browse-everything mode can be
  decided later.

## Consequences

- ADR-0009 §1's question and table gain *what*. On acceptance, the
  AGENTS.md summary line ("for Milky Way photography") and the PLAN.md
  "The job" section need updating.
- `conditions-thresholds.json` moves to version 2, and
  `ConditionsThresholds` stops rejecting any `window` other than
  `moon_free_darkness`. Every existing verdict test must pass unmodified
  under `nightscape`.
- New math (target windows, the Lorentzian, FOV and image scale, Glover,
  opposition) is pure SkyCore with published worked examples as tests.
  Whether the web app ports it, and so whether it joins
  `shared/golden/`, is owner decision D6.
- Each new source (OpenNGC, Caldwell mapping, any VizieR catalog, any
  lunar-feature list) gets a `docs/data-licensing.md` row before code
  reads it.
- The iPhone's 1 s frame ceiling (CAPTURE-LIMITS.md) holds on any mount.
  The app must say plainly that iPhone-only deep sky is limited, and that
  smart telescopes are the realistic phone-driven path (gear.md §4).
- Smart-telescope handoff depends on unofficial community bridges with no
  stability guarantee (gear.md §1, apps.md §2). It is opt-in, and a
  copy-coordinates fallback always works.
- The profile work sits on the M11 shot window and the verdict. Review
  findings B-2 to B-5 (`docs/ios/REVIEW-2026-09-27-FABLE.md`) are fixed
  first. The plan is `docs/deepsky/PLAN-ANY-ASTRO.md`, and the open calls
  are in `docs/deepsky/OWNER-DECISIONS.md`.
