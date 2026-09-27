# Deep-sky and planetary app/tool landscape — research for Dark Sky expansion

Date: 2026-09-27. Compiled for the Dark Sky astrophotography app's expansion from Milky Way
nightscapes into deep-sky/telescope astrophotography. All claims are cited inline; anything
that could not be verified from a source is marked **unverified**.

---

## 1. Planning tools

### Telescopius (web + app)
- **What it does well:** Combines target search, a Telescope Simulator/FOV framing tool (enter
  telescope + camera to preview field of view on a target), mosaic planning, altitude/visibility
  charts, and weather data in one place. Its filtering engine can sort the sky by minimum
  altitude, minimum visible hours, and distance from the Moon. It also hosts a large
  community astrophotography gallery. [Telescopius on the App Store](https://apps.apple.com/us/app/telescopius/id6479415751); [RASC Hamilton guide](https://www.hamiltonrasc.ca/exploring-the-cosmos-with-telescopius-a-comprehensive-guide-for-astrophotographers/); [Telescope Live: Planning Mosaics with Telescopius](https://telescope.live/blog/planning-mosaics-telescopius)
- **Pricing:** Free to use, on web and as an app (Android via Play Store TWA wrapper, and an
  iOS App Store listing). [Telescopius App Store listing](https://apps.apple.com/us/app/telescopius/id6479415751); [AppBrain: Telescopius](https://www.appbrain.com/app/telescopius/com.telescopius.twa)
- **Data sources:** Weather/transparency and cloud-cover data reportedly sourced from
  meteoblue, per user forum discussion; users note occasional discrepancies vs. other
  services — **unverified against an official Telescopius statement**. [Telescopius forum: "Seeing forecast"](https://forum.telescopius.com/t/seeing-forecast/335)
- **Target database:** Deep-sky object catalog with altitude charts and moon-distance
  filtering, described by reviewers as "the most complete planning tool available" combining
  target finding, FOV simulation, mosaic planning and weather in one workflow. [RASC Hamilton guide](https://www.hamiltonrasc.ca/exploring-the-cosmos-with-telescopius-a-comprehensive-guide-for-astrophotographers/)

### SkySafari 7/8 Pro (Simulation Curriculum)
- **What it does well:** Full planetarium with telescope control, plate-solving of imported
  images, AR sky-pointing, and a 5-million-year time simulation range. Version 8 adds
  **ASCOM Alpaca camera support** ("connect and control ALPACA-compatible astronomy cameras
  directly from SkySafari"), five new UI themes, and iCloud sync of imported astrophotos across
  devices. Telescope control protocols supported: **ASCOM Alpaca, INDI, and StarSense
  Explorer**. [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420)
- **Pricing:** SkySafari 8 Pro is a paid app (App Store price observed at $24.99–$49.99
  depending on source/region — **treat exact figure as unverified**, confirm at purchase
  time), with an optional "SkySafari Premium" subscription layer at $5.99/month or
  $49.99/year for cloud sync (LiveSky) and related services. SkySafari 7 Pro is being phased
  out ("will be removed from sale soon") in favor of version 8. [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420); [Cloudy Nights: SkySafari 8 Pro for Apple](https://www.cloudynights.com/forums/topic/987626-skysafari-8-pro-for-apple/)
- **Requirements:** iOS 18.6+ / iPadOS 18.6+, ~2.6 GB storage; macOS 15.6 with Apple Silicon
  or later for the Mac version. [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420)

### Stellarium (Mobile Plus, and Web)
- **Stellarium Mobile Plus:** A from-scratch, newly engineered rendering core (not the
  classic Stellarium Mobile codebase) built to display "a potentially unlimited amount of
  data" — includes the Gaia DR2 catalog (1.4B+ stars), a combined deep-sky catalog of 3M+
  nebulae/galaxies, full solar-system bodies with high-res imagery, 10,000+ asteroids, comets,
  and visible-satellite tracking including the ISS. As of this research it was still in
  **alpha**, with an alpha-promotional price around $5.99–$11.99 depending on platform/region
  (Android figures cited; iOS pricing **unverified** at time of writing — check current App
  Store listing). [Stellarium Labs: Introducing Stellarium Mobile Plus](https://stellarium-labs.com/blog/introducing-stellarium-mobile-plus/); [Stellarium Mobile — App Store](https://apps.apple.com/us/app/stellarium-mobile-star-map/id1458716890)
- **Stellarium Web:** Free, no-install browser planetarium at stellarium-web.org, showing a
  realistic naked-eye/binocular/telescope sky for any location and time. [Stellarium Web](https://stellarium-web.org/); [Stellarium Labs: Stellarium Web](https://stellarium-labs.com/stellarium-web/)
- **Desktop Stellarium** (for context) is free/open-source (GPL) and remains the base for the
  classic mobile app; the "Plus" mobile product is a separate commercial rebuild by Stellarium
  Labs. [Stellarium (software) — Wikipedia](https://en.wikipedia.org/wiki/Stellarium_(software))

### AstroPlanner
- **What it does well:** Windows/Mac desktop tool aimed at visual observers and imagers
  planning faint/obscure deep-sky targets, with telescope-type customization and advanced
  equipment integration. [Mac Observatory: AstroPlanner on the Mac](https://macobservatory.com/astroplanner-mac-review/)
- **Pricing:** Reported figures vary by source ($45–$75); **treat as approximate/unverified**
  pending a check of the current vendor price page. [Cloudy Nights: low-cost planning software thread](https://www.cloudynights.com/topic/671071-what-is-a-low-cost-computer-based-observing-planning-software/)
- **Platform:** Desktop (Windows; Mac via the Mac Observatory review above) — **not iOS**.

### Deep Sky Planner (Knightware)
- **What it does well:** Long-running (currently version 9, released June 2024) planning and
  logging software for visual observers and imagers: large object database, telescope
  control, planetarium-program interoperation, and extensive session-reporting. Telescope
  control requires **ASCOM** (6.5 or earlier, free) — a Windows-only dependency. [Knightware: Deep-Sky Planner 9 Features](https://knightware.biz/dsp/productinfo.htm); [Astronomy Technology Today: Deep-Sky Planner 9 Release](https://astronomytechnologytoday.com/2024/07/23/deep-sky-planner-9-release/)
- **Pricing:** A free trial edition is available; full pricing was not published in the pages
  checked — **unverified**, check knightware.biz store directly. [Knightware: Deep-Sky Planner 9 Trial Edition](https://knightware.biz/dsp/trial.htm)
- **Platform:** Windows desktop — **not iOS**.

### Sky Guide (iOS)
- **What it does well:** Consumer-friendly stargazing/planning app with an astrophotography-
  oriented **FOV Rotation Preview** (live-preview camera field-of-view rotation in sky view for
  composition), a **Deep Sky Symbols** toggle highlighting galaxies/nebulae/clusters, and a
  **Coordinate Picker** for tapping between RA/Dec, alt-az, and galactic coordinate systems.
  Recent updates add more language support and Apple Watch/widget Moon complications. [Sky Guide — App Store](https://apps.apple.com/us/app/sky-guide/id576588894); [Space.com: Sky Guide review](https://www.space.com/sky-guide-stargazing-app-review)
- **Positioning:** Framed by reviewers as more accessible than SkySafari/dedicated planning
  tools, complementary rather than a full deep-sky planning replacement. [AstroBackyard: 20 Best Astronomy Apps in 2026](https://astrobackyard.com/astronomy-apps-for-stargazing/)

### PhotoPills (comparison point — nightscape, not deep-sky)
- **What it does well:** Photo planner + ephemerides + calculators, with augmented-reality
  overlay of the Milky Way's future position at a chosen date/place/time — the closest
  functional relative to Dark Sky's existing nightscape planning. Strong at framing
  landscape-scale night shots; not built for telescope FOV/deep-sky cataloging. [PhotoPills app review 2026 — Night Sky Pix](https://nightskypix.com/photopills-app-review/); [Digital Photography School: Plan Astrophotography With PhotoPills](https://digital-photography-school.com/plan-astrophotography-with-photopills-app/)
- **Pricing:** One-time purchase, cited around $10–$11 (Google Play figure; iOS pricing
  typically matches within regional rounding — **confirm current price**). Rated 4.7/5 from
  ~1.5K reviews; a "steep learning curve" is a common complaint. [PhotoPills — Google Play](https://play.google.com/store/apps/details?id=com.photopills.android.photopills&hl=en&gl=US)

### NINA (Nighttime Imaging 'N' Astronomy) — Framing Assistant and Sky Atlas
- **What it is:** Free, fully open-source (Windows) astrophotography sequencing suite that
  centralizes hardware control, plate solving, guiding and automated focusing. [NINA — Nighttime Imaging 'N' Astronomy](https://nighttime-imaging.eu/); [Dale Ghent: Introducing NINA](https://daleghent.com/nina-introduction)
- **Sky Atlas:** Search/filter NINA's own deep-sky object database, then push a selected
  target to a Sequence or to the Framing Assistant. [NINA docs: Sky Atlas](https://nighttime-imaging.eu/docs/master/site/tabs/skyatlas/)
- **Framing Assistant:** Overlays the camera's actual field of view on a target, lets the
  user fine-tune position/rotation, pulling imagery from online sky-survey services, an
  inbuilt planetarium, or a user-supplied image; can plate-solve to align telescope/rotator to
  match the planned framing rectangle. [NINA docs: Framing Assistant](https://nighttime-imaging.eu/docs/master/site/tabs/framing/)
- **License/platform:** Free and open source, Windows desktop only — **not iOS**, but its
  Framing Assistant/Sky Atlas UX is a strong functional reference for what an iOS framing tool
  should offer.

---

## 2. Control and capture ecosystems

### ZWO ASIAIR (app + hardware unit)
- **What it does:** Controls ZWO ASI USB3/Mini cameras, select DSLR/MILCs, popular EQ mounts,
  plus EFW filter wheels and EAF focusers. Workflow covers preview, plate-solve, autofocus,
  polar-align, guiding, multi-target/mosaic planning, video, live stacking, and post-stacking.
  V3.0 (released 2026-07-29) added an in-app Astronomy Community, post-stacking, file sharing,
  remote/off-network device control, camera-rotation assist and mosaic/plan editing in Sky
  Atlas, and a guiding dark-frame library. [ZWO: ASIAIR V3.0 New Features](https://www.zwoastro.com/2026/07/15/asiair-new-features-and-user-guide/); [ZWO Software page](https://www.zwoastro.com/software_v1/)
- **API:** **No official public API.** Community discussion (Cloudy Nights forum, ZWO's own
  user Facebook group) shows repeated user requests for a REST/Python API to monitor system
  status or integrate third-party tools, with no confirmed official release found in this
  research. Any integration today would require reverse-engineering ASIAIR's private
  protocol, which is both technically fragile and a plausible ToS concern — **do not build on
  an undocumented protocol without checking ZWO's terms**. [Cloudy Nights: "API for AsiAir?"](https://www.cloudynights.com/forums/topic/928509-api-for-asiair/); [ZWO User Facebook group: ASIAIR API question](https://www.facebook.com/groups/ASIAIR/posts/2294737537356123/)
- **License:** Closed-source commercial app tied to ZWO hardware.

### Seestar app (ZWO Seestar S30/S50/Pro line)
- **What it does:** In-app catalog of 80,000+ deep-sky objects and 600,000+ stars; select a
  target, tap GOTO, and the telescope locates/tracks/captures automatically. One documented
  limitation: the stock app reportedly cannot accept raw RA/Dec coordinates for objects not in
  its catalog (**unverified** — sourced from a third-party smart-telescope comparison, not
  ZWO's own docs). The Seestar S50 Pro released 2026-08-25; the line now spans S30, S30 Pro,
  S50, S50 Pro. [Wido's AstroForum: Best Budget Smart Telescope 2026](https://astroforumspace.com/best-budget-smart-telescope-in-2026-seestar-s30-s30-pro-s50-vs-dwarf-3-and-mini/); [ZWO Seestar: Quick Guide to the Seestar App](https://www.seestar.com/blogs/seestar-guide/quick-guide-to-the-seestar-app)
- **Community API — seestar_alp:** GitHub repo `smart-underworld/seestar_alp` ("Complete
  Control and Automation for Seestar S50"), a standalone controller with a web-based front end
  talking to a backend server that drives the telescope. As of this research: **292 stars**,
  **1,997 commits on main** (specific last-commit date not captured in this pass — verify at
  https://github.com/smart-underworld/seestar_alp for current activity). It **implements the
  ASCOM Alpaca protocol** for the Seestar (documented via an included "Seestar Alpaca API.json"
  spec and Bruno REST-client collection), plus INDI/PyIndi components. **License is mixed
  within the repo**: MIT and BSD-3-Clause for original code, GPL-3.0 and other licenses for
  bundled AlpacaDevice/PyIndi components — **any reuse must check per-file/per-component
  licensing, not assume one blanket license**. [GitHub: smart-underworld/seestar_alp](https://github.com/smart-underworld/seestar_alp); [seestar_alp Alpaca API directory](https://github.com/smart-underworld/seestar_alp/tree/main/bruno/Seestar%20Alpaca%20API)
- **Practical implication for Dark Sky:** Because seestar_alp exposes an ASCOM Alpaca (HTTP/
  JSON) endpoint, an iOS app could in principle send target coordinates and read status by
  speaking Alpaca to a Mac/PC/Raspberry Pi running seestar_alp on the same local network — it
  would not need to reverse-engineer ZWO's own app protocol directly. This is a community
  bridge, not an official ZWO-sanctioned integration; stability and continued maintenance are
  not guaranteed.

### Dwarflab app (DWARF II / DWARF 3 / DWARF mini)
- **What it does:** Official app (iOS/Android) for WiFi (and newer NFC one-touch) pairing and
  control of the DWARF smart telescope line. [DWARFLAB App Firmware Download](https://www.dwarflab.com/us/pages/dwarflab-app-firmware-download); [DWARF 3 User Manual](https://help.dwarflab.com/en/docs/DWARF-3-Smart-Telescope-User-Manual-Part1-App-Interface-Introduction)
- **Documented integration paths (more open than ZWO/Seestar's official stance):**
  - **Stellarium remote-control integration:** DWARF telescopes can connect to Stellarium via
    a documented API and Stellarium's remote-control plugin — select an object in Stellarium
    and command the DWARF to slew to it. [Amazon/manufacturer feature notes referenced via search](https://help.dwarflab.com/en/docs/DWARF-3-Smart-Telescope-User-Manual-Part1-App-Interface-Introduction)
  - **dwarfAlp** (GitHub: `acocalypso/dwarfAlp`): an ASCOM Alpaca driver making DWARF 2/3/mini
    available to any Alpaca-aware software (e.g., NINA), primarily built for Windows users.
    License/stars/last-activity **not captured in this pass — verify directly on GitHub before
    relying on it**. [GitHub: acocalypso/dwarfAlp](https://github.com/acocalypso/dwarfAlp)
  - **Dwarfium** (GitHub: `stevejcl/dwarfium`): a separate community app connecting DWARF II
    and 3 to Stellarium. License/activity **not captured — verify on GitHub**. [GitHub: stevejcl/dwarfium](https://github.com/stevejcl/dwarfium)

### Vaonis Singularity app (Stellina, Vespera, Vespera II)
- **What it does:** Official control-center app for Vaonis's observation stations. Automatic
  setup uses GPS for self-location and autofocus in under 5 minutes; users pick a target from
  Vaonis's built-in object catalog or enter celestial coordinates and the station slews and
  tracks automatically. Includes SkyColor Studio, an integrated astro image-editing/color-
  calibration workflow for deep-sky images. 2026 updates cited include iOS 26 compatibility
  fixes. [Vaonis: Singularity, the new companion app](https://vaonis.com/blogs/travel-journal/singularity-the-new-companion-app-of-your-observation-station); [Vaonis Vespera II product page](https://vaonis.com/pages/product/vespera-ii)
- **API:** No public third-party API found in this research; the app supports manual
  coordinate entry (useful precedent — confirms smart telescopes in this class can accept raw
  RA/Dec, unlike the Seestar app's apparent catalog-only limitation). **Third-party/API access
  beyond manual coordinate entry is unverified.**
- **License:** Closed-source commercial app tied to Vaonis hardware; see Vaonis's own
  Singularity App Terms of Use for legal integration boundaries. [Vaonis: Singularity App Terms of Use](https://vaonis.com/pages/singularity-app-general-term-of-use)

### Unistellar app (eVscope, eQuinox, Odyssey lines)
- **What it does:** Each unit creates a password-less WiFi hotspot for phone/tablet pairing;
  the app is required for control and live viewing. App v5.0.0 (2026-07-15) added a full
  interface redesign, a celestial-and-terrestrial planetarium mode, and "Vivid Vision"
  processing improvements across eQuinox 2, eVscope 2, Odyssey and Odyssey Pro. [Unistellar Help Center: App Changelog](https://help.unistellar.com/hc/en-us/articles/7306522999324-The-UNISTELLAR-App-Changelog-for-Telescopes-App-and-Firmware-Updates)
- **API:** Unistellar has reportedly said it intends to offer fuller computer/API access, but
  **no official public API was confirmed as released** as of this research. A community
  reverse-engineering project exists (`jankais3r/Unistellar-eVscope-research` on GitHub) but is
  unofficial. [GitHub: jankais3r/Unistellar-eVscope-research](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/README.md)
- **License:** Closed-source commercial app; any integration beyond the official app is
  unofficial/community and legally untested — treat as **unverified for legitimate iOS
  integration**.

### Open protocols relevant to all of the above

**ASCOM Alpaca**
- An open, network-based evolution of the classic Windows-only ASCOM COM standard: same
  device command set, carried over **HTTP + JSON** (RESTful, TCP/IP) instead of COM. Explicitly
  designed to be cross-platform — "any application on any operating system, macOS included,
  can talk directly to mounts, domes, focusers, power switches" on an Alpaca device. Intended
  for use **within an isolated, protected in-observatory local network**; a device can be a
  standalone WiFi unit needing no separate server. [ASCOM Standards: About Alpaca Connectivity](https://ascom-standards.org/About/Conn-Alpaca.htm); [ASCOM Standards home](https://ascom-standards.org/); [Mac Observatory: ASCOM Alpaca Protocol 2026](https://macobservatory.com/ascom-alpaca-mac-observatory-automation/)
- **Answer to the research question "could an iOS app talk to Alpaca devices on the local
  network?": yes, in principle.** Alpaca is plain HTTP/JSON with no Windows/COM dependency, so
  a native iOS HTTP client can call an Alpaca device or Alpaca-bridging server (e.g.,
  seestar_alp, dwarfAlp) directly on the local network, the same way SkySafari 8 Pro already
  does for Alpaca-compatible cameras. [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420)
- A Python client library (Alpyca) exists for reference implementations; useful for
  understanding the wire format even though an iOS app would implement its own Swift HTTP
  client. [Alpyca docs](https://ascom-standards.org/alpyca/introduction.html)

**INDI**
- "Instrument-Neutral-Device-Interface" — open-source POSIX protocol/driver framework for
  astronomical device control (mounts, cameras, focusers, domes, GPS, weather stations), with
  cross-platform client libraries. Repo `indilib/indi`: **455 stars**, ~10,356 commits on
  master, active CI at time of check. **Licensed under a mix of LGPL-2.1, GPL-2.0 and BSD**
  depending on component — GPL components in particular constrain closed-source commercial
  reuse; any INDI code linked into a proprietary iOS app needs a license review before
  shipping. [GitHub: indilib/indi](https://github.com/indilib/indi); [INDI docs: Getting Started](https://docs.indilib.org/getting-started/)

**INDIGO**
- A newer, INDI-adjacent framework built explicitly for scalability and commercial reuse:
  "INDIGO has no GPL dependency to allow commercial use under application stores licenses."
  Runs as a software bus (drivers/agents/clients) that can live in one process or be
  distributed over a network; can fall back to the legacy INDI 1.7 wire protocol for
  compatibility with INDI drivers/clients. Repo `indigo-astronomy/indigo`: **186 stars**.
  [GitHub: indigo-astronomy/indigo](https://github.com/indigo-astronomy/indigo); [INDIGO Astronomy](https://www.indigo-astronomy.org/)
- **This is the more App-Store-friendly of the two protocols** given the explicit no-GPL
  design intent — worth a deeper licensing read before choosing between INDI and INDIGO as an
  integration target.

---

## 3. Processing on phones and desktops (context only)

| Tool | Platform | License/price | Notes |
|---|---|---|---|
| **Siril** | Windows/macOS/Linux | Free, open source, **GPL-3.0-only** | Full pre-processing/stacking/stretching pipeline; scriptable. [Siril (software) — Wikipedia](https://en.wikipedia.org/wiki/Siril_(software)) |
| **PixInsight** | Windows/macOS/Linux | Commercial, ~€300 | Industry-standard deep processing suite; steep learning curve. [Zelpio: AstroWizard vs Siril vs PixInsight 2026](https://www.zelpio.com/blog/astro-wizard-vs-siril-vs-pixinsight-2026/) |
| **GraXpert** | Windows/macOS/Linux | Free, open source — **license unclear/mixed**: PyPI package lists GPL-3.0, other project pages reference BSD-3; verify per-repo before reuse. Also on PyPI. | Gradient removal specialist, including an AI (no-manual-points) mode; integrates as a plugin/tool called from Siril and Seti Astro Suite Pro. [GraXpert — PyPI](https://pypi.org/project/graxpert/); [GitHub: Steffenhir/GraXpert](https://github.com/Steffenhir/GraXpert/); [GraXpert official site](https://graxpert.com/) |
| **Seti Astro Suite** | Windows/macOS | Commercial (paid "Pro" tier); exact price **unverified** | Positioned by reviewers as a lower-cost alternative to PixInsight ("a mini PixInsight"). [Cloudy Nights: Seti Astro Editing Suite or PixInsight?](https://www.cloudynights.com/forums/topic/953621-seti-astro-editing-suite-or-pixinsight/) |
| **Astro Pixel Processor (APP)** | Windows/macOS/Linux | Commercial: renter's license ~$60/yr, owner's license ~$150 (EUR ~165+VAT cited by an alternate source — confirm at purchase) | Popular stacking/integration tool with mosaic and multi-session support. [Astro Pixel Processor: Owner License](https://www.astropixelprocessor.com/product/astro-pixel-processor-owner-license/) |
| **DeepSkyStacker** | Windows only | Free, proprietary (source not fully open) | Long-standing free stacker; no Mac version. [Mac Observatory: Best Deep-Sky Stacking Software for Mac](https://macobservatory.com/mac-deep-sky-stacking-software-guide/) |
| **Sequator** | Windows only | Free | Handles both nightscape/star-trail stacking and deep-sky stacking. [AstroBackyard: Astrophotography Image Stacking Software](https://astrobackyard.com/astrophotography-image-stacking-software/) |

**Mobile (iOS) processing landscape:** thin but real. Identified iOS apps that capture, stack,
and edit directly on-device:
- **Astro Stacker: Star Images** — average and median stacking (median stacking used to
  reject satellite/plane trails), automatic star-detection alignment, one-time purchase, no
  subscription. [Astro Stacker — App Store](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598)
- **AstroShader** — capture + live-stack (up to 1,000 frames per run, aligned/stacked during
  capture) + edit, one-time purchase. [AstroShader official site](https://www.astroshader.com/); [Stargazers Lounge: iOS live stacking app - Astroshader](https://stargazerslounge.com/topic/406419-ios-live-stacking-app-astroshader/)
- **Star Stacker** — raw-preserving stacking with time-lapse/video export options. [Star Stacker — App Store](https://apps.apple.com/us/app/star-stacker/id1549693927)

None of these approach PixInsight/Siril-level processing depth (no gradient-removal AI,
limited calibration-frame support found in store listings); they target casual nightscape/
light deep-sky stacking, not serious narrowband or multi-session integration.

---

## 4. Plate-solving services

### Astrometry.net / nova.astrometry.net
- **What it does:** Given an image, matches star patterns against its index to return a full
  WCS astrometric solution plus a list of known catalog objects in the field — useful when
  coordinates are unknown or untrusted. [Nova Astrometry.net](https://nova.astrometry.net/)
- **API:** A documented JSON API supports uploading images, polling job/submission status, and
  retrieving calibration results programmatically. Requires an account and an API key (found
  under the user's nova.astrometry.net profile). [Nova Astrometry.net API docs](https://astrometrynet.readthedocs.io/en/stable/net/api.html); [Nova: api_help](https://nova.astrometry.net/api_help)
- **Terms:** Each upload can be flagged for commercial-use licensing (`y`/`n`/`d` for
  "default"), tied to the API key's default license setting — meaning **licensing is
  per-image, configurable, and must be set deliberately** if Dark Sky were to route user images
  through the service. Full ToS text was not independently re-verified in this pass beyond the
  API help page — **read nova.astrometry.net's terms directly before integrating**. [Nova Astrometry.net API docs](https://astrometrynet.readthedocs.io/en/stable/net/api.html)
- **Practical fit:** Free, well-documented, good for occasional/low-volume solves or as a
  fallback; not designed for high-frequency mobile/real-time solving (network round-trip,
  queue times).

### Local solvers (no network dependency)
- **ASTAP** — free, offline once a star-index database is downloaded; works with FITS, RAW
  DSLR, XISF, and common image formats. Its native solver is command-line compatible with
  PlateSolve2 and is used as the plate-solving backend inside NINA, CCDCiel, APT, Voyager, and
  Sequence Generator Pro. Considered the most popular free local/offline solver. [HNSky: ASTAP](https://www.hnsky.org/astap.htm); [Stellarnomads: Plate Solving Guide 2026](https://stellarnomads.com/plate-solving/)
- **PlateSolve2** — commercial/bundled solver from PlaneWave Instruments, favored by Sequence
  Generator Pro users; needs approximate starting coordinates ("near solving") and star
  catalogs such as APM or UCAC3. [Stellarnomads: Plate Solving Guide 2026](https://stellarnomads.com/plate-solving/)
- **Relevance to Dark Sky:** a local/offline solver (ASTAP-style index data bundled or
  downloaded) would let an iOS companion app plate-solve without depending on network
  connectivity in the field — directly aligned with Dark Sky's existing offline-maps
  philosophy.

---

## 5. Gap analysis — where Dark Sky could uniquely add value

Dark Sky's existing strengths (conditions + verdict scoring, terrain-aware horizon, a weather-
model spread with freshness indicator, a shot-window planner, offline maps, AR) are largely
**absent or only partially present** across the deep-sky planning and control tools surveyed
above. Specific gaps, named against the competitors who own each individual piece today:

1. **"Tonight's best deep-sky targets for MY gear from THIS spot, above MY horizon, away from
   the Moon, under the actual forecast transparency" — no single competitor does the full
   chain today.**
   - Telescopius comes closest on the *target* side: it already combines altitude filtering,
     moon-distance filtering, FOV/telescope simulation, and meteoblue-sourced weather in one
     product. [RASC Hamilton guide](https://www.hamiltonrasc.ca/exploring-the-cosmos-with-telescopius-a-comprehensive-guide-for-astrophotographers/); [Telescopius forum: Seeing forecast](https://forum.telescopius.com/t/seeing-forecast/335)
   - But Telescopius uses a flat horizon/altitude cutoff, not a **terrain-derived horizon
     profile** — Dark Sky's terrain horizon (used today for Milky Way core visibility) is a
     genuine differentiator DarkScout also claims via its "Horizon Profile" per-spot feature
     with local-obstruction-aware planning. [DarkScout app site](https://darkscout.app/)
   - No deep-sky-specific competitor found combines a **multi-model weather spread with a
     freshness/staleness indicator** (Dark Sky's approach to forecast trust) with target
     altitude/moon filtering; Astrospheric is the closest weather-specialist (transparency,
     seeing, smoke, multi-altitude cloud layers) but is a weather app, not a target planner,
     and has no telescope/gear-aware framing. [AstroBackyard: Best Weather Apps for Astronomy 2026](https://astrobackyard.com/best-weather-app-astronomy/)
   - **Gap for Dark Sky:** be the first to fuse (a) terrain-real horizon, (b) a trust-scored
     multi-model forecast, (c) gear-aware FOV/target filtering, and (d) moon-avoidance into one
     ranked "tonight's targets" list. Every piece exists somewhere; no competitor found joins
     all four.

2. **Handing a target off to a smart telescope.**
   - Today this is siloed: ZWO's Seestar app, Dwarflab's app, Vaonis's Singularity app, and
     Unistellar's app each do their own in-app GOTO with **no official cross-app API** (ZWO,
     Unistellar) or a narrower community bridge (Seestar via seestar_alp's Alpaca endpoint;
     Dwarflab via its own documented Stellarium remote-control integration plus the
     third-party dwarfAlp Alpaca driver). [GitHub: smart-underworld/seestar_alp](https://github.com/smart-underworld/seestar_alp); [DWARF 3 User Manual](https://help.dwarflab.com/en/docs/DWARF-3-Smart-Telescope-User-Manual-Part1-App-Interface-Introduction); [GitHub: acocalypso/dwarfAlp](https://github.com/acocalypso/dwarfAlp)
   - SkySafari 8 Pro is the one **planning app** already doing real telescope handoff via
     Alpaca (camera control specifically, plus general Alpaca/INDI/StarSense Explorer mount
     support) — proof that a planetarium-style iOS app talking Alpaca to local-network gear is
     both technically and commercially viable today. [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420)
   - **Gap for Dark Sky:** no competitor combines conditions-aware target *selection* with a
     direct-to-telescope *handoff* in one app. Dark Sky could plan the shot (accounting for
     horizon/moon/forecast) and then push RA/Dec + start-session directly to an Alpaca-
     reachable device (natively for Seestar via seestar_alp, DWARF via dwarfAlp; not
     currently possible for ZWO ASIAIR, Unistellar, or Vaonis without an official API).

3. **A session log that compares forecast with results.**
   - This exists today, but as **separate, desktop/web-first tools**, not integrated into a
     mobile conditions/planning app: N.I.N.A. Session Analysis (guiding/focus/seeing review,
     PDF reports), Photon Hunter (planned-vs-actual integration time per target, per-site
     forecast of cloud/seeing/transparency/temperature), DeepSkyLog (visibility vs. site
     forecast), AstroLog (session stats), and Nebulis (auto-organizes captures into a
     per-object log with conditions and stack counts). [N.I.N.A. Session Analysis — App Store](https://apps.apple.com/us/app/n-i-n-a-session-analysis/id6499096460?mt=12); [Photon Hunter](https://photonhunter.space/); [DeepSkyLog](https://deepskylog.space/); [AstroLog](https://astro-log.app/); [Nebulis](https://nebulis.app/)
   - **Gap for Dark Sky:** none of these are the same app that made the *forecast-based
     plan* in the first place. Dark Sky already produces a "verdict" from forecast data before
     the session; closing the loop by logging what actually happened (and comparing it back to
     the pre-session verdict/forecast spread) inside the same app is not something any
     surveyed competitor does end-to-end.

4. **Offline maps + AR** — Dark Sky's existing strengths have no close deep-sky-specific
   competitor doing both together. PhotoPills has AR (Milky Way overlay) but is
   nightscape-only, not deep-sky/gear-aware. [PhotoPills review](https://nightskypix.com/photopills-app-review/) Sky Guide has some AR-adjacent live framing (FOV Rotation Preview) but is a general
   planetarium, not a conditions/horizon/offline-map product. [Sky Guide — App Store](https://apps.apple.com/us/app/sky-guide/id576588894) No deep-sky planning tool surveyed (Telescopius, AstroPlanner, Deep Sky Planner, NINA)
   ships offline maps as a core feature — **unverified for AstroPlanner/Deep Sky Planner
   specifically, since this wasn't directly tested**, but none of the reviewed sources
   mentioned it.

**Net assessment:** the deep-sky app landscape is fragmented along the same lines as
general-purpose GIS-vs-domain-tool fragmentation — a few tools are excellent at one slice
(Telescopius: targets+FOV+weather; SkySafari: planetarium+Alpaca control; NINA:
framing+sequencing, desktop only; Photon Hunter/DeepSkyLog: post-session analytics) but none
combine conditions trust-scoring + terrain-real horizon + gear-aware target ranking +
telescope handoff + forecast-vs-actual logging in one mobile app. That combination is Dark
Sky's opening.

---

## Comparison table

| Tool | Category | Platform | Price/License | Telescope control API | Notes |
|---|---|---|---|---|---|
| Telescopius | Planning | Web, iOS, Android | Free | No device control; weather via meteoblue (unverified official) | Best-in-class FOV/framing + target filtering [source](https://apps.apple.com/us/app/telescopius/id6479415751) |
| SkySafari 8 Pro | Planning + control | iOS, Android, macOS | ~$24.99–$49.99 one-time + optional $5.99/mo or $49.99/yr Premium (verify) | **Yes** — ASCOM Alpaca, INDI, StarSense Explorer | Only planning app in this survey with real Alpaca camera/mount control [source](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420) |
| Stellarium Mobile Plus | Planning (planetarium) | iOS, Android | ~$5.99–$18.99 (alpha pricing, verify) | No | New engine, huge catalog depth, still alpha [source](https://stellarium-labs.com/blog/introducing-stellarium-mobile-plus/) |
| Stellarium Web | Planning (planetarium) | Browser | Free | No | No-install reference sky map [source](https://stellarium-web.org/) |
| AstroPlanner | Planning | Windows/Mac desktop | ~$45–$75 (unverified) | Some equipment integration claimed | Desktop only, faint/obscure-target focus [source](https://macobservatory.com/astroplanner-mac-review/) |
| Deep Sky Planner 9 | Planning + logging | Windows desktop | Trial free; paid (unverified) | Yes, via ASCOM (Windows) | Deep logging/reporting, Windows/ASCOM only [source](https://knightware.biz/dsp/productinfo.htm) |
| Sky Guide | Planning (consumer) | iOS | Freemium (verify) | No | FOV rotation preview, coordinate picker [source](https://apps.apple.com/us/app/sky-guide/id576588894) |
| PhotoPills | Nightscape planning | iOS, Android | ~$10 one-time | No | AR Milky Way overlay; not deep-sky [source](https://play.google.com/store/apps/details?id=com.photopills.android.photopills&hl=en&gl=US) |
| NINA (Framing Assistant + Sky Atlas) | Planning + sequencing | Windows desktop | Free, open source | Yes, extensive (Windows/ASCOM/Alpaca) | Best-in-class framing UX; desktop only [source](https://nighttime-imaging.eu/) |
| ZWO ASIAIR | Control + capture | Dedicated hardware + app | Closed, hardware-bundled | **No official API**; undocumented protocol only | Biggest gap: most popular smart-imaging rig, least open [source](https://www.cloudynights.com/forums/topic/928509-api-for-asiair/) |
| Seestar app | Control + capture | iOS/Android + hardware | Closed | No official API; **seestar_alp** community bridge exposes Alpaca | seestar_alp: 292 stars, mixed MIT/BSD/GPL [source](https://github.com/smart-underworld/seestar_alp) |
| Dwarflab app | Control + capture | iOS/Android + hardware | Closed | Official Stellarium remote-control integration; community dwarfAlp (Alpaca) and Dwarfium (Stellarium) | Most third-party-friendly of the smart-telescope apps [source](https://help.dwarflab.com/en/docs/DWARF-3-Smart-Telescope-User-Manual-Part1-App-Interface-Introduction) |
| Vaonis Singularity | Control + capture | iOS/Android + hardware | Closed | Manual RA/Dec entry supported in-app; no confirmed third-party API | See Vaonis ToU before any integration attempt [source](https://vaonis.com/pages/singularity-app-general-term-of-use) |
| Unistellar app | Control + capture | iOS/Android + hardware | Closed | Promised, not confirmed released; unofficial reverse-engineering project exists | Least integration-ready of the four smart-scope apps [source](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/README.md) |
| ASCOM Alpaca | Protocol | Any (HTTP/JSON) | Open standard | N/A (it *is* the API) | Confirmed iOS-reachable on local network; SkySafari 8 Pro proves it [source](https://ascom-standards.org/About/Conn-Alpaca.htm) |
| INDI | Protocol | Cross-platform | Mixed LGPL-2.1/GPL-2.0/BSD | N/A | GPL components complicate closed-source iOS reuse [source](https://github.com/indilib/indi) |
| INDIGO | Protocol | Cross-platform | Permissive, "no GPL dependency" | N/A | Explicitly designed for app-store/commercial reuse [source](https://github.com/indigo-astronomy/indigo) |
| Siril | Processing | Desktop (Win/Mac/Linux) | Free, GPL-3.0 | N/A | Full scriptable pipeline [source](https://en.wikipedia.org/wiki/Siril_(software)) |
| PixInsight | Processing | Desktop (Win/Mac/Linux) | ~€300 commercial | N/A | Industry standard, steep learning curve [source](https://www.zelpio.com/blog/astro-wizard-vs-siril-vs-pixinsight-2026/) |
| GraXpert | Processing | Desktop (Win/Mac/Linux) | Free, open source (license mixed — verify per repo) | N/A | Gradient removal, AI mode, plugs into Siril/Seti Astro [source](https://graxpert.com/) |
| Seti Astro Suite | Processing | Desktop (Win/Mac) | Commercial (price unverified) | N/A | Lower-cost PixInsight alternative [source](https://www.cloudynights.com/forums/topic/953621-seti-astro-editing-suite-or-pixinsight/) |
| Astro Pixel Processor | Processing | Desktop (Win/Mac/Linux) | ~$60/yr or ~$150 owner license | N/A | Popular stacker/integrator [source](https://www.astropixelprocessor.com/product/astro-pixel-processor-owner-license/) |
| DeepSkyStacker | Processing | Windows only | Free | N/A | No Mac support [source](https://macobservatory.com/mac-deep-sky-stacking-software-guide/) |
| Sequator | Processing | Windows only | Free | N/A | Nightscape + deep-sky stacking [source](https://astrobackyard.com/astrophotography-image-stacking-software/) |
| iOS stacking apps (Astro Stacker, AstroShader, Star Stacker) | Processing | iOS | One-time purchase, no subscription | N/A | Shallow vs. desktop tools; no gradient/narrowband workflow found [sources](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598) |
| Astrometry.net (nova) | Plate solving | Cloud API | Free, API key required; per-image commercial-license flag | N/A | Good fallback; not built for real-time mobile use [source](https://nova.astrometry.net/api_help) |
| ASTAP | Plate solving | Desktop, offline | Free | N/A | Most popular free offline solver; used inside NINA et al. [source](https://www.hnsky.org/astap.htm) |
| PlateSolve2 | Plate solving | Desktop, offline | Bundled/commercial | N/A | Needs approximate starting coordinates [source](https://stellarnomads.com/plate-solving/) |
| DarkScout | Nightscape/dark-sky planning (closest existing rival) | iOS | Freemium (Pro tier) | No | Horizon Profile + Astro Score; closest existing analog to Dark Sky's current scope [source](https://darkscout.app/) |
| Photon Hunter / DeepSkyLog / AstroLog / Nebulis | Session logging | Desktop/web/self-hosted | Free/freemium, mixed | N/A | Forecast-vs-actual logging exists, but not inside a planning+control app [sources](https://photonhunter.space/) |

---

## Sources

- [Telescopius — App Store](https://apps.apple.com/us/app/telescopius/id6479415751)
- [Telescopius — Google Play](https://play.google.com/store/apps/details?id=com.telescopius.twa&hl=en_US)
- [RASC Hamilton: Exploring the Cosmos with Telescopius](https://www.hamiltonrasc.ca/exploring-the-cosmos-with-telescopius-a-comprehensive-guide-for-astrophotographers/)
- [Telescope Live: Planning Mosaics with Telescopius](https://telescope.live/blog/planning-mosaics-telescopius)
- [Telescopius forum: Seeing forecast](https://forum.telescopius.com/t/seeing-forecast/335)
- [SkySafari 8 Pro — App Store](https://apps.apple.com/us/app/skysafari-8-pro/id6752672420)
- [Cloudy Nights: SkySafari 8 Pro for Apple](https://www.cloudynights.com/forums/topic/987626-skysafari-8-pro-for-apple/)
- [SkySafari 7 Pro — App Store](https://apps.apple.com/us/app/skysafari-7-pro/id1567658979)
- [Stellarium Labs: Introducing Stellarium Mobile Plus](https://stellarium-labs.com/blog/introducing-stellarium-mobile-plus/)
- [Stellarium Mobile — App Store](https://apps.apple.com/us/app/stellarium-mobile-star-map/id1458716890)
- [Stellarium Web](https://stellarium-web.org/)
- [Stellarium Labs: Stellarium Web](https://stellarium-labs.com/stellarium-web/)
- [Stellarium (software) — Wikipedia](https://en.wikipedia.org/wiki/Stellarium_(software))
- [Cloudy Nights: low-cost planning software thread](https://www.cloudynights.com/topic/671071-what-is-a-low-cost-computer-based-observing-planning-software/)
- [Mac Observatory: AstroPlanner on the Mac](https://macobservatory.com/astroplanner-mac-review/)
- [Knightware: Deep-Sky Planner 9 Features](https://knightware.biz/dsp/productinfo.htm)
- [Knightware: Deep-Sky Planner 9 Trial Edition](https://knightware.biz/dsp/trial.htm)
- [Astronomy Technology Today: Deep-Sky Planner 9 Release](https://astronomytechnologytoday.com/2024/07/23/deep-sky-planner-9-release/)
- [Sky Guide — App Store](https://apps.apple.com/us/app/sky-guide/id576588894)
- [Space.com: Sky Guide stargazing app review](https://www.space.com/sky-guide-stargazing-app-review)
- [AstroBackyard: 20 Best Astronomy Apps in 2026](https://astrobackyard.com/astronomy-apps-for-stargazing/)
- [PhotoPills app review 2026 — Night Sky Pix](https://nightskypix.com/photopills-app-review/)
- [Digital Photography School: Plan Astrophotography With PhotoPills](https://digital-photography-school.com/plan-astrophotography-with-photopills-app/)
- [PhotoPills — Google Play](https://play.google.com/store/apps/details?id=com.photopills.android.photopills&hl=en&gl=US)
- [NINA — Nighttime Imaging 'N' Astronomy](https://nighttime-imaging.eu/)
- [Dale Ghent: Introducing NINA](https://daleghent.com/nina-introduction)
- [NINA docs: Sky Atlas](https://nighttime-imaging.eu/docs/master/site/tabs/skyatlas/)
- [NINA docs: Framing Assistant](https://nighttime-imaging.eu/docs/master/site/tabs/framing/)
- [ZWO: ASIAIR V3.0 New Features and User Guide](https://www.zwoastro.com/2026/07/15/asiair-new-features-and-user-guide/)
- [ZWO Software page](https://www.zwoastro.com/software_v1/)
- [Cloudy Nights: "API for AsiAir?"](https://www.cloudynights.com/forums/topic/928509-api-for-asiair/)
- [ZWO User Facebook group: ASIAIR API question](https://www.facebook.com/groups/ASIAIR/posts/2294737537356123/)
- [GitHub: smart-underworld/seestar_alp](https://github.com/smart-underworld/seestar_alp)
- [seestar_alp: Seestar Alpaca API directory](https://github.com/smart-underworld/seestar_alp/tree/main/bruno/Seestar%20Alpaca%20API)
- [Wido's AstroForum: Best Budget Smart Telescope 2026](https://astroforumspace.com/best-budget-smart-telescope-in-2026-seestar-s30-s30-pro-s50-vs-dwarf-3-and-mini/)
- [ZWO Seestar: Quick Guide to the Seestar App](https://www.seestar.com/blogs/seestar-guide/quick-guide-to-the-seestar-app)
- [DWARF 3 User Manual](https://help.dwarflab.com/en/docs/DWARF-3-Smart-Telescope-User-Manual-Part1-App-Interface-Introduction)
- [DWARFLAB App Firmware Download](https://www.dwarflab.com/us/pages/dwarflab-app-firmware-download)
- [GitHub: acocalypso/dwarfAlp](https://github.com/acocalypso/dwarfAlp)
- [GitHub: stevejcl/dwarfium](https://github.com/stevejcl/dwarfium)
- [Vaonis: Singularity, the new companion app](https://vaonis.com/blogs/travel-journal/singularity-the-new-companion-app-of-your-observation-station)
- [Vaonis Vespera II product page](https://vaonis.com/pages/product/vespera-ii)
- [Vaonis: Singularity App Terms of Use](https://vaonis.com/pages/singularity-app-general-term-of-use)
- [Unistellar Help Center: App Changelog](https://help.unistellar.com/hc/en-us/articles/7306522999324-The-UNISTELLAR-App-Changelog-for-Telescopes-App-and-Firmware-Updates)
- [GitHub: jankais3r/Unistellar-eVscope-research](https://github.com/jankais3r/Unistellar-eVscope-research/blob/master/README.md)
- [ASCOM Standards: About Alpaca Connectivity](https://ascom-standards.org/About/Conn-Alpaca.htm)
- [ASCOM Standards home](https://ascom-standards.org/)
- [Mac Observatory: ASCOM Alpaca Protocol 2026](https://macobservatory.com/ascom-alpaca-mac-observatory-automation/)
- [Alpyca docs: Introduction and Quick Start](https://ascom-standards.org/alpyca/introduction.html)
- [GitHub: indilib/indi](https://github.com/indilib/indi)
- [INDI docs: Getting Started](https://docs.indilib.org/getting-started/)
- [GitHub: indigo-astronomy/indigo](https://github.com/indigo-astronomy/indigo)
- [INDIGO Astronomy](https://www.indigo-astronomy.org/)
- [Siril (software) — Wikipedia](https://en.wikipedia.org/wiki/Siril_(software))
- [Zelpio: AstroWizard vs Siril vs PixInsight 2026](https://www.zelpio.com/blog/astro-wizard-vs-siril-vs-pixinsight-2026/)
- [GraXpert — PyPI](https://pypi.org/project/graxpert/)
- [GitHub: Steffenhir/GraXpert](https://github.com/Steffenhir/GraXpert/)
- [GraXpert official site](https://graxpert.com/)
- [Cloudy Nights: Seti Astro Editing Suite or PixInsight?](https://www.cloudynights.com/forums/topic/953621-seti-astro-editing-suite-or-pixinsight/)
- [Astro Pixel Processor: Owner License](https://www.astropixelprocessor.com/product/astro-pixel-processor-owner-license/)
- [Mac Observatory: Best Deep-Sky Stacking Software for Mac](https://macobservatory.com/mac-deep-sky-stacking-software-guide/)
- [AstroBackyard: Astrophotography Image Stacking Software](https://astrobackyard.com/astrophotography-image-stacking-software/)
- [Astro Stacker: Star Images — App Store](https://apps.apple.com/us/app/astro-stacker-star-images/id6753679598)
- [AstroShader official site](https://www.astroshader.com/)
- [Stargazers Lounge: iOS live stacking app - Astroshader](https://stargazerslounge.com/topic/406419-ios-live-stacking-app-astroshader/)
- [Star Stacker — App Store](https://apps.apple.com/us/app/star-stacker/id1549693927)
- [Nova Astrometry.net](https://nova.astrometry.net/)
- [Nova Astrometry.net API docs](https://astrometrynet.readthedocs.io/en/stable/net/api.html)
- [Nova: api_help](https://nova.astrometry.net/api_help)
- [HNSky: ASTAP](https://www.hnsky.org/astap.htm)
- [Stellarnomads: Plate Solving Guide 2026](https://stellarnomads.com/plate-solving/)
- [DarkScout app site](https://darkscout.app/)
- [DarkScout — App Store](https://apps.apple.com/br/app/darkscout/id6760223860)
- [AstroBackyard: Best Weather Apps for Astronomy 2026](https://astrobackyard.com/best-weather-app-astronomy/)
- [N.I.N.A. Session Analysis — App Store](https://apps.apple.com/us/app/n-i-n-a-session-analysis/id6499096460?mt=12)
- [Photon Hunter](https://photonhunter.space/)
- [DeepSkyLog](https://deepskylog.space/)
- [AstroLog](https://astro-log.app/)
- [Nebulis](https://nebulis.app/)
