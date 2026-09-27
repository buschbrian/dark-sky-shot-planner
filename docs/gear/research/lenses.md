# Astrophotography lens reference: nightscapes, Milky Way, star trails

Research date: **2026-09-27**. All specs and claims below were checked against manufacturer pages
and named reviews on this date unless a claim explicitly says otherwise. Where a value could not be
sourced, it is recorded as `null` in `lenses.json` with a note, per the "never guess" rule — see the
**Uncertain values** section at the end.

This file is the human-readable companion to `lenses.json`, which the app's gear presets are built
from. Each lens below has a matching `id` in the JSON.

## How to read the tables

- **Focal length** is the astro preset value: for primes, the lens's only focal length; for zooms,
  the widest (fastest field-of-view) end, with the full range noted separately.
- **AF/MF** — autofocus or manual focus.
- **Infinity stop** — whether the lens has a genuine mechanical hard stop at infinity (rare on modern
  AF mirrorless lenses, which mostly use focus-by-wire with no hard stop) or is focus-by-wire only.
- **Coma rating** is a paraphrase of a named review's findings, not a numeric score invented here.
  Read the linked source for the full test.
- **Price tier** is budget / mid / premium — relative within this list, not an exact price (per the
  task's "no exact prices" rule).

---

## Full-frame lenses

### Native mirrorless wide primes (Sony E, Nikon Z, Canon RF, L-Mount)

| Lens | Focal length | Max f/ | Mount(s) | AF/MF | Infinity stop | Weight | Filters | Coma (source) | Launch | Price |
|---|---|---|---|---|---|---|---|---|---|---|
| Sigma 14mm F1.4 DG DN Art | 14mm | f/1.4 | Sony E, L-Mount | AF | No hard stop; MFL lock switch | 1160–1170 g | Rear gel only | Coma/astigmatism well controlled even wide open ([PetaPixel](https://petapixel.com/2023/06/08/sigma-14mm-f-1-4-dg-dn-art-review-a-nocturnal-monster/)) | 2023 | Premium |
| Sigma 20mm F1.4 DG DN Art | 20mm | f/1.4 | Sony E, L-Mount | AF | Not documented | 630 g | Front + rear | Coma extremely well controlled, slight winging at extreme corners ([Fstoppers](https://fstoppers.com/originals/sigma-20mm-f14-art-special-astronomy-review-104169)) | 2022 | Mid |
| Sigma 24mm F1.4 DG DN Art | 24mm | f/1.4 | Sony E, L-Mount | AF | Not documented | 510 g | 67mm front | AstroBackyard's top overall Milky Way pick ([AstroBackyard](https://astrobackyard.com/best-milky-way-lens/)) | 2021 | Mid |
| Sigma 14-24mm F2.8 DG DN Art | 14mm (range 14–24) | f/2.8 | Sony E, L-Mount | AF | Not documented | 795 g | Rear gel only | Excellent corner sharpness, well-controlled coma at f/2.8 ([Cameralabs](https://www.cameralabs.com/sigma-14-24mm-f2-8-dg-dn-art-review/)) | 2022 | Premium |
| Sigma 15mm F1.4 DG DN Fisheye Art | 15mm (fisheye) | f/1.4 | Sony E, L-Mount | AF | No hard stop; MFL lock switch | Not sourced | Rear only | Designed to correct sagittal coma flare ([Sigma](https://www.sigmaphoto.com/15mm-f1-4-dg-dn-diagonal-fisheye-a); [PetaPixel](https://petapixel.com/2024/02/27/sigma-15mm-f-1-4-dg-dn-art-review-wide-weird-and-wonderful/)) | 2024 | Premium |
| Sony FE 14mm F1.8 GM | 14mm | f/1.8 | Sony E | AF | Focus-by-wire | 460 g | None sourced | Coma essentially eliminated; astigmatism measured ~25.7% ([LensTip](https://www.lenstip.com/606.7-Lens_review-Sony_FE_14_mm_f_1.8_GM_Coma__astigmatism_and_bokeh.html)) | 2021 | Premium |
| Sony FE 20mm F1.8 G | 20mm | f/1.8 | Sony E | AF | Focus-by-wire | 373 g | 67mm front | "Sharp corners, popular choice" ([Capture the Atlas](https://capturetheatlas.com/best-lenses-milky-way-photography/)) | 2020 | Mid |
| Sony FE 24mm F1.4 GM | 24mm | f/1.4 | Sony E | AF | Focus-by-wire | 445 g | 67mm front | Not independently sourced this pass | 2018 | Premium |
| Sony FE 12-24mm F2.8 GM | 12mm (range 12–24) | f/2.8 | Sony E | AF | Focus-by-wire | 847 g | None (bulbous) | Not independently sourced this pass | 2020 | Premium |
| Sony FE 16-35mm F2.8 GM | 16mm (range 16–35) | f/2.8 | Sony E | AF | Focus-by-wire | Not sourced | 82mm front | Called "best Sony wide zoom for Milky Way" in aggregate 2026 coverage; no single named review with coma data captured | 2017 | Premium |
| Nikon Z 14-24mm f/2.8 S | 14mm (range 14–24) | f/2.8 | Nikon Z | AF | Focus-by-wire | 650 g | 112mm via hood + rear gel | Not independently sourced this pass | 2020 | Premium |
| Nikon Z 20mm f/1.8 S | 20mm | f/1.8 | Nikon Z | AF | Focus-by-wire | 505 g | 77mm front | Mixed: some reviews call coma minimal; LensTip measured 12.9% astigmatism, "borderline medium/high" ([LensTip](https://www.lenstip.com/587.7-Lens_review-Nikon_Nikkor_Z_20_mm_f_1.8_S_Coma__astigmatism_and_bokeh.html)) | 2020 | Mid |
| Nikon Z 14-30mm f/4 S | 14mm (range 14–30) | f/4 | Nikon Z | AF | Focus-by-wire | 485 g | 82mm front | Slower f/4 limits faint-detail use; valued for filter compatibility | 2019 | Mid |
| Canon RF 15-35mm F2.8L IS USM | 15mm (range 15–35) | f/2.8 | Canon RF | AF | Focus-by-wire | 840 g | 82mm front | "Most versatile Canon lens for Milky Way and landscape ... fast and sharp" ([AstroBackyard](https://astrobackyard.com/best-milky-way-lens/)) | 2020 | Premium |
| Canon RF 16mm F2.8 STM | 16mm | f/2.8 | Canon RF | AF | Focus-by-wire | 165 g | 43mm front | Budget option; not a primary fast-aperture astro pick | 2021 | Budget |
| Canon RF 24mm F1.4L VCM | 24mm | f/1.4 | Canon RF | AF | Focus-by-wire | 515 g | 67mm front | Strong, compact fast-aperture pick ([Space.com](https://www.space.com/stargazing/skywatching-kit/canon-rf-24mm-f-1-4l-vcm-lens-review)) | 2024 | Premium |
| Canon RF 10-20mm F4L IS STM | 10mm (range 10–20) | f/4 | Canon RF | AF | Focus-by-wire | 570 g | Rear gel only | Widest rectilinear RF zoom; f/4 limits faint-detail use | 2021 | Premium |

### Manual-focus and third-party wide primes (multi-mount)

| Lens | Focal length | Max f/ | Mount(s) | AF/MF | Infinity stop | Weight | Filters | Coma (source) | Launch | Price |
|---|---|---|---|---|---|---|---|---|---|---|
| Samyang/Rokinon AF 14mm F2.8 | 14mm | f/2.8 | Sony E, Canon EF/RF, Nikon F | AF | Mixed: EF/F hard stop reported; RF is focus-by-wire, no hard stop | 474–505 g | None (bulbous) | "Best affordable lens"; inconsistent QC across copies ([Capture the Atlas](https://capturetheatlas.com/best-lenses-milky-way-photography/)) | 2018 | Budget |
| Samyang/Rokinon 24mm F1.4 ED AS IF UMC (MF) | 24mm | f/1.4 | Canon EF, Nikon F, Sony E | MF | Yes, true hard stop | 565–590 g | 77mm front | Long-standing reputation for good coma correction, brand-level (Lonely Speck) | 2015 | Budget |
| Samyang/Rokinon AF 18mm F2.8 FE | 18mm | f/2.8 | Sony E | AF | Focus-by-wire | 145 g | 58mm front | Ultralight pancake; not a primary fast-aperture pick | 2020 | Budget |
| Rokinon/Samyang 14mm f/2.8 IF ED UMC (legacy MF) | 14mm | f/2.8 | Canon EF, Nikon F | MF | Yes, true hard stop | Not sourced | None (bulbous) | A Lonely Speck-era favorite; largely superseded by the AF version, still common used | 2011 | Budget |
| Viltrox AF 16mm F1.8 FE | 16mm | f/1.8 | Sony E, Nikon Z, L-Mount | AF | No hard stop | 553 g | 77mm front | Mixed: some call coma outstanding for price, matching premium lenses; others find astigmatism visible wide open ([PetaPixel](https://petapixel.com/2023/07/17/viltrox-af-16mm-f-1-8-fe-lens-review-it-has-no-business-being-this-cheap/)) | 2023 | Budget |
| Viltrox AF 20mm F2.8 FE (Air) | 20mm | f/2.8 | Sony E, Nikon Z | AF | Focus-by-wire | 157–173 g | 52mm front | Budget value; not as fast as premium primes ([OpticalLimits](https://opticallimits.com/sony/viltrox-af-20mm-f-2-8-fe-review/)) | 2023 | Budget |
| Laowa 15mm f/2 Zero-D FF | 15mm | f/2.0 | Sony E, Nikon Z, Canon RF, L-Mount | MF | Yes, true hard stop | 500 g | 72mm front | "Manual focus, compact, affordable" ([Capture the Atlas](https://capturetheatlas.com/best-lenses-milky-way-photography/)) | 2017 | Mid |
| Laowa 12mm f/2.8 Lite Zero-D FF | 12mm | f/2.8 | Sony E, Nikon Z (AF); more mounts as older MF version | AF (new)/MF (older) | AF version focus-by-wire; older MF version has hard stop | 377 g (AF Lite); 609 g (older MF) | 72mm front | Strong Zero-D rectilinear correction; no numeric coma test captured | 2025 | Mid |
| Laowa 10mm f/2.8 Zero-D FF | 10mm | f/2.8 | Sony E, Nikon Z (AF); Canon RF, L-Mount (MF) | Mixed | AF mounts focus-by-wire; MF mounts have hard stop | 420 g | 77mm front | World's first rectilinear 10mm f/2.8 full-frame filterable lens ([PhotoPills](https://www.photopills.com/articles/best-lens-for-shooting-milky-way)) | 2024 | Mid |
| Irix 15mm f/2.4 Blackstone | 15mm | f/2.4 | Canon EF, Nikon F, Pentax K, Sony E | MF | **Yes, genuine click hard stop** — marketed explicitly for astro | 619–647 g | 95mm front + rear gel | Well-corrected at f/2.4; favored specifically for its true infinity stop ([DustinAbbott.net](https://dustinabbott.net/2018/08/irix-15mm-f-2-4-blackstone-edition-review/)) | 2017 | Mid |
| Tamron 17-28mm F/2.8 Di III RXD | 17mm (range 17–28) | f/2.8 | Sony E | AF | Focus-by-wire | 420 g | 67mm front | "Lightweight, weather-sealed, affordable" ([Capture the Atlas](https://capturetheatlas.com/best-lenses-milky-way-photography/)) | 2019 | Budget |
| Tokina atx-i 11-20mm F2.8 CF | 11mm (range 11–20) | f/2.8 | Canon EF, Nikon F | AF | Not documented | 550 g | 82mm front | Marketed for astro (low distortion, low falloff); **note: APS-C-format DSLR lens**, not full-frame | 2019 | Budget |
| TTArtisan 11mm f/2.8 Fisheye | 11mm (fisheye) | f/2.8 | Sony E, Canon RF, Nikon Z, Leica L | MF | Yes, true hard stop | ~439–600 g | None | Solid full-frame fisheye correction for the price ([phillipreeve.net](https://phillipreeve.net/blog/review-ttartisan-11mm-2-8-fisheye/)); 2nd-most-used lens in 2026 MWPOTY winners | 2021 | Budget |
| Canon EF 16-35mm f/2.8L III USM (legacy, adapted) | 16mm (range 16–35) | f/2.8 | Canon EF | AF | Not confirmed | ~790 g (approx.) | 82mm front | "Excellent, surpassing predecessors in sharpness" ([Digital Camera World](https://www.digitalcameraworld.com/buying-guides/best-lenses-for-astrophotography)) | 2016 | Premium |
| Sigma 14mm F1.8 DG HSM Art (legacy DSLR) | 14mm | f/1.8 | Canon EF, Nikon F, Sigma SA | AF | Not confirmed | ~1170 g (approx.) | Rear gel only | Fast but noted coma/astigmatism wide open, more pronounced at corners — **lower-confidence, no single named review captured** | 2017 | Premium |

---

## APS-C lenses

| Lens | Focal length | Max f/ | Mount(s) | AF/MF | Infinity stop | Weight | Filters | Coma (source) | Launch | Price |
|---|---|---|---|---|---|---|---|---|---|---|
| Sigma 16mm F1.4 DC DN Contemporary | 16mm | f/1.4 | Sony E, L-Mount, Canon EF-M, Nikon Z | AF | Focus-by-wire | ~380–405 g | 67mm front | Regarded as one of the sharpest fast APS-C primes; no single numeric test captured ([OpticalLimits](https://opticallimits.com/sony/sigma-16mm-f-1-4-dc-dn-contemporary-review/)) | 2017 | Mid |
| Sigma 10-18mm F2.8 DC DN Contemporary | 10mm (range 10–18) | f/2.8 | Sony E, Canon RF, L-Mount, Fujifilm X | AF | Focus-by-wire | Not sourced | Not confirmed | Recommended APS-C zoom option ([Capture the Atlas](https://capturetheatlas.com/best-lenses-milky-way-photography/)) | 2022 | Mid |
| Viltrox AF 13mm F1.4 | 13mm | f/1.4 | Sony E, Fujifilm X, Nikon Z | AF | Focus-by-wire | 420–455 g | 67mm front | "Great lens, better price" ([PetaPixel](https://petapixel.com/2022/06/20/viltrox-af-13mm-f-1-4-stm-xf-lens-review-great-lens-better-price/)) | 2022 | Budget |
| Viltrox AF 23mm F1.4 | 23mm | f/1.4 | Sony E, Fujifilm X, Nikon Z, Canon EF-M | AF | Focus-by-wire | 260 g | 52mm front | Outperforms Fuji's own equivalent at lower price ([Fstoppers](https://fstoppers.com/originals/fstoppers-reviews-viltrox-23mm-f14-aps-c-dont-buy-fuji-equivalent-504111)); standard rather than wide-field focal length | 2021 | Budget |
| Samyang/Rokinon 12mm F2.0 NCS CS | 12mm | f/2.0 | Sony E, Fujifilm X, Canon EF-M, MFT | MF | Yes, true hard stop | 245 g | 67mm front | Capture the Atlas's "best all-around" APS-C pick | 2014 | Budget |
| Fujifilm XF 16mm F1.4 R WR | 16mm | f/1.4 | Fujifilm X | AF | Distance scale; no confirmed hard stop | 375 g | 67mm front | Long-standing favorite fast Fuji astro prime; no single numeric coma test captured | 2015 | Mid |
| Fujifilm XF 14mm F2.8 R | 14mm | f/2.8 | Fujifilm X | AF | **Yes — pull-back clutch hard stop** | 235 g | 58mm front | Valued for its true mechanical infinity clutch, rare on modern AF lenses | 2014 | Mid |
| Fujifilm XF 8-16mm F2.8 R LM WR | 8mm (range 8–16) | f/2.8 | Fujifilm X | AF | Focus-by-wire | 805 g | None (bulbous) | Professional-grade with field-curvature correction ([Photography Life](https://photographylife.com/reviews/fuji-xf-8-16mm-f2-8-r-lm-wr)) | 2019 | Premium |
| Fujifilm XF 8mm F3.5 R WR | 8mm | f/3.5 | Fujifilm X | AF | Focus-by-wire | 215 g | 62mm front | Slower aperture; smallest/lightest Fuji rectilinear ultra-wide | 2021 | Mid |
| Sony E 11mm F1.8 | 11mm | f/1.8 | Sony E (APS-C) | AF | Focus-by-wire | 181 g | 55mm front | "Tiny beast," strong for its size ([DustinAbbott.net](https://dustinabbott.net/2022/06/sony-e-11mm-f1-8-review/)) | 2022 | Mid |
| Laowa 9mm f/2.8 Zero-D | 9mm | f/2.8 | Sony E, Fujifilm X, Canon EF-M | MF | Yes, true hard stop | 215 g | 49mm front | World's widest rectilinear f/2.8 APS-C lens at launch; strong distortion control ([Digital Camera World](https://www.digitalcameraworld.com/reviews/laowa-9mm-f28-zero-d-lens-review)) | 2018 | Budget |
| TTArtisan 7.5mm f/2 Fisheye (APS-C) | 7.5mm (fisheye) | f/2.0 | Sony E, Fujifilm X, Canon EF-M/RF, Nikon Z, MFT | MF | Yes, true hard stop | 343–370 g | None | Budget 180° fisheye for creative Milky Way arcs | 2021 | Budget |
| Meike 6.5mm f/2 Circular Fisheye | 6.5mm (circular fisheye) | f/2.0 | Sony E, Fujifilm X, Canon EF-M, MFT | MF | Not confirmed | 300 g | None | Produces a circular (not full-frame) 190° image — niche/novelty use | 2017 | Budget |
| Sirui Sniper 16mm F1.2 AF | 16mm | f/1.2 | Sony E, Fujifilm X, Nikon Z | AF | Focus-by-wire | 384 g | 58mm front | Unusually fast f/1.2 for the price; no dedicated astro/coma test captured, general reviews only | 2024 | Budget |

---

## Micro Four Thirds lenses (flagged MFT)

| Lens | Focal length | Max f/ | Mount(s) | AF/MF | Infinity stop | Weight | Filters | Coma (source) | Launch | Price |
|---|---|---|---|---|---|---|---|---|---|---|
| Laowa 7.5mm f/2 MFT | 7.5mm | f/2.0 | Micro Four Thirds | MF | Yes, true hard stop | 150–170 g | 46mm front | 15mm-equivalent field of view; favored for light weight, no dedicated coma test captured | 2015 | Budget |
| Olympus/OM System M.Zuiko 8mm F1.8 Fisheye PRO | 8mm (fisheye) | f/1.8 | Micro Four Thirds | AF | Not confirmed | 315 g | None (rear not confirmed) | Fast fisheye reference for MFT astro-landscape; no dedicated coma test captured | 2015 | Premium |
| Panasonic Leica DG Vario-Summilux 10-25mm F1.7 ASPH | 10mm (range 10–25) | f/1.7 | Micro Four Thirds | AF | Focus-by-wire | 690 g | Front thread (size not confirmed) | Fastest constant-aperture zoom in the format; general-purpose rather than dedicated astro prime | 2019 | Premium |

---

## Guidance: how to choose an astro lens

### Focal length vs. the NPF rule (star-trailing limit)

The **500 Rule** (`500 ÷ focal length = max exposure seconds`) is a rough legacy guide that ignores
sensor resolution, aperture, and declination. The **NPF Rule**, developed by Frédéric Michaud for the
Société Astronomique du Havre, is more accurate for modern high-resolution sensors:

```
shutter speed (s) = (35 × aperture + 30 × pixel pitch) ÷ focal length
```

It accounts for aperture and pixel pitch (how finely the sensor samples the sky), not just focal
length, so denser pixels or wider apertures push the safe exposure time down. Use the NPF rule for
20+ MP bodies; the 500 rule is only "good enough" for older, lower-resolution sensors.
Sources: [Fstoppers, "Using the NPF Rule for Photographing Night Skies"](https://fstoppers.com/apps/using-npf-rule-photographing-night-skies-504525);
[Photography Life, "500 Rule vs NPF Rule"](https://photographylife.com/500-rule-vs-npf-rule).

This is exactly what the app's `LensProfile` + `CameraProfile` pixel-pitch fields are for — the NPF
math needs focal length, max f-number, and pixel pitch together, not focal length alone.

### Aperture vs. ISO

A wider aperture (lower f-number) lets you use a lower ISO for the same exposure, which directly
reduces noise — this is usually a bigger win for image quality than an even-shorter exposure time
from a narrower field of view. This is why fast primes (f/1.4–f/1.8) dominate dedicated astro
lens lists over slower zooms (f/2.8–f/4), even though the zooms are more versatile.

### Coma and sagittal astigmatism

Point light sources (stars) reveal lens aberrations that are invisible in normal daytime shooting.
**Coma** stretches off-axis stars into comet-like shapes; **sagittal astigmatism** stretches them
into wings or seagull shapes, usually worse in the corners and wide open. Lonely Speck's guidance:
astrophotography prioritizes low coma/astigmatism and a manual focus-distance scale over autofocus
speed or peak center sharpness — the opposite priority order from most lens reviews.
Source: [Lonely Speck, "A Practical Guide to Lens Aberrations"](https://www.lonelyspeck.com/a-practical-guide-to-lens-aberrations-and-the-lonely-speck-aberration-test/);
[Lonely Speck, "How to Pick a Lens for Milky Way Photography"](https://www.lonelyspeck.com/lenses-for-milky-way-photography/).

Lonely Speck also notes a brand-level pattern (not a guarantee for every model): Samyang/Rokinon's
manual-focus lenses are usually well corrected for coma and astigmatism, while some of Canon and
Nikon's older fast primes were historically weaker in this specific respect — a generalization, not
a substitute for checking a specific lens's own review.

### Stopping down

Coma and astigmatism are almost always worse wide open and improve by stopping down 1–2 stops (e.g.,
f/1.4 → f/2 or f/2.8). This is a real trade-off against the faster shutter speed (or lower ISO) a
wide-open aperture buys you — several reviews above show a lens with messy corners at f/1.4 cleaning
up by f/2.8. Capture the Atlas's guidance: "A lens that looks messy in the corners at f/1.4 may clean
up nicely at f/2.0–f/2.8," so test a candidate lens at multiple apertures before settling on its astro
working aperture. Source: [AstroBackyard, "Best Milky Way Lens"](https://astrobackyard.com/best-milky-way-lens/).

### Focusing at infinity

Very few current autofocus mirrorless lenses have a genuine **mechanical hard stop** at infinity;
most use focus-by-wire, where the ring can keep turning past the point of correct focus with no
tactile feedback (confirmed for the Samyang/Rokinon RF 14mm f/2.8 and the Viltrox AF 16mm f/1.8 FE
in the sources above). Lenses that do have a true hard stop or focus clutch — the Irix 15mm f/2.4
Blackstone, the Fujifilm XF 14mm f/2.8 R's pull-back clutch, and most manual-focus lenses from
Samyang/Rokinon, Laowa, and TTArtisan — make repeatable night focus meaningfully easier, since you
can return to a known-good infinity position by feel. On focus-by-wire lenses, focus must be set
each session using live view magnification on a bright star, then locked (a focus-lock switch, if
present, or tape).

---

## Popularity evidence and criteria

Two different kinds of "popular" are used across this file, and they are kept distinct:

1. **Competition-usage popularity (dated, most rigorous):** Capture the Atlas's *Milky Way
   Photographer of the Year 2026* gear analysis reviewed the EXIF/caption gear data of the 25 winning
   images from that year's competition (6,500 submissions, 12 countries). The **Viltrox 16mm f/1.8**
   was the single most-used lens among the 25 winners — the first time a budget third-party lens has
   topped that list — and the **TTArtisan 11mm f/2.8 fisheye** was used by two photographers.
   Source: [Capture the Atlas via WebSearch synthesis, "Best Lenses for Milky Way Photography in
   2026"](https://capturetheatlas.com/best-lenses-milky-way-photography/) (the dedicated gear-analysis
   page returned HTTP 403 to automated fetch and could not be read directly; this claim is drawn from
   that same site's lens-guide page and corroborating search-result summaries, all dated 2026).
2. **Buyer's-guide / editorial popularity (less rigorous, no stated sample):** Recommendations in
   2025–2026 buyer's guides from Capture the Atlas, AstroBackyard, PhotoPills, and Digital Camera
   World, which reflect editorial judgment rather than a counted sample of real shooters. These are
   cited per-lens above as "Capture the Atlas guide," "AstroBackyard guide," etc., and should be read
   as informed opinion, not usage statistics.

No claim in this file states a specific lens is "the most popular" without one of these two kinds of
citation attached.

---

## Sources consulted

- Manufacturer spec pages: Sigma (sigmaphoto.com, sigma-global.com), Sony (sony.com), Nikon
  (nikonusa.com), Canon (canon-cna.com, usa.canon.com), Fujifilm (fujifilm-x.com), Samyang/Rokinon
  (rokinon.com, samyangus.com), Viltrox (viltrox.com), Laowa/Venus Optics (venuslens.net), Irix
  (irixusa.com), Tamron (tamron.com), Tokina (tokinalens.com), TTArtisan (ttartisan.com), Meike
  (meikeglobal.com), Sirui (store.sirui.com), Panasonic (panasonic.com).
- Optical-quality reviews: [Lonely Speck](https://www.lonelyspeck.com/), [Capture the
  Atlas](https://capturetheatlas.com/), [Christopher Frost / general aggregation via
  WebSearch], [LensRentals](https://www.lensrentals.com/blog/) (general testing methodology, no
  lens-specific coma comparison found this pass), [DPReview](https://www.dpreview.com/),
  [PetaPixel](https://petapixel.com/), [AstroBackyard](https://astrobackyard.com/), plus
  [LensTip](https://www.lenstip.com/) (numeric coma/astigmatism measurements),
  [phillipreeve.net](https://phillipreeve.net/), [DustinAbbott.net](https://dustinabbott.net/),
  [OpticalLimits](https://opticallimits.com/), [Photography Life](https://photographylife.com/),
  [Fstoppers](https://fstoppers.com/), [Digital Camera World](https://www.digitalcameraworld.com/).
- Guidance sources: [Fstoppers NPF rule explainer](https://fstoppers.com/apps/using-npf-rule-photographing-night-skies-504525),
  [Photography Life 500 vs NPF](https://photographylife.com/500-rule-vs-npf-rule),
  [Lonely Speck lens-aberration guide](https://www.lonelyspeck.com/a-practical-guide-to-lens-aberrations-and-the-lonely-speck-aberration-test/).

---

## Uncertain values

The following are recorded as `null` in `lenses.json` because no source in this pass gave a citable
value — do not treat any of these as zero or "none," they are simply unverified as of 2026-09-27:

- **Weight not found:** Sigma 15mm f/1.4 DG DN Fisheye Art; Sigma 10-18mm F2.8 DC DN Contemporary;
  Rokinon/Samyang legacy 14mm f/2.8 IF ED UMC; Sony FE 16-35mm F2.8 GM (not re-verified this pass).
- **Infinity hard-stop status not confirmed:** most AF mirrorless lenses in this list where no review
  explicitly described focus-ring behavior at the infinity end (marked "Not documented" or "Not
  confirmed" in the tables above) — absence of a citation here means *unknown*, not *no hard stop*,
  except where a source explicitly described focus-by-wire behavior with no stop.
- **Filter thread size not confirmed:** Sigma 10-18mm F2.8 DC DN Contemporary; Sony FE 16-35mm F2.8
  GM (thread size given only for the original, not re-verified this pass); Panasonic Leica DG
  10-25mm f/1.7 (thread present per manufacturer, size not independently confirmed); Olympus 8mm
  f/1.8 Fisheye PRO (rear filter capability not confirmed).
- **No dedicated coma/astigmatism test found:** roughly a third of the lenses in this list, mostly
  budget/niche or very recent (2024–2025) models — marked "no dedicated coma test captured" or
  "not independently sourced" in their `coma_notes` field. This is common for niche or very recent
  lenses; it does not imply poor performance, only that no named review with specific findings was
  located in this research pass.
- **Lower-confidence claim flagged explicitly:** the legacy Sigma 14mm F1.8 DG HSM Art's coma/
  astigmatism note is drawn from aggregated search-result synthesis rather than one named, directly
  quoted review, and is flagged as such in `lenses.json`.
- **Capture the Atlas MWPOTY 2026 gear-analysis page:** the dedicated page
  (`skiesandscopes.com/milky-way-photographer-of-the-year-2026-gear-analysis/` and
  Capture the Atlas's own gear-analysis page) returned an HTTP 403 to automated fetch during this
  research pass; the popularity claims above are drawn from that same source's corroborating
  lens-guide page and search-result summaries dated 2026, not a direct read of the gear-analysis
  page itself. If precision on exact photographer counts matters later, that page should be
  re-checked manually.
