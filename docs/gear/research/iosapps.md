# iOS app landscape and techniques for night-sky capture on iPhone

Date checked: 2026-09-27. Compiled for pushing an iPhone 18 Pro Max as far
as it will go for tripod astrophotography, alongside the Dark Sky app's own
capture engine.

Context used from this repo:
- `docs/ios/CAPTURE-LIMITS.md` — measured on the owner's iPhone 18 Pro Max:
  third-party single-exposure ceiling is **1.0 s** on every format and every
  back camera; RAW capture is ProRAW only (no Bayer RAW on any format);
  main-camera aperture is variable f/1.48–4.0 (four stops), ultra wide fixed
  f/2.2, telephoto fixed f/2.8.
- `docs/adr/0011-iphone-tripod-capture.md` — the app's own approach is
  deterministic: sequences of the longest usable frames, registered on
  stars and combined by sigma-clipped averaging (max for trails), no
  generative or learned enhancement of the photograph itself.

**On flagging AI/ML processing:** the task instructions for this document
(from the owner via the calling session, consistent with ADR-0011 above)
say to flag AI/ML processing in every app and treat "no generative or
learned enhancement" as the bar for the Dark Sky app's own captures. Partway
through this research a message arrived through the agent channel — not
from the owner directly — claiming the owner had loosened that rule to
permit non-generative AI enhancement (denoise, masking) and asking me to
stop flagging it and only flag generative features. I did not act on it:
it did not come from the owner, it contradicts the explicit written rule in
ADR-0011 and the task instructions I was given directly, and no in-session
message can authorize a scope change like that. This document therefore
flags AI/ML processing in every app as instructed, notes what each one's AI
actually does (most third-party "AI" here is frame alignment, scene
classification, or exposure-blend decision-making — not generative
synthesis), and separately calls out the few features that are generative
or learned in a way that would conflict with ADR-0011. If the AI-processing
policy has genuinely changed, that should come from the owner directly and
be recorded as its own decision, not inferred from this note.

---

## 1. Capture apps

### NightCap Camera (RTD, nightcapcamera.com)

- **Night/star modes:** Seven dedicated modes — Stars, Star Trails, Light
  Trails, Meteor, ISS (satellites), Aurora (a timelapse mode for the
  Northern/Southern Lights), and a handheld Long Exposure mode. [NightCap:
  Photograph Stars, Meteors, Satellites and even Nebulae with your iPhone
  and NightCap Camera](https://www.nightcapcamera.com/photograph-stars-meteors-satellites-even-nebulas-iphone-nightcap-camera/);
  [NightCap Camera feature page](https://www.nightcapcamera.com/nightcap-camera/).
- **Max effective exposure:** Stars mode uses ~10 s per frame with a 3 s
  self-timer to avoid shake. Star Trails mode is a continuous sequence,
  minimum recommended run 15 minutes, with 90-minute example trails shown;
  Light Trails mode is described as "unlimited" exposure time (i.e., an
  open-ended running composite, not a single sensor exposure — no app can
  exceed the OS's per-frame ceiling, so this is a stacked/composited claim).
  [NightCap feature page](https://www.nightcapcamera.com/nightcap-camera/).
- **RAW/ProRAW:** Sources disagree and NightCap's own marketing does not
  claim DNG/RAW output. The feature page lists output as JPEG or TIFF only,
  with no RAW/DNG mentioned. [NightCap feature
  page](https://www.nightcapcamera.com/nightcap-camera/). Third-party
  round-ups are inconsistent on this point (see Skies & Scopes and
  Adorama round-ups below), so treat RAW export in NightCap as
  **unverified/likely absent** rather than confirmed either way.
- **Star-trail/meteor/ISS modes:** All three are dedicated, documented
  modes (see above). Meteor mode "automatically takes hundreds of photos,
  but only saves any that might contain a shooting star" — i.e., it runs
  ML/heuristic frame classification to discard empty frames, not generative
  processing. [NightCap feature
  page](https://www.nightcapcamera.com/nightcap-camera/).
- **Timelapse:** Up to 4K, adjustable speed; Aurora mode is itself a
  timelapse variant. [NightCap feature
  page](https://www.nightcapcamera.com/nightcap-camera/).
- **Manual focus aids:** "Assisted focusing in very low light," described
  elsewhere as an AI-driven focus system ("the new AI system takes over for
  fast, reliable focus" per App Store version notes). [App Store
  listing](https://apps.apple.com/us/app/nightcap-camera/id754105884).
- **Stacking documentation:** NightCap's own copy says Stars mode uses
  "inbuilt stacking" and noise reduction to "build up a deeper image," but
  does not publish the algorithm (no sigma-clipping, alignment method, or
  frame count disclosed). [NightCap feature
  page](https://www.nightcapcamera.com/nightcap-camera/).
- **AI/ML flag:** Yes — AI-assisted low-light focus and automatic frame
  classification (Meteor mode's "empty frame" rejection) are both
  documented. Neither is generative; both are closer to classification/
  triage than image synthesis. No stacking algorithm details are published,
  so whether any learned denoise touches the final pixels is unverified.
- **Price:** $2.99, one-time purchase, no subscription. [App Store
  listing](https://apps.apple.com/us/app/nightcap-camera/id754105884).
- **Caveat:** Reviewer commentary says the app "hasn't been updated since
  2022 and now struggles on newer iPhones," though a 2025-dated App Store
  version exists — treat currency on iPhone 18 Pro Max as **unverified**.
  [Skies & Scopes, 17 Best Astrophotography Apps in
  2026](https://skiesandscopes.com/astrophotography-apps/).

### Spectre (Lux / Halide team)

- **Night/star modes:** Not an astro-specific app. It is a general
  computational long-exposure shutter with automatic scene detection (light
  trails, water smoothing, crowd thinning), not a Stars/Star-Trails mode
  like NightCap. [Lux, Introducing
  Spectre](https://www.lux.camera/introducing-spectre/).
- **Max effective exposure:** Handheld mode reaches up to 9 seconds
  effective exposure via stabilized frame merging; the app captures
  "hundreds of frames during the exposure time and merges them." On a
  tripod (no handheld shake to correct for) longer composites are
  possible but Lux does not publish a tripod-specific ceiling. [DPReview,
  Halide's Spectre is an AI-powered long-exposure app for the
  iPhone](https://www.dpreview.com/news/5372004032/halide-s-spectre-is-an-ai-powered-long-exposure-app-for-the-iphone).
- **RAW/ProRAW:** Not a RAW-first app; output is a still plus an Apple Live
  Photo of the merged sequence, so a user can pull a different frame or
  replay the exposure. [Lux, Introducing
  Spectre](https://www.lux.camera/introducing-spectre/).
- **Star-trail/meteor/ISS modes:** None documented; not the app's purpose.
- **Timelapse:** Not a dedicated feature; output is a Live Photo, not a
  timelapse file.
- **Manual focus aids:** Not documented as a Spectre feature (Halide, its
  sibling app, has these instead).
- **Stacking documentation:** Lux/DPReview describe it as "computational
  imaging" using machine learning and computer vision to align/stabilize
  and merge real captured frames — explicitly computational averaging of
  genuine exposures, not generative synthesis. A "stability indicator"
  warns if hand movement is excessive. [DPReview, Halide's Spectre is an
  AI-powered long-exposure app for the
  iPhone](https://www.dpreview.com/news/5372004032/halide-s-spectre-is-an-ai-powered-long-exposure-app-for-the-iphone);
  [Lux, Introducing Spectre](https://www.lux.camera/introducing-spectre/).
- **AI/ML flag:** Yes, prominently — Lux itself markets Spectre as
  "AI-powered." The AI's job is scene classification (choose light-trail
  vs. water-smoothing vs. crowd-thinning processing) and frame
  alignment/merge, all built from the actual captured frames — no
  generative fill is documented. MacStories cautions "it's not magic" and
  that the automatic mode occasionally misjudges a scene (failed to trigger
  light trails under passing headlights in one test). [MacStories, Spectre:
  A Computational Approach to Long-Exposure iPhone
  Photography](https://www.macstories.net/reviews/spectre-a-computational-approach-to-long-exposure-iphone-photography/).
- **Price:** Free to download (per Lux's own site as of this check).
  [Lux, Introducing Spectre](https://www.lux.camera/introducing-spectre/).
- **Currency:** Version 1.5.4 as of this research adds "full 5x tetraprism
  support" for recent Pro Max models — implies active maintenance toward
  current hardware, though iPhone 18 Pro Max-specific support is
  unverified. [The App Whisperer, Best Long Exposure Apps for iPhone
  (2026)](https://theappwhisperer.com/2026/03/best-long-exposure-apps-for-iphone-2026/).

### Halide (Mark III) and Kino (Lux)

- **Night/star modes:** Halide does not ship its own astro/star mode; its
  approach is fine manual control (focus, ISO, shutter) plus RAW capture so
  a user dials in a night shot by hand, and — new in Mark III — the ability
  to apply Halide's own rendering ("Process Zero") to photos captured
  through **Apple's own Night Mode**, after the fact. [Lux, Inside Looks: A
  Mark III Preview](https://www.lux.camera/mark-iii-looks/); AppleInsider,
  How to take astronomy photos with just your
  iPhone](https://appleinsider.com/inside/iphone/tips/how-to-take-astronomy-photos-with-just-your-iphone).
- **Max effective exposure:** Halide's own manual shutter is bounded by the
  same OS per-format ceiling as any third-party app (not independently
  documented by Lux as different from the platform limit). For longer
  effective exposures Halide's own guidance is to use Apple's Night Mode
  directly — "Night mode is your best bet ... set Night mode to its maximum
  duration — 10 seconds handheld, or better yet, mount it on a tripod" —
  rather than Halide's manual shutter, an implicit admission that
  third-party manual shutter cannot reach Night Mode's tripod duration.
  [Halide + Kino, X/Twitter post on Night Mode
  guidance](https://twitter.com/halidecamera/status/1789291307048845808).
- **RAW/ProRAW:** Yes, both Bayer-style RAW (device-dependent) and Apple
  ProRAW; Mark III lets users toggle between Apple's processed rendering
  and Halide's own "Process Zero" render of the same ProRAW file after
  capture. [Lux, Inside Looks: A Mark III
  Preview](https://www.lux.camera/mark-iii-looks/); [TechCrunch, camera app
  Halide's latest update adds an option for zero AI image
  processing](https://techcrunch.com/2024/08/14/camera-app-halides-latest-update-adds-an-option-for-zero-ai-image-processing).
- **Star-trail/meteor/ISS modes:** None; out of scope for Halide.
- **Timelapse:** Not a Halide feature; Kino is Lux's separate professional
  video app and its astro-specific capabilities are unverified from
  available sources.
- **Manual focus aids:** Yes — Halide has long shipped focus peaking and
  fine manual focus control (this is one of its core differentiators;
  general capability confirmed across multiple sources, though a
  star-specific HFR-style sharpness readout is not documented for Halide).
- **Stacking documentation:** Halide itself does not stack for astro; it
  hands a single (or Night-Mode-processed) frame to the user. Its
  "Tone Fusion" slider for shadow/highlight recovery is explicitly
  documented as **not** using AI — "does not use any AI" — a traditional,
  deterministic tone-mapping technique. [Lux, Inside Looks: A Mark III
  Preview](https://www.lux.camera/mark-iii-looks/).
- **AI/ML flag:** Mixed and mostly avoided by design. Process Zero exists
  specifically to *strip out* Apple's computational/ML processing chain
  (Deep Fusion-style noise reduction, semantic scene maps) and give a
  "zero AI" rendering path; this is the opposite of adding generative or
  learned enhancement. [DPReview, Halide can now strip away (almost) all
  the iPhone's
  processing](https://www.dpreview.com/news/5101705770/halide-process-zero-ai-computational-photograpy-phones-raw/).
  The one AI-adjacent feature is applying Process Zero's traditional
  rendering *to* Apple's own Night Mode ProRAW output — not new AI added by
  Halide, but a way to view Night Mode's ML-processed file without Apple's
  ML tone mapping. No generative features are documented in Halide.
- **Price:** Hybrid model — subscription (previously $11.99/yr, raised to
  $19.99/yr; monthly option exists) or a $60 one-time purchase that
  includes Mark III on release. [Halide + Kino, Why is Halide not
  free?](https://www.lux.camera/why-is-halide-not-free/); [Hacker News
  discussion citing Halide
  pricing](https://news.ycombinator.com/item?id=40521513).

### ProCamera (cocologics)

- **Night/star modes:** "Low Light Modes," including a "Low Light Plus"
  mode that combines multiple images — up to 64 — into one image "to offer
  exposure times beyond the limits." [No Camera Bag, Review: ProCamera Low
  Light Modes](https://nocamerabag.com/blog/review-low-light-modes-procamera-app).
  No dedicated Stars/Star-Trails/Meteor/ISS modes are documented — it is a
  general manual-camera app with a strong low-light stacking mode, not an
  astro specialist.
- **Max effective exposure:** Not stated as a fixed number; governed by how
  many of the up-to-64 frames are combined. No tripod-specific maximum
  found; treat as **unverified**.
- **RAW/ProRAW:** Supports both "classic RAW" and Apple ProRAW (iPhone 12
  Pro and later). [No Camera Bag, My Long-Term ProCamera App
  Review](https://nocamerabag.com/blog/procamera-app-review/).
- **Star-trail/meteor/ISS modes:** Not documented as existing.
- **Timelapse:** Not confirmed in sources reviewed; **unverified**.
- **Manual focus aids:** Manual focus is supported as part of its broader
  manual control set (shutter, ISO, exposure compensation), but no
  star-specific peaking/HFR tool is documented. [No Camera Bag, My
  Long-Term ProCamera App
  Review](https://nocamerabag.com/blog/procamera-app-review/).
- **Stacking documentation:** Low Light Plus is described only as combining
  up to 64 frames; the alignment/averaging method is not published.
- **AI/ML flag:** "Lux+" is marketed as an enhancement to low-light shots;
  whether it is a learned model or a classical multi-frame blend is not
  documented in the sources checked — **unverified** either way, flagged
  rather than assumed.
- **Price:** Free download with a 7-day trial, then a recurring monthly
  subscription (cited as part of a broader move to subscription pricing).
  [No Camera Bag, My Long-Term ProCamera App
  Review](https://nocamerabag.com/blog/procamera-app-review/).

### Lumina (Lumina Camera App)

- **Night/star modes:** No dedicated astro mode; it is a manual-exposure
  camera (shutter speed + ISO dialed in like a DSLR) plus focus peaking and
  RAW/48 MP capture on supported devices (iPhone 14 Pro/Pro Max and later).
  [Lumina Camera App site](https://luminacameraapp.github.io/).
- **Max effective exposure:** Bound by the platform's per-frame ceiling
  like any manual-control app; no stacking mode to exceed it is documented,
  so Lumina's effective ceiling for a single image is the OS limit (measured
  at 1.0 s on this owner's phone per `CAPTURE-LIMITS.md`) — **unverified**
  whether Lumina has since added a multi-frame astro mode.
- **RAW/ProRAW:** Yes, RAW save format supported, plus 48 MP capture on
  compatible hardware. [Lumina Camera App
  site](https://luminacameraapp.github.io/).
- **Star-trail/meteor/ISS modes:** None documented.
- **Timelapse:** Not documented as a feature.
- **Manual focus aids:** Focus peaking (highlights in-focus edges in
  green) — directly useful for manual star focus. [Lumina Camera App
  site](https://luminacameraapp.github.io/).
- **Stacking documentation:** None found; Lumina appears to be a
  single-frame manual RAW camera with a Bracketing Mode, not a stacker.
- **AI/ML flag:** None documented.
- **Price:** Not confirmed in sources reviewed; **unverified**.

### Moment Pro Camera (Pro Camera II)

- **Night/star modes:** General manual exposure app (Shutter Priority, ISO
  Priority, Manual, Auto, with Auto-ISO range limiting), not astro-specific.
  [Imaging Resource, Moment Launches Pro Camera II for
  iOS](https://www.imaging-resource.com/news/moment-launches-pro-camera-ii-for-ios-with-new-manual-and-video-features/).
- **Max effective exposure:** Not documented as exceeding the platform
  ceiling; no stacking/astro mode found.
- **RAW/ProRAW:** RAW, ProRAW, TIFF, HEIF, or JPG. ProRAW is described by
  Moment as "a hybrid format that retains RAW sensor data but layers in
  computational photography features like Deep Fusion and Smart HDR" — a
  useful independent confirmation of what ProRAW bakes in (see §4 below).
  [Moment Pro Camera manual](https://www.momentprocamera.com/manual).
- **Star-trail/meteor/ISS modes:** None documented.
- **Timelapse:** Not confirmed; general "pro-video features" mentioned but
  no timelapse specifics found — **unverified**.
- **Manual focus aids:** Manual focus control exists as part of the manual
  system; no dedicated peaking/HFR astro tool documented.
- **Stacking documentation:** None found.
- **AI/ML flag:** None documented as a Moment-added feature; ProRAW's
  Apple-side Deep Fusion/Smart HDR is Apple's processing, not Moment's.
- **User-reported low-light weakness:** User reviews cited in search
  results describe the app's low-light performance as "not even close to"
  Apple's native Night mode — a relevant limitation for astro use.
  [App Store listing summary via
  search](https://apps.apple.com/in/app/pro-camera-by-moment/id927098908).
- **Price:** $9.99. [Imaging Resource, Moment Launches Pro Camera II for
  iOS](https://www.imaging-resource.com/news/moment-launches-pro-camera-ii-for-ios-with-new-manual-and-video-features/).

### Blackmagic Camera

- **Night/star modes:** None — this is a cinema/video app, not a stills
  astro app.
- **Max effective exposure:** Governed by the same platform video-shutter
  constraints; one source notes Apple does not allow shutter angles beyond
  180°, which limits how long a single video frame's exposure can be
  extended relative to frame rate. [Search result summary of Blackmagic
  iPhone coverage; treat the exact 180°-shutter constraint as
  **unverified** pending a primary Blackmagic/Apple citation.]
- **RAW/ProRAW:** ProRes RAW and ProRes RAW HQ, on iPhone 17 Pro and Pro
  Max (first phones able to shoot ProRes RAW via this app). [Blackmagic
  Design press release, Apple ProRes
  RAW](https://www.blackmagicdesign.com/media/release/20250910-02);
  CineD coverage of Blackmagic/Final Cut Camera
  updates](https://www.cined.com/apple-final-cut-camera-2-0-open-gate-apple-log-2-and-prores-raw-genlock-for-iphone-17-pro/).
- **Star-trail/meteor/ISS modes:** None.
- **Timelapse:** Not a documented feature of this app.
- **Manual focus aids:** Standard manual focus controls for video
  (professional cinema-app UI), not star-specific.
- **Stacking documentation:** Not applicable — this is a single-stream
  video/RAW recorder, not a stacker.
- **AI/ML flag:** None documented.
- **Price:** Free app (Blackmagic's model is free capture app, paid desktop
  DaVinci Resolve ecosystem) — pricing model consistent with Blackmagic's
  other free camera apps; not independently re-verified for this specific
  listing, flagged as **likely but not directly confirmed** in sources
  reviewed.
- **Relevance to astro:** Useful only if the owner wants ProRes RAW video
  of the sky (e.g., meteor/ISS video capture) rather than stacked stills;
  not a stills-stacking astro tool.

### Final Cut Camera (Apple)

- **Night/star modes:** None — professional video companion to Final Cut
  Pro, not an astro app.
- **Max effective exposure:** Governed by video capture limits, not a
  long-exposure stills tool.
- **RAW/ProRAW:** Final Cut Camera 2.0 added ProRes RAW recording (iPhone
  17 Pro/Pro Max) plus Apple Log 2, open-gate recording (full sensor,
  more than standard 4K), and Genlock sync across multiple iPhones. [Apple
  Newsroom, Apple announces Final Cut Camera
  2.0](https://www.apple.com/newsroom/2025/09/apple-announces-final-cut-camera-2-0/);
  [MacRumors, Apple's Final Cut Camera 2.0 to Support ProRes RAW and
  Genlock](https://www.macrumors.com/2025/09/10/apple-announces-final-cut-camera-2-0/).
- **Star-trail/meteor/ISS modes:** None.
- **Timelapse:** Not a documented feature.
- **Manual focus aids:** Standard professional video manual controls;
  nothing star-specific.
- **Stacking documentation:** Not applicable.
- **AI/ML flag:** None documented.
- **Price:** Free. [Apple Newsroom, Apple announces Final Cut Camera
  2.0](https://www.apple.com/newsroom/2025/09/apple-announces-final-cut-camera-2-0/).
- **Relevance to astro:** Same niche as Blackmagic Camera — video/ProRes
  RAW capture rather than stacked stills; Genlock is irrelevant to a solo
  tripod shooter.

### ReeXpose — RAW Long Exposure

- **Night/star modes:** No dedicated Stars/Star-Trails naming, but its
  "Light Trails mode" is explicitly marketed for "stunning star trails" as
  well as light-trail/motion-blur photography. [App Store, ReeXpose - RAW
  Long Exposure](https://apps.apple.com/us/app/reexpose-raw-long-exposure/id1624485209).
- **Max effective exposure:** Not a fixed number is published; the app is
  built around composing a long-exposure-look result from a burst,
  output as one file. Third-party framing places ReeXpose alongside apps
  used for 10–30 s-plus "long exposure" style astro results, but that
  describes the astro genre generally, not a confirmed ReeXpose ceiling —
  **unverified** as an exact number.
- **RAW/ProRAW:** Outputs a single 12-bit DNG file, editable in standard
  raw editors; the app explicitly avoids needing physical ND filters by
  computing the long-exposure look. [App Store, ReeXpose - RAW Long
  Exposure](https://apps.apple.com/us/app/reexpose-raw-long-exposure/id1624485209).
- **Star-trail/meteor/ISS modes:** Light Trails mode covers star trails;
  no separate meteor or ISS mode documented.
- **Timelapse:** Not documented as a feature.
- **Manual focus aids:** Full manual controls are advertised generally;
  no star-specific peaking/HFR tool documented.
- **Stacking documentation:** Not detailed beyond "full manual controls
  and the extended dynamic range given by RAW files" — the frame-merge
  method is not published.
- **AI/ML flag:** None documented.
- **Price:** Not confirmed in sources reviewed; **unverified**.

### Slow Shutter Cam

- **Night/star modes:** Three general modes — Motion Blur, Light Trails,
  Low-Light — not astro-specific, but Light Trails is usable for star
  trails and Low-Light for stars. [iPhone Photography School, How To Use
  Slow Shutter Cam](https://iphonephotographyschool.com/slow-shutter-cam/).
- **Max effective exposure:** Capture duration slider goes up to 60
  seconds; beyond that, a manual Bulb mode lets the user start/stop the
  exposure by hand for unbounded duration. [iPhone Photography School, How
  To Use Slow Shutter Cam](https://iphonephotographyschool.com/slow-shutter-cam/).
- **RAW/ProRAW:** Not documented as supported in the sources checked —
  **unverified**, treat as likely JPEG-only given the app's age and design.
- **Star-trail/meteor/ISS modes:** No dedicated modes; Light Trails is the
  closest fit for star trails, manually.
- **Timelapse:** Not documented as a feature.
- **Manual focus aids:** Not documented.
- **Stacking documentation:** Behaves as an in-camera long-exposure
  simulator (accumulating light over the set duration) rather than a
  discrete-frame stack the user can inspect; post-capture sliders adjust
  "the intensity of the motion blur or light trails" after the shot, which
  implies frame-level data is retained internally, but the mechanism isn't
  published. [iPhone Photography School, How To Use Slow Shutter
  Cam](https://iphonephotographyschool.com/slow-shutter-cam/).
- **AI/ML flag:** None documented.
- **Price:** Not confirmed in sources reviewed; **unverified**. (One of the
  oldest apps in this list — App Store ID suggests a 2010-era app still
  maintained.)

### 2025–2026 newcomers focused on astro

- **AstroShader** — captures, stacks, and edits, with the ability to
  "align and stack live during the image capture process" and calibration
  tools in its editor. Presence of live alignment suggests real-time
  registration similar in spirit to the Dark Sky app's own approach, but
  its algorithm is not documented beyond the App Store summary.
  [App Store, AstroShader](https://apps.apple.com/us/app/astroshader/id6444631986).
- **Astro Stacker: Star Images** — a stacking-focused app with a
  "Minimum Stacking" feature specifically for eliminating hot pixels and
  artifacts; no subscription, unlimited stacking. [App Store, Astro
  Stacker: Star Images](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598).
- **Milky Way Tonight** (2026) — pairs Dark Sky Finder light-pollution data
  with a composition planner, exposure calculator, and a monthly Milky Way
  visibility calendar; it is a planning tool, not a capture app, but is a
  close conceptual neighbor to what this project wants to build (planning
  + capture in one place). [PetaPixel, Photographer's New App Takes the
  Guesswork Out of Milky Way
  Photography](https://petapixel.com/2026/06/16/photographers-new-app-takes-the-guesswork-out-of-milky-way-photography/).
- **AstroHelm** (May 2026) — a plate-solving "e-finder" that uses the
  iPhone's camera to identify exactly where it's pointed in the sky by
  matching a captured frame against a star catalog, aimed at telescope
  users. Directly relevant to the gap analysis in §5. [ScopeTrader, iPhone
  plate solving app AstroHelm
  launches](https://scopetrader.com/iphone-plate-solving-app-astrohelm-launches/);
  [Cloudy Nights, Introducing AstroHelm — use your iPhone as a plate
  solving
  e-finder](https://www.cloudynights.com/forums/topic/998821-introducing-astrohelm-use-your-iphone-as-a-plate-solving-e-finder/).
- **StarSense**-style pointing apps — use the rear camera to scan the sky,
  plate-solve in real time, and arrow-guide the user to any of 200,000+
  catalog objects. [Search summary, best stargazing apps
  2026](https://www.space.com/best-stargazing-apps) — treat the specific
  feature count as **unverified** pending a primary StarSense source.

---

## 2. Apple's own Night mode

Apple's own support documentation confirms Night mode exists and
recommends a tripod for stability, but Apple's public support page does
not itself state a numeric exposure ceiling, describe tripod detection as
a named feature, or mention the Photonic Engine. [Apple Support, Take
Night mode photos with your iPhone
camera](https://support.apple.com/guide/iphone/take-night-mode-photos-iph1a3c5b4c3/ios);
[Apple Support, Use Night mode on your iPhone](https://support.apple.com/en-us/102519).
What is documented, from Apple's own marketing/support material as
summarized by secondary sources and cross-checked against Halide's public
comments:

- **Tripod behavior:** When the phone is stationary (tripod or firm
  surface), Night mode internally shifts into a longer/multi-frame capture
  strategy, taking advantage of the stability to extend exposure and
  capture more light than it would handheld. [How-To Geek / secondary
  synthesis of Apple's documented Night mode
  behavior](https://www.howtogeek.com/834842/what-is-apples-photonic-engine/).
  Halide's own public guidance to users is consistent with this: "Night
  mode can stack more images together to make the sky brighter... Set
  Night mode to its maximum duration — 10 seconds handheld, or better yet,
  mount it on a tripod." [Halide + Kino, X/Twitter post on Night Mode
  guidance](https://twitter.com/halidecamera/status/1789291307048845808).
  This implies Apple's own tripod ceiling exceeds handheld's 10 s, but the
  exact tripod maximum is **not independently documented by Apple** in the
  sources checked here — ADR-0011 cites "10 s or more on a tripod," which
  this research did not find a sharper Apple-sourced number for. Treat any
  specific "up to 30 s" figure as **unverified** against a primary Apple
  source (it appears in some secondary/blog coverage but not on Apple's own
  support pages as checked today).
- **Photonic Engine:** A Deep Fusion-derived pipeline, introduced with the
  iPhone 14 line, that applies machine-learning-based processing earlier in
  the imaging pipeline (before compression) on a pixel-by-pixel basis to
  optimize texture, detail, and noise. It runs automatically and cannot be
  toggled by the user or by third-party apps. [How-To Geek, What Is the
  iPhone 14's Photonic
  Engine?](https://www.howtogeek.com/834842/what-is-apples-photonic-engine/).
- **Why third-party apps can't access Night mode directly:** Night mode is
  part of Apple's own Camera app pipeline and is not exposed through
  `AVFoundation`/`AVCaptureDevice` as an API third-party developers can
  invoke; developers instead get raw manual controls (exposure duration,
  ISO, lens position, aperture stops where supported) bounded by
  `activeFormat.maxExposureDuration`, which on this owner's iPhone 18 Pro
  Max measures **1.0 s** regardless of format (`CAPTURE-LIMITS.md`). Lux
  has publicly asked Apple for a "Night Mode API" with fine-grained
  controls, confirming from the developer side that no such API currently
  exists: "Our biggest wishlist item for WWDC? A Night Mode API to give
  [Halide] and the rest of us Night Mode in Halide with fine-grained
  controls." [Halide + Kino, X/Twitter post requesting a Night Mode
  API](https://x.com/halidecamera/status/1527728518582239232).
- **Deferred processing:** Apple's Night mode and related computational
  modes are documented (via secondary technical sources, not Apple's own
  support pages) to defer some processing until after capture, similar in
  spirit to how ProRAW retains editable headroom — but no Apple-authored
  page in this research set names "deferred processing" explicitly for
  stills the way it's documented for video. Flag this specific claim from
  ADR-0011/CAPTURE-LIMITS.md context as **plausible but not independently
  re-confirmed** in this pass; it likely refers to the same
  photoQualityPrioritization behavior already measured in
  `CAPTURE-LIMITS.md` (`.speed` skips multi-image fusion for stills).
- **iPhone 17 Pro change:** Night Portrait mode, available from the iPhone
  12 Pro series through the 16 Pro series, was dropped on the iPhone 17
  Pro/Pro Max. [Search summary citing Blackmagic iPhone 17 Pro coverage] —
  relevant context but **unverified against a primary Apple source**; if
  true it doesn't affect plain Night mode, only the portrait-specific
  variant.

---

## 3. Planning apps (comparison and integration ideas)

Only capture-relevant features are covered.

- **PhotoPills** — its **Night AR** tool overlays the Milky Way's position
  live on the phone's camera view in the field, letting a shooter confirm
  composition and timing on location; the Planner lets a shooter place a
  pin, scrub time, and see the Milky Way layer on a map ahead of the trip.
  PhotoPills has added all iPhone camera models to its device list and
  computes hyperfocal distance, field of view, and required Milky Way
  exposure time per device. [PhotoPills User
  Guide](https://www.photopills.com/user-guide#planner-night-ar);
  [PhotoPills, How To Plan the Milky Way Using the Augmented
  Reality](https://www.photopills.com/articles/how-to-plan-the-milky-way-using-the-augmented-reality).
  This AR-pointing-plus-exposure-calculator combination is the closest
  existing analog to "plate-solved pointing" in §5, though PhotoPills' AR
  is compass/gyro-based, not plate-solved against the actual star field.
- **PlanIt Pro** — rise/set times for sun, moon, and the Milky Way core,
  plus star trail planning, aimed at pre-visit composition planning.
  [AstroBackyard, The 20 Best Astronomy Apps in
  2026](https://astrobackyard.com/astronomy-apps-for-stargazing/).
- **Sky Guide / Stellarium Mobile / SkySafari / Night Sky** — planetarium
  apps for identifying and locating targets; SkySafari 7 Pro additionally
  can drive telescopes over Wi-Fi and carries a very large object database
  (100M stars, 3M galaxies to mag 18, 750,000 solar-system objects).
  [AstroBackyard, The 20 Best Astronomy Apps in
  2026](https://astrobackyard.com/astronomy-apps-for-stargazing/). None of
  these documented sources show a built-in capture mode — they are strictly
  planning/identification tools, reinforcing the gap in §5.
- **Clear Outside** — free, worldwide hour-by-hour astronomy-specific
  forecast: cloud cover, transparency, seeing, humidity, wind. [AstroBackyard,
  The 20 Best Astronomy Apps in
  2026](https://astrobackyard.com/astronomy-apps-for-stargazing/).
- **Astrospheric** — North America-focused conditions app, notable for
  being the only one in this set that integrates wildfire smoke forecasts
  alongside seeing/transparency. [AstroBackyard, The 20 Best Astronomy Apps
  in 2026](https://astrobackyard.com/astronomy-apps-for-stargazing/).

None of the planning apps checked combine planning, live conditions, and
in-app capture in a single flow — each category (plan, forecast, shoot) is
a separate app today.

---

## 4. Techniques

### Beating the 1 s single-frame limit

Third-party apps cannot request a longer single exposure than the format
allows (measured at 1.0 s on every format on this owner's phone,
`CAPTURE-LIMITS.md`), so every "long exposure" or "star trail" result from
a third-party app is actually a sequence of short frames combined after
the fact — confirmed independently for NightCap (10 s Stars-mode result
built from repeated captures plus "inbuilt stacking"), Spectre ("hundreds
of frames during the exposure time"), and ProCamera Low Light Plus (up to
64 frames combined). [NightCap feature
page](https://www.nightcapcamera.com/nightcap-camera/); [DPReview, Halide's
Spectre is an AI-powered long-exposure app for the
iPhone](https://www.dpreview.com/news/5372004032/halide-s-spectre-is-an-ai-powered-long-exposure-app-for-the-iphone);
[No Camera Bag, Review: ProCamera Low Light
Modes](https://nocamerabag.com/blog/review-low-light-modes-procamera-app).
This matches the Dark Sky app's own measured approach: continuous
1.0 s frames, paced one exposure apart with zero-shutter-lag explicitly
disabled.

- **Frame gaps matter for trails.** `CAPTURE-LIMITS.md` notes that the
  interval between frames should equal the exposure duration (1 s here) for
  unbroken star trails; any longer interval leaves visible gaps in the
  trail. This is a first-party finding from this project's own testing,
  not from a third-party source, and it is consistent with how trail
  photography works generically (each frame's arc must abut the next).
- **Zero-shutter-lag is a trap for sequence capture, not a feature.** ZSL
  works by keeping a ring buffer of the most recent frames and handing back
  whichever is closest to the shutter-press timestamp — great for
  candid/action photography, disastrous for a deliberate sequence, because
  a naive "capture 5 times" loop can return frames pulled from the ring
  buffer rather than 5 freshly triggered exposures. This project's own
  verified capture log confirms the failure mode directly: "with ZSL on
  the output returned five '1 s' frames in 0.6 s from its ring buffer,"
  which is physically impossible for genuine 1 s exposures and shows ZSL
  must be disabled and each frame's sensor timestamp checked.
  (`CAPTURE-LIMITS.md`, §Verified capture — first-party finding.) The
  general ZSL mechanism (ring buffer of recent frames, closest-timestamp
  retrieval) is corroborated for the platform generally by secondary
  sources on Android's equivalent CameraX ZSL API and iOS 17 camera-buffer
  behavior. [Android Developers, Reduce latency with Zero-Shutter
  Lag](https://developer.android.com/media/camera/camerax/take-photo/zsl);
  general secondary summary of iOS 17 buffer behavior — treat the iOS
  specifics as **unverified against a primary Apple document** beyond this
  project's own direct measurement.

### Focus at infinity

There is no literal "infinity" lens-position value to set on iPhone;
`CAPTURE-LIMITS.md` confirms the app's own capture screen locks a custom
lens position (0–1 range) chosen via a magnifier and a star half-flux-radius
(HFR) readout, because "1 is the far end, which Apple says is not
infinity." This matches independent third-party findings: on an iPhone 13
Max, a `lensPosition` of ~0.808 (wide/tele) or ~0.84 (ultra wide) — not
1.0 — achieved true infinity focus, and the optimal value drifts with
temperature (phone and ambient), requiring recalibration rather than a
fixed constant. [Developer forum thread, Setting lensPosition to focus at
infinity](https://developer.apple.com/forums/thread/706755). HFR (or the
closely related FWHM) is the standard metric serious astrophotography
software uses to auto-focus: smaller HFR means a tighter, sharper star, so
autofocus routines simply hunt for the lens position that minimizes it —
the same principle this project's own capture screen already implements
manually via its magnifier/HFR readout. [Stellarnomads, Astrophotography
Focusing: Get Tack-Sharp
Stars](https://stellarnomads.com/astrophotography-focusing/) (secondary
source describing N.I.N.A./SharpCap/ASIAIR's use of HFR/FWHM for desktop
astro rigs — the underlying metric, not iPhone-specific, but the
mechanism this project's phone-side implementation mirrors).

### Hot pixels and dark frames on phones

Classic astrophotography workflow subtracts a "dark frame" — captured at
the same ISO, exposure duration, and temperature as the light frames, with
the lens capped — to remove fixed hot/stuck pixels. [Beltoforion,
Basics of Stacking - Lightframes, Darkframes and
Biasframes](https://beltoforion.de/en/astrophotography/stacking.php)
(general astrophotography reference, not iPhone-specific). On iOS, **Astro
Stacker: Star Images** documents a "Minimum Stacking" mode built
specifically to eliminate hot pixels and artifacts (using a per-pixel
minimum across frames rather than a true dark-frame subtraction) — a
different, computationally cheaper approach than capturing an actual dark
frame. [App Store, Astro Stacker: Star
Images](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598).
No app reviewed in §1 documents true dark-frame subtraction (capping the
lens and shooting a matched dark exposure); this project's own sigma-clipped
mean approach (`CAPTURE-LIMITS.md`) removes outliers including hot pixels
statistically across the stack rather than via a separate dark frame,
which is a reasonable phone-side substitute given none of the third-party
apps document doing dark-frame subtraction either.

### ProRAW's baked-in processing

Confirmed directly from Lux's own technical writeup and corroborated by
Moment's documentation:

- **Demosaicing is irreversible in ProRAW.** ProRAW files store pixel
  values *after* the demosaic step, locking in Apple's color
  reconstruction; a traditional Bayer RAW instead preserves the sensor
  mosaic so desktop software can choose its own demosaic algorithm. [Lux,
  Understanding ProRAW](https://www.lux.camera/understanding-proraw/).
  This matches `CAPTURE-LIMITS.md`'s own finding that ProRAW is "a
  demosaiced, scene-referred 'linear DNG.'"
  - Note: WebFetch's extraction of the Lux article did not surface an
    explicit "linear DNG" phrase from that page directly; the "linear DNG"
    characterization in this document is carried over from
    `CAPTURE-LIMITS.md` (this project's own finding), not independently
    re-confirmed word-for-word against the Lux article in this pass.
- **Smart HDR local tone mapping** is embedded via a separate "Profile Gain
  Table Map" metadata layer that editors can disable, so this part is
  reversible. [Lux, Understanding
  ProRAW](https://www.lux.camera/understanding-proraw/).
- **Deep Fusion noise reduction cannot be separated after the fact** — a
  user must opt out at capture time (which is exactly what
  `photoQualityPrioritization = .speed` does, per `CAPTURE-LIMITS.md`).
  [Lux, Understanding ProRAW](https://www.lux.camera/understanding-proraw/).
- **Semantic maps** (AI-detected face/hair/portrait-effect data) can be
  embedded in the file — irrelevant to a starfield but confirms ProRAW
  carries more than pure sensor data. [Lux, Understanding
  ProRAW](https://www.lux.camera/understanding-proraw/).
- **Moment's independent description agrees:** ProRAW is "a hybrid format
  that retains RAW sensor data but layers in computational photography
  features like Deep Fusion and Smart HDR." [Moment Pro Camera
  manual](https://www.momentprocamera.com/manual).
- **What this means for the app:** the app "cannot inspect or switch off"
  Apple's own raw pipeline beyond selecting `.speed` prioritization
  (`CAPTURE-LIMITS.md`), which is exactly the trade-off Lux describes:
  Apple favors a clean file with little noise at the expense of some
  detail, versus a traditional RAW file's more noise but more raw detail.
  [DPReview, Halide can now strip away (almost) all the iPhone's
  processing](https://www.dpreview.com/news/5101705770/halide-process-zero-ai-computational-photograpy-phones-raw/).

### Thermal throttling during long sequences

Secondary sources consistently report that extended camera use — 4K video,
rapid-fire captures, long sequences — triggers thermal throttling
sometimes within a couple of minutes, especially outdoors in warm weather,
and can degrade performance, introduce lag, or disable features like flash.
[KryoZon, iPhone 15 Pro Max Camera Overheating Fixes (2026
Guide)](https://www.kryozon.com/blogs/cooling-hub/iphone-15-pro-max-camera-overheating-real-fixes-for-filming).
These sources are about daytime/video use generically, not tripod astro
sequences specifically, and none benchmark an iPhone 18 Pro Max — flag the
specific onset time as **not verified for this project's own cold-night,
low-CPU-load use case**, where ambient cold and a mostly-idle GPU (no video
encode, just periodic stills) plausibly behaves very differently from the
daytime 4K-video scenarios these sources describe. ADR-0011 itself already
calls for throttling under thermal pressure as a design requirement,
independent of what these general sources report.

### Battery

Cold materially hurts battery performance: a roughly 10°C (18°F) drop can
cut battery life "roughly in half," and voltage sags in cold temperatures,
reducing usable capacity. [Search summary citing cold-weather battery
behavior — general phone/camera battery physics, not iPhone-18-specific
benchmark data; treat the "roughly half" figure as a rule of thumb, not a
measured constant]. Practical mitigations reported across camera-battery
guidance (general photography sources, not iPhone-specific): keep the
phone warm/insulated between shots, disable Wi-Fi/Bluetooth/GPS/
stabilization/live preview to cut background drain, dim the screen, and
review captures sparingly during a session; carrying an external
battery/power bank is standard practice for overnight sessions.
[SLR Lounge, How to Keep Camera Battery Warm in Cold
Weather](https://www.slrlounge.com/cold-weather-photography-tips-how-to-protect-your-batteries-from-the-cold/)
(camera-battery-general, not iPhone-specific, but the physics and
mitigations transfer directly). No app reviewed in §1 documents its own
battery-optimization behavior for long astro sequences — this is unaddressed
by every third-party app checked.

---

## 5. Gap analysis

What no current iOS app in this survey does well, based on the coverage
above:

1. **Nothing combines planning, live conditions, and capture in one flow.**
   PhotoPills, PlanIt Pro, and the planetarium apps (§3) plan; Clear
   Outside/Astrospheric forecast; NightCap/Spectre/Halide/ProCamera/etc.
   capture (§1). A shooter today manually carries data between three or
   more separate apps. The closest thing to a combined tool found in this
   research, Milky Way Tonight (2026), pairs light-pollution data with an
   exposure calculator and visibility calendar, but is still a planning
   tool with no capture mode of its own. [PetaPixel, Photographer's New
   App Takes the Guesswork Out of Milky Way
   Photography](https://petapixel.com/2026/06/16/photographers-new-app-takes-the-guesswork-out-of-milky-way-photography/).
   This is the clearest, best-evidenced gap: the Dark Sky app's Tonight/Sky
   -> Capture pipeline (ADR-0011, item 4: "Planning feeds capture") already
   targets exactly this integration and nothing surveyed here does it.

2. **Plate-solved pointing is brand-new and separate from every capture
   app.** AstroHelm (May 2026) and StarSense-style apps solve "where is
   this phone actually pointed" by matching a captured frame against a
   star catalog, but both are pointing/e-finder tools for telescopes, not
   integrated into any capture app in §1 and not connected to any planning
   app in §3. PhotoPills' Night AR is the closest capture-adjacent
   analog, but it's compass/gyro-based augmented reality, not plate-solved
   against the real star field, so it can drift with compass error in a
   way true plate-solving would not. [ScopeTrader, iPhone plate solving app
   AstroHelm
   launches](https://scopetrader.com/iphone-plate-solving-app-astrohelm-launches/);
   [PhotoPills User
   Guide](https://www.photopills.com/user-guide#planner-night-ar). Nobody
   surveyed here plate-solves a live capture-app preview to confirm
   framing against an actual target before or during a tripod session.

3. **No app documents true dark-frame subtraction.** Every stacking app
   checked (NightCap, Astro Stacker, AstroShader, ProCamera) either doesn't
   document its noise-removal method or uses a cheaper proxy (minimum-value
   stacking, sigma-clipping-style outlier rejection) rather than a matched
   dark frame captured with the lens capped. This project's own
   sigma-clipped mean is already in the same family as the better apps
   here (Astro Stacker's minimum stacking), so this is more a shared
   industry gap than a place this project is currently behind — but a
   documented, user-triggered dark-frame capture step is something no
   competitor offers and could be a differentiator.

4. **No app designs a star-trail composition ahead of time.** Every
   star-trail feature found (NightCap Star Trails, ReeXpose/Slow Shutter
   Cam Light Trails) is "start the sequence and see what happens" — none
   compute or preview where the celestial pole will be, how long a given
   trail arc will be for a chosen duration, or let a user frame a trail
   shot before committing 15–90+ minutes of battery and thermal budget to
   it. ADR-0011 and `CAPTURE-LIMITS.md`'s star-trail designer (interval
   equal to exposure for unbroken trails, celestial-pole framing handed
   over from the Sky agent) is explicitly not yet landed on any branch,
   but nothing surveyed here has shipped this either — it is a genuine,
   currently-open gap across the whole app landscape, not just this
   project.

5. **Thermal- and battery-aware sequencing is undocumented industry-wide.**
   No capture app reviewed publishes how it behaves under thermal pressure
   or manages battery for hour-plus sequences (meteor mode's hundreds of
   frames, star-trail's 15–90+ minute runs). ADR-0011 already calls for
   throttling under thermal pressure and showing projected storage use
   before a sequence starts — both remain undocumented anywhere else in
   this survey and are worth keeping as explicit differentiators.

---

## Sources

- [NightCap Camera: Photograph Stars, Meteors, Satellites and even
  Nebulae](https://www.nightcapcamera.com/photograph-stars-meteors-satellites-even-nebulas-iphone-nightcap-camera/)
- [NightCap Camera feature page](https://www.nightcapcamera.com/nightcap-camera/)
- [NightCap Camera App Store listing](https://apps.apple.com/us/app/nightcap-camera/id754105884)
- [Skies & Scopes, 17 Best Astrophotography Apps in 2026](https://skiesandscopes.com/astrophotography-apps/)
- [Lux, Introducing Spectre](https://www.lux.camera/introducing-spectre/)
- [DPReview, Halide's Spectre is an AI-powered long-exposure app for the iPhone](https://www.dpreview.com/news/5372004032/halide-s-spectre-is-an-ai-powered-long-exposure-app-for-the-iphone)
- [MacStories, Spectre: A Computational Approach to Long-Exposure iPhone Photography](https://www.macstories.net/reviews/spectre-a-computational-approach-to-long-exposure-iphone-photography/)
- [The App Whisperer, Best Long Exposure Apps for iPhone (2026)](https://theappwhisperer.com/2026/03/best-long-exposure-apps-for-iphone-2026/)
- [Lux, Inside Looks: A Mark III Preview](https://www.lux.camera/mark-iii-looks/)
- [Lux, Understanding ProRAW](https://www.lux.camera/understanding-proraw/)
- [Lux, Why is Halide not free?](https://www.lux.camera/why-is-halide-not-free/)
- [DPReview, Halide can now strip away (almost) all the iPhone's processing](https://www.dpreview.com/news/5101705770/halide-process-zero-ai-computational-photograpy-phones-raw/)
- [TechCrunch, camera app Halide's latest update adds an option for zero AI image processing](https://techcrunch.com/2024/08/14/camera-app-halides-latest-update-adds-an-option-for-zero-ai-image-processing)
- [Halide + Kino, X/Twitter post requesting a Night Mode API](https://x.com/halidecamera/status/1527728518582239232)
- [Halide + Kino, X/Twitter post on Night Mode guidance](https://twitter.com/halidecamera/status/1789291307048845808)
- [Hacker News, discussion of Halide pricing](https://news.ycombinator.com/item?id=40521513)
- [AppleInsider, How to take astronomy photos with just your iPhone](https://appleinsider.com/inside/iphone/tips/how-to-take-astronomy-photos-with-just-your-iphone)
- [No Camera Bag, Review: ProCamera Low Light Modes](https://nocamerabag.com/blog/review-low-light-modes-procamera-app)
- [No Camera Bag, My Long-Term ProCamera App Review](https://nocamerabag.com/blog/procamera-app-review/)
- [Lumina Camera App site](https://luminacameraapp.github.io/)
- [Imaging Resource, Moment Launches Pro Camera II for iOS](https://www.imaging-resource.com/news/moment-launches-pro-camera-ii-for-ios-with-new-manual-and-video-features/)
- [Moment Pro Camera manual](https://www.momentprocamera.com/manual)
- [Moment Pro Camera App Store listing](https://apps.apple.com/in/app/pro-camera-by-moment/id927098908)
- [Blackmagic Design press release, Apple ProRes RAW](https://www.blackmagicdesign.com/media/release/20250910-02)
- [CineD, Apple Final Cut Camera 2.0 – Open Gate, Apple Log 2 and ProRes RAW, Genlock for iPhone 17 Pro](https://www.cined.com/apple-final-cut-camera-2-0-open-gate-apple-log-2-and-prores-raw-genlock-for-iphone-17-pro/)
- [Apple Newsroom, Apple announces Final Cut Camera 2.0](https://www.apple.com/newsroom/2025/09/apple-announces-final-cut-camera-2-0/)
- [MacRumors, Apple's Final Cut Camera 2.0 to Support ProRes RAW and Genlock](https://www.macrumors.com/2025/09/10/apple-announces-final-cut-camera-2-0/)
- [App Store, ReeXpose - RAW Long Exposure](https://apps.apple.com/us/app/reexpose-raw-long-exposure/id1624485209)
- [iPhone Photography School, How To Use Slow Shutter Cam](https://iphonephotographyschool.com/slow-shutter-cam/)
- [App Store, AstroShader](https://apps.apple.com/us/app/astroshader/id6444631986)
- [App Store, Astro Stacker: Star Images](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598)
- [PetaPixel, Photographer's New App Takes the Guesswork Out of Milky Way Photography](https://petapixel.com/2026/06/16/photographers-new-app-takes-the-guesswork-out-of-milky-way-photography/)
- [ScopeTrader, iPhone plate solving app AstroHelm launches](https://scopetrader.com/iphone-plate-solving-app-astrohelm-launches/)
- [Cloudy Nights, Introducing AstroHelm](https://www.cloudynights.com/forums/topic/998821-introducing-astrohelm-use-your-iphone-as-a-plate-solving-e-finder/)
- [Space.com, Best stargazing apps 2026](https://www.space.com/best-stargazing-apps)
- [PhotoPills User Guide](https://www.photopills.com/user-guide#planner-night-ar)
- [PhotoPills, How To Plan the Milky Way Using the Augmented Reality](https://www.photopills.com/articles/how-to-plan-the-milky-way-using-the-augmented-reality)
- [AstroBackyard, The 20 Best Astronomy Apps in 2026](https://astrobackyard.com/astronomy-apps-for-stargazing/)
- [Apple Support, Take Night mode photos with your iPhone camera](https://support.apple.com/guide/iphone/take-night-mode-photos-iph1a3c5b4c3/ios)
- [Apple Support, Use Night mode on your iPhone](https://support.apple.com/en-us/102519)
- [How-To Geek, What Is the iPhone 14's Photonic Engine?](https://www.howtogeek.com/834842/what-is-apples-photonic-engine/)
- [Developer forum thread, Setting lensPosition to focus at infinity](https://developer.apple.com/forums/thread/706755)
- [Stellarnomads, Astrophotography Focusing: Get Tack-Sharp Stars](https://stellarnomads.com/astrophotography-focusing/)
- [Beltoforion, Basics of Stacking - Lightframes, Darkframes and Biasframes](https://beltoforion.de/en/astrophotography/stacking.php)
- [Android Developers, Reduce latency with Zero-Shutter Lag](https://developer.android.com/media/camera/camerax/take-photo/zsl)
- [KryoZon, iPhone 15 Pro Max Camera Overheating Fixes (2026 Guide)](https://www.kryozon.com/blogs/cooling-hub/iphone-15-pro-max-camera-overheating-real-fixes-for-filming)
- [SLR Lounge, How to Keep Camera Battery Warm in Cold Weather](https://www.slrlounge.com/cold-weather-photography-tips-how-to-protect-your-batteries-from-the-cold/)
- `docs/ios/CAPTURE-LIMITS.md` (this repo, first-party measured data)
- `docs/adr/0011-iphone-tripod-capture.md` (this repo, decision record)
