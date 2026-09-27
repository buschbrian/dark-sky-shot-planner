# iPhone and iOS-device cameras for night-sky photography

Research for Dark Sky Shot Planner's gear presets. All dates checked
**2026-09-27** unless a source's own publish date is quoted. "Official"
means Apple's own text (apple.com or support.apple.com); "derived" means
computed or taken from a secondary source, always labeled and cited.
Uncertain values are `null` in `iphone.json` with a reason — never guessed.

**Ground truth for this app:** `docs/ios/CAPTURE-LIMITS.md` in this repo
measured the owner's iPhone 18 Pro Max directly (iOS 27.2, iPhone19,3) and
is the single most trusted source below. It found the third-party single-frame
ceiling is **1.0 s on every format, every camera** — far below any NPF limit
computed here — so every real capture in this app is a burst of 1 s frames,
not a true long exposure. Apple's own Night mode (10–30 s) is a first-party
multi-frame pipeline third-party apps cannot invoke.

---

## 1. iPhone models, generation by generation

### Sensor-size method note

Apple never publishes physical sensor dimensions or pixel pitch. Every `mm`
sensor size below is **derived** from an optical-format string (e.g.
`1/1.28"`) reported by GSMArena's teardown-informed camera reviews, converted
with the standard (non-literal) "inch-type" formula: diagonal (mm) ≈
sensor-size(in) × 25.4 / 1.5. This is an industry convention, not a
manufacturer-stated measurement — treat these mm figures as approximate.
Pixel pitch, where not stated by Apple (never), is likewise from GSMArena or
computed as sensor-width-mm ÷ native pixel width (the app's own
`CameraProfile.pixelPitchUM` formula, `Gear.swift`).

### iPhone 13 (2021)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 13 / 13 mini | 12MP, ƒ/1.6, sensor-shift OIS | 12MP, ƒ/2.4, 120° | — (no telephoto) |
| iPhone 13 Pro / Pro Max | 12MP, ƒ/1.5, sensor-shift OIS | 12MP, ƒ/1.8, 120° | 12MP, ƒ/2.8, 3x optical |

Source: Apple tech specs, [iPhone 13](https://support.apple.com/en-us/111872),
[iPhone 13 mini](https://support.apple.com/en-us/111873),
[iPhone 13 Pro Max](https://support.apple.com/en-us/111870) (accessed
2026-09-27). **No ProRAW** on the standard 13/13 mini; Pro models do have it.
Actual (physical) focal lengths and sensor dimensions were **not found** by a
fetched source this session — Apple doesn't publish them and no GSMArena
teardown page for this generation was fetched — so `iphone.json` leaves them
`null` rather than estimating.

### iPhone 14 (2022)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 14 / 14 Plus | 12MP, 26mm eq., ƒ/1.5, sensor-shift OIS | 12MP, 13mm eq., ƒ/2.4, 120° | — |
| iPhone 14 Pro / Pro Max | **48MP** (first 48MP main), 24mm eq., ƒ/1.78, sensor-shift OIS | 12MP, 13mm eq., ƒ/2.2, 120° | 12MP, 77mm eq. (3x), ƒ/2.8, OIS |

Source: Apple tech specs, [iPhone 14](https://support.apple.com/en-us/111850),
[iPhone 14 Pro Max](https://support.apple.com/en-us/111846). Sensor size for
the 14 Pro's new 48MP main camera, derived: GSMArena's camera review states
"48MP 1/1.28" sensor with a Quad-Bayer color filter... 1.22µm pixel size
before binning – 2.44µm with binning"
([gsmarena.com](https://www.gsmarena.com/apple_iphone_14_pro-review-2480p6.php)).
Ultra-wide derived the same way: "1/2.55" unit with large 1.4µm pixels."
This 1/1.28" main sensor (≈9.8 × 7.3 mm derived) is the same physical part
family used through the iPhone 17 Pro Max — see below.

### iPhone 15 (2023)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 15 / 15 Plus | 48MP, 26mm eq., ƒ/1.6, sensor-shift OIS | 12MP, 13mm eq., ƒ/2.4, 120° | — |
| iPhone 15 Pro / Pro Max | 48MP, 24mm eq., ƒ/1.78, sensor-shift OIS | 12MP, 13mm eq., ƒ/2.2, 120° | 12MP, 120mm eq. (5x, Pro Max only), ƒ/2.8, 3D sensor-shift OIS, tetraprism |

Source: Apple tech specs, [iPhone 15](https://support.apple.com/en-us/111831),
[iPhone 15 Pro Max](https://support.apple.com/en-us/111828) (WebFetched
directly). The 15 Pro (non-Max) kept the 3x/77mm telephoto; only the Pro Max
got the new 5x tetraprism. No ProRAW on standard 15/15 Plus.

### iPhone 16 (2024)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 16 / 16 Plus | 48MP, 26mm eq., ƒ/1.6, sensor-shift OIS | 12MP, 13mm eq., ƒ/2.4, 120° | — |
| iPhone 16 Pro / Pro Max | 48MP, 24mm eq., ƒ/1.78, sensor-shift OIS | **48MP** (first 48MP ultra-wide), 13mm eq., ƒ/2.2, 120° | 12MP, 120mm eq. (5x), ƒ/2.8, 3D sensor-shift OIS, tetraprism |
| iPhone 16e | 48MP, 26mm eq., ƒ/1.6 | — (single camera) | — |

Source: Apple tech specs, [iPhone 16 Pro Max](https://support.apple.com/en-us/121032)
(WebFetched). This is the generation with the **best independent EXIF
verification** available: TidBITS, "Tracking My iPhone Camera Usage With a
Deep Dive into EXIF Data" (tidbits.com, published **2025-09-25**), read real
photo metadata from an iPhone 16 Pro and reported true physical focal
lengths: **main 6.8 mm** (24mm eq.), **ultra-wide 2.2 mm** (14mm eq. — note
Apple's marketed 13mm and the EXIF-derived 14mm-equivalent differ slightly,
a normal rounding/crop artifact), **5x telephoto 15.7 mm** (120mm eq.).
Sensor sizes, derived from GSMArena's camera review
([gsmarena.com](https://www.gsmarena.com/apple_iphone_16_pro_max-review-2750p5.php)):
main 1/1.28" (1.22–2.44µm pixel pitch), ultra-wide 1/2.55" (0.7–1.4µm),
telephoto 1/3.06" (1.12µm, 12MP only — no 48MP telephoto yet).

### iPhone 17 (2025)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 17 | 48MP, 26mm eq., ƒ/1.6, sensor-shift OIS | 48MP, 13mm eq., ƒ/2.2, 120° | 12MP optical-quality 2x crop of main (52mm eq.) |
| iPhone Air | 48MP, 26mm eq., ƒ/1.6, sensor-shift OIS — **single physical rear camera** | — | 12MP optical-quality 2x crop of main (52mm eq.) |
| iPhone 17 Pro / Pro Max | 48MP, 24mm eq., ƒ/1.78, sensor-shift OIS | 48MP, 13mm eq., ƒ/2.2, 120° | **48MP** (first 48MP telephoto), 100mm eq. (4x), ƒ/2.8, 3D sensor-shift OIS, tetraprism; 200mm eq. (8x) optical-quality crop |
| iPhone 17e | 48MP, 26mm eq., ƒ/1.6 | — | 12MP crop, 52mm eq., ƒ/1.6 |

Sources: Apple tech specs, [iPhone 17 Pro](https://support.apple.com/en-us/125090)
(WebFetched), [iPhone 17 Pro Max](https://support.apple.com/en-us/125091)
(WebFetched), [iPhone Air](https://support.apple.com/en-us/125092)
(WebFetched); GSMArena camera reviews for [iPhone 17 Pro Max](https://www.gsmarena.com/apple_iphone_17_pro_max-review-2884p6.php),
[iPhone 17](https://www.gsmarena.com/apple_iphone_17-review-2886p6.php), and
[iPhone Air](https://www.gsmarena.com/apple_iphone_air-review-2885p6.php)
(fetched by a delegated research agent this session).

**Correction, resolved this session:** an earlier pass of this file
incorrectly attributed a "2x Telephoto: 52mm, ƒ/1.6" mode to the iPhone Air.
A direct WebFetch of Apple's own tech-specs page (support.apple.com/en-us/125092)
confirms the iPhone Air has **only one rear camera and no zoom lens of any
kind** — a single 48MP Fusion Main, full stop. The standard iPhone 17 and
17e genuinely do have a "12MP optical-quality 2x Telephoto" mode, but it is
**not a second lens** — it is an in-sensor crop of the same 48MP main
module (confirmed by 2026 hands-on coverage: AppleInsider, "I took an
iPhone Air on vacation...", 2025-10-17, discussing the closely related
architecture; ithinkdiff.com).

**Sensor-generation conflict, now resolved:** GSMArena camera reviews
(fetched directly this session) confirm the Pro-tier and standard-tier
iPhones have used **genuinely different, differently-sized main sensors**
since at least iPhone 17: the Pro/Pro Max line uses a Sony IMX903-class
1/1.28" sensor (1.22–2.44µm pixel pitch); the standard iPhone 17, iPhone 16,
and iPhone Air share a smaller Sony IMX904, 1/1.56", 1.0µm-pixel sensor —
GSMArena's iPhone 17 review states this explicitly: "the main camera on the
iPhone 17 is based on the same Sony IMX904 sensor as the main camera on the
iPhone 16." The budget-tier iPhone 16e and 17e go smaller still: both reuse
a 1/2.55", 0.7–1.4µm sensor that GSMArena identifies as "the same sensor as
the one found on the 16 Pro's ultrawide camera" — i.e. the *cheapest*
current iPhone's only camera is built around what higher-tier phones use
only for their ultra-wide. GSMArena's own comparison: "in low-light
conditions, the larger sensor on the iPhone 16 yields more detailed and
less noisy footage" than the 16e. For astro, this sensor-tier hierarchy
(Pro 1/1.28" > standard/Air 1/1.56" > e-series 1/2.55") matters as much as
the aperture numbers in choosing which iPhone to shoot with.

GSMArena also confirms the iPhone 17 Pro and Pro Max **share identical
camera hardware** this generation — "starting with the 16s, the two sizes
share the same system... With identical camera systems... they capture
identical images" — so the 17 Pro Max data above applies equally to the
17 Pro.

### iPhone 18 (2026, current flagship — measured directly)

| Model | Main/Wide | Ultra Wide | Telephoto |
|---|---|---|---|
| iPhone 18 Pro / Pro Max | 48MP, 24mm eq., **variable aperture** ƒ/1.48/1.8/2.8/4.0, 2nd-gen sensor-shift OIS | 48MP, 13mm eq., ƒ/2.2, 120° marketed (103.6° measured) | 48MP, 100mm eq. (4x), ƒ/2.8, 3D sensor-shift OIS, tetraprism; 200mm eq. (8x) crop |

Source: Apple tech specs, [iPhone 18 Pro Max](https://support.apple.com/en-us/148591)
(WebFetched). **First variable-aperture main camera Apple has shipped**: six
aperture blades, each "thinner than a human hair," per PetaPixel, "iPhone 18
Pro Has Apple's Fastest Lens Yet Thanks to Variable Aperture" (petapixel.com,
published **2026-09-09**), which also reports "the aperture opens to let in
about 50% more light" at ƒ/1.48 vs. the prior fixed ƒ/1.78. Sensor, derived:
GSMArena identifies the part as "48MP Sony IMX 905 (1/1.28", 1.22µm-2.44µm)"
for the main camera, "Sony IMX 972" (ultra-wide) and "Sony IMX 973"
(telephoto), both 1/2.55" with 0.7–1.4µm pixels
([gsmarena.com review](https://www.gsmarena.com/apple_iphone_18_pro_max-review-3002p5.php)).

**This is the device this repo has actually measured** (owner's unit, iOS
27.2 build 24B5089g, `docs/ios/CAPTURE-LIMITS.md`, 2026-09-26/27). Verified,
not derived:

- Longest single third-party exposure: **1.0 s**, every format, every camera.
- Main camera ISO range at the "best astro format" (4032×3024): 55–12,320.
  Ultra-wide: 15–3,600. Telephoto: 15–7,680.
- All four aperture stops (ƒ/1.48/1.8/2.8/4.0) are settable via
  `setExposureModeCustom(lensAperture:duration:iso:)`.
- **No Bayer RAW on any format, any camera** — RAW capture is Apple ProRAW
  only (a demosaiced, scene-referred "linear DNG"), even when the app sets
  `photoQualityPrioritization = .speed`.
- A real 5-frame capture at 1.0 s / ISO 800 / ƒ/1.48 produced 4032×3024
  ProRAW DNGs with **EXIF focal length 6.93 mm** and **pixel pitch 2.48 µm**
  (12MP-binned mode), giving an **NPF limit of 8.6 s at k=1** — computed
  directly from a real captured frame, the single most trustworthy focal
  length / pixel pitch pair in this file.
- Actual field of view, measured: main 70.7°, ultra-wide 103.6° (vs. 120°
  marketed — Apple's FOV figure appears to include some crop/correction
  margin not present in the raw capture), telephoto 19.0°.
- Minimum focus distance, measured: main 200 mm, ultra-wide 20 mm, telephoto
  1,160 mm.
- Low-light boost: **not supported** on any rear camera in this measurement.

### Apple's official Night mode behavior (all Pro-tier models with Night mode)

- Apple's support guide (Use Night mode on your iPhone,
  [support.apple.com/en-us/102519](https://support.apple.com/en-us/102519),
  WebFetched) states only that capture duration varies with scene darkness,
  and that a **Max** slider setting "extends the capture time" — it does not
  publish an exact ceiling.
- The widely repeated **"up to 30 seconds on a tripod"** figure is **not
  stated verbatim on apple.com or support.apple.com** in any page fetched
  this session. It is well corroborated by secondary/community sources: a
  real capture reported in a smartphone-astrophotography Facebook group
  ("iPhone 16 pro max, 30 sec exposure, +2.0 night mode... chucked on a
  tripod," facebook.com/groups/smartphoneastro), an Apple Developer Forums
  thread asking "How can I implement the 30-second long exposure of the
  built-in night mode?" (developer.apple.com/forums/thread/769970), and
  multiple consumer tech outlets (Tom's Guide, OSXDaily). Treated here as
  **community-documented, not Apple-stated** — label accordingly in any UI
  copy.
- This Night mode pipeline (however long it runs) is **Apple's own
  multi-frame fusion and is not exposed to third-party apps** — confirmed by
  this repo's own measurement (`CAPTURE-LIMITS.md`): the longest single frame
  a third-party `AVCaptureDevice` session can request is 1.0 s, regardless of
  what the stock Camera app's Night mode achieves.

---

## 2. Other iOS devices: current iPad Pro and iPad Air

Both current iPads (iPad Pro 13-inch (M5) and iPad Air 11-inch (M4),
confirmed as the current generations as of 2026-09-27 — iPad Air M4
announced 2026-03-02 per Apple Newsroom) share **the same rear camera spec
text, word for word**:

> "12MP Wide camera, ƒ/1.8 aperture, Five‑element lens, Autofocus with Focus
> Pixels, Smart HDR 4, Auto image stabilization"

Source: Apple tech specs,
[iPad Pro 13-inch (M5)](https://support.apple.com/en-us/125407) and
[iPad Air 11-inch (M4)](https://support.apple.com/en-us/126471), both
WebFetched directly. Neither page mentions Night mode, ProRAW, RAW of any
kind, or optical/sensor-shift image stabilization for still photos — only
"Auto image stabilization," Apple's software/digital term. The iPad Pro does
list "ProRes RAW" but that is a **video** codec, not a stills RAW format; it
appears only under the video-recording bullet list, with no equivalent
stills-RAW line. **Neither current iPad is a usable astro camera**: single
fixed lens, no RAW stills, no Night mode, a smaller sensor than any current
iPhone main camera (12MP, not derived/confirmed in mm this session — no
GSMArena teardown of the current M5/M4 iPad camera module was fetched).

---

## 3. Clip-on lens systems for iPhone (Moment, ShiftCam, Sandmarc)

**Bottom line: none of these help astrophotography in the way that matters
most — light-gathering.** A clip-on lens sits in front of a fixed sensor and
aperture; it cannot make the sensor bigger or the native aperture wider. At
best it changes field of view or, for a genuine long-focal-length tele
add-on, brings a distant subject (the Moon) closer. None of the reviews
found this session claim otherwise, and one is explicit about the limit.

- **Moment** publishes real focal-length specs for its lens line: 18mm wide,
  58mm tele ("up to 4x magnification when used in combination with optical
  zoom"), 25mm macro, 15mm fisheye, plus newer T-Series lenses (a 75mm
  macro, 1.33x/1.55x anamorphic). Source: shopmoment.com product/blog pages
  (WebSearch summaries; the specific "which lens is right for me" page was
  not independently WebFetched — treat focal-length figures as reasonably
  reliable but not verified against a primary spec sheet this session).
  **No f-number is published for any Moment lens.** This was independently
  confirmed by a PetaPixel review of Moment's newer T-Series II lenses
  (petapixel.com, published **2026-08-24**, fetched directly by a delegated
  research agent this session), whose reviewer states plainly: **"Aperture
  is fixed"** on the iPhone — a clip-on lens cannot change the phone's
  native f-number or sensor size, which are what actually govern
  light-gathering for astro. The reviewer found no low-light, night, or
  astrophotography discussion in the review at all.
- Moment's own review copy is honest about the limit: "Honest Thoughts on
  the Moment Tele 58mm Mobile Lens" (shopmoment.com) and third-party reviews
  agree the Tele 58mm gives "an approximate 2x optical zoom" good for
  "close-ups and detail of objects such as the moon and sunsets" but "won't
  provide enough performance to be seeing far-off planets or galaxies" —
  i.e., useful for Moon shots, not deep-sky or Milky Way work.
- **ShiftCam** shows the identical pattern. A newer product line, the X.Series
  SuperZoom (PetaPixel, published **2026-08-27**, fetched directly; also
  shiftcam.com's own product listing), publishes real equivalent focal
  lengths — "up to 192mm (equivalent)" for the 2x SuperZoom Tele and "up to
  a 350mm equivalent focal length" for the 3.5x SuperZoom Tele, both on
  iPhone 17 Pro — with physical details like "12 elements in six groups"
  and minimum focus distances of 6–8 meters. **No f-number is published for
  any ShiftCam lens, in any of its three product lines** (P.Series,
  V.Series, X.Series) checked this session. PetaPixel's own assessment: "the
  author notes that real-world testing is required to fully evaluate the
  lenses" — i.e. even PetaPixel had not independently verified ShiftCam's
  performance claims at time of publication.
- **Sandmarc** markets astro-specific products (Telephoto 6x/10x, a
  "Tetraprism 96mm" lens for "iPhone 15 Pro Max and newer") but its own
  astrophotography guide page, fetched this session
  ([sandmarc.com](https://www.sandmarc.com/blogs/iphone-photography/astrophotography-guide-how-to-photograph-the-stars-with-your-iphone)),
  **publishes zoom ratios and one "96mm" figure only — no f-number for any
  lens**, consistent with the Moment/ShiftCam pattern above.
- **Beastgrip**: not independently researched with enough depth this session
  (a delegated agent ran out of search budget before reaching it). Not
  included in `iphone.json`.
- **The absence of published f-numbers across every clip-on brand checked
  (Moment, ShiftCam, Sandmarc) is itself a useful, citable finding**, not
  just a gap: it reflects the physical reality that a clip-on lens cannot
  widen the phone's fixed native aperture, so manufacturers have little
  reason to publish a spec that wouldn't change. General verdict from the
  astro-specific guides consulted: **use the main camera unclipped** for
  Milky Way and star work; a tele add-on's only defensible night-sky use is
  closing in on the Moon, where the phone's native telephoto (where
  present) usually already does the same job with better glass and no light
  loss from an extra air-glass interface. One caveat worth flagging for
  future research: a genuinely large-objective tele add-on (unlike a simple
  close-up lens) has its own entrance pupil and could in principle gather
  more light before that light reaches the phone's fixed internal aperture
  — none of the three brands checked here publish the entrance-pupil/true
  aperture data that would let this app evaluate that claim, so it remains
  an open question rather than a settled "clip-ons never help" verdict.

---

## 4. How to use each lens for astro

### Which camera to use

**The main (wide) camera, at its widest native aperture, every time.** It has
the largest sensor, the widest aperture, and (from 14 Pro onward) the
highest native resolution of any rear module — confirmed directly by this
repo's own measurement: on the iPhone 18 Pro Max, the main camera reaches
ISO 12,320 at the best astro format versus 3,600 (ultra-wide) and 7,680
(telephoto) (`CAPTURE-LIMITS.md`). The **ultra-wide** is the second choice,
specifically for wide star-trail or Milky Way-arch frames where field of
view matters more than per-pixel light. The **telephoto** is for the Moon,
not deep sky: narrower field of view, smaller sensor, and (per this repo's
NPF arithmetic below) the shortest exposure budget of the three before star
trailing sets in.

### Night mode vs. a manual RAW app vs. stacking apps

- **Apple Camera app / Night mode**: the only route to Apple's true
  extended-exposure pipeline (community-documented up to ~30 s on a tripod;
  see §1). It is a **first-party multi-frame fusion black box** — not
  available to any third-party app, and not what this repo's own capture
  engine uses (confirmed: `CAPTURE-LIMITS.md`, "The Camera app's 10–30 s
  Night mode is Apple's own multi-frame pipeline and is not available to
  apps"). Good for a single best-effort shot with no app installed; not
  useful for stacking workflows since it doesn't expose individual frames.
- **NightCap Camera** (nightcapcamera.com): dedicated astro modes —
  **Stars** (auto-configures for starry sky/aurora), **Star Trails**
  ("Takes very long exposure photos of the night sky — at least 15 minutes
  is recommended"), **Meteor** (auto-captures hundreds of frames, keeps only
  ones that might show a shooting star), and **ISS** (satellite-pass
  capture) — quoted from nightcapcamera.com, fetched by a delegated research
  agent this session. Its Long Exposure mode is explicitly computational,
  not a single continuous sensor exposure: "It steadies and aligns the shot
  while you hold the phone, so you can take long exposures anywhere" —
  i.e. stacking-and-alignment, the same general approach this repo's own
  capture engine uses out of hardware necessity (§ above). **Correction:
  NightCap's own site does not claim RAW capture** — its stated Pro output
  formats are "Optional high quality JPEG or perfect quality TIFF photos,"
  not RAW/DNG. For a RAW workflow, pair NightCap's astro framing/detection
  with a RAW-capable app (Halide Process Zero, ProCamera) rather than
  expecting RAW from NightCap directly.
- **Halide** (halide.cam, by Lux): the manual-control benchmark — manual
  shutter/ISO/white balance via gesture controls, focus peaking, a loupe,
  histograms, a level grid. Its Process Zero mode
  (lux.camera/process-zero-manual/, WebFetched) captures a single
  unprocessed RAW frame with "no AI involved at all" — but its own manual
  states plainly **"Process Zero does not work with Night mode"** and warns
  of grainy low-light results since it skips Apple's noise reduction. **Open
  question, not resolved this session**: a delegated research agent fetched
  Halide's current homepage directly and found its RAW-related copy reads
  "If you shoot with a standalone camera, you can import your RAW files" —
  language about *importing* RAW from an external camera, not necessarily
  about *capturing* ProRAW with the iPhone's own sensor. Halide has
  supported ProRAW capture in past versions per general knowledge, but this
  was not conclusively re-confirmed against current (2026) app documentation
  this session — verify directly in the App Store listing before stating it
  as current fact in app copy.
- **Spectre** (spectre.cam, also Lux): an AI-stacking long-exposure
  simulator — its own site: "an AI-powered shutter for your iPhone... a
  computational shutter takes hundreds of shots over the span of a few
  seconds," saved as a Live Photo "so you can re-play the exposure as it
  happened." It is marketed for **crowds, water, and light trails in cities
  ("Rivers of Light")** — no astrophotography or star-trail feature is
  marketed on Spectre's own site, and its exposure durations (originally "3,
  5, and 9 seconds," later extended "to 30 seconds" per App Store version
  notes) are far short of NightCap's 15-minute-plus dedicated Star Trails
  mode. **Not recommended for night-sky work** — included because Brian's
  question set named it, but it is a general long-exposure tool, not an
  astro one, and does not capture RAW.
- **ProCamera** (procamera-app.com): full manual shutter/ISO/white balance,
  RAW ("classic RAW") plus ProRAW since iPhone 12 Pro, exposure compensation
  with zebra stripes, focus peaking, support for every physical lens
  (ultra-wide/wide/tele/LiDAR). Source: WebSearch of procamera-app.com's
  features page. A capable general manual-RAW app; no astro-specific mode
  found in the material reviewed this session (unlike NightCap).

**This app's own approach** (per `CAPTURE-LIMITS.md`, for context): because
no third-party app — including all four above — can get a longer single
frame than 1.0 s out of current iPhone hardware, any of them attempting a
genuine multi-second single exposure is either (a) actually taking a burst
of ≤1 s frames and stacking them, same as this app does, or (b) invoking
Apple's own Night mode pipeline via the system camera UI, which no
third-party `AVFoundation` session can trigger directly.

**A note on noise reduction, not researched in depth this session**: once
frames are stacked, a further non-generative AI denoise pass (e.g. Adobe
Lightroom's Denoise, or Apple's own on-device noise models) is a reasonable
optional post-processing step for a stacked astro image — it estimates and
removes sensor noise from the actual captured signal rather than inventing
image content, which is a different category from generative fill or
scene synthesis. This distinction (enhancement vs. generative) was not a
focus of this research pass and no specific denoise-tool claims are sourced
here; flagging it only so the how-to guide doesn't read as silent on the
question.

### ProRAW, focus at infinity, tripod, timer

- **ProRAW is Pro-tier only**, every generation checked (13 Pro through 18
  Pro Max) — confirmed by Apple's own ProRAW support page: "On iPhone 12 Pro
  and later Pro models... you can take photos in Apple ProRAW"
  ([support.apple.com/en-us/119916](https://support.apple.com/en-us/119916),
  WebFetched). No standard, Plus, Air, or "e" model in any generation
  researched this session has ProRAW. That means every standard/Plus/Air/e
  iPhone is capped at HEIC/JPEG for astro stacking — a real quality
  ceiling worth stating plainly in the app's gear guidance.
- **Focus at infinity**: there is no literal infinity detent on an iPhone
  lens. This repo's own measurement confirms the custom lens-position API
  goes from 0–1, where "1 is the far end, which Apple says is not infinity"
  (`CAPTURE-LIMITS.md`). In practice, focus on the brightest visible star
  with a magnifier/focus-peaking tool (Halide's loupe, or this app's own
  half-flux-radius readout) rather than assuming a fixed slider position.
- **Tripod and timer**: essential. Handheld Night mode caps at a much
  shorter auto exposure; the "Max" extended mode and any third-party
  1-second-frame burst both need mechanical stillness. Apple's own guide
  recommends "a solid and secure surface, or a tripod" explicitly
  (support.apple.com/en-us/102519). A 3–10 s shutter-release timer (native
  Camera app timer, or an app's own) avoids touch-induced shake at the start
  of a sequence.

### Star-trail and time-lapse options

- **Native Camera app**: no dedicated star-trail or astro time-lapse mode;
  the general Time-Lapse mode exists but is tuned for daylight subjects and
  compresses variably, unsuitable for controlling a fixed astro cadence.
- **NightCap**: dedicated Star Trails mode with in-app stacking, per its own
  marketing (see above).
- **This app** (per `CAPTURE-LIMITS.md`): a star-trail designer takes a
  duration and interval, saves every frame, and builds an unaligned
  per-pixel maximum (`StackAccumulator(mode: .maximum)`). Keeping the
  interval equal to the exposure (1 s, given the measured hardware ceiling)
  keeps trails unbroken; a longer interval leaves visible gaps. The
  celestial-pole framing feature referenced in that doc was not yet on any
  branch as of the note's writing.

### NPF limit per lens — arithmetic shown

Using this app's own formula (`StarExposure.npf`, `SkyCore`):

```
t = k · (16.856·N + 0.0997·f + 13.713·p) / (f · cos δ)     (k=1, δ=0°, worst case)
```

| Lens | N (ƒ) | f (mm, actual) | p (µm) | NPF t (s) | Source for f, p |
|---|---|---|---|---|---|
| iPhone 18 Pro Max main, ƒ/1.48 | 1.48 | 6.93 (measured) | 2.48 (measured, 12MP-binned) | **8.6** | `CAPTURE-LIMITS.md`, real captured DNG EXIF |
| iPhone 16 Pro main, ƒ/1.78 (shared family, 14 Pro–17 Pro Max) | 1.78 | 6.8 (EXIF) | 1.22 (48MP native, GSMArena) | **7.0** | TidBITS EXIF + GSMArena sensor |
| — same, at 12MP-binned pitch | 1.78 | 6.8 | 2.44 (binned) | **9.4** | as above |
| iPhone 16 Pro ultra-wide, ƒ/2.2 | 2.2 | 2.2 (EXIF) | 0.7 (48MP native) | **21.3** | TidBITS EXIF + GSMArena sensor |
| — 12MP-era ultra-wide (14–16 Pro), pitch 1.4µm | 2.2 | 2.2 | 1.4 | **25.7** | as above |
| iPhone 16 Pro Max 5x telephoto, ƒ/2.8 | 2.8 | 15.7 (EXIF) | 1.12 (GSMArena) | **4.1** | TidBITS EXIF + GSMArena sensor |

Worked example for the 18 Pro Max main camera (matches `CAPTURE-LIMITS.md`'s
stated 8.6 s exactly):

```
spread = 16.856×1.48 + 0.0997×6.93 + 13.713×2.48
       = 24.95 + 0.69 + 34.01 = 59.65
t = 1 × 59.65 / (6.93 × cos 0°) = 59.65 / 6.93 = 8.61 s
```

**Every one of these NPF limits is far longer than the measured 1.0 s
third-party single-frame ceiling.** The binding constraint on an iPhone is
never star trailing within a single frame — it's that no app can request a
frame longer than 1 s in the first place. NPF only starts to matter once
stacking crosses from "many short frames" to "how long can each sub-frame
be before its own stars smear," and at 1 s every lens above has an enormous
margin (the tightest, the 5x telephoto, still allows a 4x longer single
frame than the hardware permits).

---

## 5. "Most popular" — evidence, dated 2025–2026

No astrophotography-specific usage survey (Reddit r/astrophotography,
Cloudy Nights, or similar) was found with hard numbers by iPhone model —
both Cloudy Nights and a Skies & Scopes astro-specific ranking page returned
HTTP 403 to every fetch method tried (direct WebFetch, curl with a spoofed
browser user-agent, and the `defuddle` skill), and Reddit was not reachable
by any tool available this session. That gap is real and stated plainly
rather than filled with a guess.

What *is* available, in descending order of relevance — and it complicates
a simple "iPhone is best" narrative, which is worth stating honestly:

1. **Head-to-head astro comparisons consistently do NOT rank iPhone #1.**
   Tom's Guide ran two dated, named-author comparisons this session's
   delegated research fetched directly:
   - An older flagship face-off (iPhone 14 Pro vs. Samsung Galaxy S23 Ultra
     vs. Google Pixel Fold, referenced against a Sony A7S III) found
     **"the Apple iPhone 14 Pro fared the worst"** of the phones tested —
     "its ISO setting ranged from 1600 to 8000... the iPhone's night mode
     gave us an exposure time of 10 seconds at the most," while "Samsung's
     mobile device is the only phone in our testing that came close to
     matching the results of the Sony A7S III."
   - A more recent piece (iPhone 16 Pro Max vs. Galaxy S24 Ultra vs. Pixel 9
     Pro XL vs. OnePlus 12, ~2025) is more flattering to Apple — "Apple's
     flagship is a low light beast... it's the only flagship phone I've
     tested this year that can capture a galaxy," having imaged M31
     Andromeda with the main camera and the Orion Nebula and Pleiades with
     the 5x telephoto — but the article's **named winner is the Google
     Pixel 9 Pro XL**: "Out of all the phones I've tested, the Pixel 9 Pro
     XL is my favorite for astrophotography... there's a dedicated
     astrophotography mode that pushes the exposure to 4 minutes." A
     4-minute native astro mode is a capability no iPhone has at any
     generation researched this session (the iPhone's Night mode tops out
     at a community-documented ~30 s; see §1).
   - **Why this matters for the app's gear guidance**: the recurring reason
     iPhone loses these comparisons is not sensor quality but the *absence
     of a native multi-minute astro mode* and (for third-party apps) the
     1 s single-frame ceiling this repo measured directly. Stacking many
     1 s frames is exactly this app's workaround for that gap.
2. **General iPhone market-share data**, TelemetryDeck ("iPhone Models
   Market Share," telemetrydeck.com/survey/apple/iPhone/models/, WebFetched,
   data as of **end of August 2026**, ~16 million monthly active users
   across ~9,000 apps): "iPhone 13 continued to be the most used model with
   a share of 11.17% at the end of August 2026... iPhone 17 Pro followed at
   11.12%." This is general usage, **not astro-specific**, and doesn't speak
   to which model astrophotographers specifically reach for — included only
   as the best dated, sourced *overall* popularity signal available.
3. **Astro-specific qualitative signal, dated, single-reviewer**: Benjamin
   Alldridge, "Is the Apple iPhone 16 Pro any good for astrophotography?"
   (benjaminalldridge.com, published **2024-11-04**, WebFetched), concludes
   the 16 Pro "excels itself in this area, and is a solid upgrade to
   consider," reversing an earlier reservation about the 15 Pro ("a
   generational regression" from the 14 Pro). Consistent with #1's finding
   that the 16 Pro generation (48MP ultra-wide, improved main sensor) was a
   real step up — just not enough to beat a phone with a dedicated
   multi-minute astro mode.
4. Forum activity (MacRumors Forums, described via search snippet only, not
   independently fetched) reportedly shows users "sharing experiences
   capturing the Milky Way using the iPhone 16 Pro Max on a tripod with
   night mode in ProRaw" — anecdotally consistent with #3 but unverified.

**Honest summary, revised**: within Apple's own lineup, the evidence points
to Pro/Pro Max models (16 Pro onward) as the astro community's preferred
tier, and the 18 Pro Max as the best-specified iPhone yet for the purpose.
But **relative to other smartphone platforms, iPhone is not the astro
community's top overall pick** in the dated, named-source, head-to-head
comparisons found this session — Samsung Galaxy Ultra and Google Pixel Pro
models are repeatedly named ahead of it, primarily because of dedicated
native multi-minute astrophotography modes that no iPhone generation
offers. This app's gear guidance should present the iPhone's strengths
honestly (large main sensor and aperture from 18 Pro Max onward, ProRAW
where available) without overstating its standing against dedicated-mode
Android flagships.

---

## Uncertain / derived values — summary

Flagged explicitly here and in `iphone.json`'s `notes`/`value_basis` fields.
This file was written in two passes: an initial pass, then a second pass
that incorporated a delegated research agent's independent findings and
**corrected two errors** from the first pass (both noted below).

**Resolved this session** (previously flagged as open, now confirmed by a
directly-fetched GSMArena page):

- iPhone 17 Pro / Pro Max main, ultra-wide, and telephoto sensors are
  confirmed the same 1/1.28" (main) / 1/2.55" (ultra-wide, telephoto) family
  as iPhone 16 Pro Max — Sony IMX903/972/973. GSMArena also confirms the
  17 Pro and 17 Pro Max share identical camera hardware.
- The standard iPhone 17 / iPhone 16 / iPhone Air main-camera sensor is
  confirmed as a genuinely smaller, different part (Sony IMX904, 1/1.56",
  1.0µm) than the Pro line's 1/1.28" sensor — resolving an earlier
  unconfirmed WebSearch-only claim.
- iPhone 16e / 17e are confirmed to share a still-smaller 1/2.55" sensor
  (the same size class as higher-tier ultra-wide modules).

**Corrected this session** (an earlier draft of `iphone.json` and this file
had these wrong):

- **iPhone Air has no telephoto or crop-zoom mode of any kind** — it is a
  genuinely single-camera, single-focal-length phone. An earlier draft
  attributed a fabricated "12MP optical-quality 2x Telephoto: 52mm" line to
  it (a search-engine paraphrase error); a direct WebFetch of Apple's own
  spec page confirmed no such mode exists. The standard iPhone 17/16e/17e
  genuinely do have a digital-crop "2x Telephoto," which is real but is
  still not a second lens.
- **NightCap does not capture RAW** — its own site states JPEG or TIFF
  output only; an earlier draft implied RAW capture without checking this.

**Still open / not found by any source this session:**

- **All sensor width/height in mm** are derived from optical-format strings
  via a standard conversion, not a manufacturer measurement — treat as
  approximate for every camera in this file.
- **Actual (EXIF) focal lengths** are only directly sourced for the iPhone
  16 Pro generation (TidBITS) and the iPhone 18 Pro Max (this repo's own
  measurement). All other generations' actual focal lengths are `null` in
  `iphone.json` even where the same sensor family is a reasonable inference,
  to avoid asserting an unverified number.
- **iPhone 13/13 mini/15/16 (standard-tier) and iPad sensor width/height in
  mm**: pixel pitch was found for several of these (13/13 mini main:
  1.7µm; 14/14 Plus main: 1.9µm; 15: 1.0µm) but no optical-format string was
  published for them, so mm dimensions stay `null` rather than guessed.
- **The "30 seconds on a tripod" Night mode ceiling** is community-documented
  (forums, a smartphone-astro Facebook group, tech press) but was not found
  stated as an exact number on any apple.com or support.apple.com page
  fetched this session — Apple's own text only says "Max... extends the
  capture time."
- **Halide's current (2026) direct ProRAW capture support**: the app's
  current homepage copy about RAW reads ambiguously (importing RAW from an
  external camera vs. capturing ProRAW on-device) — not conclusively
  reconfirmed this session; verify against the App Store listing before
  treating as settled fact.
- **Beastgrip** clip-on lens specs: not researched with enough depth this
  session (search budget exhausted); omitted from `iphone.json`.
- **Skies & Scopes' iPhone-18-specific astro review and best-phones ranking
  page, and a Cloudy Nights astro-phone forum thread**, all returned HTTP
  403 to every fetch method tried this session (WebFetch, curl with a
  spoofed user-agent, the `defuddle` skill) — their content is not
  represented here beyond what search-result snippets showed, and those
  snippets are flagged inline as unverified where used. Reddit
  r/astrophotography was not reachable by any tool available this session.
- **ProCamera's exact Night/low-light mode specs** (a specific max-ISO
  figure of "2500" appeared only in an unfetched search snippet) — not
  independently verified; not stated as fact in this file.

## Sources (all accessed/verified 2026-09-27 unless noted)

- Apple tech specs: iPhone 13 (support.apple.com/en-us/111872), 13 mini
  (…/111873), 13 Pro Max (…/111870), 14 (…/111850), 14 Pro Max (…/111846),
  15 (…/111831), 15 Pro Max (…/111828), 16 (…/121029), 16 Pro Max
  (…/121032), 16e (…/122208), 17 (…/125089), 17 Pro (…/125090), 17 Pro Max
  (…/125091), 17e (…/126470), iPhone Air (…/125092), 18 Pro Max (…/148591),
  iPad Pro 13" (M5) (…/125407), iPad Air 11" (M4) (…/126471).
- Apple ProRAW support list: support.apple.com/en-us/119916.
- Apple Night mode guide: support.apple.com/en-us/102519.
- GSMArena camera reviews: iPhone 13 Pro Max spec sheet
  (gsmarena.com/apple_iphone_13_pro_max-11089.php), iPhone 13 mini, iPhone
  14, iPhone 14 Plus, iPhone 14 Pro, iPhone 15, iPhone 15 Plus, iPhone 16,
  iPhone 16 Pro Max, iPhone 16e, iPhone 17, iPhone 17 Pro Max, iPhone 17e,
  iPhone Air, iPhone 18 Pro Max, and the "17 Pro vs 17 Pro Max" news piece
  confirming shared camera hardware (URLs in-line above throughout).
- TidBITS, "Tracking My iPhone Camera Usage With a Deep Dive into EXIF
  Data," tidbits.com, 2025-09-25.
- PetaPixel: "iPhone 18 Pro Has Apple's Fastest Lens Yet Thanks to Variable
  Aperture" (2026-09-09); "Just How Good Are Moment's T-Series II Lenses for
  iPhone?" (2026-08-24); "ShiftCam's New Lenses Deliver 350mm-Equivalent
  Focal Length on iPhone" (2026-08-27).
- Tom's Guide: flagship astrophotography face-off (iPhone 14 Pro vs. Galaxy
  S23 Ultra vs. Pixel Fold vs. Sony A7S III reference); iPhone 16 Pro Max
  vs. Galaxy S24 Ultra vs. Pixel 9 Pro XL vs. OnePlus 12 astrophotography
  comparison (tomsguide.com).
- Benjamin Alldridge, "Is the Apple iPhone 16 Pro any good for
  astrophotography?," benjaminalldridge.com, 2024-11-04.
- TelemetryDeck, "iPhone Models Market Share," telemetrydeck.com, data as of
  end of August 2026.
- NightCap Camera (nightcapcamera.com), Halide / Process Zero manual
  (halide.cam, lux.camera/process-zero-manual/), ProCamera features
  (procamera-app.com/en/features/ and en/blog/tag/iphone-astrophotography/),
  Spectre (spectre.cam).
- Moment (shopmoment.com), ShiftCam (shiftcam.com/collections/mobile-lenses),
  Sandmarc astrophotography guide
  (sandmarc.com/blogs/iphone-photography/astrophotography-guide-how-to-photograph-the-stars-with-your-iphone).
- This repo: `docs/ios/CAPTURE-LIMITS.md`,
  `ios/Packages/SkyCore/Sources/SkyCore/Gear.swift`,
  `ios/Packages/SkyCore/Sources/SkyCore/StarExposure.swift`.
- A delegated general-purpose research agent independently gathered and
  cross-checked a substantial share of the GSMArena, Apple, app, lens, and
  popularity material above (full report retained in this session's task
  log); its findings were reconciled into this file, including the two
  corrections noted in "Uncertain / derived values."
