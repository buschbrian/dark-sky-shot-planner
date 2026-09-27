# Full-frame cameras for astrophotography — research reference

Compiled for Dark Sky Shot Planner's gear presets. Covers Milky Way / nightscape /
star-trail use on full-frame (36×24 mm class) sensors only — no APS-C, medium
format, or dedicated cooled astro cameras (ZWO, QHY, etc.).

**Date checked:** 2026-09-27. All specs sourced from manufacturer spec pages where
available, cross-checked against DPReview's specifications database (which mirrors
manufacturer data in a consistent table format) and PetaPixel/press-release coverage
for the newest bodies. See `fullframe.json` for the machine-readable version with
per-camera source URLs. Every uncertain value is `null` in the JSON and called out in
the [Uncertain values](#uncertain-values-and-open-items) section below — nothing here
is guessed.

## Inclusion criteria (popularity)

A body qualifies for this list if it appears as a named recommendation in at least
one dated 2025–2026 astro-photography buying guide or gear-popularity source, or is
the direct current-model successor to a body that does. Sources used:

- [Capture the Atlas — Best Cameras for Milky Way Photography (2026)](https://capturetheatlas.com/best-camera-milky-way-photography/) — the single richest source; named Sony a7 IV, Nikon Z6 III, Canon R8, Sony a7S III, Canon R6 III, Nikon Z5 II, Sony a1 II, Nikon Z8, Canon R5 II, Sony a7 III.
- [PetaPixel — Best Astrophotography Cameras (updated Jan 2026)](https://petapixel.com/best-astrophotography-cameras/) — named Nikon Z6/Z6 II ("best overall for nightscape") and the Canon EOS 6D Mark I as a budget DSLR; also indexes the R6 II and R8.
- [DigitalCameraWorld — Best camera for astrophotography 2026](https://www.digitalcameraworld.com/buying-guides/best-camera-for-astrophotography) — corroborates the Sony a7 III/a7S III and Nikon Z6 III picks.
- [Skies & Scopes — Nikon Z6/Z6 II for astrophotography](https://skiesandscopes.com/nikon-z6-astrophotography/) — independent field comparison of the Z6 generations, source for the Z6 III dynamic-range trade-off note.
- [High Point Scientific — Top Astrophotography Cameras (2025/2026)](https://www.highpointscientific.com/astronomy-hub/post/astro-photography-guides/best-astrophotography-cameras-2025) — corroborates the D850 as a popular used full-frame DSLR pick (their main list favors dedicated cooled cameras, not reproduced here since those are out of scope).
- [PetaPixel — Canon discontinues the EOS Ra (2021)](https://petapixel.com/2021/09/03/canon-has-discontinued-the-astro-focused-eos-ra-mirrorless-camera/) and [Lonely Speck's Ra review](https://www.lonelyspeck.com/canon-eos-ra-astrophotography-review/) — basis for including the discontinued, astro-specific Ra as a flagged historical entry.
- Manufacturer announcement coverage for the newest body: [PetaPixel — Canon R6 Mark III, Nov 2025](https://petapixel.com/2025/11/05/the-canon-r6-iii-is-a-hybrid-powerhouse-with-32-5mp-sensor/).

Bodies not backed by a dated 2025–2026 astro-specific source were excluded even
where they are popular for other genres — for example, Leica SL3/M11 did not appear
in any astro-specific buying guide checked, so they are left out rather than
included on general reputation.

## Comparison table

| Camera | Launch | Sensor (mm) | Resolution | Pixel pitch (µm) | Native ISO | Max shutter | IBIS | Status |
|---|---|---|---|---|---|---|---|---|
| Sony a7 IV | 2021 | 35.6 × 23.9 | 7008×4672 (33 MP) | 5.08 | 100–51,200 | 1/8000s | 5.5 EV | Current |
| Sony a7 III | 2018 | 35.8 × 23.8 | 6000×4000 (24.2 MP) | 5.97 | 100–51,200 | 1/8000s | 5.0 EV | Discontinued |
| Sony a7S III | 2020 | 35.6 × 23.8 | 4240×2832 (12.1 MP) | 8.40 | 80–102,400 | 1/8000s | 5.5 EV | Current |
| Sony a7R V | 2022 | 35.7 × 23.8 | 9504×6336 (60.2 MP) | 3.76 | 100–32,000 | 1/8000s | 8.0 EV | Current |
| Sony a7C II | 2023 | 35.6 × 23.9 | 7008×4672 (33 MP) | 5.08 | 100–51,200 | 1/8000s | IBIS present (rating unconfirmed) | Current |
| Sony a1 II | 2024 | 35.9 × 24.0 | 8640×5760 (50.1 MP) | 4.15 | 100–32,000 | 1/32000s (e) | 8.5 EV | Current |
| Nikon Z6 III | 2024 | 35.9 × 23.9 | 6048×4032 (24.5 MP) | 5.94 | 100–64,000 | 1/16000s (e) | 8.0 EV | Current |
| Nikon Z6 II | 2020 | 35.9 × 23.9 | 6048×4024 (24.3 MP) | 5.94 | 100–51,200 | 1/8000s | 5.0 EV | Discontinued |
| Nikon Z8 | 2023 | 35.9 × 23.9 | 8256×5504 (45.7 MP) | 4.35 | 64–25,600 | 1/32000s (e) | 6.0 EV | Current |
| Nikon Z f | 2023 | 35.9 × 23.9 | 6048×4032 (24.5 MP) | 5.94 | 100–64,000 | 1/8000s | 8.0 EV | Current |
| Nikon Z5 II | 2025 | 35.9 × 23.9 | 6048×4032 (24 MP) | 5.94 | 100–64,000 | 1/8000s | 7.5 EV | Current |
| Nikon D850 | 2017 | 35.9 × 23.9 | 8256×5504 (45.7 MP) | 4.35 | 64–25,600 | 1/8000s | None (DSLR) | Discontinued |
| Nikon D750 | 2014 | 35.9 × 24.0 | 6016×4016 (24.3 MP) | 5.97 | 100–12,800 | 1/4000s | None (DSLR) | Discontinued |
| Canon EOS R6 Mark II | 2022 | 36.0 × 24.0 | 6000×4000 (24.2 MP) | 6.00 | 100–102,400 | 1/8000s | 8.0 EV | Current |
| Canon EOS R6 Mark III | 2025 | 35.9 × 23.9 | 6960×4640 (32.5 MP) | 5.16 | 100–64,000 | 1/8000s | IBIS present (rating unconfirmed) | Current |
| Canon EOS R8 | 2023 | 36.0 × 24.0 | 6000×4000 (24.2 MP) | 6.00 | 100–102,400 | 1/4000s | None | Current |
| Canon EOS R5 Mark II | 2024 | 36.0 × 24.0 | 8192×5464 (45 MP) | 4.39 | 100–51,200 | 1/8000s | 8.5 EV | Current |
| Canon EOS R | 2018 | 36.0 × 24.0 | 6720×4480 (30.3 MP) | 5.36 | 100–40,000 | 1/8000s | None | Discontinued |
| Canon EOS Ra | 2019 | 36.0 × 24.0 | 6720×4480 (30.3 MP) | 5.36 | 100–40,000 | 1/8000s | None | **Discontinued — astro-specific** |
| Panasonic Lumix S5 II (and S5 IIX) | 2023 | 35.6 × 23.8 | 6000×4000 (24.2 MP) | 5.93 | 100–51,200 | 1/8000s (unconfirmed) | 5.0 EV | Current |

*(e) = electronic shutter maximum; mechanical shutter maxes are typically 1/8000s and
are what governs long-exposure astro work either way, since astro shutter speeds run
in the opposite direction (seconds to minutes, not fractions of a second).*

## Notes per camera

### Sony

- **a7 IV** — The current default recommendation across most 2026 guides
  (Capture the Atlas: "best overall value"). 33 MP BSI sensor, native Bulb Timer
  (set an exposure length in the menu, no external remote needed) and built-in
  interval shooting. Star-eater raw spatial filtering — Sony's noise-reduction
  algorithm that historically softened or removed faint stars in long exposures —
  was substantially reduced starting with the Mark III generation of Sony bodies;
  no fresh regression has been reported for the a7 IV in the sources checked, but
  Sony has not published a formal statement confirming it is fully gone, so treat
  it as "improved, not manufacturer-confirmed."
- **a7 III** — Still the "best quality-price" pick per Capture the Atlas and widely
  used secondhand. This is the specific body most credited (PetaPixel, 2018) with
  Sony visibly fixing the worst of the star-eater filtering versus the Mark II
  generation, via a 2018 firmware/processing change. Built-in interval shooting
  was *not* present at launch — it arrived in the v3.0 firmware update in 2019.
- **a7S III** — 12.1 MP, ~8.4 µm pixel pitch (large by full-frame standards),
  optimized for high-ISO cleanliness over resolution — the classic "hybrid
  shooter's astro camera" pick. Documented dual-gain switch near ISO 2000 in
  standard picture profiles per DPReview measurement (video S-Log profiles switch
  at different, profile-dependent points — Sony does not publish a single
  still-photo dual-gain ISO figure).
- **a7R V** — Capture the Atlas's "best high-resolution nightscape camera." 60 MP
  means a materially shorter NPF-rule exposure ceiling than the 24 MP bodies at
  the same focal length (see Guidance below). Cloudy Nights and other astro-forum
  measurement (2023–2024 era) reports Sony made "huge changes" to raw-data
  filtering on this body, suggesting star eater is largely resolved here — this
  is community measurement, not a Sony claim.
- **a7C II** — Compact-bodied sibling sharing the a7 IV's 33 MP sensor; same core
  astro capability in a smaller grip/battery package.
- **a1 II** — Flagship speed/AF body; astro-capable but not astro-optimized.
  Capture the Atlas calls it an "unbeatable all-rounder" while noting it's more
  camera than most astro-only buyers need at the price.

### Nikon

- **Z6 III** — PetaPixel and Capture the Atlas both cite this generation.
  Partially-stacked sensor (extra readout circuitry, not the full stack of the
  Z8/Z9) enables "Starlight View" (a boosted live-view gain for framing in the
  dark) and autofocus down to -10 EV. Trade-off: independent review analysis
  found base-ISO dynamic range about 0.82 EV lower than the Z6 II (10.44 EV vs
  11.26 EV), which matters most for shadow-heavy foregrounds in blended
  nightscapes; the gap narrows by about ISO 800. Nikon's older star-eater
  noise-reduction filtering is reported eliminated on this generation.
- **Z6 II** — PetaPixel's "best overall for nightscape" pick specifically because
  it avoids the Z6 III's dynamic-range trade-off while keeping the same
  ISO-invariant, low-read-noise sensor family, with Bulb mode fixing the original
  Z6's 30-second shutter ceiling.
- **Z8** — 45.7 MP stacked sensor (shared with the Z9) in a smaller body. Built-in
  intervalometer confirmed usable together with extended (long) shutter speeds.
  Extended-ISO ceiling is not published in the sources checked — recorded as
  `null` in the JSON rather than guessed.
- **Z f** — Retro-styled body on the same 24.5 MP sensor generation as the Z6 III;
  included as a genuinely popular current option, not just for its looks.
- **Z5 II** — Capture the Atlas's "best budget full-frame" pick; inherits
  Starlight View despite the lower price tier.
- **D850 / D750 (used DSLRs)** — Both remain popular secondhand recommendations
  (High Point Scientific, Capture the Atlas) for photographers entering
  astrophotography on a budget. The D750 in particular is frequently cited for
  strong ISO-invariant behavior, letting shooters expose at low ISO and push in
  post with little quality penalty versus raising ISO in-camera. Neither has
  IBIS — both are optical SLRs relying on in-lens stabilization only, which is
  irrelevant for tripod astro work anyway.

### Canon

- **EOS R6 Mark II** — Named across most current guides. 24.2 MP, large 6.0 µm
  pixel pitch. Canon's built-in interval-timer shooting is capped at normal
  (sub-30-second) shutter speeds and cannot combine with Bulb mode for a repeating
  long-exposure sequence — a separate Bulb Timer allows one long single exposure,
  but multi-frame star-trail/time-lapse sequences beyond 30s/frame need an
  external or app-based intervalometer (Canon community documentation, current as
  of this check).
- **EOS R6 Mark III** — Announced 2025-11-05, so real-world astro field testing is
  thin as of 2026-09-27. New 32.5 MP sensor, native ISO ceiling deliberately
  lowered to 64,000 from the R6 II's 102,400 in exchange for the resolution
  increase, per Canon's own press materials. Extended-ISO figures vary slightly
  between outlets reviewed (recorded as 50–102,800, flagged for confirmation
  against Canon's own spec page); exact IBIS CIPA rating also unconfirmed.
  Included because current 2026 buying guides already point toward it as the R6
  line's new default, not because of an established astro track record yet.
- **EOS R8** — The most frequently cited "budget full-frame" pick alongside the
  Z5 II. No IBIS (real trade-off for handheld work, irrelevant on a tripod).
- **EOS R5 Mark II** — High-resolution flagship, named by Capture the Atlas among
  premium picks that "excel across multiple genres" rather than being an
  astro specialist.
- **EOS R / EOS Ra** — The original EOS R is included primarily as the direct
  donor body for the **EOS Ra**, Canon's dedicated astrophotography camera:
  announced November 2019, **discontinued by Canon in September 2021**
  (flagged per task instructions). The Ra's only hardware differences from the
  plain EOS R are a modified IR-cut filter passing roughly 4× more 656 nm
  (hydrogen-alpha) transmission — useful for emission-nebula reds — and EVF/LCD
  live-view magnification up to 30× for precise manual star focus. No Canon
  successor to the Ra has been announced as of this check.

### Panasonic

- **Lumix S5 II (and S5 IIX)** — 24.2 MP sensor with Panasonic-documented **Dual
  Native ISO** — two distinct hardware gain stages, stated directly in Panasonic's
  own marketing/spec language rather than inferred only from third-party noise
  curves, which is a meaningfully stronger claim than most competitors'
  dual-gain behavior (usually only visible in independent read-noise
  measurement). On-sensor phase-detect AF aids focusing in low light. The S5 IIX
  variant is stills-identical to the S5 II — its differences (ProRes/All-I video
  recording, SSD output, IP streaming) are video-workflow features only, so it is
  not listed as a separate camera entry. IBIS confirmed at 5 stops CIPA for the
  body alone (up to 6.5 stops combined with a stabilized L-Mount lens via Dual
  IS). Exact bulb/intervalometer menu behavior was not independently confirmed
  from a primary Panasonic spec page in this pass.

## Guidance: what actually matters for astro

**Sensor size** sets the physical light-collecting area for a given angle of view.
A full-frame (36×24 mm) sensor gathers roughly 2.3× the light of an APS-C sensor at
the same f-number and shutter speed, which is the core reason full-frame remains the
default recommendation for serious Milky Way/nightscape work even though APS-C
bodies (not covered here) are lighter and cheaper.

**Read noise and dual conversion gain** matter more than headline ISO numbers.
Every sensor has a noise floor set by its electronics, not just shot noise from the
scene; this is "read noise," and it sets the practical limit on how much you can
recover from a dark, underexposed frame. Many modern sensors (all bodies in this
list from roughly 2018 onward, per manufacturer and independent measurement) use
**dual conversion gain**: a second, lower-noise readout circuit that kicks in past a
certain ISO, roughly halving read noise in electron terms above that threshold. For
detailed, per-camera read-noise-versus-ISO curves and where each dual-gain switch
point falls, [photonstophotos.net](https://www.photonstophotos.net/Charts/RN_e.htm)
publishes DxOMark-derived and directly-measured charts across most bodies in this
list; it is the single best public source for this and is worth consulting per-body
before recommending exposure settings inside the app.

**Pixel size versus the NPF rule.** Smaller pixels (higher-resolution sensors at a
given sensor size) sample the sky more finely, which means star trailing becomes
visible at a *shorter* shutter speed than the traditional "500 rule" suggests. The
[NPF rule](https://petapixel.com/2017/04/07/npf-rule-formula-sharp-star-photos-every-time/)
— `(35 × aperture + 30 × pixel pitch) / focal length = max shutter speed in seconds`
— accounts for this directly via pixel pitch, which is why this dataset carries
pixel pitch (computed, where not manufacturer-stated, as sensor width in mm ÷ image
width in pixels × 1000) for every body: a 60 MP a7R V (3.76 µm pitch) needs a
meaningfully shorter exposure than a 24 MP a7 III (5.97 µm pitch) at the same lens
and framing to avoid trailed stars.

**ISO invariance** describes how closely a sensor's noise behavior at a low ISO,
pushed up in post-processing, matches its noise behavior at a high in-camera ISO for
the same net brightness. On a strongly ISO-invariant sensor (Sony and
Nikon/Sony-sensor bodies are frequently cited as more invariant than older Canon
sensors, per multiple independent write-ups), shooting at a lower ISO to protect
highlights and pushing exposure in post costs little to nothing in shadow noise
versus raising ISO in-camera — useful for astro because it decouples "protect the
sky's dynamic range" from "make the preview image usable in the field." This is a
generalization with real per-body variation; it is not something to assert as fact
for a specific camera without checking that camera's own noise curve.

**Long-exposure noise reduction (LENR) / dark-frame subtraction** is a standard,
user-toggleable menu setting across all bodies in this list. It shoots a second,
shutter-closed "dark frame" after the real exposure and subtracts it in-camera to
remove hot pixels and fixed-pattern noise — at the direct cost of doubling capture
time (Nikon and most bodies) or, on some Canon models, allowing the camera to remain
partially usable during the dark-frame capture. Most dedicated astrophotographers
turn LENR off and either stack multiple light frames or shoot their own manual dark
frames in post, to avoid losing the faintest stars to the subtraction and to avoid
losing half their shooting time on a cold night.

**"Star eater" and Nikon's lossy-raw artifacts** are the two most-cited
brand-specific astro quirks and are documented per-body in the notes above and the
JSON's `astro_notes` field:

- *Sony star eater*: a spatial noise-reduction filter applied during raw
  processing on exposures at or above a few seconds (historically most aggressive
  in Bulb mode), which can erode or remove faint stars and shift star colors
  toward green. First widely documented by [Lonely Speck](https://www.lonelyspeck.com/sony-star-eater-and-how-to-fix-it/)
  and [PetaPixel](https://petapixel.com/2017/05/04/star-eater-issue-no-longer-recommend-sony-cameras-astrophotography/)
  in 2016–2017 on the a7-series Mark II generation; substantially reduced from the
  Mark III generation (a7 III/a7R III) onward per the same sources, with further
  community-measured improvement reported on the a7R V. No Sony body should be
  assumed star-eater-free without a specific, dated test of that body.
- *Nikon lossy raw / hardcoded corrections*: Nikon's lossy raw compression and a
  separate hardcoded image correction (likely a color-shading correction) can
  introduce faint concentric-ring artifacts that become visible when many
  exposures are stacked, as documented in detail by
  [markshelley.co.uk](https://www.markshelley.co.uk/Astronomy/NikonConcentricRings/nikon_lossy_compression.html).
  Nikon's own star-eater-equivalent raw spatial filtering affected the Z6/Z7
  generation and is reported eliminated by the Z6 III generation per Skies &
  Scopes' direct field comparison.

## Uncertain values and open items

Per the task's "never guess" rule, the following are recorded as `null` (or flagged
in prose) in `fullframe.json` rather than estimated:

- **Canon EOS R6 Mark III** — exact IBIS CIPA stop rating not confirmed from a
  primary Canon spec page (the official Canon UK/US/CNA spec pages returned
  HTTP 403 to automated fetches during this research pass); extended-ISO ceiling
  figure (50–102,800) sourced from a single spec-sheet aggregator and should be
  re-verified against Canon's own page before being treated as authoritative.
- **Sony a7C II** — IBIS is present (Sony markets 5-axis stabilization on this
  body) but the exact CIPA stop rating was not independently confirmed in this
  pass.
- **Panasonic Lumix S5 II** — exact built-in intervalometer and Bulb-mode menu
  behavior (max single exposure length, whether Bulb combines with interval
  shooting) was not confirmed from a primary Panasonic spec or manual page;
  Panasonic's own product page did not return usable content to the fetch tool
  used in this pass (404).
- **Nikon Z8** — extended ISO range (beyond the 64–25,600 native range) is not
  published in the sources checked.
- **Dual-gain ISO switch points** are, in most cases, independent measurements
  (DPReview, photonstophotos.net-style analysis) rather than manufacturer-stated
  values, and are noted as such per camera. Panasonic is the one brand in this
  list that states Dual Native ISO directly in its own marketing copy.
- **Star-eater status for Sony bodies newer than the a7R V** (a7 IV, a1 II, a7C
  II) is inferred from the general trend reported for the Mark III+ generation
  rather than a dated, body-specific astro test for each one; this is flagged in
  each camera's `astro_notes` rather than stated as confirmed fact.

## Sources

Popularity / buying-guide sources: [Capture the Atlas](https://capturetheatlas.com/best-camera-milky-way-photography/), [PetaPixel best-astrophotography-cameras](https://petapixel.com/best-astrophotography-cameras/), [DigitalCameraWorld](https://www.digitalcameraworld.com/buying-guides/best-camera-for-astrophotography), [Skies & Scopes (Nikon Z6 comparison)](https://skiesandscopes.com/nikon-z6-astrophotography/), [High Point Scientific](https://www.highpointscientific.com/astronomy-hub/post/astro-photography-guides/best-astrophotography-cameras-2025).

Spec sources: DPReview specifications database (per-camera URLs in `fullframe.json`); [Canon R6 III announcement, PetaPixel](https://petapixel.com/2025/11/05/the-canon-r6-iii-is-a-hybrid-powerhouse-with-32-5mp-sensor/); manufacturer spec-sheet aggregation for the R6 III sensor dimensions and ISO figures where Canon's own pages were unreachable.

Astro-issue sources: [Lonely Speck — Star Eater](https://www.lonelyspeck.com/sony-star-eater-and-how-to-fix-it/); [PetaPixel — Star Eater issue](https://petapixel.com/2017/05/04/star-eater-issue-no-longer-recommend-sony-cameras-astrophotography/); [markshelley.co.uk — Nikon lossy compression & hardcoded correction](https://www.markshelley.co.uk/Astronomy/NikonConcentricRings/nikon_lossy_compression.html); [PetaPixel — EOS Ra discontinued](https://petapixel.com/2021/09/03/canon-has-discontinued-the-astro-focused-eos-ra-mirrorless-camera/); [Lonely Speck — EOS Ra review](https://www.lonelyspeck.com/canon-eos-ra-astrophotography-review/).

Guidance sources: [photonstophotos.net read-noise charts](https://www.photonstophotos.net/Charts/RN_e.htm); [PetaPixel — NPF rule](https://petapixel.com/2017/04/07/npf-rule-formula-sharp-star-photos-every-time/); [DIYPhotography — ISO invariance](https://www.diyphotography.net/what-is-iso-invariance-and-why-is-it-such-a-big-deal/); [Lonely Speck — best ISO for astrophotography](https://www.lonelyspeck.com/how-to-find-the-best-iso-for-astrophotography-dynamic-range-and-noise/).
