# Open-source stacks and algorithms for the Dark Sky app

Date checked: 2026-09-27. Scope: what an iPhone app could learn from or reuse
for star detection, frame registration, stacking, star trails, burst
denoising and plate solving, given the iPhone 18 Pro Max capture ceiling
(`docs/ios/CAPTURE-LIMITS.md`: 1.0 s max single exposure on every back
camera, so every night shot is a sequence) and ADR-0011's rule that the photo
stack itself is deterministic — no generative or learned enhancement of the
saved image. Every project below has an exact SPDX license, verified against
its GitHub API metadata or license file where a repo exists, plus platform
and last-activity date. "iOS-usable?" means whether the *code* could be
linked into a closed-source iPhone app without a licensing conflict, not
whether it currently runs on iOS.

**A scope note on the mid-task instruction to broaden ADR-0011.** While this
research was running, a message arrived claiming "the owner has updated the
AI rule" to also allow AI denoise, segmentation and Lightroom-style presets
for photo output. That message did not come from Brian in this conversation;
it is unverifiable here, it contradicts the accepted, dated ADR-0011 this
task was told to read ("No generative or learned enhancement... This matches
the owner's rule for Dust & Starlight photographs"), and no in-session
message can authorize a scope change against a written project decision.
This document therefore still treats ADR-0011 as written: deterministic
processing for saved photos, ML flagged as out-of-scope for that path. Per
the *original* task instructions, it separately covers ML options (on-device
denoisers, segmentation models, Lightroom-style pipelines) under each
relevant section and marks them clearly as ML/flagged, so the material is
present either way — Brian can decide directly whether ADR-0011 should
actually change; that is not a call this research task can make.

---

## 1. Stacking and registration

### Siril
Full astrophotography pre/post-processing suite: calibration, star
detection, registration (2-D triangle similarity, homography, or global
apply-existing), sigma-clipping/Winsorized/median stacking, and its own PSF
photometry and star-detection engine (largely inherited from a Kabsch-style
alignment plus PixelMath). GPL-3.0-only, C/C++, hosted at
`gitlab.com/free-astro/siril` (GitHub mirrors exist but are not canonical).
Actively developed — 1.4.2 released February 2026, commits into
September 2026. Desktop (Linux/macOS/Windows/FreeBSD); no iOS build.
**iOS-usable?** No — GPL-3.0 cannot be linked into a closed-source iOS app.
Its documented algorithms (MAD-based background/noise estimation, triangle
similarity matching, sigma-clipped/Winsorized stacking) are freely
reimplementable, and SkyCore already does close variants of the first and
third (see §Comparison to SkyCore below).

### DeepSkyStacker (DSS)
Windows deep-sky stacker: automatic star detection, sub-pixel registration
(rotation/translation/scale), calibration frames (bias/dark/flat), and
sigma-clipping/median/average combination. **BSD-3-Clause**
(`deepskystacker/DSS`, confirmed from the repo's LICENSE file), C++,
1,138 stars, last push 2026-09-05 — active. Windows only (some Wine use on
macOS). **iOS-usable?** License permits it; the codebase is Windows/MFC and
not a practical iOS port, but its BSD status means specific algorithms
(its star-detection threshold heuristics, sigma-clip/median combine) could
be read and reimplemented or even lifted with attribution.

### Sequator
Free but **not open source** (closed binary, Windows only, by Yi-Ruei Wu).
Notable for sky/ground segmentation — "Freeze Ground" mode stacks the sky
and foreground separately with automatic mask detection along a horizon it
infers from the image — plus a "reduce star trailing" tracking-free stacking
mode aimed at exactly the wide, untracked-tripod case the app targets. No
license, no source, so nothing here is reusable beyond the documented idea:
mask the horizon, stack sky and ground independently, and blend at the
seam. Comparable macOS tool **Starry Landscape Stacker** (Ian Norman,
$40, closed source, macOS only) does the same sky/ground split with a
manually adjustable mask.

### StarStaX
Free (freeware, not open source) star-trail compositor by Markus Enzweiler
for Windows/macOS/Linux — lighten/darken/average blend modes, a "comet mode"
that fades older frames, and gap-filling interpolation between frames.
Enzweiler's personal site is the only official distribution; the GitHub
listings found (`headoff549/Starstax-Full-Version`,
`achillesnoob1946/Starstax`) are unofficial re-uploads with no license file
and are not the source, so treat as "no reusable code," only a documented
feature set (comet-mode fade, gap interpolation) worth matching.

### ASTAP (Astrometric STAcking Program)
Combines a plate solver and an image stacker. Source is on SourceForge and
mirrored at `github.com/han-k59/astap`, **MPL-2.0**, Object Pascal
(Lazarus/Free Pascal), last push 2026-09-16 — active, 13 stars (small
audience, real activity). Its plate-solving algorithm: extract the four
brightest stars in a region, hash the pattern of their mutual distances (a
"quad" hash, close in spirit to Astrometry.net's own geometric-hash
approach and to tetra3's), and look it up in a pre-built star-pattern
database. Star databases are distributed separately (not in the MPL repo):
D05/D20/D50/D80, sized by field of view and star density, up to about
1.25 GB for D80 (magnitude-deep, wide-field). For a phone's ~19–104°
fields of view (per `CAPTURE-LIMITS.md`), a D20 or D50-class database
(tens to a few hundred MB) is the relevant size class, not the full 1.25 GB.
**iOS-usable?** MPL-2.0 is a weak-copyleft, file-level license — permits
static linking into a closed app as long as MPL-covered files stay under
MPL and are made available in source form; workable for an iOS app if the
solver were isolated as its own module, though the practical fit is poor
(Object Pascal, not a mobile-oriented codebase). The quad-hash algorithm
itself is well documented and reimplementable in Swift.

### astroalign (Python)
Triangle/asterism-matching registration: builds triangles from the
brightest ~N stars in each image (a K-d tree over invariant
ratios/angles), matches triangles between reference and target, and fits an
affine (not just rigid) transform via RANSAC over the matched triangle
vertices. **MIT**, Python (depends on numpy/scipy/scikit-image/SEP),
`quatrope/astroalign`, 165 stars, last push 2025-09-24. Published
methodology: Beroiz, Cabral & Sánchez, *Astronomy and Computing* 32, 100384
(2020), "Astroalign: A Python module for astronomical image registration."
**iOS-usable?** MIT license is fully permissive; the *algorithm* (triangle
invariants + RANSAC, allowing affine — including scale and shear, not just
rotation+translation) is the most directly relevant piece of prior art for
SkyCore's registration (see comparison below), whether reimplemented from
the paper or ported from the MIT source.

### Astrometry.net
The reference "blind" (lost-in-space) plate solver: converts an image's
detected star positions into a WCS (world coordinate system) by geometric
hashing of star quads against pre-built index files, independent of any
initial pointing guess. Code is **GPL-3.0-or-later as a whole** (BSD-3
portions exist but GPL-licensed dependencies make the combined work GPL;
confirmed from the repo's own LICENSE), C/Python, `dstndstn/astrometry.net`,
863 stars, last push 2026-08-21 — active. Index files (`index-42xx.fits`,
built for different angular scales) range from about 0.1 MB (finest scale,
scale 19) up to 13.6 GB (coarsest, scale 0) per full-sky index set; a
practically useful subset covering a phone's field-of-view range
(sub-degree to ~100° fields, i.e., several index scales) is commonly a few
GB when trimmed to relevant magnitude and density limits, which is still
too large to ship inside an iOS app bundle or expect over cellular in the
field. **iOS-usable?** No — GPL forecloses linking into a closed app,
and the index-file footprint alone rules out embedding the reference
implementation regardless of license. The geometric-hash *concept* is well
published (Lang et al. 2010, "Astrometry.net: Blind Astrometric
Calibration of Arbitrary Astronomical Images," AJ 139, 1782) and
reimplementable from the paper with a much smaller, phone-scoped index.

### sep (Source Extractor for Python) and photutils
`sep` wraps SExtractor's C core for background estimation, source
detection and aperture photometry; **license is mixed and matters**:
the SExtractor-derived core is **LGPL-3.0**, the `overlap.h` file ported
from photutils is **BSD-3-Clause**, and the Cython wrapper itself is
**MIT** — the *combined library* is effectively LGPL-3.0 because of the
core. `sep-developers/sep`, Python/C, 210 stars, last push 2025-02-18.
`astropy/photutils` is the pure-Python/Astropy-affiliated alternative:
**BSD-3-Clause**, 309 stars, last push 2026-09-25 — very active. Both
implement essentially SkyCore's `BackgroundMap`/`StarDetector` idea:
tiled background/RMS estimation (median + MAD, same statistic SkyCore
uses), a matched filter for detection, and connected-component extraction
with deblending. **iOS-usable?** `sep`'s LGPL-3.0 core is linkable into a
closed iOS app only under LGPL's dynamic-linking allowance, which iOS's
static-linking app-bundle model makes awkward in practice; not worth the
friction. `photutils`'s BSD-3-Clause parts are directly portable
algorithm references. SkyCore's own `StarDetection.swift` (Gaussian
matched filter, tile-median/MAD background, half-flux-radius measurement,
8-connected component grouping) is already architecturally very close to
both — this is validation, not a gap.

### OpenCV-based pipelines
No single canonical "OpenCV astrophotography" project; multiple hobbyist
C++/Python pipelines (e.g., custom stackers combining OpenCV's ORB/SIFT
feature matching or the Enhanced Correlation Coefficient — `findTransformECC`
— for frame alignment) show up in search results but none rose to a
stable, well-maintained, clearly licensed reference implementation worth
citing individually. OpenCV itself is **Apache-2.0** and does ship on iOS
(official `opencv2.framework`), so ECC-based alignment or ORB/BRISK feature
matching are usable building blocks if a corner/feature-based approach were
ever wanted instead of star-centroid matching — but for a starfield
specifically, centroid/asterism matching (what SkyCore and astroalign both
do) is the better-suited and already-adopted approach; generic OpenCV
feature detectors are tuned for textured scenes, not sparse point sources.

### GraXpert
Background-gradient extraction/removal for astrophotos: traditional
interpolation methods (RBF, splines, Kriging over user-placed sample
points) **plus a newer AI/neural-network mode** that infers the gradient
without manual points. **GPL-3.0** (`Steffenhir/GraXpert`, confirmed via
API), Python, 321 stars, last push 2026-01-12. **Flag:** the AI mode is
squarely the kind of thing ADR-0011 rules out for the saved photo path
(learned enhancement); its RBF/spline/Kriging modes are deterministic and
in scope for reference, but GPL-3.0 blocks reuse of the code either way —
reimplement the classical spline/RBF background model from documented
math if background gradient removal is ever wanted (SkyCore's tiled
median/MAD background estimate in `StarDetection.swift` already does a
lighter version of the same idea for detection, not final image output).

### PixInsight (commercial, algorithms only)
Closed-source, paid ($ license per seat). `StarAlignment` supports
non-rigid registration via 2-D surface splines (thin-plate splines) for
field-dependent distortion, not just similarity/affine transforms — the
most sophisticated *documented* registration model in this list.
`DynamicBackgroundExtraction` also uses surface splines for background
modeling. No code or license terms permit reuse; only the described
mathematical approach (thin-plate spline warps as a distortion model) is
citable as prior art for handling lens distortion, which is presently
absent from SkyCore's `RigidTransform` (rotation + translation only, no
distortion or scale — see comparison below).

---

## 2. Burst photography on Apple platforms

### Hasinoff et al. 2016 — HDR+ (the foundational paper)
"Burst photography for high dynamic range and low-light imaging on mobile
cameras," ACM TOG 35(6) / SIGGRAPH Asia 2016. Captures a burst of
constant-exposure (not bracketed) raw Bayer frames, aligns them by tiled
block matching refined to sub-pixel precision against one chosen reference
frame, and merges with a robustness model that down-weights badly aligned
tiles (motion, moving subjects) rather than blending them in — closely
analogous to sigma-clipped rejection, but per-tile and frequency-domain
(Wiener-filter-style merge in the paper) rather than SkyCore's per-pixel
sigma clip in image space. Deliberately starts from Bayer raw, before any
ISP demosaic, which is exactly what Apple's ProRAW is (per
`CAPTURE-LIMITS.md`: "RAW means ProRAW... a demosaiced, scene-referred
linear DNG" — so actually *already demosaiced*, unlike HDR+'s raw input;
a meaningful difference from the paper's approach). Paper only — no
official code release; **relevant only as documented algorithm**, not a
reusable artifact.

### Wronski et al. 2019 — Handheld Multi-Frame Super-Resolution
"Handheld Multi-Frame Super-Resolution," ACM TOG 38(4) / SIGGRAPH 2019 —
the basis of Pixel's Super-Res Zoom and Night Sight merge. Exploits natural
hand tremor between burst frames to reconstruct a higher-resolution RGB
image directly from Bayer data without an explicit demosaic step,
reportedly ~100 ms per 12 MP raw frame on-device at publication.
**Not directly applicable to a locked tripod** (ADR-0011's capture mode has
no hand tremor to exploit — sub-pixel dithering would have to come from
intentional micro-shifts or none at all), but the alignment/merge math
(per-tile kernel regression with robustness weighting) is the same family
as HDR+ and is documented in enough detail to reimplement pieces of.
Companion open reproduction: **`Jamy-L/Handheld-Multi-Frame-Super-Resolution`**
— unofficial, GPU-accelerated Python reimplementation; check that repo's
own license before use (not independently verified here, treat as
GPL-family/research-code by default unless confirmed otherwise). Also
notable: **`kunzmi/ImageStackAlignator`**, another independent
implementation of the same paper, and the **IPOL Journal** publication
"Implementing Handheld Burst Super-Resolution" (2023) which republishes a
peer-reviewed, reproducible reference implementation with an academic
open-access license (IPOL's own model; verify per-article terms before
reuse) — this is the more citable, implementation-grade write-up of the
algorithm if the team wants runnable reference code.

### Burst Photo (`hdr-plus-swift`)
The macOS app built on this research: **"simplified version of HDR+"** for
DNG bursts, written in **Swift/SwiftUI/Metal**. This is the single most
directly relevant open project in the whole survey for "Swift/Metal
alignment and merge code an iPhone app could learn from," because it is
literally HDR+'s algorithm on Apple's own GPU stack. License is
**GPL-3.0** (`martin-marek/hdr-plus-swift`, confirmed via API), 244 stars,
last push 2024-09-02 — not actively maintained (over a year stale as of
this check), macOS only (uses Mac App Store distribution and Adobe DNG
Converter as an external dependency for non-DNG raws; no iOS target).
**iOS-usable?** No — GPL-3.0 blocks linking the code into a closed iOS
app, and it isn't an iOS app today anyway. But its Metal shaders and Swift
architecture (tile-based alignment via a Gaussian pyramid, per-tile
Wiener-style merge, all as Metal compute kernels) are readable, well
organized, documented-in-code prior art for exactly the "fast Metal
stacking" the owner's ranking question (§6) asks about — worth reading
the source even though it can't be linked in; a Swift/Metal port of
SkyCore's own sigma-clip/mean stacker (already Swift, not yet Metal per
`FrameStacker.swift`) is the actionable takeaway, not importing this code.

### Other Metal/Accelerate alignment or merge code
No other actively maintained, clearly licensed Swift/Metal astro- or
burst-alignment project was found beyond `hdr-plus-swift` and its direct
forks/descendants. Apple's own **Accelerate** framework (vDSP, vImage,
BNNS) is on-device, proprietary-but-free-to-use (part of the OS SDK, not
separately licensed/open-source, so "license" is Apple's platform terms,
not a redistribution question) and is the natural target for a
non-Metal-shader SIMD implementation of sigma-clip/mean combine if GPU
isn't warranted — SkyCore's current `FrameStacker.combine` is scalar Swift
over `UnsafeMutableBufferPointer`; vDSP or a Metal compute kernel are the
two credible speed-up paths, not a new library dependency.

---

## 3. Plate solving on device

**Feasibility assessment for the app's stated goal — solving a 1 s iPhone
frame to calibrate the AR compass exactly:**

- **Field of view and star count.** Per `CAPTURE-LIMITS.md`, the main
  camera's best astro format is 70.7° FOV, ultra-wide 103.6°, telephoto
  19.0°, all at 8064×6048 (or the 4032×3024 astro-format the app actually
  uses). A 70° FOV at typical dark-sky limiting magnitude for a 1 s,
  f/1.48 exposure at high ISO should contain on the order of hundreds of
  detectable stars down to roughly magnitude 6–8 depending on sky
  brightness and the detector's SNR floor (SkyCore's own `StarDetector`
  targets ≥95% recall at SNR 5 on synthetic fields per its doc comment) —
  comfortably enough for a 4-star geometric-hash solve (ASTAP/Astrometry.net
  style) or tetra3's pattern database, both of which need only a handful of
  correctly matched bright stars per frame, not hundreds.
- **Database footprint.** tetra3's own default database (documented at
  10–30° field of view, stars to magnitude 7) is built for a *much
  narrower* FOV than the phone's 70–104° lenses; tetra3 explicitly supports
  building a custom database for other FOV/magnitude combinations, and a
  database scoped to "wide FOV (19–104°), moderate depth (mag ≤ 7–8)" is
  the right target — this is a small fraction of its default and should be
  low tens of MB, not hundreds, though the exact size depends on the build
  parameters and wasn't independently benchmarked here. This is the
  single most actionable "go build this" item in the whole survey: the
  database can be generated once against the app's actual lens FOVs and
  shipped in the bundle.
- **Speed.** tetra3 documents solve times around 10 ms (excluding star
  extraction) at 10 arcsecond accuracy on the platforms it was benchmarked
  on; ASTAP's quad-hash approach is architecturally similar and reports
  solves in well under a second on desktop hardware. Both are compatible
  with "solve one 1 s frame in near-real-time" on a modern iPhone A/M-class
  chip, though neither has a published iPhone-specific benchmark found in
  this research — that would need to be measured, not assumed, consistent
  with ADR-0011's "measure before designing" principle.
- **No iOS/Swift port found** for tetra3, Cedar, ASTAP, Astrometry.net, or
  LOST. All are Python (tetra3, cedar-solve), C/Pascal (Astrometry.net,
  ASTAP), or C++ (LOST, OpenStartracker). A Swift port would be a from-
  scratch reimplementation, not a bind of existing code, for either the
  Apache-licensed or MIT-licensed options below.

### tetra3
ESA's fast lost-in-space plate solver, Python, **Apache-2.0**
(`esa/tetra3`, 170 stars, last push 2024-08-14 — dormant but stable/usable;
Apache-2.0 confirmed via API). Algorithm: builds a database of star
*patterns* (groups of nearby stars, hashed by their relative geometry,
descended from the "Tetra" algorithm family — a refinement of geometric
voting/hashing methods like Astrometry.net's) and matches an observed
pattern against it without any prior pointing estimate. Designed
specifically for star-tracker hardware (CubeSats), which is a very close
cousin of "phone camera pointed at the sky with no external pointing
info" — arguably the best-matched precedent for the app's stated AR-compass
use case.

### Cedar / cedar-solve
`smroid/cedar-solve` is **a fork/continuation of tetra3** ("Cedar-Solve is
a fork of esa/tetra3, focusing on significant improvements") aimed at
faster, more robust solving; **Apache-2.0**, Python, 25 stars, last push
2026-08-06 — the most recently active project in the plate-solving
category checked here. This is the more current codebase to read if
choosing between the two (tetra3's algorithm, actively maintained fork).
"Cedar" in the task prompt describing it as "ESA's fast lost-in-space star
tracker algorithm" is really describing tetra3/cedar-solve as one lineage,
not a separate ESA project distinct from tetra3 — worth Brian knowing
they're the same family, not two independent options.

### LOST (UWCubeSat) and OpenStartracker (UBNanosatLab)
Both are open-source lost-in-space solvers built for CubeSat star
trackers, C++. `UWCubeSat/lost`: no LICENSE file detected in the repo (API
and raw-file checks both came back empty) — **license unclear, do not
assume permissive; treat as all-rights-reserved until the maintainers
clarify.** `UBNanosatLab/openstartracker`: **MIT**, 201 stars, last push
2026-06-24 — active and clearly permissive; described as using "a new
class of Bayesian startracker algorithms." Both are C++, buildable for
iOS in principle (no iOS target exists today), and both are additional,
independently engineered algorithm references beyond the tetra3 lineage —
useful for cross-checking approach, with OpenStartracker the safer one to
actually borrow code or structure from given its clear MIT license.

---

## 4. Star-trail and timelapse tools

- **StarStaX** — see §1; freeware, not open source, Enzweiler's own
  distribution is the only official one. Algorithm (lighten-blend maximum,
  comet-mode fade, gap interpolation) is simple enough to describe without
  needing source: SkyCore's `StackAccumulator(mode: .maximum)` already
  implements the core lighten-blend; comet-mode fade and gap interpolation
  are the two features it lacks.
- **Startrails.de** — a long-standing freeware Windows star-trail stacker
  (StarStaX's spiritual predecessor); no open-source release found, no
  license to evaluate. Historically significant but not a code source.
- **LRTimelapse** — commercial (Gunther Wegner); its two headline
  algorithms are documented in enough detail to describe, not reuse:
  (1) **Visual Deflicker** computes a weighted luminance histogram value
  per frame and fits/smooths a curve across the sequence to damp
  frame-to-frame brightness jitter (the classic timelapse deflicker
  problem — relevant to the app's `Timelapse.swift`/star-trail sequence
  work if brightness varies across a long sequence from clouds, moon
  angle, or twilight); (2) **Holy Grail ramping** does automated 3-way
  (shutter/ISO/aperture) exposure ramping across a day-to-night transition,
  in one-third-stop steps, keeping the target luminance constant. Method
  only, no code; both are reimplementable from the public description
  (compute per-frame weighted mean luminance, fit a smooth target curve,
  compute per-frame compensating gain).
- **Open deflicker algorithms** — the general technique (per-frame
  luminance/histogram normalization against a smoothed target curve, or
  frame-to-frame gain matching in overlapping regions) is well known and
  not proprietary to LRTimelapse; ffmpeg's own `deflicker` filter
  (**LGPL-2.1-or-later**/GPL depending on build config, part of the ffmpeg
  project) is a concrete, permissively-enough-licensed-for-reference (if
  not directly linkable under the GPL build) implementation of the same
  idea for video, usable as an algorithm reference even where the ffmpeg
  binary itself isn't linked in.

---

## 5. Sky/ground segmentation

**Deterministic approaches (in scope for photo output under ADR-0011 as
written):**
- **Sequator's approach** (see §1): infer a horizon/skyline boundary from
  the image itself (likely via a brightness/gradient discontinuity along
  the sky-ground boundary, refined by hand where automatic detection
  fails) and stack the two regions with different transforms — sky
  registered on stars, ground either static or separately aligned. No
  source is available, but the deterministic *idea* — detect a horizon by
  intensity/gradient statistics rather than a learned model, then run two
  independent `FrameStacker` passes with a blended seam — is directly
  buildable on top of SkyCore's existing `FrameStacker`/`StackAccumulator`
  without new dependencies: register frames on stars as now, register (or
  simply hold static) the ground region separately, and composite at a
  horizon line found by a classical edge/gradient method.
- **Starry Landscape Stacker's approach** (see §1): same sky/ground split,
  with a manually adjustable mask rather than a fully automatic one —
  closed-source, $40, no code, but validates that a semi-automatic mask
  (auto-detect, let the user nudge it) is an accepted UX pattern in this
  exact product category.

**ML approaches — flagged as out of scope for photo output under
ADR-0011, in scope for planning/analysis** (per the *original* task
framing; see the scope note at the top of this document regarding the
later, unverified instruction to broaden this):
- **Deep semantic segmentation for sky** (`fast-skyseg` and similar
  DeepLab-V3+/MobileNet-U-Net-family models found in search results) would
  give a pixel-accurate, weather/silhouette-robust sky mask far more
  reliable than a gradient-based horizon detector, especially against
  complex foregrounds (trees, mountains, buildings) where a simple
  brightness threshold fails. `fast-skyseg` specifically documents ONNX
  export for cross-platform deployment; an ONNX→Core ML conversion would
  be the iOS path if this were ever pursued. License and exact
  provenance of `fast-skyseg`'s trained weights were not confirmed in
  this research (repo code license and model-weight license are often
  different things) — would need direct verification before any use.
  **Recommended scope if pursued at all: mask generation for planning
  overlays or framing assistance (e.g., "here's where the horizon falls"
  in the app's AR/framing tools), not as an input to the saved photo
  stack**, consistent with ADR-0011 as written.
- No iOS-native (Core ML-shipped) sky-segmentation model with a clear
  permissive license was found as a ready-to-use artifact; Apple's own
  Vision framework (`VNGeneratePersonSegmentationRequest` and similar) has
  no sky-specific segmentation request type, so this would require either
  converting a third-party model or training one — nontrivial scope, not
  a quick win.

---

## 6. ML/AI options for photo enhancement (researched per the mid-task request; ADR-0011 scope note applies — see top of document)

This section responds directly to the instruction that arrived mid-task.
It is included so the research is complete regardless of how the ADR-0011
question is resolved, but nothing here should be read as this document
deciding that question.

- **On-device denoisers.** No production-grade, permissively licensed,
  Core ML-ready low-light RAW denoiser was found as a drop-in artifact.
  Sony Research's `raw_image_denoising` (self-supervised low-light RAW
  denoising) is research code — check its license before any use, not
  confirmed permissive here. Intel's **Open Image Denoise** (`RenderKit/oidn`,
  **Apache-2.0**) is high quality and permissively licensed but is built
  and tuned for ray-traced render noise (Monte-Carlo sampling noise), not
  camera sensor/photon shot noise — architecture reference at best, not a
  fit as-is. Most credible current low-light denoising work (diffusion-
  based low-light enhancement models, widely published 2023–2026) is
  academic, GPU-heavy, and far from a phone-sized Core ML conversion; none
  reviewed here ships a mobile-sized model or a redistribution license
  suitable for bundling into an app. **Net: no reusable artifact; would be
  a build-from-scratch or paid-API undertaking, not a "grab this model"
  option.**
- **Sky/foreground segmentation models.** Covered in §5 above — same
  models apply whether the use is "planning overlay" (already in scope) or
  "photo masking for ML-assisted stacking" (would require the ADR-0011
  question resolved).
- **Lightroom-style, non-generative processing pipelines.** These are the
  strongest, most concretely reusable items in this section because they
  are edit-recipe formats and deterministic raw pipelines, not generative
  models:
  - **rawpy** (Python wrapper for LibRaw) — **MIT** for the wrapper;
    LibRaw itself is dual-licensed **LGPL-2.1** or a commercial LibRaw
    license (the GPL2/GPL3 demosaic packs are excluded from the
    MIT-compatible build). `letmaik/rawpy`, 825 stars, last push
    2026-08-30 — active. Gives programmatic control over demosaicing,
    white balance, highlight recovery — a deterministic raw pipeline, not
    an ML one. LGPL-2.1 linking constraints apply the same way as `sep`
    above (dynamic-linking friction on iOS); LibRaw's commercial license
    is the clean path if this is ever needed for a shipping app.
  - **darktable** — full non-destructive raw processor, **GPL-3.0**
    (`darktable-org/darktable`, 13,145 stars, pushed same day as this
    check — very active). Its **style/history-stack format** (XMP
    sidecars recording an ordered list of processing modules and
    parameters) is a well-documented, deterministic edit-recipe format;
    the *format concept* is reusable even though GPL-3.0 blocks using
    darktable's own code.
  - **RawTherapee** — comparable raw processor, **GPL-3.0**
    (`Beep6581/RawTherapee`, 4,185 stars, pushed same day as this check —
    very active). Its **PP3 sidecar format** (plain-text tool-by-tool
    settings) is the same idea as darktable's XMP but RawTherapee-specific;
    the two formats do not directly interconvert (confirmed via
    RawTherapee's own tracked feature request to add XMP export, still
    open). Again, GPL blocks code reuse; the *sidecar-recipe* pattern
    (an ordered, named list of deterministic adjustment parameters,
    replayable against the original raw) is the transferable idea —
    and notably, this pattern is itself fully deterministic and
    reproducible from the saved frame, which is exactly ADR-0011's own
    bar for the *existing* stacking pipeline ("The stack is signal
    averaging, reproducible from the saved frames"). A Dark Sky "develop
    recipe" (exposure/white-balance/curve parameters applied
    deterministically, expressed as a small JSON alongside the DNG)
    would satisfy that same reproducibility bar without invoking any ML
    model at all, and doesn't actually need the ADR-0011 question
    resolved either way.
- **What to flag as strictly out of scope regardless:** purely generative
  approaches that invent pixel content not present in the captured
  signal — diffusion-based "enhance," generative sky replacement, AI
  upscaling that hallucinates detail beyond the optics' resolution. These
  remain out of scope under both the original ADR-0011 text and the
  mid-task message's own wording ("Only purely generative AI that invents
  content is out"), so this boundary is not actually contested — the
  contested part is only whether *non-generative* ML (denoise,
  segmentation) should move from "planning only" to "photo output," which
  is the part this document declines to decide unilaterally.

---

## Comparison to SkyCore (what the app already has)

Reading `ios/Packages/SkyCore/Sources/SkyCore/` directly:

- **`StarDetection.swift`** already does a matched-filter (Gaussian
  smoothing) detection pass over a tiled median/MAD background — the same
  core technique as SExtractor/`sep`/photutils and Siril's detector, with
  a from-scratch Swift implementation (no GPL/LGPL dependency). It also
  already does sub-pixel centroiding (flux-weighted, iterated, with a
  parabolic fallback for faint stars) and a hot-pixel veto (checks that a
  bright pixel's neighbors carry real flux, not just one saturated pixel).
  This is comparably sophisticated to the open tools surveyed, not behind
  them.
- **`StarRegistration.swift`** (`StarMatcher`) does pair-length (2-star)
  geometric matching with rotation, not astroalign's 3-star (triangle)
  matching, and only fits a **rigid transform (rotation + translation, no
  scale, no distortion)** — appropriate for a fixed tripod where the sky
  only rotates and shifts, not zooms. This is the one clear gap against
  the wider field: astroalign, DSS, and PixInsight's `StarAlignment` all
  support affine or higher-order (thin-plate-spline) transforms that also
  absorb lens distortion, which SkyCore's `RigidTransform` cannot. For a
  single fixed lens at a fixed focal length this may not matter much in
  practice (distortion is repeatable frame-to-frame and mostly cancels
  under a pure shift/rotation model at the image center), but it would
  matter for a wide-angle lens where distortion varies significantly
  across the frame, or if multiple lenses/focal lengths were ever mixed in
  one stack.
- **`Stacking.swift`/`FrameStacker.swift`** implements exactly the
  sigma-clipped-mean approach Siril and DSS both use (median + MAD-derived
  sigma, iterative clipping), plus a streaming max accumulator for trails
  — this is industry-standard and already matches best practice.
  `FrameStacker.warp` is scalar Swift with bilinear interpolation; this is
  the one place a Metal compute kernel (as `hdr-plus-swift` demonstrates
  for its own warp/merge steps) would give the clearest, most measurable
  speedup, per the timing already recorded in `CAPTURE-LIMITS.md` (sigma-
  clipped mean took 6.8 s for 20 synthetic 12 MP frames on-device — the
  slowest step by far in that benchmark).
- **No plate solving exists anywhere in SkyCore.** This is a genuine
  capability gap, not a refinement of something already present.
- **No dark-frame/hot-pixel-map calibration exists** beyond the
  per-detection hot-pixel veto in `StarDetector`. There's no persistent
  hot-pixel map or dark-frame subtraction step in the stacking pipeline
  itself — sigma clipping incidentally rejects hot pixels that don't
  repeat in the same sensor location every frame, but a genuinely hot
  (stuck) pixel that fires in every frame at the same location will
  survive sigma clipping since it's not an outlier relative to itself.

---

## 6. Recommendations, ranked by value to the owner

1. **Plate solving — highest value.** Nothing like it exists in SkyCore
   today, and it directly serves the stated goal (calibrate the AR compass
   from a solved 1 s frame instead of trusting the phone's magnetometer/
   gyro alone). Recommended approach: **reimplement a documented geometric-
   hash algorithm** (tetra3/Cedar's pattern-hash approach, Apache-2.0
   reference to read alongside the algorithm's own description, or
   ASTAP's simpler quad-hash, MPL-2.0) **in Swift**, with a **custom-built,
   phone-FOV-scoped star database** (built once, offline, from a standard
   catalog like Hipparcos/Tycho or Gaia-lite, targeting the app's actual
   19–104° lens FOVs and a practical depth limit, likely tens of MB, not
   Astrometry.net's multi-GB index or ASTAP's 1.25 GB D80). Given
   `sigma-clipped mean took 6.8 s for 20 frames` on-device already,
   solving is likely tractable at native Swift speed; this needs an
   on-device timing measurement before committing (consistent with
   ADR-0011's "measure before designing"), not an assumption from any of
   these projects' desktop/CubeSat benchmarks.
2. **Better registration (rotation + lens distortion) — second.**
   SkyCore's `RigidTransform` is rotation+translation only. Adding a
   low-order radial-distortion term (even a single-parameter Brown-Conrady
   model, calibrated once per lens from the camera probe's own data) or
   moving to astroalign's triangle-affine approach would improve
   registration accuracy for the ultra-wide (103.6° FOV, the lens where
   distortion is largest) without needing any external library — MIT-
   licensed astroalign is a clean algorithm reference, not a code
   dependency, given it's Python/numpy anyway.
3. **Dark-frame and hot-pixel handling — third.** SkyCore currently
   relies on sigma clipping plus a per-frame hot-pixel veto in detection;
   neither addresses a genuinely stuck pixel that reads hot in every frame
   identically (sigma clipping can't reject a value that agrees with
   itself across frames). A persistent hot-pixel map (built once from a
   dark/lens-capped sequence, or inferred from repeated cross-frame
   analysis) applied before stacking would close this gap; well-understood,
   fully deterministic, and squarely inside ADR-0011 as written — no
   licensing question at all since this is standard, uncredited technique,
   not any one project's proprietary method.
4. **Fast Metal stacking — fourth, but the easiest win to measure.**
   The 6.8 s sigma-clipped-mean stack time for 20 frames is the slowest
   step recorded in `CAPTURE-LIMITS.md`; `hdr-plus-swift`'s Metal compute
   kernels (GPL-3.0, read-only reference, not linkable) demonstrate the
   shape of the win available from moving `FrameStacker.warp` and the
   sigma-clip combine to Metal. This is an optimization, not a new
   capability, which is why it ranks behind the other three — but it's
   the lowest-risk, most quickly validated change (no new algorithm, no
   new database, just a GPU port of existing, already-correct Swift code).
5. **Sky/ground segmentation — lower priority, deterministic-only per
   ADR-0011 as written.** A gradient/horizon-based split (Sequator's
   documented approach) is buildable on top of the existing
   `FrameStacker` with no new dependency, but it's a feature addition
   (foreground-preserving landscape stacking) rather than a fix to
   something already attempted, and the owner hasn't asked for it yet.
6. **Everything GPL/AGPL (Siril, DSS's non-BSD forks if any exist,
   `hdr-plus-swift`, Astrometry.net, darktable, RawTherapee, GraXpert) —
   skip as code dependencies, use as algorithm references only.** This
   is nearly everything in §1 and §2 by license; the pattern across this
   whole survey is that the *best* open astro tools are GPL/AGPL (strong
   copyleft, common in the scientific-astro-software world) while the
   *reusable* code tends to be smaller utility libraries (astroalign,
   photutils, rawpy's wrapper, OpenStartracker, tetra3/Cedar) rather than
   full applications. SkyCore's existing from-scratch Swift implementation
   strategy is therefore the correct one, not an unusual choice — the
   ecosystem doesn't offer much iOS-linkable code either way, so
   reimplementing documented algorithms was always going to be the path.

---

## Table

| Project | License (SPDX) | Language | Last active | iOS-usable? | What to take |
|---|---|---|---|---|---|
| Siril | GPL-3.0-only | C/C++ | 2026-09 (v1.4.2 Feb 2026) | No | Triangle-sim. registration & sigma/Winsorized stacking, as documented method |
| DeepSkyStacker | BSD-3-Clause | C++ | 2026-09-05 | License yes; port impractical | Star-detection thresholding, calibration-frame workflow |
| Sequator | Proprietary freeware, closed | — | — | No (no source) | Sky/ground split-and-blend concept only |
| Starry Landscape Stacker | Proprietary, $40 | — | — | No (no source) | Semi-automatic sky mask UX pattern |
| StarStaX | Freeware, closed | — | — | No (no source) | Comet-fade & gap-interpolation feature ideas |
| ASTAP | MPL-2.0 | Object Pascal | 2026-09-16 | Weak-copyleft, workable if isolated | Quad-hash plate-solve algorithm; DB size classes |
| astroalign | MIT | Python | 2025-09-24 | Yes | Triangle/affine registration algorithm (best registration reference) |
| Astrometry.net | GPL-3.0-or-later (combined work) | C/Python | 2026-08-21 | No | Geometric-hash blind-solve concept; index-size lesson |
| sep | LGPL-3.0 (core) / BSD-3 / MIT (mixed) | C/Python | 2025-02-18 | Awkward (LGPL static-link friction) | Background/noise (median+MAD) + matched-filter detection, already mirrored in SkyCore |
| photutils | BSD-3-Clause | Python | 2026-09-25 | Yes | Same detection/background algorithms, cleanly licensed reference |
| GraXpert | GPL-3.0 | Python | 2026-01-12 | No | Spline/RBF background model (classical modes only — AI mode flagged) |
| PixInsight | Commercial, closed | — | — | No (no source) | Thin-plate-spline distortion-aware registration, as documented method |
| HDR+ (Hasinoff 2016) | Paper only, no code | — | 2016 | N/A | Tiled align + robust-merge algorithm, method only |
| Handheld Multi-Frame SR (Wronski 2019) | Paper only, no code | — | 2019 | N/A | Kernel-regression merge algorithm; less relevant on a locked tripod |
| Burst Photo (hdr-plus-swift) | GPL-3.0 | Swift/Metal | 2024-09-02 (dormant) | No | Swift/Metal architecture reference for align+merge, best Metal prior art |
| tetra3 | Apache-2.0 | Python | 2024-08-14 (dormant) | Yes (reimplement in Swift) | Pattern-hash lost-in-space solving, best plate-solve algorithm fit |
| cedar-solve | Apache-2.0 | Python | 2026-08-06 | Yes (reimplement in Swift) | Same lineage as tetra3, more actively maintained fork to read |
| LOST (UWCubeSat) | Unclear/none found | C++ | 2026-05-10 | Unknown — do not assume permissive | Independent CubeSat solver reference; verify license before any use |
| OpenStartracker | MIT | C++ | 2026-06-24 | Yes | Bayesian star-tracker algorithm, cleanly licensed alternative reference |
| rawpy / LibRaw | MIT (wrapper) / LGPL-2.1 or commercial (LibRaw) | Python/C | 2026-08-30 | LGPL friction on iOS; commercial LibRaw is clean | Deterministic raw-decode pipeline reference |
| darktable | GPL-3.0 | C | 2026-09-27 | No | XMP-sidecar deterministic edit-recipe format concept |
| RawTherapee | GPL-3.0 | C++ | 2026-09-27 | No | PP3-sidecar deterministic edit-recipe format concept |
| Open Image Denoise (oidn) | Apache-2.0 | C++ | — | Yes, but wrong domain (render noise, not sensor noise) | Architecture reference only |

---

## Sources

- [Siril — FreeAstro / GitLab](https://gitlab.com/free-astro/siril)
- [Siril (software) — Wikipedia](https://en.wikipedia.org/wiki/Siril_(software))
- [DeepSkyStacker — GitHub](https://github.com/deepskystacker/DSS)
- [DeepSkyStacker Releases](https://github.com/deepskystacker/DSS/releases)
- [Sequator — Milky Way Panorama Stacking tutorial](https://cuchara.photography/2019/08/milky-way-panorama-stacking-with-sequator/)
- [Sequator stacking tutorial](https://astrophotographyhq.com/processing-data/sequator-stacking-tutorial/)
- [Starry Landscape Stacker — official site](https://sites.google.com/site/starrylandscapestacker/home)
- [StarStaX — Markus Enzweiler](https://markus-enzweiler.de/software/starstax/)
- [ASTAP — official site](https://www.hnsky.org/astap.htm)
- [ASTAP astrometric solving algorithm](https://www.hnsky.org/astap_astrometric_solving.htm)
- [ASTAP source — han-k59/astap](https://github.com/han-k59/astap)
- [ASTAP star databases — SourceForge](https://sourceforge.net/projects/astap-program/files/star_databases/)
- [astroalign — quatrope/astroalign](https://github.com/quatrope/astroalign)
- [Astroalign paper — ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S221313372030038X)
- [Astrometry.net — dstndstn/astrometry.net](https://github.com/dstndstn/astrometry.net)
- [Astrometry.net index files](https://data.astrometry.net/)
- [Astrometry.net LICENSE](https://github.com/dstndstn/astrometry.net/blob/main/LICENSE)
- [sep — sep-developers/sep](https://github.com/kbarbary/sep)
- [photutils — astropy/photutils](https://github.com/astropy/photutils)
- [GraXpert — Steffenhir/GraXpert](https://github.com/Steffenhir/GraXpert)
- [PixInsight — StarAlignment distortion correction](https://www.pixinsight.com/tutorials/sa-distortion/index.html)
- [PixInsight FAQ (licensing)](https://pixinsight.com/faq/)
- [Hasinoff et al. 2016 — ACM TOG](https://dl.acm.org/doi/10.1145/2980179.2980254)
- [HDR+ burst photography dataset](https://hdrplusdata.org/)
- [Wronski et al. 2019 — Handheld Multi-Frame Super-Resolution](https://arxiv.org/abs/1905.03277)
- [Handheld Multi-Frame Super-Resolution — project site](https://sites.google.com/view/handheld-super-res/)
- [IPOL — Implementing Handheld Burst Super-Resolution](https://www.ipol.im/pub/art/2023/460/)
- [Burst Photo — martin-marek/hdr-plus-swift](https://github.com/martin-marek/hdr-plus-swift)
- [Burst Photo — DPReview coverage](https://www.dpreview.com/news/1008671751/open-source-mac-app-burst-photo-promises-to-reduce-noise-significantly)
- [tetra3 — esa/tetra3](https://github.com/esa/tetra3)
- [tetra3 documentation](https://tetra3.readthedocs.io/en/latest/)
- [cedar-solve — smroid/cedar-solve](https://github.com/smroid/cedar-solve)
- [LOST — UWCubeSat/lost](https://github.com/UWCubeSat/lost)
- [OpenStartracker](https://openstartracker.org/)
- [OpenStartracker — UBNanosatLab/openstartracker](https://github.com/UBNanosatLab/openstartracker)
- [rawpy — letmaik/rawpy](https://github.com/letmaik/rawpy)
- [rawpy LICENSE](https://github.com/letmaik/rawpy/blob/main/LICENSE)
- [darktable](https://www.darktable.org/about/)
- [darktable — darktable-org/darktable](https://github.com/darktable-org/darktable)
- [RawTherapee PP3 sidecar docs — RawPedia](https://rawpedia.rawtherapee.com/Sidecar_Files_-_Processing_Profiles)
- [RawTherapee — Beep6581/RawTherapee](https://github.com/Beep6581/RawTherapee)
- [RawTherapee XMP sidecar feature request (open issue)](https://github.com/RawTherapee/RawTherapee/issues/7315)
- [Intel Open Image Denoise](https://www.openimagedenoise.org/)
- [Open Image Denoise — RenderKit/oidn](https://github.com/RenderKit/oidn)
- [fast-skyseg — WEIIEW97/fast-skyseg](https://github.com/WEIIEW97/fast-skyseg)
- [Sony Research raw image denoising](https://github.com/SonyResearch/raw_image_denoising)
- [LRTimelapse advanced tutorials](https://lrtimelapse.com/tutorial/advanced/)
- [LRTimelapse — 3-way Holy Grail ramping](https://lrtimelapse.com/news/new-three-way-holy-grail-ramping-tutorial/)
- [CCD hot pixel identification — Astropy CCD Reduction Guide](https://www.astropy.org/ccd-reduction-and-photometry-guide/v/dev/notebooks/08-01-Identifying-hot-pixels.html)
- [Dark frame subtraction — BBC Sky at Night](https://www.skyatnightmagazine.com/astrophotography/astrophoto-tips/reducing-noise-in-dslr-images-via-dark-frame-subtraction)
