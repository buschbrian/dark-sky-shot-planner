# How far this iPhone can go: capture roadmap

Written 2026-09-27 for the owner's iPhone 18 Pro Max (iOS 27.2). Synthesized
from four research files, `docs/gear/research/iphone-techstack.md`,
`opensource.md`, `iosapps.md` and `actioncams.md`, and grounded in the
measurements in [CAPTURE-LIMITS.md](CAPTURE-LIMITS.md). Decisions this plan
works inside: ADR-0011 (capture is deterministic-first; *amended 2026-09-27*:
non-generative AI is allowed as an optional, labelled step, generative AI is
not) and the repo rule that no GPL/AGPL code is linked into the app.

## The phone's hard limits

These are measured on the owner's phone or documented by Apple. No item below
gets around them; each works within them.

| Limit | Value | Source |
|---|---|---|
| Longest single frame for any third-party app | **1.0 s**, every format, all three back cameras | [CAPTURE-LIMITS.md](CAPTURE-LIMITS.md) |
| RAW | **ProRAW only**, no Bayer RAW. Demosaic is locked in; Deep Fusion can only be avoided at capture (`.speed`); Apple's pipeline cannot be inspected or turned off | CAPTURE-LIMITS.md; [Lux, Understanding ProRAW](https://www.lux.camera/understanding-proraw/) |
| Night mode | **No API.** The Camera app's 10–30 s Night mode is Apple-only; Lux has asked Apple for one | [Halide on X](https://x.com/halidecamera/status/1527728518582239232); [iosapps.md §2](../gear/research/iosapps.md#2-apples-own-night-mode) |
| ISO ceiling (12 MP astro format) | Main 12,320, ultra wide 3,600, telephoto 7,680 | CAPTURE-LIMITS.md |
| Aperture | Main f/1.48, 1.8, 2.8, 4.0; ultra wide f/2.2; telephoto f/2.8 | CAPTURE-LIMITS.md |
| Focus | No infinity value; lens position 0–1 and 1 is not infinity | CAPTURE-LIMITS.md; [Apple forum](https://developer.apple.com/forums/thread/706755) |
| Low-light boost | Not supported on any back camera | CAPTURE-LIMITS.md |
| Memory | 48 MP × 16-bit RGBA ≈ 371 MB per working frame (derived) | [iphone-techstack.md §2](../gear/research/iphone-techstack.md#memory-limits-for-large-frames) |
| Background GPU | Unconfirmed whether Metal runs unthrottled under `BGContinuedProcessingTask` | iphone-techstack.md §2 |

**What that means.** Every long exposure is a sequence of 1 s frames. The
NPF limit for the main camera is 8.6 s, so a single frame never trails; the
ceiling is the phone's, not the sky's. Stacking has no total-time limit, so
the phone can integrate as long as a Pixel's 4-minute astrophotography mode
or longer ([Google AI Blog](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html)),
but each frame adds its own read noise, so 240 frames of 1 s stay noisier
than one 240 s exposure on the same sensor would be (general sensor physics,
not a measurement here). High ISO, where read noise is lowest, and many
frames are the phone's answer. The one place the 1 s ceiling hurts most is
exposure-ramped timelapse (item 14), where a DSLR or GoPro can stretch the
shutter to 15–30 s and the phone can only raise ISO.

## What the app already has

1 s ProRAW sequences with zero-shutter-lag off and timestamps checked; star
detection (matched filter, median/MAD background, hot-pixel veto),
rigid registration (rotation + translation), sigma-clipped mean and a
streaming maximum (`FrameStacker`, `StackAccumulator`); a 5-frame stack in
2.8 s on the phone; a 20-frame 12 MP bench with the sigma clip at 6.8 s
(CAPTURE-LIMITS.md). `opensource.md` finds SkyCore's detection and stacking
on par with Siril, DeepSkyStacker and photutils, and names three real gaps:
**no plate solving, rigid-only registration, and no persistent hot-pixel
map** ([opensource.md, Comparison](../gear/research/opensource.md#comparison-to-skycore-what-the-app-already-has)).

## The plan, ranked

Ranked in build order: value to the owner per unit of effort, with
dependencies first. Effort: **S** days, **M** one to two weeks, **L** longer.
"ML" means a learned model; "generative" means it invents content. Nothing
here is generative.

| # | Item | Phase | Value | Effort | ML |
|---|---|---|---|---|---|
| 1 | Star-trail video | Next | High | S | No |
| 2 | Comet trails | Next | Medium | S | No |
| 3 | Light painting mode | Next | Medium | S | No |
| 4 | Persistent hot-pixel and dark map | Next | High | S | No |
| 5 | Metal port of the stacker | Next | High | M | No |
| 6 | `BGContinuedProcessingTask` stacking | Next | High | M | No |
| 7 | Flatter linear decode via `CIRAWFilter` | Next | Medium | S | No |
| 8 | Camera Control shutter | Next | Medium | S | No |
| 9 | On-device plate solving to calibrate the AR compass | Soon | Very high | L | No |
| 10 | Triangle/affine plus distortion-aware registration | Soon | High | M | No |
| 11 | Sky and foreground stacked separately | Soon | High | M | No (optional ML mask) |
| 12 | Live Activity for sequence progress | Soon | Medium | S–M | No |
| 13 | Optional RAW 9 ML denoise | Soon | Medium | S | Yes, non-generative |
| 14 | Exposure-ramped night timelapse with deflicker | Later | Medium | L | No |
| 15 | LiDAR-assisted foreground focus | Later | Low–medium | M | No |
| 16 | Full 48 MP stacking | Later | Medium | M | No |

### Next

#### 1. Star-trail video

- **What:** while a star-trail sequence runs, snapshot the running maximum
  every N frames and encode the snapshots with `AVAssetWriter` into a video
  of the trails growing, alongside the final still.
- **Why:** it is the output people know from GoPro's Star Trails and
  Insta360's Star Trails Video, and the app already builds the maximum.
- **Evidence:** GoPro "takes a series of photos and stitches them together
  into a video showing the movement of the night sky"; Insta360 documents
  Star Trails Video and Star Trails Photo as separate outputs and keeps the
  raw frames for re-rendering
  ([actioncams.md §1.1, §2.4](../gear/research/actioncams.md#11-night-effects-star-trails)).
  Mapped onto `StackAccumulator(mode: .maximum)`, it is a render step, not a
  new capture capability ([actioncams.md §4](../gear/research/actioncams.md#4-techniques-to-adopt-and-what-avfoundation-cancant-do)).
- **License path:** own code on Apple's AVFoundation.
- **Effort:** S. **Device check:** a 15-minute sequence on the phone
  produces a playable video; memory stays flat.
- **ML:** none.

#### 2. Comet trails

- **What:** a sliding-window maximum over the last N seconds of frames, so
  trails have a fixed length and move (GoPro's Trail Length Short/Long).
  Implement with block maxima (van Herk/Gil-Werman style) so memory is a few
  frames, not N.
- **Why:** a distinct, popular look; the same accumulator with one parameter.
- **Evidence:** GoPro documents Short/Long as "a comet-like trail"; StarStaX
  has a comet mode ([actioncams.md §1.1](../gear/research/actioncams.md#11-night-effects-star-trails);
  [opensource.md §4](../gear/research/opensource.md#4-star-trail-and-timelapse-tools)).
- **License path:** own code; StarStaX is closed freeware, feature idea only.
- **Effort:** S. **Device check:** memory with a 60 s window on 12 MP frames.
- **ML:** none.

#### 3. Light painting mode

- **What:** a preset of the trail pipeline for a moving light: near-field
  manual focus, short duration, no celestial framing.
- **Why:** GoPro's Light Painting and Vehicle Lights come free once star-trail
  video exists: "any light motion is saved as a line."
- **Evidence:** [actioncams.md §1.2](../gear/research/actioncams.md#12-night-effects-light-painting-and-vehicle-light-trails).
- **License path:** own code. **Effort:** S (after item 1).
- **Device check:** a hand-held torch traced in front of the tripod.
- **ML:** none.

#### 4. Persistent hot-pixel and dark map

- **What:** build a hot-pixel map per camera and ISO from a lens-covered
  1 s sequence (or from pixels that stay hot across many sessions), store it,
  and replace those pixels with the neighbour average before registration.
  Offer a "shoot darks" step at the end of a session.
- **Why:** sigma clipping cannot remove a pixel that is hot in every frame
  (it agrees with itself); those survive into the stack today.
- **Evidence:** [opensource.md, Comparison and §6.3](../gear/research/opensource.md#comparison-to-skycore-what-the-app-already-has);
  Pixel's Night Sight finds hot pixels as outliers across space and time and
  fills them from neighbours ([Google AI Blog](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html));
  no iOS app surveyed documents true dark-frame subtraction
  ([iosapps.md §5](../gear/research/iosapps.md#5-gap-analysis)).
- **License path:** standard technique
  ([Astropy CCD guide](https://www.astropy.org/ccd-reduction-and-photometry-guide/v/dev/notebooks/08-01-Identifying-hot-pixels.html)),
  reimplemented in SkyCore.
- **Effort:** S. **Device check:** a capped-lens sequence at ISO 800 and
  12,320; count hot pixels and check they repeat between nights and with
  temperature.
- **ML:** none.

#### 5. Metal port of the stacker

- **What:** move the warp and the sigma-clipped combine from scalar Swift to
  Metal compute (or vDSP where simpler), keeping the Swift version as the
  reference the tests compare against.
- **Why:** the sigma clip is the bottleneck: 6.8 s for 20 frames at 12 MP,
  and it grows with frames and resolution. Faster stacks mean a live preview
  of the stack and make items 6 and 16 practical.
- **Evidence:** [CAPTURE-LIMITS.md](CAPTURE-LIMITS.md) bench;
  [iphone-techstack.md §6.2](../gear/research/iphone-techstack.md#6-recommendations-for-the-dark-sky-app-ranked);
  `hdr-plus-swift` shows tiled align and merge as Metal kernels
  ([opensource.md §2](../gear/research/opensource.md#burst-photo-hdr-plus-swift)).
- **License path:** own code on Metal/MPS/Accelerate. `hdr-plus-swift` is
  GPL-3.0: read for architecture at most, copy nothing.
- **Effort:** M. **Device check:** the `-CaptureBench` run before and after;
  identical output within float tolerance; thermal state over 100 frames.
- **ML:** none.

#### 6. `BGContinuedProcessingTask` stacking

- **What:** submit the stack as a continued-processing task when the user
  starts it, report progress, and let it finish after they leave the screen.
- **Why:** long stacks survive the user switching apps or locking the phone;
  iOS shows its own progress UI.
- **Evidence:** new in iOS 26
  ([Apple docs](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask);
  [WWDC25 session 227](https://developer.apple.com/videos/play/wwdc2025/227/));
  ranked first by [iphone-techstack.md §6.1](../gear/research/iphone-techstack.md#6-recommendations-for-the-dark-sky-app-ranked).
- **License path:** Apple API. **Effort:** M.
- **Device check:** whether Metal runs at full speed in this state is
  unconfirmed: time the same stack foreground vs background.
- **ML:** none.

#### 7. Flatter linear decode via `CIRAWFilter`

- **What:** decode each ProRAW frame with `localToneMapAmount = 0` (and a
  `linearSpaceFilter` if needed) so less of Apple's tone curve is baked in
  before our own averaging.
- **Why:** a cleaner, more linear input for stacking and for later
  development; the one real control an app has over ProRAW after capture.
- **Evidence:** [Apple docs](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount);
  [iphone-techstack.md §2](../gear/research/iphone-techstack.md#core-image-raw-filters-cirawfilter-what-can-be-turned-off).
- **License path:** Apple API. **Effort:** S.
- **Device check:** A/B stacks of the same frames; compare background
  levels and star profiles.
- **ML:** none (this is the classic decoder, not RAW 9).

#### 8. Camera Control shutter

- **What:** an `AVCaptureControl` that starts and stops a sequence (and
  maybe adjusts ISO) from the Camera Control button, in the app.
- **Why:** start a sequence with gloves on, without touching the screen or
  shaking the tripod.
- **Evidence:** [Apple docs](https://developer.apple.com/documentation/avfoundation/avcapturecontrol);
  [WWDC25 session 253](https://developer.apple.com/videos/play/wwdc2025/253/).
  Lock Screen launch would need a separate capture extension; in-app use does not.
- **License path:** Apple API. **Effort:** S.
- **Device check:** the press does not jolt the first frame (compare star
  shapes in frame 1 and frame 5).
- **ML:** none.

### Soon

#### 9. On-device plate solving to calibrate the AR compass

- **What:** detect stars in one 1 s frame, match their pattern against a
  database built offline for the phone's fields of view, and get the exact
  pointing. Feed the solved direction into the existing
  `CalibrationObservation` / `AttitudeCorrection` so the Night AR overlay is
  corrected by the real sky instead of the magnetometer. Also confirm framing
  before a long sequence.
- **Why:** compass error near cars and tripods is the AR's weak point (PLAN
  M7). Nobody surveyed plate-solves inside a capture app: PhotoPills' Night
  AR is compass and gyro only; AstroHelm and StarSense solve for telescopes
  ([iosapps.md §5](../gear/research/iosapps.md#5-gap-analysis)).
- **Evidence:** tetra3 (ESA) solves lost-in-space in about 10 ms after star
  extraction, and cedar-solve is its maintained fork; a 70° field at 1 s
  should hold hundreds of detectable stars, far more than a solve needs
  ([opensource.md §3](../gear/research/opensource.md#3-plate-solving-on-device)).
  SkyCore already bundles the Yale Bright Star Catalogue (8,404 stars
  down to magnitude 6.5), a starting point for a wide-field database.
- **License path:** reimplement the tetra3/cedar-solve pattern-hash method in
  Swift from the Apache-2.0 source and its description; OpenStartracker (MIT)
  as a cross-check. ASTAP (MPL-2.0) and Astrometry.net (GPL) are described
  methods only; no code. Build the database with a script in the repo.
- **Effort:** L. Start with a spike: solve saved frames on the Mac, then time
  it on the phone.
- **Device check:** solve time on the phone; solved azimuth vs a known peak
  and vs the moon; residual after calibration at a dark site.
- **ML:** none; pattern matching is geometry.

#### 10. Triangle/affine plus distortion-aware registration

- **What:** match star triangles (astroalign's invariants) with RANSAC and
  fit an affine transform, then add a per-lens radial distortion term
  (Brown–Conrady, calibrated once per lens), falling back to the current
  rigid fit.
- **Why:** the rigid transform cannot absorb lens distortion, which is
  largest on the 103.6° ultra wide; stars in the corners smear after
  alignment over long spans.
- **Evidence:** [opensource.md, astroalign and Comparison](../gear/research/opensource.md#astroalign-python);
  Beroiz et al., *Astronomy and Computing* 32 (2020); PixInsight's
  thin-plate-spline registration as the documented upper bound.
- **License path:** reimplement from the paper (astroalign is MIT); shares
  the pattern code with item 9.
- **Effort:** M. **Device check:** corner star shape in a 20-minute
  ultra-wide stack, before and after.
- **ML:** none.

#### 11. Sky and foreground stacked separately

- **What:** find the horizon, stack the sky registered on stars and the
  foreground unregistered, and blend at the seam. Start with a deterministic
  horizon from brightness gradients (or the spot's horizon profile) that the
  user can nudge; optionally offer Vision's foreground mask as a labelled
  ML mask.
- **Why:** today a registered stack blurs the landscape and an unregistered
  one trails the stars; this is how Sequator and Starry Landscape Stacker
  keep both sharp.
- **Evidence:** [opensource.md §1, §5](../gear/research/opensource.md#5-skyground-segmentation);
  Pixel masks the sky with an on-device CNN only to steer denoise and
  contrast ([Google AI Blog](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html)).
- **License path:** own code (Sequator is closed: idea only). Vision is an
  Apple API; `fast-skyseg` weights have an unverified licence, so not used.
- **Effort:** M. **Device check:** a treeline and a ridgeline scene.
- **ML:** deterministic by default; the Vision mask is optional,
  non-generative and labelled.

#### 12. Live Activity for sequence progress

- **What:** frame N of M, time left and a thermal warning on the Lock Screen
  and Dynamic Island while a sequence runs.
- **Why:** the phone can lock during a 30-minute trail without losing sight
  of it; pairs with item 6 (decide which surface owns progress).
- **Evidence:** [WWDC26 session 223](https://developer.apple.com/videos/play/wwdc2026/223/);
  [iphone-techstack.md §4](../gear/research/iphone-techstack.md#4-display-and-night-use).
- **License path:** ActivityKit. **Effort:** S–M.
- **Device check:** field mode is pure red in the app, but the Lock Screen
  and Dynamic Island are iOS surfaces the app cannot recolour (ios/AGENTS.md
  invariant 5); check brightness at night.
- **ML:** none.

#### 13. Optional RAW 9 ML denoise

- **What:** an opt-in decode of the frames or the final DNG with
  `CIRAWFilter.decoderVersion = .version9`, Apple's Core ML demosaic and
  denoise, saved as a separate, labelled version next to the plain stack.
- **Why:** Apple says RAW 9 is markedly better at ISO 12,800 and above, which
  is where the main camera ends up at night.
- **Evidence:** [WWDC26 session 305](https://developer.apple.com/videos/play/wwdc2026/305/);
  [iphone-techstack.md §2](../gear/research/iphone-techstack.md#core-image-raw-filters-cirawfilter-what-can-be-turned-off).
  Once chosen it cannot be partly disabled; it needs more memory
  (extended-virtual-addressing entitlement, a larger `CIContext` limit).
- **License path:** Apple API. **Effort:** S.
- **Device check:** check `supportedCameraModels(for: .version9)` includes
  this phone; compare noise and faint-star retention against the plain
  stack; confirm it does not invent structure in dark sky.
- **ML:** yes, non-generative denoise. Allowed by the ADR-0011 amendment as
  an optional, labelled step; the original frames and plain stack stay.

### Later

#### 14. Exposure-ramped night timelapse with deflicker

- **What:** a day-to-night timelapse that meters each frame and walks ISO
  (and the main camera's four apertures) along a smooth curve with the
  shutter held at 1 s, then a deterministic deflicker that normalizes each
  frame's brightness to a smoothed target before export.
- **Why:** the "Holy Grail" sunset-to-stars shot. No action camera or iOS
  app surveyed offers a documented user-facing ramp.
- **Evidence:** LRTimelapse's Holy Grail and Visual Deflicker methods; GoPro's
  patent US10771712B2 on exposure temporal smoothing
  ([actioncams.md §1.3, §4](../gear/research/actioncams.md#13-night-lapse-video--night-lapse-photo-distinct-from-night-effects);
  [opensource.md §4](../gear/research/opensource.md#4-star-trail-and-timelapse-tools)).
- **License path:** own code from published method descriptions; ffmpeg's
  `deflicker` is a reference only. **Check GoPro's patent claims before
  shipping** a ramp-smoothing design.
- **Effort:** L: it needs a metering control loop the capture engine lacks.
  **Device check:** a full sunset to astronomical night on a tripod;
  battery and heat over two hours.
- **ML:** none.

#### 15. LiDAR-assisted foreground focus

- **What:** read the LiDAR distance to a foreground subject to set the lens
  position for the foreground frames of a blend (item 11).
- **Why:** manual focus on a dark foreground is hard; LiDAR works in the dark.
- **Evidence:** LiDAR is active infrared and works without light; nothing
  shows it helps focus on stars
  ([iphone-techstack.md §1](../gear/research/iphone-techstack.md#low-light-boost-manual-focus-lidar-in-the-dark)).
- **License path:** Apple API. **Effort:** M.
- **Device check:** does a LiDAR distance map to a sharp lens position at
  night, and how far out does it work.
- **ML:** none.

#### 16. Full 48 MP stacking

- **What:** stack the 8064 × 6048 ProRAW format, tiled, after item 5.
- **Why:** four times the pixels for large prints; NPF drops to 6.1 s, still
  far above 1 s.
- **Evidence:** 371 MB per working frame; the increased-memory-limit
  entitlement raises the ceiling
  ([iphone-techstack.md §2](../gear/research/iphone-techstack.md#memory-limits-for-large-frames)).
  Whether a third-party 48 MP capture falls back to 12 MP at high ISO is
  unconfirmed.
- **License path:** Apple entitlement. **Effort:** M.
- **Device check:** peak memory and time for 20 frames; noise vs 12 MP binned.
- **ML:** none.

## Small probes to add first

Cheap measurements the research flagged as unknown, worth adding to the
existing `-CameraProbe` before building items 1–8:

- `maxBracketedCapturePhotoCount` on the astro format (could replace manual
  pacing).
- Constant-colour capture during a locked sequence: does it help or fight a
  fixed white balance?
- EXIF FocalLength of one ProRAW frame from the ultra wide and the telephoto
  (settles two derived presets in `config/gear-presets.json`).
- Thermal state and battery over a real 30-minute sequence at night.

## What this plan does not do

- No generative AI of any kind: no sky replacement, no added stars, no
  detail "enhance".
- No GPL/AGPL code linked in; GPL projects (Siril, Astrometry.net,
  hdr-plus-swift, darktable, RawTherapee, GraXpert) are method references
  only.
- No change to the 1 s ceiling, the ProRAW pipeline or Night mode: those are
  Apple's to open.
