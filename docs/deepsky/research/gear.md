# Deep-sky and planetary gear landscape (2026-09-27)

Research for expanding Dark Sky from Milky Way nightscapes into general astrophotography:
smart telescopes, star trackers, beginner imaging rigs, and what an iPhone can realistically
do bolted to any of it. All facts below are dated **2026-09-27** and cited inline. Every
numeric value has a source; anything not found in a manufacturer page or a reputable review
is marked `null` in `gear.json` and flagged here rather than guessed.

Companion machine-readable file: `gear.json` (`smart_telescopes`, `trackers`, `telescopes`,
`astro_cameras`, `mounts`, `phone_adapters`).

---

## 1. Smart telescopes

All-in-one goto + camera + stacking units controlled from a phone app. The dominant category
for beginners entering deep-sky in 2026.

| Model | Aperture | Focal length | f-ratio | Sensor | Resolution | Mount | Max sub-exp | Weight | Price tier |
|---|---|---|---|---|---|---|---|---|---|
| ZWO Seestar S50 | 50 mm | 250 mm | f/5 | Sony IMX462 | 1920x1080 | alt-az | ~10 s (alt-az; EQ firmware update reported to 30 s) | 2.5 kg | Budget, $549, **discontinued 2026** |
| ZWO Seestar S30 | 30 mm | null | f/5 | Sony IMX662 (STARVIS 2) | 1920x1080 | alt-az, EQ mode supported | 30 s | 1.65 kg | Budget, $399 |
| ZWO Seestar S50 Pro | 50 mm (tele) / — (wide) | 260 mm / 6 mm | f/5.2 / f/1.75 | OmniVision OS08B10 / Sony IMX586 | 3840x2160 (8.3 MP) both | alt-az + EQ mode | 60 s (**EQ mode only**, per ZWO) | 2.8 kg | Mid, $999-$1,098 |
| ZWO Seestar S30 Pro | 30 mm (tele) / — (wide) | null / 6 mm | f/5.3 / f/1.75 | Sony IMX585 (STARVIS 2) | 8.3 MP | alt-az | null | 1.6 kg | Budget-mid |
| Dwarflab DWARF 3 | 35 mm (tele) / 3.4 mm (wide) | 150 mm (tele, 737 mm-equiv) / 6.7 mm (wide) | f/4.3 | Sony IMX678 STARVIS 2 (tele) | 3840x2160 (8.3 MP) | alt-az + EQ mode (tripod-adjust polar alignment) | 60 s (EQ mode) | 1.3 kg | Budget, $549 |
| Dwarflab DWARF mini | 30 mm | 150 mm | f/5 | Sony IMX662 | 2.1 MP native | alt-az | null | 0.84 kg | Budget, $399 |
| Vaonis Vespera II | 50 mm | 250 mm | f/5 | Sony IMX585 | 3840x2160 (8.3 MP), up to 24 MP mosaic | alt-az (EQ status not stated) | null | 5.0 kg | Mid, from EUR 1,590 |
| Vaonis Vespera Pro | null | null | null | Sony IMX676 | 3536x3536 (12.5 MP), up to 50 MP mosaic | null | null | null | Premium, $2,799 |
| Vaonis Stellina | 80 mm | 400 mm | f/5 | Sony IMX178 | 3096x2080 (6.4 MP) | alt-az, fixed observation-station body | null | null | Premium (legacy flagship) |
| Unistellar eQuinox 2 | 114 mm | 450 mm | f/4 | Sony IMX347 | 6.2 MP | motorized alt-az, Newtonian | null | null | Premium, $2,499 |
| Unistellar Odyssey | 85 mm | 320 mm | f/3.9 | null | null | motorized alt-az | null | 4.0 kg | Premium, $2,599 (Odyssey Pro $3,999) |

**Field of view**, where sourced: Seestar S50 Pro 2.8° (tele) / 63° (wide); Seestar S30 Pro
4.6° (tele) / 63° (wide); Vespera II 2.5°x1.4° native (up to 4.33°x2.43° mosaic); Vespera Pro
1.6°x1.6° native (up to 50 MP mosaic); Stellina 1.0°x0.7°; eQuinox 2 34x47 arcmin; Odyssey
33.6x45 arcmin. Not found for the original S50, S30, S30 Pro, or DWARF models — left `null`.

**Field rotation / EQ mode.** Alt-az smart scopes are subject to field rotation on long
subs because they track in altitude/azimuth rather than parallel to the sky's rotation
axis; this caps clean single sub-exposures well below what an equatorially mounted rig can
do. Several 2026-era models now ship or added firmware for an "EQ mode" — physically tilting
the mount to align near the celestial pole — which removes field rotation and raises the
sub-exposure ceiling (Seestar S30/S50 to 30 s per Agena Astro's how-to; Seestar S50 Pro and
DWARF 3 to 60 s per their own spec pages). Sources: [Agena Astro EQ mode guide](https://agenaastro.com/articles/imaging/how-to-set-up-and-use-eq-mode-on-the-zwo-seestar-s50-s30), [ZWO Seestar S50 Pro product page](https://www.zwoastro.com/product/seestar-s50-pro/), [AstroBackyard DWARF 3 review](https://astrobackyard.com/dwarf-3/).

**Built-in filters.** Most smart scopes ship a UV/IR-cut filter plus a switchable dual-band
narrowband filter (commonly OIII ~30 nm / H-alpha ~20 nm) for shooting emission nebulae under
light-polluted skies without a mechanical filter wheel. Confirmed for Seestar S50, Seestar S50
Pro, and DWARF 3; not confirmed for the Vaonis or Unistellar lines in this pass.

### API and automation

| Project | Targets | What it does | License | Popularity |
|---|---|---|---|---|
| **seestar_alp** (`smart-underworld/seestar_alp`) | ZWO Seestar S50 (community reports suggest broad Seestar-family coverage, unconfirmed per-model) | Full control/automation server; implements ASCOM/Alpaca-style endpoints; adds scheduling and mosaic features beyond the official app; browser-based UI, no phone app required | Mixed MIT / BSD-3-Clause / GPL-3.0 per repo | 292 stars, 71 forks, ~1,997 commits, 53 open issues (GitHub, 2026-09-27) |
| **SeestarPi** (`IZA165/SeestarPi`) | Seestar S50 | Lightweight Python framework extending the Alpaca protocol / ASCOM standards for control and automation | Not verified in this pass | Not verified |
| **pyindi_seestar** (`cgobat/pyindi_seestar`) | Seestar S50 | Python-based INDI driver, bridging Seestar into the broader INDI ecosystem (StellarMate, KStars/Ekos, etc.) | Not verified in this pass | Not verified |
| **seestar-mcp** (`joshuagillmore/seestar-mcp`) | Seestar S50 | An MCP server plus Claude Code skills to control the scope and QA its output — directly relevant as a precedent for agent-driven telescope control | Not verified in this pass | Not verified |

No manufacturer in this survey (ZWO, Dwarflab, Vaonis, Unistellar) publishes an official
public API as of 2026-09-27; all automation found is reverse-engineered community tooling,
concentrated almost entirely around the ZWO Seestar family because of its outsized install
base (50,000+ S50 units sold — see popularity note below). This is the most obvious
integration opportunity for Dark Sky: a Seestar-control surface (via seestar_alp's Alpaca
API or a similar reverse-engineered protocol) could let the app drive capture directly,
but it would be building on unofficial, unsupported protocols with no license guarantee of
stability. Source: [seestar_alp GitHub](https://github.com/smart-underworld/seestar_alp), [Gord Tulloch, "Controlling Smart Telescopes with OSS"](https://openastronomy.substack.com/p/controlling-smart-telescopes-with).

### Popularity evidence (2025-2026)

- **Seestar S50**: reported to have sold over 50,000 units worldwide and is described as
  "one of the most popular smart telescopes ever made"; ZWO discontinued it in early 2026
  in favor of the S50 Pro. Active Cloudy Nights review thread running since October 2023
  with 69+ replies. Sources: [TelescopeAdvisor, "Seestar S50 Discontinued"](https://www.telescopeadvisor.com/seestar-s50-discontinued-what-to-buy-instead/), [Cloudy Nights S50 review thread](https://www.cloudynights.com/forums/topic/894064-seestar-s50-first-light-and-review/).
- **DWARF 3**: multiple independent 2026 reviews (AstroBackyard, Astronomy.com, Space.com,
  Galactic Hunter) and buying guides now recommend it as the direct S50 successor at the
  budget tier. Source: [TelescopeAdvisor budget guide](https://www.telescopeadvisor.com/seestar-s50-discontinued-what-to-buy-instead/).
- **Vespera II**: named "best for nebula images at mid-range price" in a 2026 multi-brand
  buying guide. Source: [TelescopeAdvisor comparison](https://www.telescopeadvisor.com/smart-telescope-comparison-all-brands-2026/).
- No independent unit-sales or market-share data was found for DWARF, Vaonis, or Unistellar
  models — treat any ranking beyond the above as review-site opinion, not sales data.

---

## 2. Star trackers for camera-lens deep-sky

Lightweight equatorial trackers for a DSLR/mirrorless camera and lens (or small scope), no
built-in optics or stacking — the "manual" tier below smart telescopes.

| Model | Payload | Weight | Polar alignment | Tracking accuracy | Price tier |
|---|---|---|---|---|---|
| Sky-Watcher Star Adventurer GTi | 5.0 kg (11 lb) | 2.6 kg | Built-in illuminated polar scope + SynScan app assist | ~±10 arcsec (third-party review synthesis, not a manufacturer figure) | Mid |
| Sky-Watcher Star Adventurer 2i | 5.0 kg (11 lb) | 1.65 kg | Polar scope; SynScan app, Wi-Fi | Not found | Budget-mid, $585 (Pro Pack) |
| iOptron SkyGuider Pro | 5.0 kg (11 lb) | 1.0 kg | AccuAlign integrated polar scope (iPolar electronic variant available) | Not found | Budget-mid, $488 ($638 iPolar) |
| Move Shoot Move (original tracker) | 3.0 kg (6.6 lb) | 0.4 kg | Built-in polar scope + app | Best under 200 mm lenses per manufacturer guidance | Budget, $209 |
| Move Shoot Move NOMAD Harmonic I | 3.5 kg (7.7 lb, NOMAD spec) | Not found | Not found | Stable 2-minute exposures up to 280 mm per manufacturer | Mid, from $599 |
| Benro Polaris Astro Edition | 7.0 kg (15 lb) | 1.1 kg (head); +0.4 kg astro module | Motorized/electric head with camera-interface controller; app-guided, no traditional polar scope | 0.0025° adjustment resolution per manufacturer | Premium, $1,149 |

None of the sources reviewed published a sourced "typical max unguided exposure by focal
length" table (the kind derived from the NPF rule) for these specific trackers — that
calculation is something the app itself should compute per-lens rather than something to
hard-code from a single tracker's marketing copy. The Benro Polaris stands out for payload
(7 kg, highest here) and its motorized, non-polar-scope alignment workflow; Move Shoot Move
is the lightest and cheapest, explicitly scoped by its maker to shorter lenses.

Sources: [AstroBackyard GTi review](https://astrobackyard.com/sky-watcher-star-adventurer-gti/), [Sky-Watcher USA 2i Pro Pack](https://www.skywatcherusa.com/products/star-adventurer-pro-pack), [High Point Scientific SkyGuider Pro](https://www.highpointscientific.com/ioptron-skyguider-pro-camera-tracking-mount-ioptron-3350), [Move Shoot Move store](https://www.moveshootmove.com/collections/star-trackers), [Digital Camera World Benro Polaris review](https://www.digitalcameraworld.com/reviews/benro-polaris-astro-edition-star-tracker-review).

---

## 3. Beginner-to-intermediate imaging telescopes, cameras, mounts, and controllers

### Apochromatic refractors (specs for FOV/image-scale math)

| Model | Aperture | Focal length | f-ratio | Notes |
|---|---|---|---|---|
| William Optics RedCat 51 (Gen 3, WIFD) | 51 mm | 250 mm | f/4.9 | Petzval, FPL53 ED glass, 45 mm flat image circle (full-frame capable) |
| William Optics RedCat 61 (WIFD) | 61 mm | 300 mm | f/4.9 | Petzval, FPL53 ED glass, full-frame corrected |
| Askar FRA400 | 72 mm | 400 mm | f/5.6 | Quintuplet APO; optional 0.7x reducer → 280 mm f/3.9; 44 mm image circle |
| Askar FMA180 Pro | 40 mm | 180 mm | f/4.5 | Sextuplet (3+3) APO, compact internal-focus astrograph |
| SVBony SV503 70ED | 70 mm | 474 mm | f/6.78 | Also sold as 80 mm f/7 (560 mm) and 102 mm (714 mm) variants |
| SVBony SV550 122 mm | 122 mm | 854 mm | f/7 | Triplet APO with ED center element; 80 mm f/6 variant also sold |

### Astro cameras (specs for FOV/image-scale math)

| Model | Sensor | Sensor size | Pixel size | Resolution | Notes |
|---|---|---|---|---|---|
| ZWO ASI585MC | Sony IMX585 | 11.13 x 6.26 mm (1/1.2") | 2.9 µm | 3840x2160 (8.3 MP) | Budget dual-purpose (DSO/planetary), 47 fps max, 91% peak QE |
| ZWO ASI533MC Pro | Sony IMX533 | 11.1 x 11.1 mm (1", square) | 3.76 µm | 3008x3008 (9 MP) | Square format avoids camera-rotation framing issues; 2-stage TEC cooling |
| ZWO ASI2600MC Pro | Sony IMX571 | 23.5 x 15.7 mm (APS-C) | 3.76 µm | 6248x4176 (26 MP) | Premium step-up; 14-stop dynamic range, 80% peak QE |
| Player One Neptune-C II | Sony IMX464 | 1/1.8" (9 mm diagonal) | 2.9 µm | 2712x1538 (4.2 MP) | Planetary-focused: 93 fps at full res |
| Player One Uranus-C | Sony IMX585 (STARVIS 2) | 1/1.2" (12.85 mm diagonal) | 2.9 µm | 3856x2180 (8.3 MP) | Dual-purpose planetary/light DSO, 47Ke full well |

### Mounts

| Model | Payload | Price tier | Notes |
|---|---|---|---|
| ZWO AM3 / AM3N | 8 kg (no CW) / 13 kg (with CW) | Mid-premium, $1,499-$1,999 | Harmonic/strain-wave, 4.1 kg head, Wi-Fi/Bluetooth phone control, alt-az + EQ GoTo |
| ZWO AM5 / AM5N | 13-15 kg (no CW) / 20 kg (with CW) | Premium, ~$2,350+ | Harmonic drive; periodic error ±20″/288s (AM5) tightened to ±10″/288s (AM5N) |
| Sky-Watcher HEQ5 Pro / HEQ5-R Pro | 11 kg (24 lb photo) / 15 kg (33 lb, R Pro) | Mid, under £600 | SynScan GoTo, 42,900+ object database, illuminated polar scope |
| Sky-Watcher EQ6-R Pro | 20 kg (44 lb photo) | Mid-premium, under $2,000 | Belt-driven steppers, ST-4 port, ~0.8″ RMS guided per a reviewer's field test |
| iOptron CEM26 | 11.8 kg (26 lb) | Mid | Center-balanced, <0.3″ RMS periodic error per manufacturer, optional iPolar |

### Guiding basics

A separate small guide scope + guide camera (or an off-axis guider) feeding software like
PHD2 corrects for periodic error and seeing-induced drift during long unguided subs — this
is what lets an EQ6-R- or HEQ5-class rig hold multi-minute exposures where a bare star
tracker cannot. This survey did not deep-dive specific guide-camera/guide-scope combos;
flagged as a gap for a follow-up pass if the app needs specific guide-scope FOV math.

### Controllers

| Product | Role | Price | Notes |
|---|---|---|---|
| ZWO ASIAIR Plus | Dedicated Wi-Fi imaging controller/computer | $299 (base) | ASI-camera-only ecosystem lock-in; 2x USB3.0, 2x USB2.0, Gigabit Ethernet, 4x 12V outputs, 32 GB storage, auto-recovery mode |
| StellarMate Pro | INDI-based observatory controller (Raspberry-Pi-class hardware) | Not found (search results lacked pricing) | Camera-agnostic (supports DSLR/mirrorless plus dedicated astro cameras via INDI drivers), 4/8 GB RAM variants, built-in GPS, stepper-motor focuser control |

Reviewer consensus (Optics Central, Cloudy Nights forum threads): choose ASIAIR Plus for
tight ZWO-hardware integration and simplicity; choose StellarMate for broader third-party
camera/hardware compatibility and flexibility at a comparable or lower total cost once
accessories are added. Sources: [Optics Central comparison](https://www.opticscentral.com.au/blog/stellarmate-pro-vs-zwo-asiair-plus/), [ZWO ASIAIR Plus product info](https://optcorp.com/products/zwo-asiair-plus-wireless-imaging-controller), [StellarMate Pro spec page](https://stellarmate.com/support/first-time-setup/stellarmate-pro).

---

## 4. The iPhone on telescopes

### Adapters

**Celestron NexYZ 3-Axis Universal Smartphone Adapter** — the most commonly cited
eyepiece-projection adapter. Clamps an eyepiece 35-60 mm or 65-90 mm in diameter and uses
X/Y/Z screw adjustment to center the phone's lens over the eyepiece exit pupil. Weighs 283 g;
metal-spring threaded lock fits most phones with cases on. Reviewers note very wide 2-inch
eyepieces (e.g., a stock 28 mm) may not clamp. Source: [Celestron product page](https://www.celestron.com/products/nexyz-3-axis-universal-smartphone-adapter), [Sky at Night Magazine review](https://www.skyatnightmagazine.com/reviews/accessories/celestron-nexyz-3-axis-universal-smartphone-adapter).

### What's realistic

- **The Moon and bright planets: yes**, via afocal eyepiece projection plus lucky-imaging
  video capture. This is the dominant workflow in the hobby (see §5) — record video through
  the eyepiece, then stack the sharpest frames in software. Reviewers report success from
  Moon to "several deep sky objects" through a NexYZ-style adapter, though DSO results this
  way are described as limited. Source: [BackyardStargazers NexYZ review](https://backyardstargazers.com/celestron-nexyz-3-axis-universal-smartphone-adapter-review/).
- **Bright deep-sky objects (large nebulae, bright galaxy cores, star clusters): limited.**
  Afocal phone imaging works for framing/documentation shots of bright, extended objects, but
  faint DSOs need long stacked exposures that the phone's own camera pipeline cannot deliver
  through an eyepiece the way a dedicated cooled astro camera or even a smart telescope can.
- **Smart telescopes are the realistic deep-sky path for an iPhone user**: rather than
  attaching a phone to a telescope's eyepiece, the phone runs the smart telescope's app
  (Seestar, DWARFLAB, Singularity, Unistellar) while the telescope's own sensor and
  onboard stacking do the actual deep-sky imaging — the phone is the controller/viewer, not
  the imaging sensor, for anything beyond the Moon/planets/Sun.

### The iPhone's 1-second exposure ceiling in this context

Per this repo's own measured capture limits
(`/Users/brianbusch/Developer/wt-gear/docs/ios/CAPTURE-LIMITS.md`, measured 2026-09-26 on an
iPhone 18 Pro Max), a third-party app on iPhone is hard-capped at **1.0 s per frame** on every
back-camera format — this is an `AVCaptureDevice.Format` limit, not a UI restriction, so it
applies identically whether the phone is on a tripod, on a star tracker, or afocally
eyepiece-mounted on a telescope. Practical consequences for the deep-sky/telescope context:

- Any iPhone-native deep-sky capture (not through a smart telescope's own sensor) must be
  built from a *sequence* of 1 s frames, stacked in software — exactly the star-trail/Milky
  Way stacking pipeline this app already implements, extended to a telescope-fed field of
  view.
  - Bayer RAW is unavailable on the iPhone in any configuration; "RAW" here means Apple
  ProRAW (demosaiced linear DNG), which still passes through Apple's own image pipeline.
  This matters if the app or a user tries to feed iPhone frames into desktop DSO stacking
  tools expecting true sensor RAW.
- For Moon/planetary lucky imaging specifically, the 1 s ceiling is not the binding
  constraint — lucky imaging uses many short video frames (tens of milliseconds each) to
  freeze atmospheric seeing, and the iPhone's minimum exposure (14 µs per the same capture
  probe) is far more than fast enough for that use case. The video/frame-rate path, not the
  long-exposure still path, is what makes iPhone lunar/planetary imaging viable.

### Apps used for iPhone eyepiece/telescope imaging

- **SharpCap** and **AutoStakkert!** — the dominant desktop tools for capturing and stacking
  lucky-imaging video of the Moon, planets, and Sun; not iPhone apps themselves, but the
  destination for video exported off a phone or a dedicated planetary camera.
  [SharpCap](https://www.sharpcap.co.uk/), [AutoStakkert!](https://www.autostakkert.com/)
- **PIPP** (Planetary Imaging PreProcessor) — desktop preprocessing (crop, resize, planet
  detection) typically run before AutoStakkert!.
- **AstroEdit Planet** — an iPad app offering an interactive "Lucky stacking" slider and
  wavelet-based detail extraction, i.e., a mobile-native equivalent to the
  AutoStakkert!/wavelet-sharpening desktop workflow. Source: [App Store listing](https://apps.apple.com/ci/app/astroedit-planet/id6758052019).
- **Smart-telescope apps** (Seestar, DWARFLAB, Vaonis Singularity, Unistellar) — these are
  the phone's actual astrophotography interface for anyone using a smart telescope; capture,
  live stacking, and object selection all happen through them rather than the iPhone Camera
  app.
- **Celestron StarSense Explorer** app — used with StarSense-enabled Dobsonians for
  phone-assisted star-hopping/goto, a different (visual/navigation) use case from imaging.

Sources: [AstroBackyard astronomy apps roundup 2026](https://astrobackyard.com/astronomy-apps-for-stargazing/), [Mac Observatory iOS astronomy directory 2026](https://macobservatory.com/iphone-ipad-astronomy-software/).

---

## 5. Planetary and lunar imaging gear basics

- **Barlows**: increase effective focal length (commonly 2x-5x) ahead of a planetary camera
  or eyepiece, trading field of view for image scale — necessary because planets are small
  and need high magnification even though they're bright enough for very short exposures.
- **ADC (atmospheric dispersion corrector)**: corrects the color-fringing caused by
  Earth's atmosphere bending different wavelengths of light by different amounts, which is
  worst when a target is low on the horizon. Physically two adjustable prisms in a housing
  placed between the Barlow and the camera/eyepiece; works best above f/15, per manufacturer
  guidance. Source: [Sky at Night Magazine ADC guide](https://www.skyatnightmagazine.com/astrophotography/atmospheric-dispersion-corrector), [SVBony ADC 101](https://www.svbony.com/blog/ADC-101).
- **High-frame-rate cameras**: e.g., Player One Neptune-C II (93 fps at full 4.2 MP
  resolution) or ZWO/Player One's larger-sensor color cameras — used to record hundreds to
  thousands of video frames per target, from which "lucky imaging" software (AutoStakkert!)
  selects and stacks only the sharpest fraction to defeat atmospheric seeing. This is the
  same lucky-imaging principle behind the app's own star-trail/stacking design, applied to
  planets instead of star fields.

---

## 6. Solar imaging — safety first

**Solar imaging without a certified, properly fitted front-mounted solar filter is
dangerous and can cause instant, permanent eye damage or fire.** This section is safety
guidance only, not a gear recommendation list.

- **Filters belong on the front of the optical train — objective end — never at the
  eyepiece.** Concentrated, focused sunlight at the eyepiece end of a telescope can crack or
  burn through an eyepiece-mounted filter almost instantly, sending unfiltered sunlight
  straight into the eye. The AAS (American Astronomical Society) explicitly states eyepiece
  solar filters should be discarded/avoided. Source: [AAS: Solar Filters for Optics](https://eclipse.aas.org/eye-safety/optics-filters).
- **Never look at the Sun through any camera lens, binoculars, or telescope without a
  certified filter secured over the front of the optics** — this instantly causes severe eye
  injury, and wearing eclipse glasses while looking through an unfiltered instrument does
  **not** make it safe, because the instrument's own light-gathering power overwhelms the
  glasses' filtering. Source: [NASA Science: Eclipse Viewing Safety](https://science.nasa.gov/eclipses/safety/), [AAS Chou Solar Eclipse Eye Safety PDF](https://eclipse.aas.org/sites/eclipse.aas.org/files/AAS-Chou-Solar-Eclipse-Eye-Safety.pdf).
- **Certification standard**: safe filters and viewers should be compliant with **ISO
  12312-2**, the international safety standard adopted in 2015; filters/viewers meeting it
  may be used to look at the Sun for as long as desired. Source: [AAS: Suppliers of Safe Solar Viewers & Filters](https://eclipse.aas.org/eye-safety/viewers-filters).
- **Eyepiece projection** (projecting a solar image onto a card or screen rather than
  viewing directly) is a legitimate technique but requires care that nobody looks into the
  eyepiece and nobody stands in the path of the projected beam; enclosed projection systems
  (e.g., a "Sun Funnel") reduce this risk versus an open card. Source: [AAS Chou PDF](https://eclipse.aas.org/sites/eclipse.aas.org/files/AAS-Chou-Solar-Eclipse-Eye-Safety.pdf).
- This research pass did **not** identify specific certified solar-filter product models
  (e.g., a Baader AstroSolar or Thousand Oaks part number) with 2026-dated manufacturer
  sourcing — if the app will recommend a specific filter product, that needs its own
  sourced follow-up rather than reusing the general safety citations above.

---

## What to buy at each budget level

Tiers, not invented prices — see `gear.json` and the tables above for the specific sourced
figures behind each tier label.

- **Entry / "try it first" tier (smart telescope, budget)**: DWARF mini or DWARF 3, or a
  Seestar S30 — all in the roughly $400-$550 tier per manufacturer pricing found above, with
  the DWARF 3 specifically called out by 2026 buying guides as the direct replacement for the
  now-discontinued Seestar S50. Everything is phone-app-driven; no separate mount, camera, or
  guiding knowledge required.
- **Entry / manual tracker tier**: a Move Shoot Move tracker ($209) or Sky-Watcher Star
  Adventurer 2i (~$585) with a camera/lens already owned, for wide-field Milky Way and
  large-nebula work — cheaper than any smart telescope but requires manual polar alignment,
  framing, and stacking knowledge the app would need to teach.
- **Mid tier (smart telescope, higher-spec)**: Seestar S50 Pro ($999-$1,098) or Vaonis
  Vespera II (from EUR 1,590) — larger sensors, dual-band filtering, and (on the S50 Pro)
  a genuine EQ mode with 60 s subs.
- **Mid tier (manual imaging rig)**: a RedCat 51/61 or Askar FRA400-class refractor
  ($~mid, exact price not sourced in this pass) on a ZWO AM3/AM5 or Sky-Watcher HEQ5-class
  mount, with a ZWO ASI533MC Pro or ASI2600MC Pro camera and an ASIAIR Plus or StellarMate
  controller — the "graduate from a smart telescope" path that unlocks real guiding, longer
  subs, and narrowband imaging.
- **Premium tier**: Unistellar Odyssey/eQuinox 2 ($2,499-$3,999) or Vaonis Vespera Pro
  ($2,799) at the smart-telescope end; an EQ6-R Pro-class mount with a premium APO refractor
  and cooled camera at the manual end.
- **iPhone-first tier**: any smart telescope above (the phone is the controller/viewer, the
  telescope does the imaging) plus, optionally, a Celestron NexYZ adapter on a conventional
  eyepiece scope for Moon/planet afocal lucky-imaging video — no separate astro camera
  needed for that specific use case.

---

## Uncertain values and gaps to close in a follow-up pass

- **Seestar S50/S30 (non-Pro)**: pixel size and field of view not found on manufacturer
  pages as fetched — likely published only in a spec-sheet PDF or third-party teardown, not
  the marketing page.
- **Seestar S30/S50 alt-az max exposure**: sourced from a How-To article and a Facebook
  group post, not a ZWO spec sheet; treat the "10 s" alt-az figure as approximate.
  **Seestar S30 Pro max sub-exposure**: not found at all.
- **Vaonis Vespera II / Pro / Stellina**: mount type (EQ mode support), built-in filters,
  and max sub-exposure were not stated on the pages fetched. Vaonis announced a "Vespera III"
  and "Vespera Pro 2" in an August 2026 press cycle; this pass did not capture their detailed
  specs.
- **Unistellar eQuinox 2 / Odyssey**: sensor pixel size, weight (eQuinox 2), and built-in
  filters not found; eQuinox 2 sourced partly from a retail (Amazon) listing rather than
  unistellar.com directly, since the manufacturer page fetch for Odyssey did not surface
  eQuinox 2 details.
- **Star tracker "typical max unguided exposure by focal length"**: no sourced table found
  for any of the five trackers covered; this is a derived (NPF-rule-based) figure the app
  should compute itself rather than one that can be honestly cited to a single source.
  Tracking-accuracy arcsecond figures for the Star Adventurer 2i and SkyGuider Pro were also
  not found.
- **iOptron CEM26 price**: tier only, no dollar figure found in sources reviewed.
- **StellarMate Pro price**: not found in sources reviewed.
- **Guiding-specific gear** (guide scopes, guide cameras, off-axis guiders): not covered in
  depth in this pass — flagged in §3 as a gap if the app needs guide-scope FOV math.
  specific certified solar filter products: general safety sourced from AAS/NASA; no
  specific 2026 product models were sourced for a recommendation list.
- All `null` fields above are mirrored in `gear.json` per row, with a `notes` field
  explaining why the value could not be sourced rather than estimated.
