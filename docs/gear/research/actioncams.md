# Action cameras, drones, and phones: night-sky and star-trail capture

Date checked: 2026-09-27. Research for the Dark Sky iPhone app — how consumer
devices handle night-sky and star-trail capture, so the app's own capture
engine (`docs/ios/CAPTURE-LIMITS.md`, `docs/adr/0011-iphone-tripod-capture.md`)
can match or beat them on an iPhone 18 Pro Max. Every claim below is cited.
Where a vendor does not document a mechanism, that is stated explicitly and
the most credible third-party account is given, labelled as analysis rather
than as vendor fact.

For context, the app's own hardware ceiling: the iPhone 18 Pro Max's
`AVCaptureDevice` custom exposure tops out at **1.0 s per frame** on every
back-camera format (measured, not from marketing), with ProRAW (not Bayer
RAW), ISO up to 12,320 on the main camera, and apertures f/1.48–4.0 on the
main camera only. ADR-0011 commits the app to deterministic stacking — signal
averaging and max-blending over saved frames, no generative or learned
"enhancement" of the image content. The note below on AI features in other
vendors' pipelines exists for comparison only; it does not change that
commitment. Frame-count math for the iPhone is always "1 s exposure ×
however many frames," unlike every device below, which can hold a single
shutter open far longer than 1 s per frame.

---

## 1. GoPro (current HERO models, 2024–2026)

GoPro's relevant modes live under the **Time Lapse** preset group: Time Lapse
Video, Time Lapse Photo, Night Lapse Video, Night Lapse Photo, and three
**Night Effects** presets — Star Trails, Light Painting, and Vehicle Light
Trails — introduced on HERO11 Black and carried forward to HERO12 and
HERO13. All were confirmed still current on HERO13 Black by GoPro's own
support article title as of this check
([community.gopro.com, HERO13 Night Effects](https://community.gopro.com/s/article/HERO13-Black-Night-Effects-Star-Trails-Light-Painting-And-Vehicle-Lights?language=en_US),
checked 2026-09-27; this and other `community.gopro.com` article pages
render client-side JavaScript and repeatedly returned only a loading shell
to both WebFetch and defuddle during this research — the *existence and
title* of the article is confirmed by search-index and third-party citation,
but its full text could not be fetched directly. Where the underlying detail
matters, third-party sources that quote or paraphrase it are used instead
and labelled).

### 1.1 Night Effects: Star Trails

- **What it is (vendor-documented):** a shooting mode, not a photo edit —
  "the camera must remain perfectly still," a tripod is recommended, and a
  capture "may take 20 minutes or even multiple hours, depending on the
  trail length you chose"
  ([community.gopro.com, Night Effects](https://community.gopro.com/s/article/Night-Effects-Star-Trails-Light-Painting-And-Vehicle-Lights?language=en_US),
  checked 2026-09-27, via search-engine summary of the article body).
- **Output:** the camera "takes a series of photos and stitches them
  together into a video showing the movement of the night sky" — the
  deliverable is an MP4, not a single still, though individual frames can be
  pulled from it afterward (same source). Digital Camera World's hands-on
  with HERO11 Black Mini confirms this directly: "To create Star Trail and
  Night Lapse files it therefore takes a series of long exposure photos
  before splicing them together into one video file that's viewable in
  seconds... 16MP stills downloadable"
  ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
  checked 2026-09-27).
- **Trail Length (documented control, three settings):**
  - **Short** — "creates a comet-like trail of planes, cars and other
    passing objects. The actual stars in the night sky won't have too long
    a trail as they move quite slowly."
  - **Long** — "creates a very long comet-like trail of fast-moving objects
    like airplanes, cars and satellites."
  - **Max** — "keeps the length of the star trails as long as possible. You
    won't get the comet-like effect at all, and it's the equivalent of an
    extremely long exposure photograph."
  (Quoted from GoPro's own HERO11 Night Effects guidance as reproduced by
  [Matthew Vandeputte / matjoez.com](https://www.matjoez.com/2022/12/13/how-to-use-gopro-star-trail-mode/),
  checked 2026-09-27, and independently by
  [projectgo.pro](https://projectgo.pro/gopro-hero-13-star-trails/), checked
  2026-09-27 — both third-party guides paraphrasing the same GoPro wording,
  cross-checked against each other for consistency.)
- **Default preset values:** Trail Length: Short, Scheduled Capture: Off,
  Duration Limit: No Limit, Timer: 3 seconds, White Balance: 3200K, ISO:
  Min and Max both 800, Denoise: High (per search-index summary of
  `community.gopro.com` HERO13 Night Effects article, checked 2026-09-27 —
  GoPro's own stated defaults, could not be independently re-verified
  against the raw page due to the JS-rendering issue above, but consistent
  with the HERO11-era defaults reported by Digital Camera World: color
  temperature "stuck at 3200K," ISO 100–1600 with 800 default).
- **Shutter range (HERO11-era, vendor UI, hands-on report):** 0.5 s to 30 s,
  in coarse steps that "jump from 10 seconds to 30 seconds" with no 20 s
  option; ISO 100–1600, default 800; no exposure compensation; white balance
  fixed at 3200K in this mode
  ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
  checked 2026-09-27).
- **How trails are built — undocumented by GoPro.** GoPro's public articles
  describe the *outcome* ("stitches them together into a video showing the
  movement of the night sky") but not the blending math. The most credible
  third-party technical explanation, **labelled as third-party analysis, not
  vendor fact**: GoPro accumulates the sequence using a **"lighten" (max)
  blend** — for each pixel position, the brightest value across all frames
  is kept, which is the standard technique used by desktop star-trail
  stacking tools like StarStaX, and is consistent with what a real star
  trail composite looks like (continuous arcs from Earth's rotation, not
  raised background noise from averaging). This is inferred from output
  behavior, not from a public statement of the algorithm
  (search-engine synthesis of star-trail stacking community sources,
  checked 2026-09-27; no single primary URL states this as GoPro's internal
  implementation). This entire stacking step happens **in-camera**, not in
  the Quik app — the Quik app is used afterward only to preview, trim, or
  pull still frames from the finished video, per the Digital Camera World
  account above ("appear in the Quik app as a low-resolution preview, easy
  to edit").
- **Known limits:**
  - No way to exclude a bad frame from the accumulated trail: "it would be
    helpful if individual frames could be removed. That's the only way to
    combat airplanes, satellites and neighbor's lights being switched on
    mid-trail becoming part of the star trail file"
    ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
    checked 2026-09-27). This is the single most-repeated complaint across
    every hands-on source found.
  - Fixed lens FOV: HERO13's standard lens is a 156° hyperfisheye FOV; an
    add-on Ultra Wide Lens Mod extends it to 177°; Linear FOV digitally
    corrects distortion at the cost of some field
    ([havecamerawilltravel.com HERO13 sample review](https://havecamerawilltravel.com/action/gopro-hero13-black-sample-images/)
    and [GoPro HERO13 Digital Lenses FOV Information](https://community.gopro.com/s/article/HERO13-Black-Digital-Lenses-FOV-Information?language=en_US),
    checked 2026-09-27). There is no interchangeable-lens option.
  - Small sensor, high noise at night: "images indoors or in low light are
    highly likely to suffer from pretty strong image noise... GoPro cameras
    use a small 1/2.3-inch sensor"
    ([havecamerawilltravel.com](https://havecamerawilltravel.com/action/gopro-hero13-black-sample-images/),
    checked 2026-09-27). GoPro's own noise-reduction control offers
    High/Default, Medium, or Low, trading noise against fine detail (same
    source). The HERO11-era sensor used for Night Effects is larger — a
    1/1.9" (6.4×5.6 mm) CMOS with an f/2.8, 12 mm-equivalent lens, reaching
    ISO 1600 for photos ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
    checked 2026-09-27).
  - Rolling shutter: GoPro does not publish per-model rolling shutter
    readout times. Third-party technical measurement of a related GoPro
    sensor generation (IMX-family, GoPro "Mission 1" analysis) found the
    sensor "reads out rows sequentially from top to bottom; at 4K30
    resolution with 3072 active lines at 2.57 µs per line, the full frame
    takes 7,889 µs (nearly 8 ms) to read out," and that "low light makes
    the jello effect worse because the camera must use slower shutter
    speeds to gather enough light... giving more time for movement to
    occur during the sensor readout" — **third-party engineering analysis,
    not a GoPro-published spec**
    ([HYPOXIC, GoPro image-pipeline teardown](https://gethypoxic.com/blogs/technical/gopro-mission-1-gp3-image-pipeline),
    checked 2026-09-27). Rolling shutter is not relevant to a static
    tripod star-trail capture (no fast pan), but matters for Vehicle Light
    Trails shot from or near a moving subject.
  - Battery/thermal endurance: a 4–5 hour all-night star trail exceeds a
    single GoPro battery; a power bank is required, and GoPro's built-in
    battery (Mini variants) or Enduro pack (full-size) both need external
    power for long sessions ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
    checked 2026-09-27).
- **Recommended settings — from GoPro's own defaults vs. experienced users:**
  GoPro's shipped default (ISO 800 fixed, WB 3200K, Trail Length Short) is
  tuned for quick social clips, not deep-sky detail. Experienced users
  consistently deviate: 30 s shutter (the max available) to maximize light,
  Trail Length Long or Max instead of the Short default, and disabling
  HyperSmooth stabilization for long exposures because "HyperSmooth causes
  the optical sensor to shift slightly during 30-second long exposures,
  producing blurred stars" (this HyperSmooth claim is third-party field
  advice, not GoPro documentation — flagged as such —
  [goprotimelapse.com night-lapse guide](https://goprotimelapse.com/night-lapse-guide),
  checked 2026-09-27; treat this specific site's numeric claims, e.g. "27MP
  GPR RAW," with caution — its per-megapixel and file-format figures did not
  match any primary GoPro spec found and may be generated/aggregated
  content rather than tested fact). Cross-checked, non-suspect field advice
  from two independent sources: shutter 30 s, ISO capped around 800 for
  dark sky, Trail Length Long/Max recommended over Short
  ([projectgo.pro](https://projectgo.pro/gopro-hero-13-star-trails/),
  [matjoez.com](https://www.matjoez.com/2022/12/13/how-to-use-gopro-star-trail-mode/),
  both checked 2026-09-27).

### 1.2 Night Effects: Light Painting and Vehicle Light Trails

- **Mechanism (vendor-documented, same article as Star Trails):** "Light
  Painting uses a light source with movement to create a design in the
  dark. Once you start the capture, any light motion is saved as a line,
  and the individual images captured will be stitched together in a video."
  "Vehicle Lights allows you to create artistic urban scenes with vehicles
  moving through the image. Like Light Painting, once you start the
  capture, any light motion is saved as a line, and the individual images
  captured will be stitched together in a video"
  ([community.gopro.com Night Effects](https://community.gopro.com/s/article/Night-Effects-Star-Trails-Light-Painting-And-Vehicle-Lights?language=en_US),
  checked 2026-09-27, via search-engine summary — same fetch limitation as
  above). Mechanically this is the same accumulate-and-stitch pipeline as
  Star Trails; only the subject differs (a handheld or vehicle-borne light
  source instead of the sky).
  - **Direct video capture, not photo-splicing.** Reporting on Vehicle
    Lights specifically: default shutter 30 s (range 0.5 s–30 s), interval
    Auto, Trail Length Max/Long/Short as in Star Trails
    (search-engine synthesis of GoPro low-light guides, checked
    2026-09-27 — third-party aggregation of vendor UI values, not a single
    primary citation).
- **Settings guidance (third-party, cross-checked across two independent
  low-light guides):** "shutter determines exposure time, with 30 seconds
  or less recommended... interval adjusts the frequency of shots — shorter
  intervals work for fast events like lightning, while longer intervals
  suit slower durations like clouds passing by... adjust shutter first,
  then raise ISO if needed" up to 800 or 1600 for very dark skies
  (search-engine synthesis, checked 2026-09-27, no single primary
  first-party URL fetchable — treated as third-party field consensus).

### 1.3 Night Lapse Video / Night Lapse Photo (distinct from Night Effects)

- Night Lapse is GoPro's general dark-scene timelapse mode, separate from
  the three Night Effects presets, and is the mode to use for a
  slower-cadence sky timelapse rather than a trail. Night Lapse Photo saves
  individual frames (RAW where the format supports it) for manual stacking
  later; Night Lapse Video produces a stitched MP4 directly, the same as
  Night Effects.
- **Recommended settings (third-party field consensus for deep dark-sky
  work, cross-checked across two sources):** 20–30 s shutter, ISO 100
  minimum and 400–800 maximum ("never exceed ISO 800 on GoPro sensors to
  prevent noise degradation" is field advice, not a GoPro-stated ceiling),
  white balance around 4000K, HyperSmooth off
  ([goprotimelapse.com](https://goprotimelapse.com/night-lapse-guide),
  cross-checked qualitatively against
  [projectgo.pro night settings](https://projectgo.pro/gopro-hero-13-night-settings/),
  both checked 2026-09-27; the specific "27MP GPR" file-size claim on the
  first source is not independently confirmed and is excluded above).
- **Hands-on verdict on clear nights (independent, credible source):**
  "Night Lapse videos are poor on clear nights. While the Star Trail mode
  works really well and stars look bright, that's not the case with Night
  Lapse videos, during which stars are virtually invisible in urban
  conditions... The only scenario in which Night Lapse impressed during our
  test was when clouds were sweeping across a location"
  ([Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on),
  checked 2026-09-27). This is a meaningful signal: GoPro's own in-camera
  Night Lapse Video processing pipeline underperforms its Star Trails
  pipeline for starfields specifically, even though both draw from the same
  sensor and shutter range.
- **Exposure ramping / deflicker:** GoPro holds a granted US patent,
  "Optimized exposure temporal smoothing for time-lapse mode" (US10771712B2
  / US11588984B2), which documents an algorithmic approach to smoothing
  exposure changes across a timelapse sequence to avoid step-change flicker
  — this is a real, vendor-authored technical document (a patent, not a
  support article), confirming GoPro has engineered a deflicker/ramping
  solution, though the patent language is legal/technical rather than a
  user-facing settings guide
  ([Google Patents, US10771712B2](https://patents.google.com/patent/US10771712),
  checked 2026-09-27). No GoPro support article was found describing a
  user-facing "auto ramp" control comparable to Holy Grail rigs (see §4).

---

## 2. DJI (Osmo Action, Osmo Pocket, Insta360, and DJI drones)

### 2.1 DJI Osmo Action 5 Pro / Action 6 — SuperNight

- **Documented mechanism:** "In extremely low-light conditions, Osmo Action
  6/Osmo Action 5 Pro shines with its AI noise reduction algorithms.
  Activate SuperNight Scene mode to tackle low-light challenges and achieve
  purer visuals" — DJI names this as an AI-based noise-reduction feature
  directly in its own support documentation, not third-party inference
  ([DJI support: About the SuperNight Mode of Osmo Action 6/Osmo Action 5 Pro/Osmo 360](https://support.dji.com/help/content?customId=en-us03400011417&spaceId=34&re=US&lang=en&documentType=artical&paperDocType=paper),
  checked 2026-09-27).
- **Documented limits:** SuperNight supports 8-bit color depth (Action 5
  Pro) or 10-bit (Action 6) at ≤60 fps; it does **not** support
  HorizonBalancing, HorizonSteady, the 155° ultra-wide FOV, or 4:3 aspect
  ratio; Action 6 additionally drops 9:16 vertical shooting in this mode
  (same source). This is a real-time video "scene mode," not a
  multi-minute stacked stills mode like GoPro Night Effects or Pixel
  Astrophotography — it applies AI denoising to normal-cadence video, useful
  for handheld/action night footage more than tripod deep-sky work.
- **Timelapse/Hyperlapse:** DJI documents Timelapse ("suitable for shooting
  from a fixed position with the camera remaining stationary") and
  Hyperlapse ("suitable for use in mobile scenarios like attaching to
  vehicles") as separate modes across the whole Osmo line. For starry-sky
  timelapse specifically, DJI's own guidance (given for the Osmo 360
  series but stated as general starry-sky advice) is: "Timelapse > Custom >
  Interval recommended: 30 seconds"
  ([DJI support: Using Timelapse with Handheld Products](https://support.dji.com/help/content?customId=en-us03400006828&spaceId=34&re=US&lang=en),
  checked 2026-09-27). No dedicated "Star Trails" preset comparable to
  GoPro's was found documented for the Osmo Action or Pocket lines as of
  this check — DJI's night capability on these bodies is SuperNight
  (single-frame-cadence AI denoise) plus generic Timelapse/Hyperlapse, not
  a purpose-built star-trail stacker.

### 2.2 DJI Osmo Pocket 3 / 4 / 4P

- Documented modes: Timelapse, Motionlapse (waypoint-driven, Pocket 4P
  only), and Hyperlapse, each with settable resolution, frame rate,
  interval, and duration; Pocket 4P Timelapse/Hyperlapse support 1x/3x
  zoom (same DJI support source as above, checked 2026-09-27).
- Pocket 3's sensor was documented by DJI as upgraded "from 1/1.7 inches to
  1 inch to deliver... low-noise night shots" — a 1-inch sensor is
  meaningfully larger than GoPro's 1/1.9–1/2.3-inch sensors, and DJI states
  this explicitly as a night-photography benefit (search-index summary of
  DJI Osmo Pocket 3 product documentation, checked 2026-09-27 — treated as
  DJI-stated spec, not independently re-measured).
- Pro mode (Pocket 3/4/4P) allows manual shutter control and saving
  individual frames as Video + JPEG or Video + RAW alongside the generated
  timelapse video, which is the closest DJI handheld analogue to GoPro's
  Night Lapse Photo — frame-level RAW capture for external stacking (same
  DJI support source, checked 2026-09-27).

### 2.3 DJI drones — Hyperlight and night hyperlapse

- **No dedicated "night mode" per DJI, by design:** community and
  third-party technical discussion states plainly that "there's no
  dedicated night mode according to DJI, as all video processing goes
  through the same pipeline" — this is a **third-party characterization**,
  not a DJI support-page statement, since no DJI first-party page
  describing "Hyperlight" internals could be fetched during this check
  (search-engine synthesis of DJI drone community sources — MavicPilots
  forum, vicvideopic.com — checked 2026-09-27).
- **Hyperlight (undocumented by DJI, third-party analysis only):**
  described by experienced users as a night mode that "takes multiple
  images and merges them together to reduce noise," and separately as
  something that "adds noise reduction and smoothness for low-lit shots as
  well as ramping up the exposure, shadows and dropping the highlights."
  DJI has not published a technical description of Hyperlight's internal
  algorithm as of this check; both characterizations above come from the
  MavicPilots community forum thread "Hyperlight: What is it actually
  doing?" and are **explicitly third-party speculation/analysis, not
  vendor documentation** (checked 2026-09-27, no DJI first-party
  confirmation found).
- **Drone hyperlapse for night/low light (credible third-party technical
  source):** DPReview's hyperlapse how-to states "it usually works better
  to shoot hyperlapses rather than video at night because you can use
  longer exposures to gather more light than the shutter speed constraints
  of real-time video allow. The Air 2S can capture photos with exposure
  times up to eight seconds"
  ([DPReview, DJI Air 2S hyperlapse technique](https://www.dpreview.com/articles/6061230102/how-to-shoot-great-hyperlapse-video-on-the-dji-mavic-air-2/),
  checked 2026-09-27). This mirrors the same architecture as GoPro/Pixel/
  the Dark Sky app: night quality comes from stacking longer per-frame
  stills, not from a single long real-time video exposure.

### 2.4 Insta360 (Ace Pro 2, X-series)

Insta360's own online manual is directly fetchable and gives the clearest
first-party mode documentation of any vendor checked.

- **Starlapse Mode (X3/X4/X4 Air/X5/X6):** "accurately captures dynamic
  light and shadow changes of the starry sky, helping you create clear,
  layered time-lapse works." Screen brightness is automatically reduced
  during capture "to reduce light pollution from the screen in dark
  environments and preserve the quality of the starry sky images,"
  explicitly stated to affect only the live display, not the final exposure
  ([Insta360 online manual: X Series Starlapse Mode](https://onlinemanual.insta360.com/x4/en-us/operating-tutorials/capture-preview/shooting-mode/starlapse),
  checked 2026-09-27).
- **Ace Pro / Ace Pro 2 — three distinct, separately named night modes**
  (this is the most granular vendor documentation found across the whole
  survey):
  - **Starlapse:** "automatically captures multiple starry sky photos and
    compiles them into a timelapse video, showcasing the dynamic effect of
    stars moving across the night sky." Real-time playback, sky drifts but
    does not trail.
  - **Star Trails Video:** "automatically captures multiple photos and
    compiles them into a timelapse video of star trails, showcasing the
    dynamic effect of stars' motion trails stretched into lines" — a video
    whose content is the *growing* trail, analogous to GoPro's Star Trails
    video output.
  - **Star Trails Photo:** "automatically captures multiple photos and
    compiles them into a single static photo, showcasing the static image
    of stars' motion trails stretched into lines" — a single stacked still,
    which none of the GoPro presets directly offer as a native in-camera
    output (GoPro's Star Trails mode is video-first; a still requires
    pulling a frame from the finished video, whereas Insta360 renders the
    full-duration stack as a still directly).
  ([Insta360 online manual: Ace Series Starlapse Mode](https://onlinemanual.insta360.com/acepro2/en-us/operation-tutorials/shoot-preview/shooting-modes/starlapse),
  checked 2026-09-27). The manual also documents that both an "original
  media" (the raw frame sequence) and an "effect-synthesized media" (the
  finished stack/trail) are saved every time, and that the composited
  output type can be re-chosen afterward in the Insta360 app from the
  original frames — i.e., the frame sequence is retained and reprocessable,
  not discarded after in-camera compositing (same source).
- **PureVideo (AI denoise, documented as an option, not exclusionary of
  other modes):** Insta360's dedicated low-light video mode "uses AI to
  intelligently reduce noise without flattening texture," is "optimized
  with algorithms for low-light conditions such as night scenes," and on
  Ace Pro 2 runs on "a dual AI chip setup: one for noise reduction and one
  for performance, with PureVideo support at up to 4K60fps"
  ([Insta360 PureVideo product/support pages](https://onlinemanual.insta360.com/acepro/en-us/operation-tutorials/shoot-preview/shooting-modes/ace-series-purevideo),
  checked 2026-09-27, cross-checked against Insta360 X5 marketing copy for
  the dual-chip claim). This is a separate, general low-light video mode,
  not part of the Starlapse/Star Trails pipeline; Insta360 Studio also
  offers an optional AI grain-removal pass at export
  ([Insta360 Studio manual, AI Effects/Remove Grain](https://onlinemanual.insta360.com/studio/en-us/operation-guide/file-management/ai-processing-image-noise-reduction),
  checked 2026-09-27).

---

## 3. Phones for comparison (published, documented methods only)

### 3.1 Google Pixel — Night Sight Astrophotography

Source: Google's own AI Blog technical write-up, the single most detailed
first-party disclosure found in this entire survey
([Astrophotography with Night Sight on Pixel Phones, Google AI Blog, Nov. 2019](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html),
checked 2026-09-27).

- **Frame count and exposure:** up to **15 frames**, each up to **16 s**,
  giving a maximum ~4-minute total exposure on Pixel 4; Pixel 3/3a capped
  total exposure at 1 minute. Per-frame time is capped at 16 s specifically
  because "motion-blurred stars that look like short line segments look
  wrong" at longer per-frame exposures — the frame length is chosen to keep
  stars as points, not because of a hardware shutter ceiling.
- **Alignment and combination:** "The frames are first aligned, compensating
  for both camera shake and in-scene motion, and then averaged, with careful
  treatment of cases where perfect alignment is not possible." This is
  align-then-average (a mean stack, conceptually the same family of
  operation as the Dark Sky app's sigma-clipped mean), not a max/lighten
  trail blend — Pixel Astrophotography produces a clean deep-sky still, not
  a star-trail image.
  - Google's stated reason for keeping total capture to 15 frames / 4
    minutes rather than more: "more tightly constrained by the
    photographer's patience. Few are willing to wait more than four minutes
    for a picture" — a deliberately UX-driven cap, not a technical one.
- **Hot pixel / warm pixel handling:** identified "by comparing the values
  of neighboring pixels within the same frame and across the sequence of
  frames recorded for a photo, and looking for outliers," then "concealed
  by replacing its value with the average of its neighbors" (spatial +
  temporal outlier detection and infill — original pixel value is
  discarded).
- **Post-shutter viewfinder:** because the live viewfinder is limited to
  ~66 ms per frame and goes "mostly gray" below roughly full-moon light
  levels, Night Sight instead shows each just-captured long-exposure frame
  on screen as soon as it lands, letting the photographer reframe mid-shot;
  the shot can then be restarted once framing looks right.
- **Post-shutter autofocus:** in very low light, normal continuous-viewfinder
  autofocus fails; Pixel 4 instead captures two dedicated up-to-1-second
  autofocus frames after the shutter press, used only to rack focus (not
  part of the final image); if even that fails, the lens focuses at
  infinity, with a manual-focus override always available.
- **Sky processing (ML-based, documented as an option/enhancement, not a
  generative replacement):** "we use machine learning to detect which
  regions of an image represent sky. An on-device convolutional neural
  network, trained on over 100,000 images that were manually labeled by
  tracing the outlines of sky regions, identifies each pixel... as 'sky' or
  'not sky.'" This segmentation is then used to selectively darken the sky
  (countering the "night scene looks like day" effect of long exposure),
  apply sky-specific noise reduction, and boost contrast for clouds/Milky
  Way detail — all masked adjustments to an already-captured, aligned
  average, not pixel generation.
- **Documented ceiling:** Google states dynamic range "can exceed
  500,000:1" between the sky and bright light sources like the moon, and
  that as of this write-up Night Sight "so far prevents us from capturing
  both" a well-exposed moonlit landscape and lunar surface detail in one
  frame — an explicit, vendor-acknowledged limit.

### 3.2 Samsung Expert RAW — Astrophotography mode

- **Availability:** Expert RAW is a separate Galaxy Store app "available on
  Galaxy S20 or later," with "Astrophotography and multiple exposure modes...
  supported on S23 series, S22 series (T OS) devices" specifically, and
  "Special photo options are only activated when set to 12MP resolution"
  ([Samsung UK support: Professional Photography with Galaxy Expert RAW App](https://www.samsung.com/uk/support/mobile-devices/professional-photography-with-galaxy-expert-raw-app/),
  checked 2026-09-27).
- **Astrophotography mode:** documented as letting the user "adjust the
  focus, white balance, and exposure time to capture the night sky and its
  celestial objects," with an optional Sky Guide constellation overlay
  (same source). Samsung's own page does not give per-frame exposure time,
  frame count, or stacking-algorithm detail for this mode.
- **Multiple Exposure mode (documented, adjacent feature used for astro by
  the community):** "taking one photo by accumulating and combining
  different images with multiple exposures into one single image," with a
  continuous or manual capture cadence and selectable "combination modes"
  (same source) — Samsung names the accumulation behavior but not the
  underlying blend math (max vs. average) per combination mode.
- **Duration and stacking, third-party (not on Samsung's own support page):**
  reported by third-party guides as capturing "for 3–5 minutes, stacking
  star trails," using "Image Stacking" that "takes several relatively short
  exposure photos and synthesizes them according to the movement of the
  celestial objects" — **labelled as third-party description**, since
  Samsung's own fetched support page does not state a duration or frame
  count (search-engine synthesis of Android Police / Samsung community
  sources, checked 2026-09-27).
- **Output:** both JPEG and 16-bit linear DNG RAW are saved, per Samsung's
  own documentation of Expert RAW generally (same first-party source).

---

## 4. Techniques to adopt, and what AVFoundation can/can't do

| Technique | How vendors do it | Feasible on iPhone via `AVCaptureDevice`/`AVCapturePhotoOutput`? |
|---|---|---|
| **Star-trail video** (cumulative max blend, growing over real time) | GoPro Star Trails, Insta360 Star Trails Video: accumulate frames with a lighten/max blend (GoPro: undocumented, inferred; Insta360: documented as "motion trails stretched into lines" but internal blend math likewise undocumented), render as a playable video that grows the trail frame by frame | Yes, and the app already has the primitive: `StackAccumulator(mode: .maximum)` is documented in `CAPTURE-LIMITS.md` §"Star-trail designer" as already building the unaligned per-pixel maximum from every saved 1 s frame. What's missing for a *video* (vs. a single final stacked photo) is rendering an intermediate frame after each accumulation step and encoding those as a video track — a SkyCore/export-layer feature, not a new capture capability. No AI needed; this is pure deterministic max-blending, consistent with ADR-0011. |
| **Gap filling between frames** | Not vendor-documented for GoPro or Insta360 (neither states whether they interpolate between exposures or leave a arc segment gap during the interval between frames). GoProTimelapse's Lightroom+StarStaX pipeline explicitly offers a "Gap-Filling Blending Mode" in StarStaX as a *third-party desktop tool*, not something GoPro's own firmware is documented to do. | The app's own `CAPTURE-LIMITS.md` already states the deterministic answer: "Keep the interval equal to the exposure (1 s here) for unbroken trails; a longer interval leaves gaps." At 1 s exposure with 1 s interval there is no dead time between frames, so gap-filling by interpolation is unnecessary at the app's native cadence — this is actually a structural advantage over GoPro (whose 30 s shutter + Auto interval can leave real dead time between long exposures) and over Insta360/Samsung, where the same shutter-vs-interval question is undocumented. If a future mode allows interval > exposure (e.g. to conserve storage), gap interpolation between the two nearest real stars' positions would need to be pure geometry (known star motion rate), not learned inference — deterministic and testable in SkyCore. |
| **"Comet" fading trails** | GoPro Trail Length Short/Long: explicitly documented as giving fast-moving objects (planes, cars, satellites) a fading comet tail rather than a full-length arc, implying older frames are weighted down or dropped from the accumulation as the window ages — undocumented mechanism, but the *effect* (a moving, bounded-length trail) is vendor-stated. | Buildable deterministically as a sliding-window max blend: instead of accumulating over the *entire* capture duration (as Max/`.maximum` does today), accumulate over only the last N seconds of frames, dropping frames older than the window as new ones arrive. This is a straightforward extension of the existing `StackAccumulator` — swap "all frames ever" for "last N frames" — no new algorithm class, no AI. |
| **Night timelapse with exposure ramping ("Holy Grail")** | Traditional Holy Grail rigs (Alpine Labs Pulse, Dynamic Perception) and GoPro's own patented "temporal smoothing" (US10771712B2) exist specifically because a day-to-night pan loses "10 to 15 stops of light" while "the camera's sensor can only handle 12–14 stops at once," so exposure must be walked up gradually across the sequence to avoid a visible step-jump | Feasible in principle: the app already runs sequences of fixed-length frames; ramping means varying ISO (and, on the main camera, aperture across its four stops) frame-to-frame according to a metered brightness curve, holding shutter at the 1.0 s ceiling throughout (since exposure *time* can't be ramped past the hardware cap the way a DSLR would). Deflickering would be a deterministic post-process — matching each frame's histogram/exposure to a smooth interpolated target curve — not a generative operation, and belongs in SkyCore next to the existing sigma-clipped mean. This is the most build-effort-heavy item of the four; it needs a metering-over-time control loop that doesn't exist yet. |
| **Light painting** | GoPro Light Painting, and implicitly Vehicle Light Trails: same accumulate-and-stitch pipeline as Star Trails, just aimed at a moving light source instead of the sky; both vendor-documented as "any light motion is saved as a line" | Same `StackAccumulator(mode: .maximum)` primitive as star trails — a moving bright point against a dark, mostly-static background maxes to a line under exactly the same math as a moving star maxes to an arc. No new stacking mode needed, only a different framing/UI preset (near-field manual focus rather than infinity-ish lock, shorter total duration, no NPF/trail-length astronomy math). This is close to a free feature once star-trail video exists. |
| **Deflickering** | Same category as exposure ramping above; GoPro's patent explicitly frames it as "optimized exposure temporal smoothing." Google's Pixel pipeline sidesteps the problem differently — by aligning and averaging within one short multi-minute capture rather than ramping across a long timelapse. | For a fixed-ISO/fixed-aperture star-trail or timelapse sequence at 1 s per frame, cross-frame flicker mainly comes from atmospheric/sensor noise variance and any auto-exposure drift, not gain changes (the app locks exposure). A deterministic per-frame brightness normalization pass (matching each frame's histogram statistics to a rolling average before accumulation) is enough, and is a natural SkyCore addition — no AI/generative step required. |

**On AI/ML more broadly:** several vendors use it as a documented *option*
layered on top of deterministic capture, not as a replacement for it —
DJI's SuperNight is stated by DJI itself to be "AI noise reduction
algorithms"; Insta360's PureVideo is stated to "use AI to intelligently
reduce noise"; Pixel's sky segmentation is an on-device CNN used to mask
*where* a deterministic contrast/denoise adjustment applies, not to
synthesize sky content. None of these generate new image content — they
denoise or mask an already-captured signal. ADR-0011 restricts the Dark Sky
app to "no AI denoise, sky replacement, or 'enhance'" for its own
deterministic-first stacking pipeline; that scope decision stands
independent of what competing hardware documents doing. If the owner later
wants an optional ML-based denoise pass (in the Pixel/DJI/Insta360 sense of
masked, non-generative noise reduction, not generative fill), that would be
a distinct, explicitly-opted-into feature layered after the deterministic
stack — not a substitute for it — and is out of scope for this research
document to design.

---

## 5. Recommendations for the Dark Sky app

All four map onto capture the app already has (1 s ProRAW frames from
`CaptureEngine.bestFormat`) and stacking it already has
(`StackAccumulator` in SkyCore, `.maximum` and sigma-clipped mean modes per
`CAPTURE-LIMITS.md`). Nothing below needs AI/generative processing; each is
achievable as deterministic accumulation or per-frame metering, consistent
with ADR-0011.

1. **Star-trail video** (matches GoPro Star Trails Video / Insta360 Star
   Trails Video). Parameters: duration, interval = exposure (1 s, to avoid
   gaps per the existing `CAPTURE-LIMITS.md` note), and a render step that
   snapshots the running `.maximum` accumulation at a fixed cadence (e.g.
   once per N accumulated frames) and encodes those snapshots as a video
   track, alongside the still-image maximum the app already produces. This
   is the lowest-effort addition — capture and the core blend already
   exist; only the video-encoding path is new.

2. **Comet trails** (matches GoPro Trail Length Short/Long). Parameters:
   window length in seconds (or frame count), applied as a sliding-window
   variant of `.maximum` that drops frames older than the window instead of
   accumulating forever. Same underlying accumulator, one new parameter and
   a frame-eviction policy. Pairs naturally with star-trail video's
   snapshot-to-video rendering.

3. **Night timelapse with exposure ramping** (matches the "Holy Grail"
   technique, and is the one gap no competitor device fully automates in a
   documented way — GoPro's ramping patent exists but no public
   user-facing control was found, and DJI/Insta360 don't document ramping
   for handheld/action bodies at all). Parameters: start/end brightness
   targets or a metered auto-ramp across the sequence, varying ISO (and
   main-camera aperture across its four stops) frame-to-frame while holding
   shutter at the 1.0 s ceiling, plus a deterministic per-frame histogram
   deflicker pass in SkyCore before frames are handed to playback/export.
   This is the highest-effort item: it needs a metering control loop that
   doesn't exist in the capture engine yet, and is the one place the
   iPhone's 1.0 s hard ceiling is a real disadvantage versus a DSLR/GoPro
   that can hold 15–30 s and therefore needs less ISO range to cover the
   same brightness swing.

4. **Light painting** (matches GoPro Light Painting / Vehicle Light Trails).
   Parameters: duration, near-field manual focus (the app's existing
   focus-lock UI, just not locked toward infinity), and the same
   `.maximum` accumulator as star-trail video with no astronomy-specific
   framing (no celestial-pole handover needed). This is close to free once
   star-trail video's snapshot-to-video path exists — it is the same
   accumulator pointed at a different subject.

None of these require a Bayer-RAW sensor, a variable shutter beyond 1 s, or
generative AI to match or exceed what GoPro, DJI, Insta360, Pixel, and
Samsung document doing — the deciding factors are software (a video-render
path, a sliding window, a metering/ramping loop, and a deflicker pass in
SkyCore), not new hardware capability. The one place the iPhone is
structurally behind every dedicated night mode surveyed is per-frame
exposure time (1.0 s vs. 8–30 s on GoPro Night Lapse/Star Trails, up to 16 s
on Pixel, several minutes cumulative on Samsung's Astrophotography mode):
the app compensates by taking more frames, which the sigma-clipped mean and
maximum accumulators already handle, at the cost of needing a
correspondingly higher frame count and more total wall-clock time per
composite than a device with a longer native shutter.

---

## Sources

- [HERO13 Black: Night Effects: Star Trails, Light Painting, And Vehicle Lights — community.gopro.com](https://community.gopro.com/s/article/HERO13-Black-Night-Effects-Star-Trails-Light-Painting-And-Vehicle-Lights?language=en_US) (checked 2026-09-27; JS-rendered, full text not directly fetchable — title/existence confirmed via search index)
- [Night Effects: Star Trails, Light Painting, And Vehicle Lights (generic) — community.gopro.com](https://community.gopro.com/s/article/Night-Effects-Star-Trails-Light-Painting-And-Vehicle-Lights?language=en_US) (checked 2026-09-27; same fetch limitation, content via search-engine summary)
- [HERO13 Black: Time Lapse Settings And Resolutions — community.gopro.com](https://community.gopro.com/s/article/HERO13-Black-Time-Lapse-Settings-And-Resolutions?language=en_US) (checked 2026-09-27; same fetch limitation)
- [HERO13 Black: Digital Lenses FOV Information — community.gopro.com](https://community.gopro.com/s/article/HERO13-Black-Digital-Lenses-FOV-Information?language=en_US) (checked 2026-09-27)
- [I used the latest GoPro for astrophotography. Here's how I got on — Digital Camera World](https://www.digitalcameraworld.com/tutorials/i-used-the-latest-gopro-for-astrophotography-heres-how-i-got-on) (checked 2026-09-27)
- [How to use GoPro Star Trail mode — matjoez.com](https://www.matjoez.com/2022/12/13/how-to-use-gopro-star-trail-mode/) (checked 2026-09-27)
- [GoPro Hero 13 Star Trails: Settings & Tips — projectgo.pro](https://projectgo.pro/gopro-hero-13-star-trails/) (checked 2026-09-27)
- [Best GoPro Hero 13 Night Settings For Photo & Video + Tips — projectgo.pro](https://projectgo.pro/gopro-hero-13-night-settings/) (checked 2026-09-27)
- [GoPro Night Lapse & Star Trails Master Guide — goprotimelapse.com](https://goprotimelapse.com/night-lapse-guide) (checked 2026-09-27; some figures, e.g. GPR file size/megapixel claims, appear unverified/possibly aggregated — flagged in text, not relied on for numeric specs)
- [GoPro HERO13 Black Sample Photos — havecamerawilltravel.com](https://havecamerawilltravel.com/action/gopro-hero13-black-sample-images/) (checked 2026-09-27)
- [GoPro Mission 1 PRO: GP3 Image Processing Architecture — HYPOXIC](https://gethypoxic.com/blogs/technical/gopro-mission-1-gp3-image-pipeline) (checked 2026-09-27; third-party technical teardown, not GoPro-published)
- [US10771712B2 — Optimized exposure temporal smoothing for time-lapse mode — Google Patents (GoPro)](https://patents.google.com/patent/US10771712) (checked 2026-09-27)
- [About the SuperNight Mode of Osmo Action 6/Osmo Action 5 Pro/Osmo 360 — support.dji.com](https://support.dji.com/help/content?customId=en-us03400011417&spaceId=34&re=US&lang=en&documentType=artical&paperDocType=paper) (checked 2026-09-27)
- [Using Timelapse with Handheld Products — support.dji.com](https://support.dji.com/help/content?customId=en-us03400006828&spaceId=34&re=US&lang=en) (checked 2026-09-27)
- [Drone technique: How to shoot 4K hyperlapse video on the DJI Air 2S — DPReview](https://www.dpreview.com/articles/6061230102/how-to-shoot-great-hyperlapse-video-on-the-dji-mavic-air-2/) (checked 2026-09-27)
- [Hyperlight: What is it actually doing? — MavicPilots forum](https://mavicpilots.com/threads/hyperlight-what-is-it-actually-doing.66142/) (checked 2026-09-27; community discussion/speculation, not DJI documentation — flagged in text)
- [X Series: Starlapse Mode — Insta360 online manual](https://onlinemanual.insta360.com/x4/en-us/operating-tutorials/capture-preview/shooting-mode/starlapse) (checked 2026-09-27)
- [Ace Series: Starlapse Mode — Insta360 online manual](https://onlinemanual.insta360.com/acepro2/en-us/operation-tutorials/shoot-preview/shooting-modes/starlapse) (checked 2026-09-27)
- [Ace Series: PureVideo Mode — Insta360 online manual](https://onlinemanual.insta360.com/acepro/en-us/operation-tutorials/shoot-preview/shooting-modes/ace-series-purevideo) (checked 2026-09-27)
- [Insta360 Studio: AI Effects (Remove Grain) — Insta360 online manual](https://onlinemanual.insta360.com/studio/en-us/operation-guide/file-management/ai-processing-image-noise-reduction) (checked 2026-09-27)
- [Astrophotography with Night Sight on Pixel Phones — Google AI Blog](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html) (checked 2026-09-27)
- [Professional Photography with Galaxy Expert RAW App — Samsung UK support](https://www.samsung.com/uk/support/mobile-devices/professional-photography-with-galaxy-expert-raw-app/) (checked 2026-09-27)
- `/Users/brianbusch/Developer/wt-gear/docs/ios/CAPTURE-LIMITS.md` (project source, read 2026-09-27)
- `/Users/brianbusch/Developer/wt-gear/docs/adr/0011-iphone-tripod-capture.md` (project source, read 2026-09-27)
