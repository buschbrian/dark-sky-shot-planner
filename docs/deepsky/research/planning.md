# Deep-sky, planetary and lunar imaging: planning science and data

Research pass for expanding Dark Sky from Milky Way nightscapes to
telescope-based astrophotography (deep-sky, planetary, lunar). Dated
2026-09-27. Every claim below is cited; where a number is a rule of thumb
rather than a measurement, that is said explicitly.

This document assumes the reader has skimmed `docs/ios/PLAN.md` §Verdict and
`config/conditions-thresholds.json`. It proposes extensions, not replacements:
the existing worst-gating-factor verdict rule, moon-free-darkness window, and
shot-window/horizon-clearing planner are the right architecture to extend to
telescope targets — they just need new factors (transparency, seeing) turned
from advisory to gating for some activities, and new geometry (framing,
airmass, per-target altitude windows) layered on `SkyPositions`.

---

## 1. Target catalogs to bundle

### 1.1 Messier (M1–M110)

- **Content:** 110 bright deep-sky objects compiled by Charles Messier,
  finalized 1781 (published in the 1784 *Connaissance des Temps*).
- **License:** Public domain. Messier died in 1817; the catalog is over 200
  years old and is in the public domain in the US (pre-1929 publication) and
  in life+70/100-style jurisdictions alike. No machine-readable "official"
  file carries a license of its own — any modern CSV/JSON derivative (RA/Dec,
  magnitude, type) is *facts*, not a creative work, and is not separately
  copyrightable. Cite: [Charles Messier — Wikipedia](https://en.wikipedia.org/wiki/Charles_Messier); [SEDS Messier database](http://www.messier.seds.org/).
- **Size:** 110 rows. Trivial to hand-curate directly from OpenNGC/NED
  cross-matches (Messier objects mostly have NGC/IC numbers; M40, M45, M24
  and a few others do not and need their own rows — OpenNGC ships these in
  its `addendum.csv`, see §1.3).
- **Recommendation:** Bundle as a small hand-curated table (like
  `config/darksky-places.csv` and `config/sky-events.json` already are in
  this repo), not a scrape. No license risk.

### 1.2 Caldwell (C1–C109)

- **Content:** 109 objects selected by Sir Patrick Moore in 1995 as a
  "complement" to Messier (brighter southern/northern objects Messier
  missed), published in *Sky & Telescope*, December 1995.
- **License and naming questions:**
  - The catalog **text/table as originally published is copyrighted** —
    "© 1995 by Patrick Moore and Sky Publishing Corporation" per contemporary
    reprints (e.g. the Prescott Astronomy Club's PDF reproduction, which
    itself is a copy of the S&T table). Cite: [Caldwell catalogue — Wikipedia](https://en.wikipedia.org/wiki/Caldwell_catalogue); [Caldwell Objects PDF, Prescott Astronomy Club](https://prescottastronomyclub.org/wp-content/uploads/2022/03/Caldwell-Objects.pdf).
  - The underlying **objects and their NGC/IC identities and coordinates are
    facts** (astronomical positions are not copyrightable), so a from-scratch
    table of "Caldwell number → NGC/IC number → RA/Dec/mag/size" recompiled
    from OpenNGC and public ephemeris data avoids reproducing Moore's
    specific prose/formatting. This is the standard practice other apps
    follow (e.g. astropixels.com republishes the numeric table without
    claiming it as Moore's copyrighted list-text).
  - **Naming:** "C" was chosen because "M" was taken by Messier; Moore used
    his mother's maiden name, Caldwell (his own surname was Caldwell-Moore).
    Cite: [Caldwell catalogue — Wikipedia](https://en.wikipedia.org/wiki/Caldwell_catalogue).
  - **Practical recommendation:** build the Caldwell mapping (C-number →
    NGC/IC identifier) as a small hand-curated join table sourced from public
    NGC/IC identities (not copied from the S&T article's descriptive text),
    and cite Moore/S&T as the origin of the *numbering scheme* in the app's
    credits, the same way the app already credits DarkSky International for
    place *names* it re-derives. If in doubt, treat the C-number-to-object
    mapping as attribution-required fact reuse, not verbatim republication.
- **Size:** 109 rows.

### 1.3 OpenNGC (NGC/IC)

- **Content:** Merged NGC (7,840 objects) + IC (5,386 objects) database,
  positions, magnitudes (B/V/J/H/K), object type, angular size, surface
  brightness, and a Messier/common-name cross-reference (`addendum.csv`
  carries objects like M40, M45, and other non-NGC/IC objects worth
  tracking).
- **License:** **CC BY-SA 4.0**, confirmed directly from the README: *"OpenNGC
  is released under CC-BY-SA-4.0 license, which allows the use for a wider
  range of cases."* Cite: [OpenNGC README, mattiaverga/OpenNGC](https://github.com/mattiaverga/OpenNGC/blob/master/README.md).
- **Sources merged:** NASA/IPAC Extragalactic Database (NED), HyperLEDA,
  SIMBAD, HEASARC, Harold Corwin's NGC/IC Positions and Notes, plus common
  names from Wikipedia. Cite: same README.
- **Share-alike implications for bundling:** CC BY-SA 4.0 is a copyleft
  license. If OpenNGC's *data files* (not just facts extracted from them) are
  redistributed inside the app bundle, CC BY-SA requires:
  1. **Attribution** — credit "OpenNGC" and its authors/contributors, with a
     link to the license.
  2. **ShareAlike** — any *adaptation* of the OpenNGC database (e.g. a
     derived CSV/JSON/SQLite subset shipped in the app) must be offered
     under the same CC BY-SA 4.0 license, meaning a third party could ask
     for the derived file and redistribute it themselves under CC BY-SA.
  3. This does **not** contaminate the app's own *code* — CC BY-SA's
     share-alike is scoped to the database/data files (this is the same
     legal posture as OpenStreetMap data used in an app: the data stays
     ODbL/CC BY-SA, the app binary does not).
  - **Bundling recommendation:** ship the trimmed OpenNGC-derived catalog
    (a few hundred KB as CSV/SQLite, see §1.7 for size math) as a clearly
    separate data file, document it exactly like the existing
    `docs/data-licensing.md` table does for VIIRS/PAD-US, state "CC BY-SA
    4.0 — this file, if redistributed, must remain CC BY-SA 4.0 and credit
    OpenNGC," and do **not** merge raw NGC/IC astrometric identity facts
    (which are facts, not copyrightable) with OpenNGC's specific curated
    fields (surface brightness classification, common names, cross-IDs)
    without carrying the license forward — the safest and simplest path is
    to just carry CC BY-SA 4.0 on the whole NGC/IC data file.
- **Size:** roughly 13,226 NGC+IC rows total; a trimmed "photogenic subset"
  (see §1.7) is 150–300 rows and only a few hundred KB.

### 1.4 Sharpless (Sh2)

- **Content:** 313 (numbered 1–313, one duplicate/typo historically) H II
  emission-nebula regions north of declination −27°, published by Stewart
  Sharpless, final version 1959 ("Sharpless 2" / Sh2). Includes some
  planetary nebulae and SNRs incidentally. Cite: [Sharpless catalog — Wikipedia](https://en.wikipedia.org/wiki/Sharpless_catalog).
- **License:** The original 1959 published catalog is a US-government-funded
  scientific paper of that era; the **VizieR machine-readable version**
  (catalog `VII/20`) is hosted by CDS/Strasbourg. CDS/VizieR's general policy
  is that catalog data are free to use for research with attribution to
  the original authors and to VizieR/CDS as the access point; no per-catalog
  restrictive license was found published on the Sharpless VizieR page
  itself in this pass — **flag this as unverified and re-check the VizieR
  "Acknowledgment" text for VII/20 directly before bundling**, since CDS
  asks for citation of both the original paper and CDS. Cite: [VizieR VII/20 Sharpless catalogue](https://en.wikipedia.org/wiki/Sharpless_catalog) (points to CDS access).
- **Size:** 313 rows — small, easy to bundle as hand-curated CSV with
  RA/Dec/diameter from VizieR, citing Sharpless (1959) + CDS.

### 1.5 Arp (peculiar galaxies)

- **Content:** 338 peculiar/interacting galaxies, Halton Arp's *Atlas of
  Peculiar Galaxies* (1966), still the reference catalog for interacting
  galaxy pairs popular in imaging (Arp 273, Arp 244/"Antennae", etc.).
- **VizieR access:** catalog `VII/74`, described as containing Arp's
  original Table 2 from the 1966 ApJS paper. Cite: [VizieR Online Data Catalog: Atlas of Peculiar Galaxies (Arp 1966) — ADS](https://ui.adsabs.harvard.edu/abs/1995yCat.7074....0A/abstract).
- **License:** Same posture as Sharpless — CDS-hosted machine-readable
  version of a 1966 published paper; attribute Arp (1966) and CDS/VizieR.
  **Unverified: confirm no additional restriction on VII/74 specifically
  before bundling**, same caveat as §1.4.
- **Size:** 338 rows, small.

### 1.6 LDN / LBN (dark and bright nebulae, Lynds)

- **Content:** Two separate catalogs by Beverly Lynds:
  - **LDN** (Lynds' Catalogue of Dark Nebulae, 1962) — opacity-classed dark
    nebulae (Barnard-style objects), ~1,791 entries.
  - **LBN** (Lynds' Catalogue of Bright Nebulae, 1965) — ~1,125 entries,
    reflection/emission nebulae, distinct from LDN. Cite: [Lynds' Catalogue of Bright Nebulae — Wikipedia](https://en.wikipedia.org/wiki/Lynds%27_Catalogue_of_Bright_Nebulae).
- **License:** Same as Sharpless/Arp — VizieR-hosted historical papers;
  cite Lynds (1962/1965) + CDS. **Unverified per-catalog terms; re-check
  before bundling.**
- **Size:** LDN + LBN together are a few thousand rows; only a small
  "photogenic" subset (large/bright enough for amateur imaging — e.g. the
  Pipe Nebula LDN complex, Barnard 33/IC 434's LDN association) would make
  the 150–300 starter set.

### 1.7 Abell planetary nebulae

- **Content:** George Abell's 1966 catalog of 86 candidate planetary
  nebulae (79 confirmed PNe on follow-up), mostly large, faint, low-surface-
  brightness targets popular in narrowband imaging (Abell 21/Medusa, Abell
  39). Cite: [Abell Catalog of Planetary Nebulae — Wikipedia](https://en.wikipedia.org/wiki/Abell_Catalog_of_Planetary_Nebulae).
- **License:** Same VizieR/CDS posture (catalog area `VII/8`-adjacent for
  PNe compilations); cite Abell (1966) + CDS. **Unverified per-catalog
  terms; re-check before bundling.**
- **Size:** 86 rows — trivial to hand-curate.

### 1.8 Sources for object size, magnitude, surface brightness

- **OpenNGC** carries B/V magnitude, major/minor axis (arcmin), position
  angle, and a surface-brightness field for NGC/IC objects — this covers
  Messier and most Caldwell objects directly.
- **SIMBAD** (CDS) and **NED** (NASA/IPAC) are the underlying authorities
  OpenNGC merges from, and are the right fallback for any object missing a
  field, with their own citation requirements (cite SIMBAD/NED on lookup,
  standard academic practice; both are free for research/non-commercial
  reuse with attribution — re-verify before any commercial distribution).
- **Surface brightness for diffuse/narrowband targets** (Sharpless, LBN,
  Abell PNe) is often *not* in OpenNGC (these aren't NGC/IC objects) — for
  those, VizieR's catalog-specific tables (or literature integrated flux)
  are the source, and many popular imaging targets simply don't have a
  well-defined "surface brightness" number in a formal catalog; community
  references (Telescopius' object pages, Cloudy Nights imaging threads) are
  where imagers get a practical "how faint is this" read, but those are not
  bulk-licensable datasets — treat them as a citation source for hand-tuned
  numbers on the ~150–300 starter set, not a bulk import.

### 1.9 Recommended starter set: ~150–300 "photogenic" targets

Recommended composition (target ~200, expandable to 300):
- All 110 Messier objects (bright, well-documented, good beginner set).
- ~60–80 Caldwell objects not already in Messier (fills gaps, esp. southern
  and dim-but-popular targets).
- ~30–50 Sharpless/LBN/Abell narrowband favorites not in either (e.g. Sh2-101
  Tulip, Sh2-155 Cave, Sh2-132 Lion, Abell 21, IC 1396/Elephant's Trunk
  region, Pacman/NGC 281 already NGC).
- A handful of Arp interacting-galaxy showpieces (Arp 273, Arp 244) for
  broadband imagers with longer focal lengths.

Fields needed per target (a flat row, matching the app's existing
target-shot-window planner which already takes RA/Dec):
| Field | Notes |
|---|---|
| `id` | catalog + number, e.g. `M31`, `NGC7000`, `Sh2-101` |
| `common_name` | e.g. "Andromeda Galaxy" |
| `ra_j2000_deg`, `dec_j2000_deg` | matches existing `SkyPositions` RA/Dec convention |
| `type` | galaxy, emission nebula, reflection nebula, planetary nebula, globular cluster, open cluster, supernova remnant, dark nebula |
| `size_arcmin` | major × minor axis |
| `magnitude` | integrated, where defined |
| `surface_brightness` | mag/arcsec², where defined (critical for narrowband/faint targets where integrated magnitude is misleading) |
| `best_season` | derived from RA (transit month at solar midnight), not hand-tagged |
| `recommended_focal_length_mm_range` | derived from `size_arcmin` + typical sensor formats (see §3) rather than hand-tagged, so it stays correct as gear changes |
| `broadband_or_narrowband` | recommended imaging approach — emission nebulae/SNRs favor narrowband; galaxies/reflection nebulae/star clusters favor broadband |
| `license_source` | which catalog it came from, for the credits screen |

**License summary table for bundling decisions:**
| Catalog | License | Bundling risk |
|---|---|---|
| Messier | Public domain | None |
| Caldwell (numbering) | S&T/Moore copyright on the *published list text*; underlying object facts are not copyrightable | Low if table is recompiled from OpenNGC/public coordinates, not copied from the S&T article |
| OpenNGC | CC BY-SA 4.0 | Must attribute + share-alike the *data file* if redistributed; does not affect app code |
| Sharpless / Arp / LDN / LBN / Abell PNe (via VizieR/CDS) | Historical published papers, CDS access; per-catalog terms **not independently confirmed in this pass** | Low but **unverified** — re-check each VizieR catalog's terms of use page before bundling; CDS's blanket policy is attribution-only for research reuse, but confirm before shipping in a distributed app |

---

## 2. Imaging-window maths

### 2.1 Altitude and airmass — why above ~30°

- **Airmass** is the path length through the atmosphere relative to zenith;
  the simple secant approximation is `airmass ≈ 1/sin(altitude)`.
  At 30° altitude, `airmass ≈ 2` — you are looking through roughly twice the
  atmosphere as at zenith. Cite: [Transparency and Atmospheric Extinction — Sky & Telescope](https://skyandtelescope.org/astronomy-resources/transparency-and-atmospheric-extinction/); [Atmospheric Extinction and Refraction — Asterism.org](https://asterism.org/resources/atmospheric-extinction-and-refraction/).
- **Extinction impact:** a typical baseline extinction is ~0.16–0.2 mag per
  airmass at a good site (plus aerosol/haze contribution, which is exactly
  what this app's existing AOD/smoke factors already estimate). At 2 airmass
  (30° altitude), total extinction can reach ~0.4–0.8 mag depending on
  aerosol loading — i.e., **losing roughly a third to half the light**
  compared to zenith. Cite: [Star brightness and altitude?, Cloudy Nights](https://www.cloudynights.com/topic/359752-star-brightness-and-altitude/); [Minimum Altitude for Imaging, Cloudy Nights](https://www.cloudynights.com/topic/702611-minimum-altitude-for-imaging/).
- **Practical rule of thumb (community consensus, not a hard physical
  cutoff):** minimal expectations below ~30°; 30–45° is usable; by 60° the
  image should already look good, or the night is not going to improve much
  by waiting further. Cite: [Minimum Altitude for Imaging, Cloudy Nights](https://www.cloudynights.com/topic/702611-minimum-altitude-for-imaging/).
- **Seeing is also worse at low altitude** (more atmospheric path = more
  turbulence cells + more refraction/differential-color smearing), compounding
  the extinction problem — this is why the existing shot-window planner's
  horizon-clearing logic (clears a terrain horizon) is necessary but not
  sufficient for deep-sky: **a target can clear the terrain horizon at 8° and
  still be a poor imaging target until it crosses ~30°.**
- **App implication:** add a **minimum imaging altitude** parameter
  (default ~30°, adjustable) *distinct from* the terrain-horizon clearance
  already computed, used to compute a target's *usable* window, not just its
  *visible* window.

### 2.2 Meridian and transit

- **Transit** is when a target crosses the local meridian — its maximum
  altitude for the night/observing session, and (for equatorial/GEM mounts)
  the point where a **meridian flip** is needed. This is pure geometry
  already computable from RA/Dec + observer longitude + sidereal time, which
  `astronomy-engine` (already in SkyCore) supports directly.
- **Why it matters for planning:** the best imaging window for most targets
  is centered on transit (`transit ± N hours`, bounded by when altitude drops
  below the 30° floor on either side) — this is a simple, deterministic
  computation extending the existing shot-window planner.
- **Meridian flip note (a mount-mechanics fact, not optics):** GEM mounts
  must flip near transit to avoid the mount crashing into the pier; worth
  surfacing as a session-planning note ("meridian flip expected near
  HH:MM") if/when the app models mount type, but is not required for a V1
  imaging-window calculation.

### 2.3 Moon separation and illumination rules by filter type

- **Broadband** (RGB/luminance, no narrowband filter): most sensitive to
  moonlight — conventional guidance is to plan broadband deep-sky sessions
  during the **moon-free window** the app already computes, or when illumination
  is low (crescent) and separation is large.
- **Narrowband / dual-band** (Ha, OIII, SII, or dual-band like
  Optolong L-eXtreme/Antlia Dual-Band): tolerates much closer moon
  proximity and higher illumination because the filter blocks most of the
  moon-scattered broadband continuum, passing only the target's emission
  lines. Cite: [Urban Narrowband Astrophotography with Dual-Band Filters](https://www.opticalmechanics.com/urban-narrowband-astrophotography-with-dual-band-filters/); [Astrophotography in Light Pollution: Filters & Workflow](https://www.opticalmechanics.com/astrophotography-in-light-pollution-filters-workflow/).
- **Lorentzian moon-avoidance formula (ACP / NINA Target Scheduler):** the
  "Moon-Avoidance Lorentzian," from the Berkeley Automated Imaging Telescope
  (BAIT) team, formulated in ACP and reused in NINA's Target Scheduler
  plugin:

  ```
  required_separation = distance / (1 + ((moon_age/29.5 − 0.5) / (width/29.5))²)
  ```

  where `distance` (degrees) is the required separation at full moon, and
  `width` (days) controls how quickly the requirement relaxes as the moon
  moves away from full. Both `distance` and `width` are also scaled by moon
  *altitude*, relaxing the constraint further as the moon gets low.
  Cite: [Exposure Templates — NINA Target Scheduler docs](https://tcpalmer.github.io/nina-scheduler/target-management/exposure-templates.html); [ACP Scheduler Constraints doc](http://solo.dc3.com/ar/RefDocs/HelpFiles/ACPScheduler81Help/Constraints.htm).
- **Concrete example values from the NINA docs:** narrowband imaging can use
  `distance=60°, width=7` (60° separation required at full moon, only 30° at
  first/last quarter) — described as noticeably more permissive than ACP's
  "very conservative" broadband defaults. Cite: same NINA docs page.
- **App implication:** the existing moon-free-darkness window computation is
  the right primitive for **broadband/nightscape** activities. For
  **narrowband/dual-band**, add a *moon-tolerant* window using the Lorentzian
  formula (with per-activity `distance`/`width` presets) rather than
  requiring full moon-free darkness — this can meaningfully increase usable
  nights per month for narrowband imagers, which the app should surface
  explicitly ("narrowband window: 11:40 PM–4:10 AM, moon at 35% illum, 68°
  separation — passes narrowband threshold").

### 2.4 Astronomical twilight

- **Definition:** astronomical twilight ends (dark begins) when the sun's
  center is 18° below the horizon; it starts again (dark ends) when the sun
  rises back above −18°. Cite: [Rise, Set, and Twilight Definitions, USNO](https://aa.usno.navy.mil/faq/RST_defs); [What is Astronomical Twilight?, AstroBackyard](https://astrobackyard.com/astronomical-twilight/).
- **Why −18° and not −12° (nautical twilight):** at −12° to −18°, residual
  sky glow from the sun still measurably brightens the sky and reduces
  contrast on faint, diffuse targets (galaxies, faint nebulae, low-surface-
  brightness objects) even though it "looks" dark to the unaided eye,
  especially under any light pollution. Cite: [What is Astronomical Twilight?, AstroBackyard](https://astrobackyard.com/astronomical-twilight/).
- **App implication:** this app's SkyCore already computes darkness bands
  (civil/nautical/astronomical); deep-sky imaging-window math should key off
  **astronomical dark only** (sun < −18°) as the hard outer bound, same
  primitive as nightscape but without the nightscape-specific moon-free
  overlay for narrowband (§2.3).

### 2.5 Usable hours per night and across a season

- **Per-night usable hours** = intersection of:
  1. astronomical-dark window (§2.4),
  2. target-above-min-altitude window (§2.1, transit-centered, §2.2),
  3. moon-tolerance window appropriate to filter type (§2.3),
  4. terrain-horizon clearance (existing planner).
  This is a straightforward interval-intersection computation the existing
  shot-window planner architecture already does for horizon + darkness; it
  needs two more interval sources (altitude floor, moon tolerance) added to
  the same intersection.
- **Across a season:** for a given RA target, transit time shifts ~4 minutes
  earlier per day (sidereal vs solar day drift), so a target's "prime
  imaging season" is the multi-week/month window where transit falls inside
  astronomical dark *and* the target clears 30°+ for a useful duration.
  Computing "best N weeks to shoot this target" is the same geometry
  repeated across dates — a natural `best_season` field for the catalog
  (§1.9) can be derived this way rather than hand-tagged, keeping it correct
  automatically as the app's date range changes.

---

## 3. Field of view and framing

- **FOV formula:** `FOV (degrees) = 57.3 × sensor_dimension_mm / focal_length_mm`
  (small-angle approximation), applied separately to sensor width and height
  for a rectangular FOV, or `arcmin = 3438 × sensor_mm / focal_length_mm` for
  arcminutes. This is standard and appears across FOV calculators (e.g. the
  CCD Suitability / Astronomy Tools calculator ecosystem cited by Telescopius
  itself). Cite: [Telescopius — telescope simulator / FOV tool](https://telescopius.com/); [CCD Suitability calculator, astronomy.tools](https://astronomy.tools/calculators/ccd_suitability).
- **Image scale (arcsec/pixel):** `image_scale = 206.265 × pixel_size_µm / focal_length_mm`.
  This is the standard plate-scale formula (206,265 arcsec/radian). Cite: [CCD pixel size — Stan Moore Astro](http://www.stanmooreastro.com/pixel_size.htm); [CCD Pixel Scale Calculator, Super Global Calculator](https://superglobalcalculator.com/calculators/astronomy/ccd-pixel-scale/).
- **Sampling vs. seeing — Nyquist and the 2–3× rule:**
  - Strict Nyquist says sample at ≥2× the highest spatial frequency (i.e.
    ≥2 pixels across the seeing-disk FWHM) to avoid aliasing.
  - Because stars are round and pixels are square, the practical amateur
    consensus is **2.5–3 pixels across FWHM is the sweet spot**; up to
    4–5×/pixel still gives good results (oversampled but forgiving); below
    ~1.5–2×/pixel loses real resolution to aliasing/undersampling. Cite: [How bad is oversampling? — AstroWorldCreations](https://www.astroworldcreations.com/blog/oversampling); [Matching Your Camera to Your Optics, Diffraction Limited](https://diffractionlimited.com/matching-camera-optics/).
  - Concretely, for typical backyard seeing of 2–3 arcsec FWHM, the
    well-sampled image-scale range is roughly **0.7–2.0 arcsec/pixel**, with
    ~1.0–1.5 arcsec/pixel a comfortable mid-point; below ~0.7 is oversampling
    (wasted SNR, no extra real detail), above ~2.0 is undersampling
    (blocky/aliased stars). Cite: same AstroWorldCreations source.
  - **App implication:** given the seeing proxy the app already computes
    (jet-stream wind speed, §5) plus a chosen scope+camera's image scale
    (§3 formula), the app can directly flag "your setup is oversampled /
    well-matched / undersampled for tonight's seeing" — a genuinely new,
    deterministic, useful computation for SkyCore.
- **Mosaics:** needed when target angular size exceeds single-frame FOV
  (e.g. large nebula complexes like the Veil, North America/Pelican, Rho
  Ophiuchi). Standard practice is panel count = ceil(target dimension /
  (frame dimension × (1 − overlap))), with typical overlap 10–20% for
  registration; Telescopius' mosaic planner computes exactly this and
  outputs per-panel center coordinates. Cite: [Planning Mosaics with Telescopius, Deep Sky Workflows](https://deepskyworkflows.com/planning-mosaics-with-telescopius/).
- **Rotation:** camera rotation angle affects framing composition
  (e.g. keeping a galaxy's disk diagonal in frame, or two objects in one
  frame) — this is a UI/framing-preview concern more than a "science"
  computation; worth a simple rotation-angle preview overlay once basic FOV
  framing exists (§7).

---

## 4. Exposure planning

### 4.1 Sub-exposure length — Glover's formula and the "swamp factor"

- **Origin:** Dr. Robin Glover (author of SharpCap) proposed a method to pick
  the shortest sub-exposure length such that sensor read noise contributes
  only a small, chosen fraction of the total noise once the sky-background
  ("light pollution") shot noise is accounted for — i.e., the sky noise
  "swamps" the read noise so additional sub length stops meaningfully
  improving SNR per unit total integration time. This is documented across
  the SharpCap forums (Glover is the forum's operator) and implemented as
  SharpCap's built-in "Sub Exposure Calculator" / "Sky Background Electron
  Rate Calculator." Cite: [calculation of sub exposure – formula, SharpCap Forums](https://forums.sharpcap.co.uk/viewtopic.php?t=5024); [Light Pollution Rate formula, SharpCap Forums](https://forums.sharpcap.co.uk/viewtopic.php?t=3213); [Picking the correct exposure for Deep Sky, SharpCap Forums](https://forums.sharpcap.co.uk/viewtopic.php?t=456).
- **The formula:**

  ```
  sub_exposure_seconds = C × ReadNoise² / LightPollutionRate
  ```

  where `ReadNoise` is in electrons (camera spec, gain-dependent for CMOS),
  `LightPollutionRate` is the sky-background electron rate per pixel per
  second (function of sky brightness/Bortle + optics), and `C` (the "swamp
  factor") sets how much the read noise is allowed to matter relative to sky
  noise:
  - `C ≈ 25` → read noise adds ~2% extra noise (very conservative/long subs)
  - `C ≈ 10` → ~5% extra noise (Glover's commonly cited "reasonable" target)
  - `C ≈ 5` → ~10% extra noise (shorter subs, more frames, more read-noise
    hits but easier guiding/rejection of satellite trails/planes)
  Cite: same SharpCap forum threads above.
- **Practical implications documented in the community:**
  - **Colour (OSC) cameras need roughly 3× longer sub-exposures** than mono
    for the same swamp factor (Bayer matrix splits photons three ways).
  - **Narrowband filters allow roughly 25× longer sub-exposures** than
    broadband at the same location, because they block most of the
    light-pollution photons that would otherwise swamp read noise quickly —
    this is the same physical reason narrowband tolerates more moonlight
    (§2.3): the filter removes the broadband noise source entirely.
  Cite: same SharpCap forum sources.
- **App implication:** this is the single most valuable deterministic
  computation to add. Given (a) a bundled/estimated sky-background rate from
  Bortle/SQM (or, better, the app's own cloud-free-sky brightness data if
  available), (b) the user's camera read-noise spec (gear profile, which the
  app's Tools screen already models per camera+lens), and (c) filter type,
  SkyCore can compute a **recommended sub-exposure length** directly from
  Glover's formula — genuinely novel, source-cited, and squarely inside
  "deterministic-first" per Brian's standing preference.

### 4.2 Total integration heuristics by target type and Bortle

- No single authoritative formula exists for "how many total hours," but
  community-consensus heuristics (Cloudy Nights, SharpCap forums, and
  general practice) converge on:
  - **Bright targets** (Orion Nebula core, bright globulars/open clusters):
    1–2 hours total integration can be presentable.
  - **Typical galaxies/nebulae, broadband, dark sky (Bortle 1–4):** 3–6
    hours total is a common "good" starting target.
  - **Same targets from suburban/urban skies (Bortle 6–9):** need
    proportionally more integration to reach the same SNR, or a switch to
    narrowband/dual-band (§5) which effectively "buys back" dark-sky-like
    SNR by suppressing sky background rather than by adding time.
  - **Faint/low-surface-brightness targets** (large SNRs, faint dark nebula
    edges, faint PNe like Abell objects): 8–20+ hours is typical among
    imagers sharing such data online.
  - This heuristic is **not from a single citable paper** — it is standard
    community practice; the app should present it explicitly as a rule of
    thumb ("~3-6h typical for broadband nebulae/galaxies at Bortle ≤4;
    scale up for higher Bortle or fainter surface brightness") rather than
    as a precise physical prediction, and note that Glover's swamp-factor
    math (§4.1) is the only part of this with a rigorous derivation — total
    integration for a *target* SNR is a straight extension of it
    (`total_SNR ∝ √(N_subs)`, so total integration time to reach a given SNR
    scales with the *square* of the desired SNR improvement), but requires
    knowing the target's actual signal flux, which the bundled catalogs
    (§1) mostly don't carry precisely (surface brightness is the closest
    proxy).

### 4.3 Untracked limits (NPF) vs. tracker vs. guided

- **NPF rule** (Frédéric Michaud): a refinement of the old "500 rule" for
  maximum untracked exposure time before star trailing becomes objectionable,
  accounting for aperture, pixel pitch, and focal length (unlike the 500
  rule, which ignores sensor resolution):

  ```
  max_exposure_seconds = (35 × f_number + 30 × pixel_pitch_µm) / focal_length_mm
  ```

  Cite: [The NPF Rule: A Formula for Sharp Star Photos, PetaPixel](https://petapixel.com/2017/04/07/npf-rule-formula-sharp-star-photos-every-time/); [NPF Rule Calculator, Skies & Scopes](https://skiesandscopes.com/npf-rule-calculator/).
- The app already implements NPF/500-rule for nightscapes per
  `docs/ios/PLAN.md` (Tools screen). For deep-sky, NPF is the *ceiling* for
  truly untracked setups (star trackers/smart telescopes without guiding
  still benefit from it as a sanity check at very long focal lengths).
- **Tracker (unguided, e.g. star tracker or GEM with periodic-error only):**
  can exceed NPF substantially (minutes instead of seconds) but is limited by
  **periodic error** of the mount's worm gear and polar-alignment accuracy,
  not a clean formula — typically 30s–2min subs are achievable unguided on a
  well-polar-aligned consumer tracker before elongation appears, scaling
  down at longer focal length.
- **Guided (autoguiding via a guide camera + PHD2-class software):**
  removes the periodic-error ceiling; sub-exposure length becomes purely a
  function of Glover's swamp-factor formula (§4.1), not a tracking limit —
  guided imagers routinely run 2–10 minute broadband subs or 5–20 minute
  narrowband subs.
- **App implication:** the Tools screen's NPF/500-rule calculator extends
  naturally to a three-tier "max sub-exposure" advisor: NPF ceiling
  (untracked) → periodic-error rule-of-thumb ceiling (tracked, unguided) →
  Glover swamp-factor recommendation (guided, or as the true SNR-optimal
  target even when a shorter ceiling from tracking applies).

### 4.4 Dithering and calibration frames

- **Dithering:** small random pointing offsets between subs (handled by
  guiding software) so that fixed-pattern noise (hot pixels, sensor pattern
  noise) falls on different sky positions each sub and averages out in
  stacking/rejection, rather than stacking into a fixed hot-pixel column.
  Community guidance (Siril's own docs) notes that with sufficient dithering,
  dark-frame calibration can become less critical because pattern noise is
  already broken up by the dither + stacking rejection algorithm — though
  darks are still recommended for bias/thermal-signal removal, especially on
  cameras without good dark-current suppression. Cite: [Siril Calibration docs](https://siril.readthedocs.io/en/stable/preprocessing/calibration.html); [Siril — Enough with dark flats](https://siril.org/2021/12/enough-with-dark-flats/).
- **Calibration frame types (Siril's model, standard across the field):**
  - **Bias**: very short (minimum) exposure, closed shutter/covered — removes
    the ADC's fixed electronic offset.
  - **Darks**: same exposure length and temperature as the lights, covered —
    removes thermal/dark-current signal (roughly doubles for every 5–6°C
    sensor-temperature rise, per Clarkvision. Cite: [Clarkvision — Astrophotography and Exposure](https://clarkvision.com/articles/astrophotography.and.exposure/)).
  - **Flats**: images of an evenly illuminated field (sky flats, flat panel)
    at the *same optical train configuration* as the lights — remove
    vignetting and dust-shadow artifacts.
  - **Dark-flats** (a.k.a. "flat darks"): darks matched to the *flats'*
    exposure time/gain, used instead of bias when flats are long enough that
    bias alone doesn't model their dark-current contribution well; Siril's
    own guidance favors dark-flats over synthetic/generic bias for
    better-calibrated flats. Cite: [Siril — Enough with dark flats](https://siril.org/2021/12/enough-with-dark-flats/); [Siril Calibration docs](https://siril.readthedocs.io/en/stable/preprocessing/calibration.html).
- **App implication:** this is squarely a **session-log / checklist**
  feature (§7), not a physics computation — remind the user to shoot flats
  when optical train changes (new filter, refocus, rotation), and log dark
  library validity (same gain/temp/exposure) rather than compute anything
  new in SkyCore.

---

## 5. Conditions that matter for deep-sky vs. widefield

### 5.1 Transparency and seeing matter far more for deep-sky/planetary

- **Transparency** (haze/humidity/aerosol scattering) directly reduces
  contrast and total photon throughput for faint extended objects — this app
  already tracks the AOD and RAP-Smoke factors as gating for the general
  verdict; for **deep-sky specifically, transparency should gate more
  strictly** than it does for nightscapes, because faint nebulae/galaxies
  have far less signal margin than the Milky Way band, which is bright
  enough to power through moderate haze. The current config explicitly notes
  transparency is advisory *because* its only source (7Timer) is optional
  and non-commercial-only — that constraint doesn't change for deep-sky, but
  the app can still use the AOD/smoke factors (already gating) as the
  primary deep-sky transparency gate, and treat 7Timer transparency as a
  bonus refinement when available.
- **Seeing** (atmospheric turbulence/steadiness) matters far more for
  **planetary/lunar** (where resolving fine surface/cloud-band detail is the
  entire point, and pixel scales are typically <1 arcsec/pixel) and less —
  but still non-trivially — for high-focal-length deep-sky (where seeing sets
  the FWHM floor regardless of tracking/guiding quality, per the Nyquist
  discussion in §3). Wide-field nightscape work "barely notices seeing" per
  the existing thresholds config's own note — this app's current framing is
  correct and should carry forward, just with seeing becoming much more
  consequential as focal length increases.
- **Jet-stream seeing proxy:** the app's existing 250/200 hPa wind-speed
  proxy (already listed in `docs/ios/PLAN.md`'s data-sources table as "our
  own, license-clean seeing indicator") is validated by community practice:
  observatories and planetary imagers commonly use 250 hPa jet-stream wind
  speed as a seeing proxy — roughly, ≥60 kt brings average-to-poor seeing,
  ≥100 kt brings poor seeing, and calm 250 hPa winds correlate with the best
  planetary seeing nights. Cite: [Seeing & Jetstream Forecast, ChileScope](http://www.chilescope.com/equipment-and-infrastructure/weather-conditions/seeing-jetstream-forecast); [Jet stream question: What altitude is most critical?, Cloudy Nights](https://www.cloudynights.com/forums/topic/850301-jet-stream-question-what-altitude-is-most-critical/).
  This directly validates keeping/expanding the app's own jet-stream proxy
  as the primary seeing signal (license-clean, no 7Timer dependency) for
  planetary/lunar verdicts.

### 5.2 Bortle/SQM impact and which filters help

- **Bortle scale** is a 9-level *visual/descriptive* scale; **SQM**
  (Sky Quality Meter) gives an instrument reading in mag/arcsec² — a higher
  SQM number is a darker sky. The mapping between Bortle class and SQM is
  approximate/non-official (the original Bortle scale did not define exact
  SQM boundaries), so any Bortle↔SQM conversion table should be labeled as
  approximate. Cite: [Bortle Scale Guide, npfcalculator.com](https://www.npfcalculator.com/bortle-scale); [Find Your Night Sky Brightness on the Bortle Scale, AstroBackyard](https://astrobackyard.com/the-bortle-scale/).
- **Filter selection by Bortle/target:**
  - **UHC** (Ultra High Contrast): narrows the passband to include Hβ and
    OIII lines while still passing more spectrum than dual-band — a
    middle-ground filter, historically more of a *visual* filter but also
    used for imaging in light pollution.
  - **Dual-band** (e.g. Ha+OIII "duo-narrowband," such as Optolong
    L-eXtreme or Antlia ALP-T): narrowest passband among the three,
    essential for **Bortle 6–9** emission-nebula imaging, effective with
    both OSC and mono cameras, and (per §2.3/§4.1) tolerates significant
    moonlight and shortens the swamp-limited sub-exposure penalty from light
    pollution dramatically. Cite: [Best Astrophotography Filters Explained: UHC vs Dual-Band vs Broadband, ORIVON](https://orivonspace.com/articles/guide-best-filters-explained.html); [Light Pollution and the Bortle Scale: A Practical Guide](https://www.opticalmechanics.com/light-pollution-and-the-bortle-scale-a-practical-guide/).
  - **Broadband targets (galaxies, reflection nebulae, most star clusters)
    get little/no benefit from narrowband filters** — these emit a
    continuous spectrum, not isolated emission lines, so narrowband filters
    remove signal along with noise. This is why the catalog's
    `broadband_or_narrowband` field (§1.9) matters: it's an object-type
    property (emission-line nebula vs. continuum source), not a
    site-condition property.

### 5.3 Dew and wind thresholds for telescopes

- Telescopes (especially fast reflectors/refractors with correctors, and
  particularly open-tube Newtonians) are far more dew-prone on corrector
  plates/lenses than a bare camera lens, and wind affects long-focal-length
  setups (more torque arm, more susceptible to vibration blur at the
  sub-exposure length) more than a wide nightscape lens. The app's existing
  dew-point-spread and wind-gust factors are the right primitives; **for
  telescope activities the wind-gust threshold should likely gate more
  strictly** (vibration blur at 1000mm+ focal length shows up far below the
  20/40 km/h thresholds currently set for nightscape tripod stability), and
  dew — currently advisory ("bring a dew heater") — should probably stay
  advisory for deep-sky too (a dew heater genuinely solves it operationally,
  it doesn't need to gate the plan), but the threshold value itself may need
  retuning for telescope corrector plates vs. bare lenses. This is a
  **retune, not a new factor** — flag for owner-night calibration per the
  existing thresholds-file philosophy ("proposals... tune against real
  shoot nights").

### 5.4 Proposed verdict profile per activity

Following the existing worst-gating-factor architecture exactly
(`config/conditions-thresholds.json`'s `gates_verdict` flag per factor), here
is a proposed gating matrix. **G** = gates verdict, **A** = advisory only,
**—** = not applicable/not shown.

| Factor | Nightscape (current) | Star trails | Deep-sky broadband | Deep-sky narrowband/dual-band | Planetary / lunar |
|---|---|---|---|---|---|
| Moon-free minutes | G | A (moon can add star-trail interest) | G (or moon-tolerant window, §2.3, if using a broadband-with-moon-avoidance mode) | A → replaced by Lorentzian moon-tolerance window (§2.3), not a hard gate | A (moon brightness irrelevant/beneficial for lunar; low relevance for bright planets) |
| Cloud cover (mean/worst-hour) | G | G | G | G | G |
| AOD (haze/smoke) | G | G | **G, stricter thresholds** (faint targets have less margin) | **G, stricter thresholds** | A (planets are bright; haze mainly costs contrast, not detectability) |
| Smoke column | G | G | G | G | A |
| PM2.5 / AQI | A | A | A | A | A |
| Transparency (7Timer) | A (source-availability reason, unchanged) | A | **G when available, else fall back to AOD/smoke as gating proxy** | **G when available, else fall back to AOD/smoke** | A (seeing dominates, §5.1) |
| **Seeing** (jet-stream proxy) | A (barely matters) | A | A (matters more at long focal length, §3) | A | **G — the dominant factor for planetary/lunar** |
| Wind gusts | G | G | **G, stricter threshold for scopes** | **G, stricter threshold** | **G, strictest — long focal length is most vibration-sensitive** |
| Dew point spread | A | A | A (dew heater note) | A | A (dew heater note) |
| GC max altitude | G (MW-target plans only) | — | — (replaced by per-target min-altitude gate, §2.1) | — (same) | — (replaced by per-target min-altitude + opposition timing, §6) |
| **Target min altitude (new)** | — | — | **G, default 30°** | **G, default 30°** | **G, default 20-30° depending on aperture/seeing** |
| Kp / aurora | Opportunity flag only | Opportunity flag only | Opportunity flag only (aurora can actually ruin faint-target backgrounds — consider a caution note, not just "opportunity," for deep-sky) | Same caution note | N/A |

Key departures from the current config worth flagging explicitly to the
owner, since the thresholds file says "the thresholds are proposals... write
disagreements in §Log":
1. **Transparency becomes gating for deep-sky** (when 7Timer is available),
   reversing the current "advisory for everyone" stance — but only for
   deep-sky activities, and only as a *when-available* gate so 7Timer's
   optionality doesn't cap every deep-sky night at "marginal — incomplete
   data" the way a blanket gate would (same reasoning the current config
   already applied when it chose advisory).
2. **Seeing becomes the dominant gating factor for planetary/lunar** — this
   is the one activity where the current "seeing barely matters" framing
   flips entirely.
3. **Moon handling for narrowband is not a simple advisory-vs-gate
   flip** — it should become a *different window computation*
   (Lorentzian moon-tolerance, §2.3) layered under the existing moon-free
   darkness primitive, not just a relaxed threshold on the same number.

---

## 6. Planetary and lunar

### 6.1 Lucky imaging

- **Concept:** instead of one long exposure, capture a high-frame-rate video
  (tens to hundreds of fps) and keep only the sharpest fraction of frames
  (the moments atmospheric turbulence briefly "settles"), then align and
  stack those. Cite: [An Introduction to Lucky Imaging for Astrophotography, Sky & Telescope](https://skyandtelescope.org/astronomy-blogs/imaging-foundations-richard-wright/lucky-imaging/).
- **File format — SER:** the de facto standard raw video format for
  planetary/lunar/solar lucky imaging (uncompressed, >8-bit depth, stores
  timestamp/exposure/instrument metadata per frame) — FITS is to single
  deep-sky frames what SER is to planetary video sequences. Supported by
  FireCapture, SharpCap, PIPP, AutoStakkert, PlanetarySystemStacker, Siril,
  RegiStax. Cite: [ser-player README, cgarry/ser-player (GitHub)](https://github.com/cgarry/ser-player/blob/master/README.md); [SER — FreeAstro](https://free-astro.org/index.php/SER).
- **Frame rates:** planetary/lunar lucky imaging typically runs tens to
  ~100+ fps depending on camera and target brightness (brighter target/
  smaller ROI → higher achievable fps); the goal is enough frames (often
  thousands) that a good "keep percentage" (commonly 5–20% of frames) still
  yields hundreds of high-quality frames to stack.
- **Stacking tools:**
  - **AutoStakkert!** (AS!2/AS!3/AS!4) — the most widely used lucky-imaging
    stacker; **Windows-only**, freeware but not stated as open source (no
    published source repo found; treat as proprietary freeware, not
    bundleable). Cite: [AutoStakkert! homepage](https://www.autostakkert.com/).
  - **PlanetarySystemStacker (PSS)** — **open source, GNU GPL**, Python 3,
    cross-platform (Windows/Linux/macOS tested), comparable quality to
    AutoStakkert!3 in community tests. Cite: [PlanetarySystemStacker, GitHub — Rolf-Hempel](https://github.com/Rolf-Hempel/PlanetarySystemStacker); [PlanetarySystemStacker on PyPI](https://pypi.org/project/planetary-system-stacker).
  - **RegiStax** — pioneered wavelet sharpening for planetary post-
    processing; last updated 2011, still functional and widely used for the
    wavelet step specifically, freeware (not confirmed open source).
    Cite: [Registax — Wikipedia](https://en.wikipedia.org/wiki/Registax).
  - (Not requested but relevant: **LuckyStackWorker**, MIT-licensed,
    automates the AutoStakkert→wavelet post-processing pipeline. Cite: [LuckyStackWorker by Wilco Kasteleijn](https://www.wilcokas.com/luckystackworker).)
  - **App implication:** the app itself is a *planning* tool, not a stacker
    — but if it ever recommends/bundles a companion tool reference,
    **PlanetarySystemStacker (GPL, cross-platform, macOS-tested)** is the
    only one of these that is both open source and confirmed to run on
    macOS, relevant given the project's Apple-first stack.

### 6.2 When planets are well placed

- **Opposition:** a superior planet (Mars, Jupiter, Saturn, etc.) is best
  placed when at opposition — Earth passes between the sun and the planet,
  so the planet is at its closest approach for that synodic cycle, largest
  in apparent size, brightest, and up all night (rises at sunset, transits
  at midnight, sets at sunrise). Cite: [What is a planet in opposition?, Royal Observatory Greenwich](https://www.rmg.co.uk/stories/space-astronomy/what-planet-opposition); [Mars opposition, BBC Sky at Night Magazine](https://www.skyatnightmagazine.com/advice/skills/mars-opposition).
  Example from this pass: Saturn's 2026 opposition is October 4 — i.e. right
  after this document's research date, illustrating this is a
  deterministically computable annual event (opposition date = when
  planet's ecliptic longitude is opposite the sun's), not something that
  needs a hand-curated calendar. Cite: [Saturn at opposition – brightest for 2026 – on October 4, EarthSky](https://earthsky.org/astronomy-essentials/saturn-at-opposition-closest-brightest-best/).
- **Altitude still matters even at opposition:** opposition maximizes size/
  brightness, but the target still needs to clear a useful altitude (§2.1) —
  a planet at opposition but low in the ecliptic (e.g. Saturn from northern
  mid-latitudes in recent/current years, given its southern declination) may
  still transit at a disappointingly low altitude, which matters more for
  planetary imaging than deep-sky because seeing/airmass dominate resolution
  at high magnification.
- **Seeing dominance:** for planetary/lunar, once basic altitude/opposition
  timing is satisfied, **seeing is the dominant remaining variable** (§5.1) —
  aperture and focal length set the theoretical resolution ceiling, but
  atmospheric seeing sets the *achieved* ceiling on most nights, which is
  exactly why the app's jet-stream proxy should gate planetary verdicts.

### 6.3 Moon-phase terminator targets

- Lunar imaging quality depends heavily on **terminator position** (the
  day/night boundary), not phase brightness — surface relief (craters,
  rilles, mountain shadows) is most dramatic near the terminator, where low
  sun angle casts long shadows; a full moon (terminator absent, flat
  lighting) is the *worst* phase for surface-detail imaging despite being
  brightest. This means the app's "moon-free" framing (good for deep-sky)
  actively inverts for lunar-surface imaging — the app should compute
  **terminator longitude per date** (straightforward from lunar phase angle,
  itself already presumably available from astronomy-engine) and surface a
  "best craters near terminator tonight" note rather than treating moon
  presence as a negative factor at all for this activity.

---

## 7. Recommendations for the app

### 7.1 New SkyCore computations (deterministic, cite-backed)

1. **Airmass / minimum-altitude window** per target (§2.1) — extend the
   existing shot-window/horizon planner with a configurable altitude floor
   (default 30°, lower for planetary/lunar per §6.2) independent of terrain
   horizon.
2. **Transit-centered usable-window intersection** (§2.2/§2.5) — combine
   astronomical-dark, altitude-floor, moon-tolerance, and terrain-horizon
   intervals into one "usable hours tonight" and "usable hours this season"
   number per target.
3. **Lorentzian moon-tolerance window** (§2.3) for narrowband/dual-band
   activities, as a second window type alongside the existing moon-free-
   darkness window, with per-activity `distance`/`width` presets.
4. **FOV / image-scale / Nyquist-match calculator** (§3) — given
   scope+camera (already modeled for Tools/gear), compute FOV, arcsec/pixel,
   and a sampling verdict (oversampled/matched/undersampled) against
   tonight's seeing proxy.
5. **Glover sub-exposure calculator** (§4.1) — given camera read noise
   (gear profile), Bortle/SQM or measured sky background, and filter type,
   compute recommended sub-exposure length and expose the swamp-factor `C`
   as a user-adjustable "aggressiveness" setting.
6. **Three-tier max-sub-exposure advisor** (§4.3): NPF ceiling → tracked
   periodic-error rule of thumb → Glover-optimal, labeled by which applies
   given the user's declared mount/guiding setup.
7. **Opposition and terminator-position calculators** (§6.2, §6.3) for
   planetary/lunar — both are pure ephemeris geometry, fitting naturally next
   to the existing astronomy-engine-backed `SkyPositions`.
8. **Per-activity verdict profiles** (§5.4) — extend
   `config/conditions-thresholds.json` with an `activity` dimension so
   `gates_verdict` can vary by activity (nightscape / star-trails /
   deep-sky-broadband / deep-sky-narrowband / planetary-lunar) rather than
   being a single global flag per factor, preserving the worst-gating-factor
   rule *within* each activity profile.

### 7.2 Data to bundle

- **Messier** (110, public domain) — bundle now, no license risk.
- **Caldwell** (109, recompute numbering-to-object mapping from OpenNGC/
  public coordinates rather than copying the S&T table) — bundle with a
  clear credit line to Patrick Moore/Sky & Telescope for the *numbering
  scheme's origin*.
- **OpenNGC trimmed subset** (150–300 rows for the starter set, full 13k+
  available for a "browse everything" mode later) — bundle under **CC BY-SA
  4.0**, ship as a separate, clearly licensed data file (mirroring how
  `docs/data-licensing.md` already documents VIIRS/PAD-US), with attribution
  text and a note that redistributing this specific file requires
  preserving CC BY-SA 4.0.
- **Sharpless / Arp / LDN / LBN / Abell PNe** — small hand-curated subsets
  (dozens to a few hundred rows total) sourced from VizieR, cited to their
  original 1959–1966 papers plus CDS; **confirm each VizieR catalog's terms
  page directly before shipping**, same diligence pattern this repo already
  applies (see the `data-licensing.md` "Verified on 2026-09-25 by fetching
  each endpoint and reading each source's terms" practice) — treat as
  unverified until that check is done.
- **Total bundle size** for the 150–300 target starter set: trivially small
  (well under 1 MB as JSON/CSV/SQLite), in the same class as the existing
  `config/darksky-places.csv` and `config/sky-events.json`.

### 7.3 New features

1. **Target browser — "tonight's best targets for my gear"** — filter the
   bundled catalog by: clears altitude floor tonight, fits current
   scope+camera's FOV reasonably (not wildly over/undersized per §3), passes
   the activity's verdict profile (§5.4/§7.1.8), and sort by usable-hours-
   tonight (§7.1.2).
2. **Framing preview** — render the bundled target's size/PA against the
   computed FOV rectangle (§3), with a rotation-angle slider.
3. **Imaging-window chart** — a per-target Gantt-style bar across the night
   (like the existing Tonight night-strip, but per-target): astronomical
   dark, altitude-floor crossing, transit, moon-tolerance window, terrain
   horizon — all on one timeline.
4. **Integration planner** — given the Glover sub-exposure recommendation
   (§7.1.5) and a target total-integration heuristic (§4.2, clearly labeled
   as a rule of thumb), compute "N subs × T seconds = target total time,"
   and let the user see how many nights that spans given tonight's/this
   season's usable hours (§7.1.2).
5. **Moon-avoidance per filter** — surface the Lorentzian window (§7.1.3)
   distinctly for broadband vs. narrowband/dual-band plans on the same
   target, so a user can see "no-go for broadband tonight (moon), but
   narrowband is fine."
6. **Session log** — calibration-frame reminders (§4.4: flats needed after
   optical-train change; dark-library validity by gain/temp/exposure match),
   plus a place to record actual vs. predicted seeing/transparency, closing
   the loop the same way `docs/ios/PLAN.md` already asks the owner to do for
   nightscape verdicts ("did the verdict match the sky? Log it").

---

## Sources

**Catalogs and licensing**
- [OpenNGC README, mattiaverga/OpenNGC (GitHub)](https://github.com/mattiaverga/OpenNGC/blob/master/README.md) — CC BY-SA 4.0 license statement, data sources.
- [Caldwell catalogue — Wikipedia](https://en.wikipedia.org/wiki/Caldwell_catalogue) — naming origin, Patrick Moore/Sky & Telescope 1995.
- [Caldwell Objects, Prescott Astronomy Club (PDF reprint)](https://prescottastronomyclub.org/wp-content/uploads/2022/03/Caldwell-Objects.pdf) — "© 1995 by Patrick Moore and Sky Publishing Corporation."
- [Charles Messier — Wikipedia](https://en.wikipedia.org/wiki/Charles_Messier) — public-domain status basis (death 1817, 1781 catalog).
- [Sharpless catalog — Wikipedia](https://en.wikipedia.org/wiki/Sharpless_catalog) — Sh2 scope, 313 objects, 1959.
- [Lynds' Catalogue of Bright Nebulae — Wikipedia](https://en.wikipedia.org/wiki/Lynds%27_Catalogue_of_Bright_Nebulae) — LBN vs LDN distinction.
- [Abell Catalog of Planetary Nebulae — Wikipedia](https://en.wikipedia.org/wiki/Abell_Catalog_of_Planetary_Nebulae) — 86 entries, 79 confirmed PNe.
- [VizieR Online Data Catalog: Atlas of Peculiar Galaxies (Arp 1966) — ADS](https://ui.adsabs.harvard.edu/abs/1995yCat.7074....0A/abstract) — Arp VII/74 access point.
- [Telescopius — telescope simulator / FOV / mosaic planner](https://telescopius.com/); [Development API](https://telescopius.com/pages/api); [Planning Mosaics with Telescopius, Deep Sky Workflows](https://deepskyworkflows.com/planning-mosaics-with-telescopius/).

**Exposure and sensor science**
- SharpCap Forums (Robin Glover, operator/SharpCap author): [calculation of sub exposure – formula](https://forums.sharpcap.co.uk/viewtopic.php?t=5024); [Light Pollution Rate formula](https://forums.sharpcap.co.uk/viewtopic.php?t=3213); [Picking the correct exposure for Deep Sky](https://forums.sharpcap.co.uk/viewtopic.php?t=456); [Is My Exposure Calculation Correct?](https://forums.sharpcap.co.uk/viewtopic.php?t=3333).
- [Clarkvision — Astrophotography and Exposure](https://clarkvision.com/articles/astrophotography.and.exposure/) — noise sources, dark-current doubling per 5–6°C, SNR ∝ √N.
- [Clarkvision — Digital Camera Review and Sensor Performance Summary](https://www.clarkvision.com/articles/digital.sensor.performance.summary/).
- [The NPF Rule: A Formula for Sharp Star Photos, PetaPixel](https://petapixel.com/2017/04/07/npf-rule-formula-sharp-star-photos-every-time/); [NPF Rule Calculator, Skies & Scopes](https://skiesandscopes.com/npf-rule-calculator/).

**Optics and sampling**
- [How bad is oversampling? — AstroWorldCreations](https://www.astroworldcreations.com/blog/oversampling) — 2–3× seeing rule, practical arcsec/pixel ranges.
- [Matching Your Camera to Your Optics, Diffraction Limited](https://diffractionlimited.com/matching-camera-optics/).
- [CCD pixel size, Stan Moore Astro](http://www.stanmooreastro.com/pixel_size.htm); [CCD Pixel Scale Calculator, Super Global Calculator](https://superglobalcalculator.com/calculators/astronomy/ccd-pixel-scale/); [CCD Suitability calculator, astronomy.tools](https://astronomy.tools/calculators/ccd_suitability).

**Altitude, airmass, twilight**
- [Transparency and Atmospheric Extinction, Sky & Telescope](https://skyandtelescope.org/astronomy-resources/transparency-and-atmospheric-extinction/).
- [Atmospheric Extinction and Refraction, Asterism.org](https://asterism.org/resources/atmospheric-extinction-and-refraction/).
- [Star brightness and altitude?, Cloudy Nights](https://www.cloudynights.com/topic/359752-star-brightness-and-altitude/); [Minimum Altitude for Imaging, Cloudy Nights](https://www.cloudynights.com/topic/702611-minimum-altitude-for-imaging/).
- [Rise, Set, and Twilight Definitions, USNO](https://aa.usno.navy.mil/faq/RST_defs); [What is Astronomical Twilight?, AstroBackyard](https://astrobackyard.com/astronomical-twilight/).

**Moon avoidance**
- [Exposure Templates — NINA Target Scheduler docs (tcpalmer.github.io)](https://tcpalmer.github.io/nina-scheduler/target-management/exposure-templates.html) — Lorentzian formula, narrowband distance/width example.
- [nina.plugin.targetplanning README, GitHub](https://github.com/tcpalmer/nina.plugin.targetplanning/blob/main/README.md).
- [ACP Scheduler Constraints doc](http://solo.dc3.com/ar/RefDocs/HelpFiles/ACPScheduler81Help/Constraints.htm) — original BAIT-team Lorentzian formulation.
- [Moon Avoidance Lorentzian, Voyager Advanced forum](https://forum.starkeeper.it/t/moon-avoidance-lorentzian/3870).

**Bortle/SQM and filters**
- [Bortle Scale Guide, npfcalculator.com](https://www.npfcalculator.com/bortle-scale); [Find Your Night Sky Brightness on the Bortle Scale, AstroBackyard](https://astrobackyard.com/the-bortle-scale/).
- [Best Astrophotography Filters Explained: UHC vs Dual-Band vs Broadband, ORIVON](https://orivonspace.com/articles/guide-best-filters-explained.html).
- [Urban Narrowband Astrophotography with Dual-Band Filters, Optical Mechanics](https://www.opticalmechanics.com/urban-narrowband-astrophotography-with-dual-band-filters/); [Astrophotography in Light Pollution: Filters & Workflow](https://www.opticalmechanics.com/astrophotography-in-light-pollution-filters-workflow/); [Light Pollution and the Bortle Scale: A Practical Guide](https://www.opticalmechanics.com/light-pollution-and-the-bortle-scale-a-practical-guide/).

**Seeing / jet stream**
- [Seeing & Jetstream Forecast, ChileScope](http://www.chilescope.com/equipment-and-infrastructure/weather-conditions/seeing-jetstream-forecast).
- [Jet stream question: What altitude is most critical?, Cloudy Nights](https://www.cloudynights.com/forums/topic/850301-jet-stream-question-what-altitude-is-most-critical/).

**Planetary and lunar imaging**
- [What is a planet in opposition?, Royal Observatory Greenwich](https://www.rmg.co.uk/stories/space-astronomy/what-planet-opposition); [Mars opposition, BBC Sky at Night Magazine](https://www.skyatnightmagazine.com/advice/skills/mars-opposition); [Saturn at opposition – Oct 4, 2026, EarthSky](https://earthsky.org/astronomy-essentials/saturn-at-opposition-closest-brightest-best/).
- [An Introduction to Lucky Imaging for Astrophotography, Sky & Telescope](https://skyandtelescope.org/astronomy-blogs/imaging-foundations-richard-wright/lucky-imaging/).
- [ser-player README, cgarry/ser-player (GitHub)](https://github.com/cgarry/ser-player/blob/master/README.md); [SER — FreeAstro](https://free-astro.org/index.php/SER).
- [AutoStakkert! homepage](https://www.autostakkert.com/) — Windows-only, freeware.
- [PlanetarySystemStacker, GitHub — Rolf-Hempel](https://github.com/Rolf-Hempel/PlanetarySystemStacker); [PyPI listing](https://pypi.org/project/planetary-system-stacker) — GNU GPL, cross-platform including macOS.
- [Registax — Wikipedia](https://en.wikipedia.org/wiki/Registax).
- [LuckyStackWorker, Wilco Kasteleijn](https://www.wilcokas.com/luckystackworker) — MIT license (supplementary, not directly requested).

**Calibration and stacking software (Siril)**
- [Siril Calibration docs (stable)](https://siril.readthedocs.io/en/stable/preprocessing/calibration.html); [Siril Calibration docs (latest)](https://siril.readthedocs.io/en/latest/preprocessing/calibration.html).
- [Siril — Enough with dark flats](https://siril.org/2021/12/enough-with-dark-flats/).
- [Siril — Synthetic biases](https://siril.org/tutorials/synthetic-biases/); [Siril FAQ](https://siril.org/faq/).

**App context read (not cited above but informing this document's fit to the existing app)**
- `/Users/brianbusch/Developer/wt-gear/docs/ios/PLAN.md` §Verdict, §Architecture, §Data sources.
- `/Users/brianbusch/Developer/wt-gear/config/conditions-thresholds.json`.
- `/Users/brianbusch/Developer/wt-gear/docs/data-licensing.md`.
