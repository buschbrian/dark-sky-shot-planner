# APS-C (and MFT) cameras for astrophotography — research reference

Date checked: **2026-09-27**. Companion machine-readable file: `apsc.json`.

This file backs the Dark Sky Shot Planner's gear presets
(`ios/Packages/SkyCore/Sources/SkyCore/Gear.swift`, `CameraProfile`). The
app only persists `sensorWidthMM`, `sensorHeightMM`, `resolution`
(width/height px) and an optional stated `pixelPitchUM` — it derives crop
factor, sensor diagonal, and circle-of-confusion itself. Everything else in
this report (ISO range, shutter/bulb, IBIS, astro notes, popularity) is
reference context for building presets and copy, not fields SkyCore reads
directly.

## Inclusion criteria

- **Bodies**: current (2024–2026) APS-C mirrorless lines from Fujifilm,
  Sony, Canon, and Nikon, plus a small number of still-common
  discontinued/used bodies explicitly called out in the brief (Sony a6100,
  Canon 90D, Nikon D7500, Fujifilm X-T30 II) because they remain widely
  owned or recommended in used-gear astro guides. Two Micro Four Thirds
  bodies are included and flagged `"format": "mft"` because they are
  repeatedly named alongside APS-C bodies in 2025–2026 astro buying guides
  for their in-body astro-specific features (OM System Starry Sky AF,
  Panasonic G9 II stabilization).
- **Popularity**: a body qualifies as "popular for astro" if it appears in
  at least one dated 2025–2026 source from the brief's suggested list
  (Capture the Atlas, PhotoPills, Lonely Speck, AstroBackyard, PetaPixel,
  DPReview, Digital Camera World, Live Science, or a retailer best-seller
  signal), OR is explicitly named in the research brief itself as a
  common used astro DSLR. Each entry's `popularity_evidence` field states
  which kind of evidence applies — a body named in an astro-specific
  buying guide is stronger evidence than one appearing only in a general
  APS-C roundup; that distinction is called out per-camera below and in
  the JSON.
- **Specs**: taken from manufacturer spec pages (Fujifilm, Sony, Canon,
  Nikon, OM System, Panasonic) where fetchable, cross-checked against
  DPReview, Neocamera, or Wikipedia aggregation where the manufacturer
  page was not directly fetchable in this session. Every `source_url` in
  `apsc.json` points to the specific page used for that entry's core specs.

## Comparison table

| Camera | Format | Sensor (mm) | Resolution | Pixel pitch (µm) | Crop factor | ISO range | Max shutter | IBIS | Launch | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| Fujifilm X-T5 | APS-C | 23.5 × 15.6 | 40.2MP (7728×5152) | 3.04 | 1.53× | 125–12800 (64–51200 ext.) | 1/180000s (e) | Yes (7.0 stop) | 2022 | Current |
| Fujifilm X-H2 | APS-C | 23.5 × 15.6 | 40.2MP (7728×5152) | 3.04 | 1.53× | 125–12800 (64–51200 ext.) | 1/180000s (e) | Yes (7.0 stop) | 2022 | Current |
| Fujifilm X-T50 | APS-C | 23.5 × 15.6 | 40.2MP (7728×5152) | 3.04 | 1.53× | 125–12800 (64–51200 ext.) | 1/180000s (e) | Yes (7.0 stop) | 2024 | Current |
| Fujifilm X-S20 | APS-C | 23.5 × 15.6 | 26.1MP (6240×4160) | 3.77 | 1.53× | 160–12800 (80–51200 ext.) | 1/32000s (e) | Yes (7.0 stop) | 2023 | Current |
| Fujifilm X-T30 III | APS-C | 23.5 × 15.6 | 26.1MP (6240×4160) | 3.77 | 1.53× | 160–12800 (80–51200 ext.) | null (uncertain) | No | 2025 | Current |
| Fujifilm X-T30 II | APS-C | 23.5 × 15.6 | 26.1MP (6240×4160) | 3.77 | 1.53× | 160–12800 (80–51200 ext.) | 1/32000s (e) | No | 2021 | Discontinued |
| Fujifilm X-M5 | APS-C | 23.5 × 15.6 | 26.1MP (6240×4160) | 3.77 | 1.53× | 160–12800 (80–51200 ext.) | null (uncertain) | No | 2024 | Current |
| Sony a6700 | APS-C | 23.5 × 15.6 | 26MP (6192×4128) | 3.80 | 1.53× | 100–32000 (50–102400 ext.) | 1/8000s (e) | Yes (5.0 stop) | 2023 | Current |
| Sony a6400 | APS-C | 23.5 × 15.6 | 24.2MP (6000×4000) | 3.92 | 1.53× | 100–32000 (to 102400 ext.) | 1/4000s (mech only) | No | 2019 | Current |
| Sony a6100 | APS-C | 23.5 × 15.6 | 24.2MP (6000×4000) | 3.92 | 1.53× | 100–32000 (to 51200 ext.) | 1/4000s (mech only) | No | 2019 | Discontinued |
| Sony ZV-E10 II | APS-C | 23.5 × 15.6 | 26MP (6192×4128) | 3.80 | 1.53× | 100–32000 (50–102400 ext.) | 1/8000s (e, no mech.) | No | 2024 | Current |
| Canon EOS R7 | APS-C | 22.3 × 14.9 | 32.5MP (6960×4640) | 3.20 | 1.61× | 100–32000 (to 51200 ext.) | 1/16000s (e) | Yes (7 stop) | 2022 | Current |
| Canon EOS R10 | APS-C | 22.3 × 14.9 | 24.2MP (6000×4000) | 3.72 | 1.61× | 100–32000 (to 51200 ext.) | 1/16000s (e) | No | 2022 | Current |
| Canon EOS R50 | APS-C | 22.3 × 14.9 | 24.2MP (6000×4000) | 3.72 | 1.61× | 100–32000 (to 51200 ext.) | null (uncertain) | No | 2023 | Current |
| Canon EOS 90D | APS-C | 22.3 × 14.9 | 32.5MP (6960×4640) | 3.20 | 1.61× | 100–25600 (to 51200 ext.) | 1/16000s (e, Live View) | No | 2019 | Discontinued |
| Nikon Z50II | APS-C | 23.5 × 15.7 | 20.9MP (5568×3712) | 4.22 | 1.53× | 100–51200 (to 204800 ext.) | 1/4000s | No | 2024 | Current |
| Nikon Z fc | APS-C | 23.5 × 15.7 | 20.9MP (5568×3712) | 4.22 | 1.53× | 100–51200 (to 204800 ext.) | 1/4000s | No | 2021 | Current |
| Nikon Z30 | APS-C | 23.5 × 15.7 | 20.9MP (5568×3712) | 4.22 | 1.53× | 100–51200 (to 204800 ext.) | 1/4000s (mech) | No | 2022 | Current |
| Nikon D7500 | APS-C | 23.5 × 15.7 | 20.9MP (5568×3712) | 4.2 | 1.53× | 100–51200 (to 1640000 boost) | 1/8000s | No | 2017 | Discontinued |
| OM System OM-1 Mark II | **MFT** | 17.3 × 13.0 | 20.4MP (5184×3888) | 3.34 | 2.00× | ~80–102400 | 1/8000s | Yes (8.5 stop) | 2024 | Current |
| Panasonic Lumix G9 II | **MFT** | 17.3 × 13.0 | 25.2MP (5776×4336) | 3.00 | 2.00× | 100–25600 | 1/32000s (e) | Yes (8.0 stop CIPA) | 2023 | Current |

All pixel-pitch values are **computed** as sensor width ÷ image width × 1000
(the same formula SkyCore uses), except the D7500 and 90D, whose
manufacturer/aggregator-stated pitches matched the computed value and are
noted as such per-entry in `apsc.json`'s `value_basis` field.

## Notes per camera

**Fujifilm X-T5 / X-H2 / X-T50** share the same 40.2MP X-Trans CMOS 5 HR
sensor (23.5 × 15.6mm). All three have 5-axis IBIS rated to 7.0 stops and a
built-in intervalometer. No confirmed "star eater" long-exposure noise
filtering was found in sources checked for the X-Trans 5 sensor generation.
The X-H2 additionally offers a 160MP Pixel Shift Multi-Shot mode, which is
a tripod-only composite feature, not relevant to single-frame Milky Way or
star-trail exposures.

**Fujifilm X-S20 / X-T30 III / X-T30 II / X-M5** use the older, larger-pixel
26.1MP X-Trans CMOS 4 sensor (pixel pitch 3.77µm vs. 3.04µm on the 40MP
bodies), which some astro shooters prefer for marginally better per-pixel
high-ISO noise. The X-T30 III (announced 2025-10-23) is the current
replacement for the X-T30 II in Fujifilm's lineup; exact shutter-speed
range and intervalometer presence for the X-T30 III were not confirmed
from the sources fetched in this session (see Uncertain values). The X-M5
has no IBIS.

**Sony a6700** is Sony's current flagship APS-C body, with 5-axis IBIS
(5.0-stop rating) and the newest BIONZ XR processor. Sony's historical
"star eater" long-exposure noise-reduction issue — well documented by
Lonely Speck and DPReview for pre-2018 sensors — was substantially reduced
starting with the a7 III generation; no strong, dated 2025–2026 report of
a persistent star-eater problem specific to the a6700 was found, though
some forum discussion of minor star softening at very long exposures
persists and is flagged as unverified community signal, not a sourced fact.

**Sony a6400 / a6100** share a 24.2MP sensor with no IBIS. The a6100 was
formally discontinued by Sony effective December 23, 2021 (PetaPixel) but
remains a common budget/used recommendation. The a6400 has continued in
production. Both are older-generation Sony sensors where some
astrophotography community discussion of long-exposure noise-reduction
filtering exists; mitigated in practice by keeping single sub-exposures
under roughly 3–4 seconds if stacking.

**Sony ZV-E10 II** is vlogging-first: electronic shutter only (no
mechanical shutter), no IBIS. Usable on a tripod for nightscapes but not
astro-optimized.

**Canon EOS R7** is Canon's flagship APS-C mirrorless body: 32.5MP sensor,
5-axis IBIS to 7 stops, built-in intervalometer and bulb timer. Canon's
APS-C sensor (22.3 × 14.9mm) is smaller than the Sony/Fujifilm/Nikon
23.5 × 15.6mm standard, giving it a ~1.61× crop factor rather than ~1.53×.

**Canon EOS R10 / R50** share Canon's 24.2MP APS-C sensor generation,
neither has IBIS. The R50 is reported by Digital Camera World (2026) as
the best-selling mirrorless camera in Japan in 2026, making it a very
common entry point even though it is not astro-specialist gear; exact
shutter/intervalometer specs for the R50 were not confirmed from sources
fetched in this session.

**Canon EOS 90D** is a DSLR (optical viewfinder, no IBIS, EF/EF-S mount),
discontinued as Canon has shifted its APS-C lineup to RF mount, but
explicitly named in the research brief and still commonly recommended in
used-DSLR astro buying guides (e.g. Starlight Optics) for its 32.5MP
sensor and mature lens ecosystem.

**Nikon Z50II / Z fc / Z30 / D7500** all share the same 20.9MP DX-format
sensor generation (23.5 × 15.7mm), giving the largest pixel pitch
(4.2–4.22µm) of any APS-C body in this survey — generally favorable for
high-ISO noise. None has IBIS; Z-mount bodies rely on lens VR where
available. The Z30 has no electronic viewfinder, which makes manual
star-focusing in the field harder than on EVF-equipped bodies. The D7500
is a DSLR, discontinued, but still commonly recommended as a budget/used
astro body (Space.com, general astro guides).

**OM System OM-1 Mark II** (MFT, flagged) has a dedicated **Starry Sky AF**
mode for automatic pinpoint focus on stars, plus in-camera **Live
Composite** and **Live Bulb** modes purpose-built for star trails and
nightscapes without external intervalometer gear. Its 8.5-stop IBIS is the
strongest in this survey. Reviewed by Live Science (2026) as possibly the
best Micro Four Thirds camera made.

**Panasonic Lumix G9 II** (MFT, flagged) has a dual native ISO sensor and
up to 8.0-stop CIPA-rated IBIS (7.5 stops with Dual IS 2, combining body
and lens stabilization). No dedicated "Starry Sky AF"-equivalent feature
was confirmed for this specific model from sources checked; flagged as
uncertain in the JSON rather than assumed from Panasonic's general
"Starlight AF" marketing on other models.

## Guidance: APS-C vs. full frame for astro

In plain language: a full-frame sensor (36 × 24mm) gathers roughly twice
the light-collecting area of an APS-C sensor (roughly 23.5 × 15.6mm, or
22.3 × 14.9mm for Canon), which generally means cleaner files at the very
high ISOs (3200–12800+) that untracked Milky Way and nightscape shots
need. Capture the Atlas's 2026 guide states plainly that "full-frame is
still the safest choice in 2026 for cleaner high-ISO files, better dynamic
range, and easier wide-angle coverage." But APS-C remains a fully viable,
lighter, and cheaper option — PhotoPills' 2026 guide and multiple
2025–2026 buying guides note that APS-C bodies like the Fujifilm X-T5 can
still produce strong astro results paired with a fast wide lens, and that
camera choice matters less than lens speed and technique.

**Crop factor and the 500 rule.** The 500 rule estimates the longest
exposure (in seconds) before stars visibly trail, as
`500 ÷ (focal length × crop factor)`. A wider APS-C crop factor shortens
the usable exposure time for the same focal length compared to full frame:
a 24mm lens on a full-frame body allows roughly `500 ÷ 24 ≈ 20.8s`, while
the same 24mm lens on a 1.53× APS-C body (most Fujifilm/Sony/Nikon bodies
in this survey) allows only `500 ÷ (24 × 1.53) ≈ 13.6s`, and on a 1.61×
Canon APS-C body about `500 ÷ (24 × 1.61) ≈ 12.9s`. On a 2.0× MFT body the
same lens allows only `500 ÷ (24 × 2.0) ≈ 10.4s`. In practice this means
APS-C and MFT shooters need either a wider lens or a shorter per-frame
exposure (compensated by higher ISO or more stacked frames) to avoid
trailing stars, compared to full frame at the same focal length.

**NPF rule and pixel pitch.** The NPF rule (developed by Frédéric Michaud,
Société Astronomique du Havre) is a more accurate, pixel-pitch-aware
alternative to the 500 rule: it factors in aperture and the sensor's pixel
pitch (photosite size) alongside focal length and declination, since a
denser sensor (smaller pixel pitch) shows trailing sooner than a sparser
one at the same focal length and exposure. Within this survey, the
40.2MP Fujifilm bodies (3.04µm pitch) are more trailing-sensitive under
the NPF rule than the 20.9MP Nikon DX bodies (4.22µm pitch) at the same
focal length and crop factor, even though both share roughly the same
1.53× crop factor — a distinction the 500 rule alone does not capture.
This is exactly the computation SkyCore's `CameraProfile.pixelPitchUM` and
NPF-rule logic are built to use.

## Sources

- Fujifilm X-T5 specifications — <https://www.fujifilm-x.com/en-us/products/cameras/x-t5/specifications/>
- Fujifilm X-H2 specifications — <https://www.fujifilm-x.com/en-us/products/cameras/x-h2/specifications/>
- Fujifilm X-T50 announcement (Amateur Photographer) — <https://amateurphotographer.com/latest/photo-news/fujifilm-announce-the-new-40mp-x-t50-with-ibis/>
- Fujifilm X-S20 specifications — <https://www.fujifilm-x.com/global/products/cameras/x-s20/specifications/>
- Fujifilm X-T30 III launch (Fujifilm USA) — <https://www.fujifilm-x.com/en-us/news/introducing-fujifilm-x-t30-iii/>
- Fujifilm X-T30 II specifications (DPReview) — <https://www.dpreview.com/products/fujifilm/slrs/fujifilm_xt30ii/>
- Fujifilm X-M5 product page — <https://www.fujifilm-x.com/en-us/products/cameras/x-m5/>
- Fujifilm X-M5 review (PetaPixel, 2024-11-28) — <https://petapixel.com/2024/11/28/fujifilm-x-m5-review-agonizingly-close-to-entry-level-excellence/>
- Sony a6700 specifications (DPReview) — <https://www.dpreview.com/products/sony/slrs/sony_a6700/specifications>
- Sony a6400 specifications (Neocamera) — <https://www.neocamera.com/camera/sony/a6400>
- Sony a6100 discontinuation (PetaPixel, 2021-12-23) — <https://petapixel.com/2021/12/23/sony-suspends-a7c-and-a6600-permanently-ends-a7-ii-and-a6100/>
- Sony ZV-E10 II review (DPReview) — <https://www.dpreview.com/reviews/8510905811/sony-zv-e10-ii-vlogging-camera-review/>
- Canon EOS R7 specifications (Canon Europe) — <https://www.canon-europe.com/cameras/eos-r7/specifications/>
- Canon EOS R10 specifications (Canon Europe) — <https://www.canon-europe.com/cameras/eos-r10/specifications/>
- Canon EOS R50 specifications (Canon UK) — <https://www.canon.co.uk/cameras/eos-r50/specifications/>
- Canon EOS 90D specifications (Canon Europe) — <https://www.canon-europe.com/cameras/eos-90d/specifications/>
- Canon EOS 90D for astrophotography (Starlight Optics) — <https://starlightoptics.com/canon-eos-90d-dlsr-camera-for-astrophotography/>
- Nikon Z50II product page — <https://www.nikonusa.com/p/z50ii/1784/overview>
- Nikon Z fc product page — <https://www.nikonusa.com/p/z-fc/1671/overview>
- Nikon Z30 product page — <https://www.nikonusa.com/p/z-30/1737/overview>
- Nikon D7500 product page — <https://www.nikonusa.com/p/d7500/1581/overview>
- Nikon D7500 astro review (Space.com) — <https://www.space.com/nikon-d7500-camera-review>
- OM System OM-1 Mark II specifications — <https://explore.omsystem.com/us/en/om-1-mark-ii>
- OM System Starry Sky AF explainer — <https://learnandsupport.getolympus.com/learn-center/photography-tips/browse-tips-by-camera-feature/starry-sky-af>
- OM-1 Mark II review (Live Science, 2026) — <https://www.livescience.com/technology/om-system-om-1-ii-review>
- Panasonic Lumix G9 II review (DPReview) — <https://www.dpreview.com/reviews/panasonic-lumix-dc-g9-ii-review/>
- Panasonic Lumix G9 II review (Amateur Photographer) — <https://amateurphotographer.com/review/panasonic-lumix-g9ii-review/>
- Best cameras for Milky Way photography 2026 (PhotoPills) — <https://www.photopills.com/articles/best-camera-for-milky-way-photography>
- Best cameras for Milky Way photography 2026 (Capture the Atlas) — <https://capturetheatlas.com/best-camera-milky-way-photography/>
- Best beginner cameras for astrophotography 2026 (Live Science) — <https://www.livescience.com/technology/best-beginner-cameras-for-astrophotography>
- Astrophotography cameras guide (AstroBackyard) — <https://astrobackyard.com/astrophotography-cameras/>
- Star Eater documentation (Lonely Speck) — <https://www.lonelyspeck.com/sony-star-eater-and-how-to-fix-it/>
- Sony Star Eater resolved in a7 III (PetaPixel, 2018-06-08) — <https://petapixel.com/2018/06/08/sonys-star-eater-problem-has-been-defeated-in-the-a7-iii/>
- Japan best-selling camera 2026 / EOS R50 (Digital Camera World) — <https://www.digitalcameraworld.com/cameras/mirrorless-cameras/so-far-japans-1-best-selling-camera-in-2026-is-a-3-year-old-aps-c-mirrorless-with-some-unusual-shooting-modes>
- 500 Rule vs NPF Rule (Galactic Hunter) — <https://www.galactic-hunter.com/post/500-rule-vs-npf-rule>
- 500 Rule Calculator (PhotoPills) — <http://www.photopills.com/calculators/spotstars>
- Crop factor (Wikipedia) — <https://en.wikipedia.org/wiki/Crop_factor>

## Uncertain / null values

The research brief requires that any value that could not be sourced is
recorded as `null` with a note, rather than guessed. The following fields
are `null` in `apsc.json`, each with an explanatory `astro_notes` entry on
the same camera:

- **Fujifilm X-T30 III** — `max_shutter_speed`, `min_shutter_bulb`,
  `built_in_intervalometer`: too newly launched (2025-10-23) for the specs
  pages fetched in this session to confirm exact shutter range and
  intervalometer presence beyond "expected, consistent with prior X-T30
  models."
- **Fujifilm X-M5** — `max_shutter_speed`, `min_shutter_bulb`,
  `built_in_intervalometer`: not confirmed from the manufacturer/PetaPixel
  sources fetched; the X-M5 is vlogging-oriented and its full shutter
  spec table was not reached in this session's searches.
- **Canon EOS R50** — `max_shutter_speed`, `min_shutter_bulb`,
  `built_in_intervalometer`: the Canon UK/Europe spec pages returned
  sensor/ISO/IBIS data but not a confirmed shutter-speed table in the
  content fetched.
- **Panasonic Lumix G9 II** — `min_shutter_bulb` (bulb-mode maximum
  duration) and any Starlight-AF-equivalent astro autofocus mode: not
  confirmed from sources checked; the G9 II's astro-specific autofocus
  feature (if any, beyond standard hybrid AF) was not found and should not
  be assumed equivalent to OM System's Starry Sky AF.
- **Sony a6700 star-eater status**: treated as a qualitative note rather
  than a hard fact. Sources agree the worst star-eater filtering was fixed
  by the a7 III generation (2018), and no dated 2025–2026 source
  specifically confirms or denies residual filtering on the a6700; this is
  recorded as mixed/unverified community signal in `astro_notes`, not
  stated as fact.

No sensor dimension, resolution, or crop-factor value in this file is a
guess — all are either a directly stated manufacturer figure or a value
computed by the same formula SkyCore itself uses
(`sensorWidthMM / resolution.widthPx * 1000` for pixel pitch;
full-frame-diagonal ÷ sensor-diagonal for crop factor).
