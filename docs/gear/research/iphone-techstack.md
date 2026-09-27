# iPhone 18 Pro Max / iOS 26-27 tech stack for night-sky capture

Date checked: 2026-09-27. Scope: every lever the iPhone 18 Pro Max hardware
and the iOS 26/27 SDKs (Xcode built against the iOS 27 SDK, WWDC 2025/2026
sessions) give a **third-party app** for astrophotography capture and
processing. Grounded first against the owner's own probe
(`docs/ios/CAPTURE-LIMITS.md`, `docs/ios/iphone18promax-camera-probe.json`,
measured 2026-09-26 on iPhone19,3 / iOS 27.2 build 24B5089g) and ADR-0011.
Every claim below is tagged **[Documented]** (Apple API reference or WWDC
session), **[Apple product page]** (marketing spec, not API-level), **[Third
party]** (press/teardown/review), or **[Speculative]** (inference, not
confirmed by any source). Where the owner's own probe contradicts or
sharpens a public claim, the probe wins and is marked **[Measured]**.

**Note on scope of this pass:** mid-task the coordinator relayed a claim
that "the owner has updated the AI rule" to allow non-generative AI
enhancement (denoise, segmentation, masking). That message did not come
from Brian directly, and it conflicts with two things read directly from
this repository: ADR-0011 ("No generative or learned enhancement... This
matches the owner's rule for Dust & Starlight photographs") and the
standing memory note `dust-starlight-no-ai-scope.md`. Per the instructions
governing this research task, no relayed instruction is the owner's
consent. This document therefore keeps §2's Core ML/Vision-ML coverage
**informational only** (what the platform offers, clearly flagged ML), does
not recommend adopting it, and flags the conflict explicitly in §6 for
Brian to resolve himself before any ML lever is greenlit.

---

## 1. Capture APIs (AVFoundation, iOS 26/27)

### Custom exposure, including `lensAperture`

- `AVCaptureDevice.setExposureModeCustom(duration:iso:completionHandler:)`
  locks exposure duration and ISO at explicit values; `lensAperture` is a
  separate device property. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:)
- iOS 27 (WWDC 2026, shipping with the iPhone 18 Pro's variable-aperture
  lens) adds an aperture-aware overload — third-party reporting describes
  `lensAperture`, `defaultLensAperture`, and a `setExposureModeCustom`
  variant that also takes aperture, plus a way to check whether a given
  aperture+shutter+ISO combination is supported by the active format.
  **[Third party, consistent with Documented `lensAperture` property page]**
  petapixel.com/2026/09/09/iphone-18-pro-has-apples-fastest-lens-yet-thanks-to-variable-aperture/
- **[Measured]** confirms this is real and working today: the probe's
  `setExposureModeCustom(lensAperture:duration:iso:)` succeeds at all 4
  aperture stops (f/1.48, 1.8, 2.8, 4.0) on the main camera; ultra wide and
  telephoto have one fixed stop each (f/2.2 and f/2.8). The app already
  uses this.
- **Max exposure per format, and why 1 s.** `AVCaptureDevice.Format` exposes
  `maxExposureDuration` / `activeFormat.maxExposureDuration`.
  **[Documented]** developer.apple.com/documentation/avfoundation/avcapturedevice/activemaxexposureduration
  The continuous-auto-exposure mode is separately capped near 1/30 s for
  viewfinder responsiveness; that cap does not apply to custom mode.
  **[Third party]** (Apple Developer Forums thread synthesis, no single
  canonical doc states the 1 s figure — it is per-format, not a documented
  constant) — **[Measured]** is the authority here: every format on all
  three rear cameras on this phone reports exactly 1.0 s as
  `maxExposureDuration`, confirmed by real capture (5 frames at 1.0000 s
  EXIF). This is almost certainly a firmware/ISP limit tied to the sensor's
  rolling-shutter readout and thermal/preview-pipeline design, not a
  documented Apple rationale — treat "why 1 s" as **[Speculative]** beyond
  the measured fact of the limit itself.

### ProRAW vs Bayer RAW; "ProRAW Max" / 48 MP rates

- Apple ProRAW is Apple's own scene-referred, demosaiced DNG — not raw
  Bayer sensor data. It layers Apple's computational pipeline (multi-frame
  fusion inputs, tone curve) into a DNG container that still exposes
  editable RAW-like headroom. **[Documented, WWDC21]**
  developer.apple.com/videos/play/wwdc2021/10160/
- **[Measured]** confirms no Bayer RAW is listed on any format on this
  phone; only `l64r`-tagged Apple ProRAW (→ DNG) is available, 2 formats per
  camera, capped at 8064×6048 (48 MP) on the "best astro" video-derived
  still format.
- "ProRAW Max" (up to 48 MP) is a real, named setting first surfaced in iOS
  17 RC code strings (iPhone 15 Pro generation onward); at higher ISO the
  system reportedly reverts from full 48 MP quad-Bayer capture to 12 MP
  binned output to protect signal-to-noise. **[Third party]**
  thetapedrive.com/p/ios-17-rc-code-reveals-new-iphone frameandfocal.com/photography-glossary/understanding-apple-proraw
  This ISO/resolution tradeoff is Apple's own Camera app behavior; **it is
  not confirmed whether `AVCapturePhotoOutput`'s 48 MP capture (via
  `maxPhotoDimensions` / `AVCapturePhotoSettings`) in a third-party app
  applies the same ISO-gated fallback** — **[Speculative]** for third-party
  apps specifically. The probe's own captures were done at fixed ISO 800 and
  returned full 4032×3024 (12 MP; the format's video-derived still size,
  not the 48 MP still-only format) — this is the format the app currently
  picks, not evidence of an ISO cutoff on the 48 MP-native still formats.
- Apple's own ProRAW pipeline (demosaic, local tone mapping, noise
  reduction) is baked in and cannot be inspected or bypassed by a
  capturing app; only post-hoc adjustable via `CIRAWFilter` after the fact
  (§2). **[Measured + Documented, ADR-0011 note]**

### `AVCapturePhotoOutput` burst limits, responsive capture, ZSL, deferred delivery, constant color

- `maxBracketedCapturePhotoCount`: hardware/format-dependent burst ceiling;
  some formats return 0 (no bracketing). Historical measured value on
  iPhone 7 Plus was 4; current iPhone 18 Pro Max value is **not yet probed**
  by the owner's script — a gap to fill. **[Documented, value itself
  device/format-specific and not published as a table]**
  developer.apple.com/documentation/avfoundation/avcapturephotooutput
- **Zero shutter lag**: `isZeroShutterLagSupported` / `isZeroShutterLagEnabled`
  on `AVCapturePhotoOutput`. Serves the most recent buffered frame instead
  of a fresh exposure — set `isZeroShutterLagEnabled = false` to force a
  true fresh capture. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagenabled
  **[Measured]**: this is load-bearing for the app today. With ZSL left on,
  five requested "1 s" frames returned from the ring buffer in 0.6 s total
  (stale/duplicated exposures); the app now disables ZSL and paces requests
  one exposure apart, verifying each frame's sensor timestamp.
- **Deferred photo delivery**: lets the output return a placeholder
  immediately and finish processing later, keeping the shutter responsive
  under burst. **[Documented, iOS 17+, extended in WWDC 2026 sessions 303/304]**
  developer.apple.com/videos/play/wwdc2026/303/ (Build a responsive camera
  app that launches quickly) and /304/ (Implement high resolution photo
  capture — explicitly covers "responsive capture for high-resolution
  images" and processing tradeoffs).
- **Responsive capture (new emphasis, WWDC 2026)**: overlapping captures —
  a new capture can start once the *capture* stage of the prior photo
  finishes, without waiting for full processing. **[Documented, WWDC26
  session 304]**
- **Constant color**: `AVCapturePhotoOutput.isConstantColorEnabled` /
  `AVCapturePhotoSettings` constant-color capture — normalizes color
  response across frames, throws if the output-level toggle is not set
  first. Relevant to stacking: reduces frame-to-frame white-balance drift
  that would otherwise need correcting before averaging. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturephotooutput
  Not yet evaluated by the owner's probe against astro exposures —
  **[Speculative]** whether it helps or interferes with a locked custom
  white balance during a sequence; worth a probe addition.

### Video path

- **Max exposure per frame at 24/30 fps**: video-format `maxExposureDuration`
  is bounded well below 1/24–1/30 s in practice for smooth playback, but
  Apple does not publish a fixed number — it is per `AVCaptureDevice.Format`,
  same mechanism as stills. **[Documented mechanism, no single published value]**
- **Apple Log 2**: new (iPhone 17 Pro generation onward) wider-gamut,
  higher-headroom log profile vs. original Apple Log. **[Apple product
  page + third party]** support.apple.com/en-us/109041,
  cined.com/apple-final-cut-camera-2-0-open-gate-apple-log-2-and-prores-raw-genlock-for-iphone-17-pro/
- **ProRes / ProRes RAW on iPhone Pro**: ProRes has shipped since iPhone 13
  Pro; **ProRes RAW is new** (iPhone 17 Pro generation onward), currently
  exposed only through Apple's own **Final Cut Camera** app (2.0), not a
  general third-party `AVFoundation` API as of this check. **[Apple
  product page + third party]**
  support.apple.com/guide/iphone/record-prores-video-iphde02c478d/ios,
  cined.com (above). Whether ProRes RAW's underlying capture path is
  reachable by arbitrary third-party apps via public `AVCaptureMovieFileOutput`
  or requires Apple's private entitlement is **[Speculative — not
  confirmed]**; Final Cut Camera may use a first-party-only capability.
- **External recording**: Apple ProRes over USB-C to an external SSD,
  supported since iPhone 15 Pro; third-party sources report confirmed
  external ProRes RAW open-gate recording up to 4224×3024 at 60 fps.
  **[Apple product page + third party]**
  cined.com (above)
- iPhone 18 Pro Apple product page confirms **[Apple product page]**:
  "ProRes video recording up to 4K at 120 fps with external recording,"
  ProRes RAW and Apple Log 2 enabled — apple.com/iphone-18-pro/specs/

### Low-light boost, manual focus, LiDAR in the dark

- `AVCaptureDevice.automaticallyEnablesLowLightBoostWhenAvailable`: Boolean,
  device auto-switches to a low-light boost mode. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturedevice/automaticallyenableslowlightboostwhenavailable
  **[Measured]**: the probe explicitly checked this and found low-light
  boost **not supported on any of the three rear cameras** on this phone
  for the astro-relevant formats. This is a hard "no" for that lever.
- **Manual focus / `lensPosition`**: settable 0–1 via custom focus mode;
  1.0 is documented by Apple as the far end of travel, **not** true optical
  infinity. **[Documented + Measured]** — matches CAPTURE-LIMITS.md exactly;
  the app locks focus with a magnifier + star half-flux-radius readout
  rather than trusting `lensPosition = 1.0`.
- **LiDAR / ToF in the dark**: LiDAR is an active infrared time-of-flight
  emitter/sensor — it works by emitting its own IR pulses and does not
  depend on ambient visible light, so it functions in full darkness for
  depth and can speed up autofocus in low light. **[Third party, consistent
  across multiple sources]**
  engadget.com/2250700/iphone-lidar-sensor-purpose-how-to-use/
  For astrophotography specifically: no source confirms LiDAR is useful for
  focusing on stars (its range and resolution target near-field geometry,
  not point sources at infinity), but it is plausible for **foreground
  subject distance** in a foreground+sky composite (silhouette/landscape
  focus stacking). **[Speculative for star-focus use; plausible and
  low-risk for foreground-distance use]**

### Camera Control button API; rotation/orientation APIs

- **Camera Control**: `AVCaptureControl` (abstract base class), with
  system-defined subclasses matching stock Camera app behavior (zoom,
  exposure bias) and generic slider/picker subclasses apps can define
  themselves. Introduced iPhone 16, refined at WWDC 2025 session 253.
  **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturecontrol
  developer.apple.com/videos/play/wwdc2025/253/
  One caveat from third-party developer experience: full Camera Control
  *lock-screen launch* integration needs a Lock Screen Capture Extension;
  in-app slider/shutter use does not. **[Third party]**
  mszpro.com/ios-camera-control-button
- **Rotation/orientation**: `AVCaptureDevice.RotationCoordinator` monitors
  physical device orientation relative to gravity and supplies rotation
  angles to keep captured images level — replaces older
  `UIDeviceOrientation`-based approaches. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator

### Multi-cam

- `AVCaptureMultiCamSession` (since iOS 13, A12+): runs several camera
  inputs concurrently (vs. the standard single-active-camera session),
  supports simultaneous video/audio/depth/photo/metadata streams from
  multiple cameras and up to 3 audio beams. **[Documented]**
  developer.apple.com/documentation/avfoundation/avcapturemulticamsession
  For a tripod astro app, the realistic use is **simultaneous wide + ultra
  wide** for a foreground/sky exposure blend captured in one shutter press,
  or a parallel low-res preview feed while the main sensor is mid-exposure.
  Not yet used by this app. **[Speculative use case — mechanism is
  Documented, application to astro is not Apple-validated]**

---

## 2. Processing on the device

### Metal / MPS / Accelerate for 48 MP stacking

- Metal and Metal Performance Shaders (`MPSGraph`, image filter/reduction
  kernels) and Accelerate/`vImage` are the standard deterministic
  GPU/CPU-vector toolchains for register-and-average stacking; no
  iOS-26/27-specific change found beyond general Core Image tiling
  improvements (below). **[Documented, general framework — no version-gated
  claim]**
- **[Measured]**: current CPU-path performance on the owner's phone (not
  yet Metal-accelerated per the probe notes): 20 synthetic 12 MP frames —
  star detection 0.079 s/frame, registration 0.013 s total, sigma-clipped
  mean 6.8 s, trail maximum 0.9 s; a 5-frame real ProRAW stack completed in
  2.8 s at 805 MB peak memory. These are CPU/Accelerate numbers today; a
  Metal/MPS port is unmeasured and a likely large speedup for the
  sigma-clip step specifically, which dominates the current runtime.

### Memory limits for large frames

- `com.apple.developer.kernel.increased-memory-limit`: Boolean entitlement,
  not exposed in Xcode's Signing & Capabilities UI, must be requested
  through a provisioning profile ("Increased Memory Limit" capability).
  Raises the app's jetsam ceiling on supported devices. **[Documented]**
  developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
  Real-world reported delta: ~3.3 GB baseline → ~6 GB with entitlement on
  an iPhone 15 Pro Max. **[Third party, illustrative only — not a promise
  for iPhone 18 Pro Max]**
- A second, narrower entitlement surfaced by the WWDC 2026 Core Image
  session: `com.apple.developer.kernel.extended-virtual-addressing`,
  recommended specifically for RAW-9-class CoreML processing at high
  resolution. **[Documented, WWDC26 session 305]**
  developer.apple.com/videos/play/wwdc2026/305/
- At 48 MP, a 16-bit-per-channel RGBA working buffer is roughly
  8064×6048×4×2 bytes ≈ **371 MB per frame**; a sigma-clip stack holding
  N frames plus a working accumulator scales roughly linearly with N.
  This arithmetic is **[Derived, not sourced]** — it is why the increased
  memory limit and tiled `CIImageProcessor` (below) matter for any
  full-48 MP stacking path, versus the current 12 MP video-derived format.

### `BGContinuedProcessingTask` (iOS 26) and background GPU access

- New in iOS/iPadOS 26 (WWDC 2025 session 227, "Finish tasks in the
  background"). Must be submitted in direct response to a user action (tap,
  swipe); the system shows persistent progress UI the user can tap back
  into; your code reports progress; UI auto-dismisses on completion.
  **[Documented]**
  developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
  developer.apple.com/videos/play/wwdc2025/227/
  This is a strong fit for "finish this 20-frame sigma-clip stack after the
  user leaves the capture screen" — explicitly the shipped use case Apple
  demonstrates (video export, large uploads) generalizes directly to a long
  stack job. **[Documented mechanism; astro-specific application is
  Speculative-but-well-supported]**
- Background GPU (Metal) access while backgrounded under
  `BGContinuedProcessingTask` is implied by the "continue foreground work
  in the background" framing but **no source explicitly confirms Metal
  compute continues unthrottled in this state** vs. being time-sliced.
  **[Speculative]** — worth an owner probe: submit a
  `BGContinuedProcessingTaskRequest` wrapping the Metal stack and measure
  actual wall-clock completion vs. foreground.

### Thermal-state APIs; low-power behavior

- `ProcessInfo.thermalState`: `.nominal` / `.fair` / `.serious` / `.critical`,
  observable via `ProcessInfo.thermalStateDidChangeNotification`. Apple's
  documented guidance: at `.fair`, delay non-visible work; at `.serious`,
  scale back CPU/GPU/I-O; at `.critical`, the device needs to cool down.
  **[Documented]**
  developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
  **[Measured]**: the probe recorded `thermalState: "nominal"` at capture
  time — no throttling data point yet from a real long sequence; ADR-0011
  already calls for throttling under thermal pressure as a design
  requirement, not yet implemented against this API per the read files.
- Low Power Mode is queryable via
  `ProcessInfo.isLowPowerModeEnabled`; no astro-specific interaction
  documented beyond the general guidance to reduce background work.
  **[Documented, general]**

### Core Image RAW filters (`CIRAWFilter`): what can be turned off

- `CIRAWFilter` exposes ProRAW/DNG processing as adjustable filter inputs:
  `exposure`, `temperature`/`tint`, `sharpness` (`sharpnessAmount`),
  `localToneMapAmount` (local tone-curve strength — **settable to 0.0 to
  get a flatter, more linear result**), `linearSpaceFilter` (an optional
  filter applied while still in linear space, before the default
  tone/color pipeline), `noiseReductionAmount`
  (`CIRAWFilterOption.noiseReductionAmount`). **[Documented]**
  developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount
  developer.apple.com/documentation/coreimage/cirawfilter/linearspacefilter
  developer.apple.com/documentation/coreimage/cirawfilteroption/noisereductionamount
  This confirms the ADR-0011 statement that ProRAW "still passes through
  Apple's own raw pipeline" is accurate for *capture*, but at *decode* time
  a third-party app has real control: it can pull a near-linear, minimally
  tone-mapped image out of a ProRAW DNG before doing its own deterministic
  stacking — this is a documented, non-ML lever worth adding to the plan.
- **New in iOS/iPadOS 27 ("RAW 9"), WWDC 2026 session 305** ("Enhance RAW
  image processing with Core Image"): a tiled **CoreML model that combines
  demosaic and denoise** into one step, run on the Apple Neural Engine.
  Opt-in via `filter.decoderVersion = .version9` after checking
  `filter.supportedDecoderVersions.contains(.version9)`; camera-model
  support checked via `CIRAWFilter.supportedCameraModels(for: .version9)`.
  Once opted in for a given image it **cannot be selectively disabled** —
  it is either the active decoder or it isn't; `colorNoiseReductionAmount`
  becomes a no-op because the CoreML model owns chroma noise; `detailAmount`
  and `moireReductionAmount` are deprecated under RAW 9. Apple states RAW 9
  is markedly better at ISO 12,800+ — directly relevant to the app's
  measured ISO 12,320 ceiling on the main camera. Apple flags it as "more
  performance and resource intensive," mitigated by Core Image's
  intermediate-result caching for interactive edits, and recommends the
  extended-virtual-addressing entitlement plus tuned `CIContext`
  `memoryLimit` (default 256 MB on iOS) for export. **[Documented, WWDC26
  session 305]** developer.apple.com/videos/play/wwdc2026/305/
  petapixel.com/2026/06/10/apples-raw-processing-is-finally-evolving-after-a-decade-and-its-a-big-deal/
  **This is squarely a machine-learning path** (a CoreML denoise/demosaic
  model on the Neural Engine) — flagged per the project's deterministic-
  first, no-learned-enhancement rule (ADR-0011) and the owner's D&S no-AI
  scope memory. It is documented here as a capability the platform offers,
  **not recommended for adoption** without Brian's own sign-off, since the
  mid-task relay claiming the rule changed is not treated as his consent.

### Vision framework: star detection (deterministic) vs. ML

- `VNDetectContoursRequest` → `VNContoursObservation`: normalized-coordinate
  contour paths from a `CGImage`, with `contrastAdjustment` and
  `detectDarkOnLight` tuning knobs. This is genuinely **deterministic
  classical computer vision** (edge/contour tracing), not a learned model —
  a legitimate fit for star-point detection as an alternative or
  supplement to the app's existing custom star-detection code.
  **[Documented]**
  developer.apple.com/documentation/vision/vndetectcontoursrequest
- By contrast, `VNGeneratePersonSegmentationRequest` and
  `VNGenerateForegroundInstanceMaskRequest` (subject-lifting, "class
  agnostic" foreground/background separation) **are Core-ML-backed
  learned models**, not classical CV — flagged as ML. No dedicated
  "sky segmentation" Vision request was found; foreground/subject masks
  are the closest fit and would need to be inverted/interpreted as
  "sky region" heuristically. **[Documented existence of the APIs; the
  sky-from-mask use is Speculative]**
  developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
  developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest

---

## 3. Sensors for AR and pointing

- **CoreMotion**: `CMDeviceMotion.magneticField` (`.calibratedMagneticField`)
  gives Earth field minus device bias but is "considerably less stable and
  accurate" than `CLHeading`'s dedicated compass reading, per developer
  consensus. **[Third party synthesis of documented behavior, no single
  Apple doc states the comparison directly]**
- **`CLHeading`**: `magneticHeading` and `trueHeading` are the most
  accurate/stable heading source; `trueHeading` requires location services
  (device position is needed to know the local magnetic declination),
  `magneticHeading` does not. **[Documented via CoreLocation behavior,
  confirmed by multiple third-party technical write-ups]**
- **Magnetometer calibration**: the system-driven figure-eight calibration
  gesture is tied to certain `CMAttitude` reference frames.
  **[Third party, consistent with long-standing documented behavior]**
- **Precise location / dual-frequency GPS**: iPhone 14 Pro generation
  onward (continues through 18 Pro Max) tracks GPS L1 and L5 bands
  simultaneously; L5's higher chip rate meaningfully reduces multipath/
  noise error versus L1-only. Marketing/lab claims of centimeter-level
  accuracy are theoretical; independent measurement of comparable Android
  dual-frequency implementations found ~1.75 m horizontal / 4.56 m
  vertical real-world accuracy. **[Third party + peer-reviewed adjacent
  study, not iPhone-specific for the accuracy figure]**
  macrumors.com/2022/09/10/iphone-14-pro-dual-frequency-gps/,
  ncbi.nlm.nih.gov/pmc/articles/PMC9788430/ (Android study, cited for
  the accuracy-order-of-magnitude context only)
- **Altitude/barometer**: `CLLocationManager`/`CLAltimeter` expose a
  barometric-relative altitude on all recent iPhones; no iPhone-18-specific
  change found. **[Documented, general — not version-gated]**

---

## 4. Display and night use

- **1-nit minimum brightness**: iPhone displays (17 Pro generation
  confirmed, 18 Pro Max inherits/matches per Apple's own spec page pattern)
  range 1–1000 nits typical, up to 1600 nits HDR peak, 3000 nits peak
  outdoor. Accessibility "Reduce White Point" / Zoom "Low Light Filter"
  push effective brightness far below 1 nit (measured as low as ~0.004 nits
  combined) but those are **system accessibility features, not something a
  third-party app can invoke directly for its own UI**. **[Third party
  measurement + Apple product page]**
  lttlabs.com/articles/2026/04/16/phone-minimum-display-brightness,
  apple.com/iphone-18-pro/specs/
- **`UIScreen.brightness`**: app-settable 0.0–1.0; changes persist only
  until the device locks, then system brightness is restored on next
  wake. A `wantsSoftwareDimming` flag can push dimming below hardware
  minimum via software emulation, at a performance cost, default `false`.
  **[Documented]** — this is the correct, real lever for the app's
  "field mode" dark-adapted UI, and it already appears to inform current
  design (per ADR-0011's field-mode tinting note). No dedicated public API
  reaches the true ~1-nit hardware floor beyond what `UIScreen.brightness`
  already exposes at its low end.
- **ProMotion**: adaptive refresh up to 120 Hz. **[Apple product page]**
  Not obviously relevant to a static capture screen; could matter for a
  smooth live star-detection/focus-magnifier overlay.
- **Always-On display**: confirmed present on iPhone 18 Pro/Pro Max.
  **[Apple product page]** No public API to draw custom Always-On content
  was found in this pass — Always-On is a system feature (Lock Screen/
  widgets), not something a foregrounded capture app controls directly.
  **[Speculative gap — needs a dedicated follow-up if Always-On progress
  display is desired]**
- **Live Activities / Dynamic Island**: `ActivityKit` — `ActivityAttributes`
  (static) + `ContentState` (dynamic, periodically updated) model; separate
  UI required for compact-leading, compact-trailing, minimal, and expanded
  Dynamic Island regions; can update locally or via push. WWDC 2026 session
  223 ("Live Activities essentials") is the current reference session.
  **[Documented]**
  developer.apple.com/videos/play/wwdc2026/223/
  Directly applicable to a running capture sequence: frame N of M, time
  remaining, thermal warning — a natural pairing with
  `BGContinuedProcessingTask`'s own system progress UI, though they are
  two different mechanisms (one for background task continuation, one for
  ongoing-activity display) and would need to be coordinated rather than
  assumed to be the same surface. **[Documented mechanisms; the pairing
  design is Speculative]**
- **Widgets**: standard WidgetKit; no astro-specific API found in this
  pass. **[Not researched in depth — out of scope gap]**

---

## 5. Hardware: iPhone 18 Pro Max camera modules

| Camera | Resolution | Aperture | Focal length | Notes |
|---|---|---|---|---|
| Main (Fusion Main) | 48 MP | Variable: f/1.48, f/1.8, f/2.8, f/4.0 | 24 mm equiv. | 1/1.28" optical format (third-party); 2nd-gen sensor-shift OIS; 100% Focus Pixels |
| Ultra Wide (Fusion Ultra Wide) | 48 MP | f/2.2 fixed | 13 mm equiv. | 120° FOV; Hybrid Focus Pixels |
| Telephoto (Fusion Telephoto) | 48 MP | f/2.8 fixed | 100 mm equiv. (4x) | Tetraprism; 3D sensor-shift OIS + AF |

Sources: Apple's own spec page (apple.com/iphone-18-pro/specs/) for
resolution/aperture/focal length/OIS — **[Apple product page]**. The
1/1.28" optical-format figure and "6.8 mm focal length" detail come from
GSMArena's technical camera review, a third-party measurement/derivation,
not an Apple-published number — **[Third party]**
gsmarena.com/apple_iphone_18_pro_max-review-3002p5.php. TechInsights'
teardown-based blog explicitly states sensor-level detail (exact sensor
model, pixel pitch per camera) is **pending physical teardown analysis** as
of this check — **[Third party, explicitly marked pending by the source
itself]** techinsights.com/blog/apple-iphone-18-pro-max-whats-new.

**Variable aperture mechanism**: six laser-cut aperture blades, each
roughly human-hair thickness, physically closing/opening across the four
stops; confirmed by iFixit's teardown. **[Third party, physical teardown —
high confidence]** ifixit.com/News/119329/inside-the-tiny-unfixable-eye-iphone-18-pro-and-pro-max-teardown

**Discrepancy note**: one third-party source (PetaPixel, citing hands-on
review) states the 48 MP main sensor is unchanged from the 17 Pro and
"fixed at f/1.78" with the *variable* mechanism being an added element in
front of it, opening to f/1.48 automatically in the dark — this reads as
in tension with Apple's own "f/1.48–f/4.0 variable aperture" framing.
**[Third party, flagged as unresolved — do not treat either framing as
settled without the pending TechInsights teardown]**

**LiDAR Scanner**: present, per Apple's own spec page. **[Apple product page]**

**A20 Pro chip** (relevant to on-device processing headroom): 2 nm process,
6-core CPU with integrated Neural Accelerators, 7-core GPU, **dual 16-core
Neural Engines**, 50% more memory bandwidth and 2x AI processing throughput
vs. prior generation (Apple's own performance claim, relayed by
TechInsights). **[Third party summary of Apple's claims — the "2x AI
processing" figure is Apple's marketing framing, not independently
verified]** techinsights.com/blog/apple-iphone-18-pro-max-whats-new

**Battery / thermal**: ~5,391–5,567 mAh (SIM config dependent); new vapor
chamber with 3x the surface area of the 17 Pro's, die-beside-memory
packaging (not stacked) to keep memory out of the chip's thermal path;
Apple's claimed up to 40% sustained-performance gain. **[Third party,
attributed to Apple's own claims]**
macrumors.com/2026/09/09/iphone-18-pro-redesigned-vapor-chamber/

---

## 6. Recommendations for the Dark Sky app (ranked)

Ranked by payoff-per-effort given the app's current state (deterministic
1 s ProRAW sequences, CPU-path stacking, ADR-0011's no-generative-AI rule
in force pending Brian's own confirmation of any change).

1. **`BGContinuedProcessingTask` for finishing long stacks — high payoff,
   medium effort.** Directly matches a shipped Apple use case. Lets a
   20+ frame sigma-clip job (currently 6.8 s CPU-bound and growing with
   frame count/resolution) survive the user backgrounding the app, with a
   system-provided progress surface. No special entitlement beyond normal
   `BGTaskScheduler` registration in `Info.plist`. **No ML involved.**

2. **Metal/MPS stacking at 48 MP — high payoff, medium-high effort.**
   The sigma-clip step is the current bottleneck (6.8 s of a 2.8 s+6.8 s+
   0.9 s pipeline on 12 MP synthetic frames); porting the accumulator to
   `MPSGraph` reduction kernels or hand-written Metal compute would likely
   give the largest single speedup, and is a prerequisite for stacking at
   the full 48 MP still format rather than the current 12 MP video-derived
   one. Needs the increased-memory-limit entitlement (§2) once frame count
   × 48 MP × 16-bit buffers exceeds default jetsam limits. **No ML
   involved — pure GPU compute, fully deterministic.**

3. **Continuous 1 s ProRAW sequences with correct gap handling — already
   done, keep hardening.** ZSL-off + paced requests + per-frame timestamp
   verification is already implemented and measured correct. The
   remaining gap: confirm `maxBracketedCapturePhotoCount` on this phone's
   astro format (not yet probed) in case native bracketing could replace
   manual pacing with less overhead — worth a probe addition, low effort.

4. **`CIRAWFilter` linear/no-tone-map decode path — medium payoff, low
   effort, no ML.** Setting `localToneMapAmount = 0.0` and using
   `linearSpaceFilter` to pull a flatter, more linear image out of each
   ProRAW DNG before stacking could reduce the amount of Apple's built-in
   tone curve baked into each frame prior to the app's own deterministic
   averaging — worth testing against the current pipeline's output.
   Deliberately **do not** opt into RAW 9's CoreML decoder
   (`decoderVersion = .version9`) without Brian's explicit sign-off, since
   it is a learned demosaic+denoise model — flagged, not recommended, per
   the scope note at the top of this document.

5. **Live Activity for sequence progress — medium payoff, low-medium
   effort.** Natural pairing with item 1: show frame N/M and thermal
   status on the Lock Screen/Dynamic Island while a sequence runs.
   Distinct mechanism from `BGContinuedProcessingTask`'s own progress UI —
   needs a design decision on which owns "the" progress surface, or how
   both coexist. **No ML involved.**

6. **A star-trail video exporter — medium payoff, low effort.** The
   star-trail mode already computes an unaligned per-pixel maximum
   (`StackAccumulator(mode: .maximum)`) and saves every frame; exporting an
   `AVAssetWriter`-based timelapse/video of the accumulating trail (or a
   frame-by-frame trail build-up) is largely assembly of existing pieces,
   no new capture-side API needed. **No ML involved.**

7. **Camera Control shutter integration — medium payoff, low effort.**
   `AVCaptureControl` custom slider/shutter mapped to "start sequence" /
   adjust exposure without touching the screen (useful with gloves on a
   tripod at night). In-app use (not lock-screen launch) needs no special
   extension. **No ML involved.**

8. **LiDAR-assisted foreground focus — low-medium payoff, medium effort,
   uncertain fit.** Plausible for a foreground-subject/landscape element
   in a composite frame, but no source confirms LiDAR is useful for the
   actual star/sky focus target (its range and design intent are near-field).
   Worth a quick owner test before investing further. **No ML involved
   (LiDAR depth capture itself is not a learned model).**

9. **Brightness control in field mode — already substantially covered.**
   `UIScreen.brightness` plus the field-mode tint (per ADR-0011) is the
   correct, available lever; the true ~1-nit hardware floor is only
   reachable via system accessibility features the app cannot invoke on
   the user's behalf — no further public API found. Low remaining effort,
   low remaining payoff (mostly done).

10. **Plate-solve calibration of AR (CLHeading/CoreMotion pointing) — high
    conceptual payoff, high effort, deterministic and in scope.** Using
    `CLHeading.trueHeading` (not `CMDeviceMotion`'s calibrated field, which
    is documented as noisier) as the AR baseline, with a plate-solve pass
    against a captured frame to correct residual compass/attitude error, is
    a legitimate deterministic-CV project (star positions are geometry, not
    a learned inference) — but it's a substantial computer-vision
    undertaking on its own, not a quick lever. **No ML required if done as
    true plate-solving (star-pattern matching), though some
    astrometry.net-style implementations use ML-assisted source extraction —
    verify any third-party library's approach before adopting it.**

**Entitlements to request ahead of time**, none of which need App Store
special review beyond normal provisioning-profile capabilities:
`com.apple.developer.kernel.increased-memory-limit` (item 2),
`com.apple.developer.kernel.extended-virtual-addressing` (only if RAW 9 is
ever adopted — item 4's declined path), standard `BGTaskScheduler`
background modes registration (item 1), and `NSCameraUsageDescription` /
Camera Control's normal capture entitlements (already presumably in place
given the app captures today).

**Flagged for Brian, not decided here**: whether Core ML/Neural Engine
denoise (RAW 9's `CIRAWFilter` decoder, or a custom Vision/Core ML model)
and Vision's learned segmentation requests (`VNGenerateForegroundInstanceMaskRequest`,
`VNGeneratePersonSegmentationRequest`) should be adopted at all, given
ADR-0011's explicit "no generative or learned enhancement" decision and the
`dust-starlight-no-ai-scope` memory. This document surfaces what the
platform offers (§2) without treating a relayed, unverified claim of a
policy change as authorization to build against it.

---

## Sources

**Apple Developer documentation**
- developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:)
- developer.apple.com/documentation/avfoundation/avcapturedevice/lensaperture
- developer.apple.com/documentation/avfoundation/avcapturedevice/activemaxexposureduration
- developer.apple.com/documentation/avfoundation/avcapturedevice/format/maxexposureduration
- developer.apple.com/documentation/avfoundation/avcapturephotooutput
- developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagenabled
- developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagsupported
- developer.apple.com/documentation/avfoundation/avcapturedevice/automaticallyenableslowlightboostwhenavailable
- developer.apple.com/documentation/avfoundation/avcapturecontrol
- developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator
- developer.apple.com/documentation/avfoundation/avcapturemulticamsession
- developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession/supportedmulticamdevicesets
- developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
- developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
- developer.apple.com/documentation/coreimage/cirawfilter
- developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount
- developer.apple.com/documentation/coreimage/cirawfilter/linearspacefilter
- developer.apple.com/documentation/coreimage/cirawfilteroption/noisereductionamount
- developer.apple.com/documentation/vision/vndetectcontoursrequest
- developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
- developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest

**WWDC sessions (2025/2026)**
- developer.apple.com/videos/play/wwdc2025/253/ — Enhancing your camera experience with capture controls
- developer.apple.com/videos/play/wwdc2025/227/ — Finish tasks in the background (BGContinuedProcessingTask)
- developer.apple.com/videos/play/wwdc2026/303/ — Build a responsive camera app that launches quickly
- developer.apple.com/videos/play/wwdc2026/304/ — Implement high resolution photo capture
- developer.apple.com/videos/play/wwdc2026/305/ — Enhance RAW image processing with Core Image (RAW 9)
- developer.apple.com/videos/play/wwdc2026/223/ — Live Activities essentials
- developer.apple.com/videos/play/wwdc2021/10160/ — Capture and process ProRAW images

**Apple product pages / support**
- apple.com/iphone-18-pro/specs/
- support.apple.com/en-us/109041 — About Apple ProRes on iPhone
- support.apple.com/guide/iphone/record-prores-video-iphde02c478d/ios

**Third-party technical analysis**
- gsmarena.com/apple_iphone_18_pro_max-review-3002p5.php
- techinsights.com/blog/apple-iphone-18-pro-max-whats-new
- ifixit.com/News/119329/inside-the-tiny-unfixable-eye-iphone-18-pro-and-pro-max-teardown
- techspot.com/news/113922-iphone-18-pro-teardown-highlights-mechanical-camera-aperture.html
- macrumors.com/2026/09/09/iphone-18-pro-redesigned-vapor-chamber/
- petapixel.com/2026/09/09/iphone-18-pro-has-apples-fastest-lens-yet-thanks-to-variable-aperture/
- petapixel.com/2026/06/10/apples-raw-processing-is-finally-evolving-after-a-decade-and-its-a-big-deal/
- skiesandscopes.com/is-the-iphone-18-good-for-astrophotography/ (via search snippet; direct fetch returned HTTP 403)
- cined.com/apple-final-cut-camera-2-0-open-gate-apple-log-2-and-prores-raw-genlock-for-iphone-17-pro/
- thetapedrive.com/p/ios-17-rc-code-reveals-new-iphone
- frameandfocal.com/photography-glossary/understanding-apple-proraw
- lttlabs.com/articles/2026/04/16/phone-minimum-display-brightness
- mszpro.com/ios-camera-control-button
- engadget.com/2250700/iphone-lidar-sensor-purpose-how-to-use/
- macrumors.com/2022/09/10/iphone-14-pro-dual-frequency-gps/
- ncbi.nlm.nih.gov/pmc/articles/PMC9788430/ (Android dual-frequency GNSS accuracy study, cited for context only)

**Repository sources (ground truth for this phone)**
- `docs/ios/CAPTURE-LIMITS.md` — measured probe results, iPhone19,3 / iOS 27.2 build 24B5089g, 2026-09-26
- `docs/ios/iphone18promax-camera-probe.json` — raw probe data
- `docs/adr/0011-iphone-tripod-capture.md` — the project's deterministic-first, no-generative-AI decision
