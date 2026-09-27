# Gear reference: iPhone, full-frame, APS-C and lenses for night-sky photography

Compiled 2026-09-27 from the nine research files in `docs/gear/research/`
and the owner's own measurements (`docs/ios/CAPTURE-LIMITS.md`). The
machine-readable version is `config/gear-presets.json` (ADR-0012), which the
app's exposure tools load as editable presets. This page is the readable
companion: what each camera and lens is, what the numbers mean for the
night sky, and how to use an iPhone for it.

## How to read this

- **Every table row links its source.** "sensor" and "lens" links on the
  iPhone rows point to where the sensor and optics numbers came from; body
  and lens rows link the spec page. Coma notes link the named review.
- **Bases are labelled.** A number is *measured* (EXIF of a real frame on the
  owner's iPhone 18 Pro Max), *stated* (printed by the maker or a spec sheet
  such as GSMArena's), or *derived* (computed here, with the method named).
  Apple publishes no sensor sizes, pixel pitches or real focal lengths, so
  most iPhone optics numbers are derived; see
  [Pixel pitch and sensor size](#pixel-pitch-and-sensor-size-on-iphones).
- **NPF** is the longest untracked exposure before stars trail, from the
  complete rule SkyCore uses (F. Michaud, Société Astronomique du Havre):
  `t = k · (16.856·N + 0.0997·f + 13.713·p) / (f · cos δ)`, with N the
  f-number, f the real focal length in mm, p the pixel pitch in µm, δ the
  declination. Every NPF here is the strict case: k = 1 (stars stay round),
  δ = 0° (the celestial equator, worst case), wide open. Aim at higher
  declinations and the limit grows by 1/cos δ.
- **"Popular" is always cited.** No row is called the best overall unless a
  named, dated source says so, and then the source is quoted.
- **Uncertain values** are collected, dated, in the
  [appendix](#appendix-b-uncertain-values-2026-09-27). Rows left out of the
  presets are in [appendix A](#appendix-a-rows-left-out-of-the-presets) with
  the reason.

## iPhone and iPad

### The hard limits of an iPhone (measured, not marketing)

On the owner's iPhone 18 Pro Max (iOS 27.2), a third-party app can get
([CAPTURE-LIMITS.md](../ios/CAPTURE-LIMITS.md)):

- **1.0 s per frame, at most**, on every format of every back camera. No app,
  this one included, can hold the shutter open longer.
- **ProRAW only.** No Bayer RAW is offered on any format. ProRAW is Apple's
  demosaiced, scene-referred DNG: demosaicing is locked in, Deep Fusion noise
  reduction can only be avoided at capture time (the app asks for `.speed`),
  and local tone mapping rides along as metadata an editor can switch off
  ([Lux, Understanding ProRAW](https://www.lux.camera/understanding-proraw/)).
- **No Night mode API.** The Camera app's 10–30 s Night mode is Apple's own
  multi-frame pipeline; Apple does not expose it to apps, and Lux (Halide)
  has asked for one publicly
  ([Halide on X](https://x.com/halidecamera/status/1527728518582239232)).
  The "up to 30 s on a tripod" figure is community-documented; Apple's own
  page only says the Max setting "extends the capture time"
  ([Apple](https://support.apple.com/en-us/102519)).
- Main camera ISO 55–12,320 at the 12 MP astro format, apertures f/1.48, 1.8,
  2.8 and 4.0; ultra wide ISO 15–3,600 at f/2.2; telephoto ISO 15–7,680 at
  f/2.8. Low-light boost is not supported on any of them.

So on an iPhone the limit is never star trailing inside one frame: every
NPF below is 4–29 times longer than the 1 s the phone allows. Long exposures
are sequences of 1 s frames, stacked.

### Per generation

Each row is one camera module. The **12 MP** column is what this app
captures (4032 × 3024, the only format with ProRAW and the full ISO range on
the 18 Pro Max); 48 MP quad-Bayer sensors also show their native pitch and
the shorter 48 MP NPF. "Real focal" is the physical focal length:
**EXIF** from a real photo, **derived** as 35 mm-equivalent ÷ crop factor,
or **FOV-derived** from the measured field of view.

| Model | Camera | f/ | Equiv. | Real focal | Pitch µm, 12 MP / 48 MP | Sensor (mm) | ProRAW | NPF 12 MP (48 MP) | Source |
|---|---|---|---|---|---|---|---|---|---|
| iPhone 13 Pro Max / 13 Pro | main | 1.5 | 26 mm | 5.75 mm (derived) | 1.90 (stated) / n/a | 7.66 × 5.75 | yes | 9.0 s | [sensor](https://www.gsmarena.com/apple_iphone_13_pro_max-11089.php) · [lens](https://support.apple.com/en-us/111870) |
| iPhone 13 Pro Max / 13 Pro | ultra-wide | 1.8 | 13 mm | 1.51 mm (derived) | 1.00 (stated) / n/a | 4.03 × 3.02 | yes | 29.3 s | [sensor](https://www.gsmarena.com/apple_iphone_13_pro_max-11089.php) · [lens](https://support.apple.com/en-us/111870) |
| iPhone 13 Pro Max / 13 Pro | telephoto | 2.8 | 77 mm | 8.97 mm (derived) | 1.00 (stated) / n/a | 4.03 × 3.02 | yes | 6.9 s | [sensor](https://www.gsmarena.com/apple_iphone_13_pro_max-11089.php) · [lens](https://support.apple.com/en-us/111870) |
| iPhone 14 Pro Max / 14 Pro | main | 1.78 | 24 mm | 6.82 mm (derived) | 2.44 (stated) / 1.22 | 9.84 × 7.38 | yes | 9.4 s (7.0 s) | [sensor](https://www.gsmarena.com/apple_iphone_14_pro-review-2480p6.php) · [lens](https://support.apple.com/en-us/111846) |
| iPhone 14 Pro Max / 14 Pro | ultra-wide | 2.2 | 13 mm | 2.12 mm (derived) | 1.40 (stated) / n/a | 5.64 × 4.23 | yes | 26.6 s | [sensor](https://www.gsmarena.com/apple_iphone_14_pro-review-2480p6.php) · [lens](https://support.apple.com/en-us/111846) |
| iPhone 14 / 14 Plus | main | 1.5 | 26 mm | 5.75 mm (derived) | 1.90 (stated) / n/a | 7.66 × 5.75 | no | 9.0 s | [sensor](https://www.gsmarena.com/apple_iphone_14-review-2481p5.php) · [lens](https://support.apple.com/en-us/111850) |
| iPhone 15 / 15 Plus | main | 1.6 | 26 mm | 6.06 mm (derived) | 2.00 (2× stated 48 MP) / 1.00 | 8.06 × 6.05 | no | 9.1 s (6.8 s) | [sensor](https://www.gsmarena.com/apple_iphone_15-review-2619p5.php) · [lens](https://support.apple.com/en-us/111831) |
| iPhone 16 Pro Max / 16 Pro | main | 1.78 | 24 mm | 6.8 mm (EXIF) | 2.44 (stated) / 1.22 | 9.84 × 7.38 | yes | 9.4 s (7.0 s) | [sensor](https://www.gsmarena.com/apple_iphone_16_pro_max-review-2750p5.php) · [lens](https://tidbits.com/2025/09/25/tracking-my-iphone-camera-usage-with-a-deep-dive-into-exif-data/) |
| iPhone 16 Pro Max / 16 Pro | ultra-wide | 2.2 | 13 mm | 2.2 mm (EXIF) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | yes | 25.7 s (21.3 s) | [sensor](https://www.gsmarena.com/apple_iphone_16_pro_max-review-2750p5.php) · [lens](https://tidbits.com/2025/09/25/tracking-my-iphone-camera-usage-with-a-deep-dive-into-exif-data/) |
| iPhone 16 Pro Max / 16 Pro | telephoto | 2.8 | 120 mm | 15.7 mm (EXIF) | 1.12 (stated) / n/a | 4.52 × 3.39 | yes | 4.1 s | [sensor](https://www.gsmarena.com/apple_iphone_16_pro_max-review-2750p5.php) · [lens](https://tidbits.com/2025/09/25/tracking-my-iphone-camera-usage-with-a-deep-dive-into-exif-data/) |
| iPhone 16 / 16 Plus | main | 1.6 | 26 mm | 6.06 mm (derived) | 2.00 (2× stated 48 MP) / 1.00 | 8.06 × 6.05 | no | 9.1 s (6.8 s) | [sensor](https://www.gsmarena.com/apple_iphone_16-review-2749p5.php) · [lens](https://support.apple.com/en-us/121029) |
| iPhone 16e | main | 1.6 | 26 mm | 4.24 mm (derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | no | 11.0 s (8.7 s) | [sensor](https://www.gsmarena.com/apple_iphone_16e-review-2805p5.php) |
| iPhone 17 Pro Max / 17 Pro | main | 1.78 | 24 mm | 6.82 mm (derived) | 2.44 (stated) / 1.22 | 9.84 × 7.38 | yes | 9.4 s (7.0 s) | [sensor](https://www.gsmarena.com/apple_iphone_17_pro_max-review-2884p6.php) |
| iPhone 17 Pro Max / 17 Pro | ultra-wide | 2.2 | 13 mm | 2.12 mm (derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | yes | 26.6 s (22.1 s) | [sensor](https://www.gsmarena.com/apple_iphone_17_pro_max-review-2884p6.php) |
| iPhone 17 Pro Max / 17 Pro | telephoto | 2.8 | 100 mm | 16.31 mm (derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | yes | 4.2 s (3.6 s) | [sensor](https://www.gsmarena.com/apple_iphone_17_pro_max-review-2884p6.php) |
| iPhone 17 | main | 1.6 | 26 mm | 6.06 mm (derived) | 2.00 (2× stated 48 MP) / 1.00 | 8.06 × 6.05 | no | 9.1 s (6.8 s) | [sensor](https://www.gsmarena.com/apple_iphone_17-review-2886p6.php) · [lens](https://support.apple.com/en-us/125089) |
| iPhone 17 | ultra-wide | 2.2 | 13 mm | 2.12 mm (derived) | 1.40 (2× stated 48 MP) / 0.70 | 5.64 × 4.23 | no | 26.6 s (22.1 s) | [sensor](https://www.gsmarena.com/apple_iphone_17-review-2886p6.php) · [lens](https://support.apple.com/en-us/125089) |
| iPhone Air | main | 1.6 | 26 mm | 6.06 mm (derived) | 2.00 (2× stated 48 MP) / 1.00 | 8.06 × 6.05 | no | 9.1 s (6.8 s) | [sensor](https://www.gsmarena.com/apple_iphone_air-review-2885p6.php) |
| iPhone 17e | main | 1.6 | 26 mm | 4.24 mm (derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | no | 11.0 s (8.7 s) | [sensor](https://www.gsmarena.com/apple_iphone_17e-review-2945p5.php) |
| iPhone 18 Pro Max / 18 Pro | main | 1.48 | 24 mm | 6.93 mm (EXIF) | 2.48 (EXIF) / 1.22 | 10.00 × 7.50 | yes | 8.6 s (6.1 s) | [sensor](../ios/CAPTURE-LIMITS.md) |
| iPhone 18 Pro Max / 18 Pro | ultra-wide | 2.2 | 13 mm | 2.22 mm (FOV-derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | yes | 25.5 s (21.1 s) | [sensor](https://www.gsmarena.com/apple_iphone_18_pro_max-review-3002p5.php) · [lens](https://support.apple.com/en-us/148591) |
| iPhone 18 Pro Max / 18 Pro | telephoto | 2.8 | 100 mm | 16.31 mm (derived) | 1.40 (stated) / 0.70 | 5.64 × 4.23 | yes | 4.2 s (3.6 s) | [sensor](https://www.gsmarena.com/apple_iphone_18_pro_max-review-3002p5.php) · [lens](https://support.apple.com/en-us/148591) |

Not in the presets (details in [appendix A](#appendix-a-rows-left-out-of-the-presets)):
iPhone 13 and 13 mini (no sourced focal length), the 14 Pro Max telephoto (no
sensor data), the 15 Pro / Pro Max (no sensor rows in the research), and both
current iPads.

**ProRAW is Pro-only** in every generation checked; the standard, Plus, Air
and "e" models save HEIC/JPEG, a real ceiling for stacking
([Apple ProRAW support list](https://support.apple.com/en-us/119916)).

**Sensor tiers matter as much as apertures.** GSMArena identifies three main
sensors: the Pro line's 1/1.28" (IMX903/905), the standard 16/17/Air's
smaller 1/1.56" IMX904, and the 16e/17e's 1/2.55", the same class the Pro
models use for their ultra wide
([GSMArena, iPhone 17 review](https://www.gsmarena.com/apple_iphone_17-review-2886p6.php);
[16e review](https://www.gsmarena.com/apple_iphone_16e-review-2805p5.php)).
GSMArena's own comparison: "in low-light conditions, the larger sensor on
the iPhone 16 yields more detailed and less noisy footage" than the 16e.

### Which camera for astro

- **Main camera, wide open.** It has the largest sensor, the most light and,
  on the 18 Pro Max, the only variable aperture and the highest ISO ceiling
  (12,320 vs 3,600 and 7,680). Use it for the Milky Way and star fields.
- **Ultra wide** for wide star-trail frames and Milky Way arches, where the
  field matters more than light per pixel. On the 18 Pro Max it covers
  103.6° measured (Apple markets 120°) and stops at ISO 3,600.
- **Telephoto** for the Moon. Its NPF is the shortest (about 4 s) and its
  sensor the smallest; on 2025 hardware Tom's Guide did image the Orion
  Nebula and Pleiades with the 16 Pro Max's 5x
  ([Tom's Guide, via iphone.md](research/iphone.md#5-most-popular--evidence-dated-20252026)),
  so deep-sky targets are possible but not its strength.

### NPF, with the arithmetic

`t = (16.856·N + 0.0997·f + 13.713·p) / f`, k = 1, δ = 0°.

| Lens | N | f (mm) | p (µm) | 16.856·N | 0.0997·f | 13.713·p | Sum | t |
|---|---|---|---|---|---|---|---|---|
| 18 Pro Max main, 12 MP | 1.48 | 6.93 | 2.48 | 24.95 | 0.69 | 34.01 | 59.65 | **8.6 s** |
| 18 Pro Max main, 48 MP | 1.48 | 6.93 | 1.22 | 24.95 | 0.69 | 16.73 | 42.37 | **6.1 s** |
| 18 Pro Max main at f/4.0, 12 MP | 4.0 | 6.93 | 2.48 | 67.42 | 0.69 | 34.01 | 102.12 | **14.7 s** |
| 18 Pro Max ultra wide, 12 MP | 2.2 | 2.22 | 1.40 | 37.08 | 0.22 | 19.20 | 56.50 | **25.5 s** |
| 16 Pro Max 5x telephoto | 2.8 | 15.7 | 1.12 | 47.20 | 1.57 | 15.36 | 64.12 | **4.1 s** |

The 8.6 s for the 18 Pro Max main camera is the figure recorded in
CAPTURE-LIMITS.md from a real frame's EXIF (6.93 mm, crop 3.46, 2.48 µm), and
a SkyCore test holds the preset to it. Stopping down lengthens NPF because
the rule counts the lens's own blur (the Airy disc grows with N), but it
costs light; on an iPhone, where the frame is capped at 1 s anyway, shoot
wide open.

### Pixel pitch and sensor size on iPhones

Apple publishes neither. The research converted GSMArena's optical-format
strings (1/1.28", 1/1.56" and so on) to millimetres with a rule-of-thumb
table. Six rows then disagreed with their own stated pitch by more than 5 %
(the 13 Pro Max ultra wide and telephoto, the 16 Pro Max telephoto, and the
16, 17 and Air main cameras; for example 1.0 µm stated vs 0.856 µm from
6.9 mm ÷ 8064 px). The presets resolve this in favour of the pitch:

1. **Measured beats stated beats derived.** The 18 Pro Max main camera uses
   the 2.48 µm from its EXIF (GSMArena says 2.44 µm binned).
2. **Sensor millimetres = pitch × pixels.** It is the only sensor size
   consistent with the EXIF focal lengths we have: pitch-implied sensors
   reproduce TidBITS' iPhone 16 Pro EXIF values within 4 % (6.82 vs 6.8 mm
   main, 2.12 vs 2.2 mm ultra wide, 15.67 vs 15.7 mm telephoto), and the 18
   Pro Max's EXIF crop of 3.46 exactly. The optical-format conversion missed
   the 16 Pro Max telephoto by 9 %.
3. The optical-format figures are kept in the JSON as
   `optical_format_estimate_mm`, labelled `optical-format estimate`, so
   nothing was dropped.
4. **12 MP is the reference resolution**, because it is what this app
   captures and what Night mode delivers by default. A 48 MP ProRAW has half
   the pitch and about 70 % of the NPF; both are far above 1 s.

### How to shoot the night sky with an iPhone

**Tripod, always.** Apple's own Night mode guide recommends "a solid and
secure surface, or a tripod" ([Apple](https://support.apple.com/en-us/102519)).
Use a 3–10 s timer, or the app's countdown, so touching the screen does not
shake the first frame.

**Three routes, and what each gives you:**

| Route | Longest effective exposure | Output | Good for | Limits |
|---|---|---|---|---|
| Camera app, Night mode (Max) | 10 s handheld; up to ~30 s on a tripod (community-documented) | One processed HEIC or ProRAW | A quick single shot with nothing installed | Apple's multi-frame pipeline; no frames to stack, no control of the fusion ([Apple](https://support.apple.com/en-us/102519); [Halide](https://twitter.com/halidecamera/status/1789291307048845808)) |
| Manual RAW app (Halide, ProCamera, Lumina, Moment) | 1 s per frame (the platform ceiling) | Single ProRAW or RAW | Full control, focus peaking, a clean single frame | One frame is too short for the Milky Way; Halide's Process Zero does not work with Night mode ([Lux](https://www.lux.camera/mark-iii-looks/); [iosapps.md](research/iosapps.md#1-capture-apps)) |
| Stacking app (this app; NightCap; ProCamera Low Light Plus) | Unlimited in total: many 1 s frames | A stack, plus every frame (this app) | Milky Way, star fields, star trails | Stacking method mostly undocumented in other apps; NightCap saves JPEG/TIFF, not RAW ([NightCap](https://www.nightcapcamera.com/nightcap-camera/)) |

**This app's capture mode** (ADR-0011, CAPTURE-LIMITS.md): 1 s ProRAW frames
on the main camera at f/1.48, fixed ISO, zero-shutter-lag off and each
frame's sensor timestamp checked, every frame kept. Frames are registered on
stars and combined by a sigma-clipped mean (which also drops satellites and
aircraft); star trails use the per-pixel maximum with the interval equal to
the exposure, so trails have no gaps. On the phone a 5-frame 12 MP stack took
2.8 s; a 20-frame synthetic bench spent 6.8 s in the sigma-clip step.

**Focus.** There is no infinity setting. The lens position runs 0–1 and
Apple says 1 is the far end, not infinity; a developer thread found infinity
near 0.81–0.84 on an iPhone 13, drifting with temperature
([Apple Developer Forums](https://developer.apple.com/forums/thread/706755)).
Focus on a bright star with a magnifier and read the half-flux radius (the
app's focus screen does this), then lock and re-check if the night cools a
lot.

**ProRAW caveats.** Keep `.speed` quality prioritization (the app does) so
Deep Fusion does not fuse frames behind your back. In an editor, turning off
the ProRAW tone-map gain layer gives a flatter file. Expect cleaner but less
detailed files than a Bayer RAW would give.

**Battery, heat, storage.** Cold roughly halves battery life per ~10 °C drop
(rule of thumb, not an iPhone measurement); carry a power bank. ProRAW frames
are 25–28 MB each, so a 10-minute sequence is about 16 GB. No app surveyed
documents thermal behaviour over long runs
([iosapps.md §4](research/iosapps.md#thermal-throttling-during-long-sequences)).

### iPad

The current iPad Pro 13-inch (M5) and iPad Air 11-inch (M4) share one rear
camera spec, word for word: "12MP Wide camera, ƒ/1.8 aperture, Five-element
lens" ([iPad Pro](https://support.apple.com/en-us/125407);
[iPad Air](https://support.apple.com/en-us/126471)). No stills RAW, no Night
mode, no optical stabilization, no published sensor size or focal length.
The iPad Pro's ProRes RAW is a video codec. Neither is an astro camera, so
neither is a preset.

## Clip-on lenses: the honest verdict

A clip-on sits in front of the phone's own lens. It cannot widen the
aperture or enlarge the sensor, which are what gather light for stars.

- **None of the brands checked publish an f-number:** Moment (18, 58 mm tele,
  fisheye, T-Series), ShiftCam (up to 350 mm-equivalent SuperZoom) or Sandmarc
  ([ShiftCam on PetaPixel, 2026-08-27](https://petapixel.com/2026/08/27/shiftcams-new-lenses-deliver-350mm-equivalent-focal-length-on-iphone/);
  [Sandmarc guide](https://www.sandmarc.com/blogs/iphone-photography/astrophotography-guide-how-to-photograph-the-stars-with-your-iphone)).
  PetaPixel's review of Moment's T-Series II (2026-08-24, cited in
  [iphone.md §3](research/iphone.md#3-clip-on-lens-systems-for-iphone-moment-shiftcam-sandmarc)):
  "Aperture is fixed."
- **Useful for the Moon, not the Milky Way.** Reviews of the Moment Tele 58 mm
  say it suits "close-ups and detail of objects such as the moon" but "won't
  provide enough performance to be seeing far-off planets or galaxies"
  ([research/iphone.md §3](research/iphone.md#3-clip-on-lens-systems-for-iphone-moment-shiftcam-sandmarc)).
  On a Pro iPhone the built-in telephoto already does that with no extra
  glass.
- **Open question:** a large-objective tele add-on could in principle gather
  more light before the phone's aperture, but no brand publishes the
  entrance-pupil data needed to check. Beastgrip was not researched.

Verdict: shoot the night sky with the main camera, unclipped. The clip-ons
are not in the presets because they have no f-number to compute with.

## Full-frame bodies

Included when a dated 2025–2026 astro buying guide names the body, or it is
the current successor of one that is
([Capture the Atlas 2026](https://capturetheatlas.com/best-camera-milky-way-photography/),
[PetaPixel 2026](https://petapixel.com/best-astrophotography-cameras/),
[Digital Camera World 2026](https://www.digitalcameraworld.com/buying-guides/best-camera-for-astrophotography)).
Pitch is sensor width ÷ image width. The NPF column puts every body behind
the same 20 mm f/1.8 lens, so the only difference is the pixel pitch.

| Camera | Mount | Sensor (mm) | Resolution | Pitch (µm) | Native ISO | Launch / status | NPF, 20 mm f/1.8 | Notes | Source |
|---|---|---|---|---|---|---|---|---|---|
| Sony a7 IV (ILCE-7M4) | Sony E | 35.6 × 23.9 | 7008×4672 (32.7 MP) | 5.08 | 100–51,200 native (ext. 50–204,800) | 2021, current | 5.1 s | Bulb timer and interval shooting built in. Star-eater filtering reduced since the a7 III generation; not Sony-confirmed gone. | [source](https://www.dpreview.com/products/sony/slrs/sony_a7iv/specifications) |
| Sony a7 III (ILCE-7M3) | Sony E | 35.8 × 23.8 | 6000×4000 (24.0 MP) | 5.97 | 100–51,200 native (ext. 50–204,800) | 2018, discontinued | 5.7 s | Used favourite. Sony visibly reduced star-eater on this body (PetaPixel 2018). Interval shooting arrived in firmware 3.0. | [source](https://www.dpreview.com/products/sony/slrs/sony_a7iii/specifications) |
| Sony a7S III (ILCE-7SM3) | Sony E | 35.6 × 23.8 | 4240×2832 (12.0 MP) | 8.40 | 80–102,400 native (ext. 40–409,600) | 2020, current | 7.4 s | 12 MP with 8.4 µm pixels: high-ISO cleanliness over resolution. Dual gain near ISO 2000 (DPReview measurement). | [source](https://www.dpreview.com/products/sony/slrs/sony_a7siii/specifications) |
| Sony a7R V (ILCE-7RM5) | Sony E | 35.7 × 23.8 | 9504×6336 (60.2 MP) | 3.76 | 100–32,000 native (ext. 50–102,400) | 2022, current | 4.2 s | 60 MP: shortest NPF of these bodies at a given lens. Community reports reduced raw filtering. | [source](https://www.dpreview.com/products/sony/slrs/sony_a7rv/specifications) |
| Sony a7C II (ILCE-7CM2) | Sony E | 35.6 × 23.9 | 7008×4672 (32.7 MP) | 5.08 | 100–51,200 native (ext. 50–204,800) | 2023, current | 5.1 s | a7 IV sensor in a compact body. | [source](https://www.dpreview.com/products/sony/slrs/sony_a7cii/specifications) |
| Sony a1 II (ILCE-1M2) | Sony E | 35.9 × 24 | 8640×5760 (49.8 MP) | 4.16 | 100–32,000 native (ext. 50–102,400) | 2024, current | 4.5 s | Flagship all-rounder; astro-capable, not astro-optimised. | [source](https://www.dpreview.com/products/sony/slrs/sony_a1ii/specifications) |
| Nikon Z6 III | Nikon Z | 35.9 × 23.9 | 6048×4032 (24.4 MP) | 5.94 | 100–64,000 native (ext. 50–204,800) | 2024, current | 5.7 s | Starlight View and AF to -10 EV; base-ISO dynamic range ~0.8 EV below the Z6 II (independent review). | [source](https://www.dpreview.com/products/nikon/slrs/nikon_z6iii/specifications) |
| Nikon Z6 II | Nikon Z | 35.9 × 23.9 | 6048×4024 (24.3 MP) | 5.94 | 100–51,200 native (ext. 50–204,800) | 2020, discontinued | 5.7 s | PetaPixel's 2026 nightscape pick; ISO-invariant, low read noise. | [source](https://www.dpreview.com/products/nikon/slrs/nikon_z6ii/specifications) |
| Nikon Z8 | Nikon Z | 35.9 × 23.9 | 8256×5504 (45.4 MP) | 4.35 | 64–25,600 native | 2023, current | 4.6 s | 45.7 MP stacked sensor; intervalometer works with long shutter speeds. Extended ISO unpublished. | [source](https://www.dpreview.com/products/nikon/slrs/nikon_z8/specifications) |
| Nikon Z f | Nikon Z | 35.9 × 23.9 | 6048×4032 (24.4 MP) | 5.94 | 100–64,000 native (ext. 50–204,800) | 2023, current | 5.7 s | Same 24.5 MP generation as the Z6 III, retro body. | [source](https://www.dpreview.com/products/nikon/slrs/nikon_zf/specifications) |
| Nikon Z5 II | Nikon Z | 35.9 × 23.9 | 6048×4032 (24.4 MP) | 5.94 | 100–64,000 native (ext. 50–204,800) | 2025, current | 5.7 s | Budget full frame with Starlight View (Capture the Atlas 2026). | [source](https://www.dpreview.com/products/nikon/slrs/nikon_z5ii/specifications) |
| Nikon D850 | Nikon F | 35.9 × 23.9 | 8256×5504 (45.4 MP) | 4.35 | 64–25,600 native (ext. 32–102,400) | 2017, discontinued | 4.6 s | Used DSLR. Watch for Nikon lossy-raw ring artifacts in large stacks (markshelley.co.uk). | [source](https://www.dpreview.com/products/nikon/slrs/nikon_d850/specifications) |
| Nikon D750 | Nikon F | 35.9 × 24 | 6016×4016 (24.2 MP) | 5.97 | 100–12,800 native (ext. 50–51,200) | 2014, discontinued | 5.7 s | Used DSLR, often cited for ISO invariance. | [source](https://www.dpreview.com/products/nikon/slrs/nikon_d750/specifications) |
| Canon EOS R6 Mark II | Canon RF | 36 × 24 | 6000×4000 (24.0 MP) | 6.00 | 100–102,400 native (ext. 50–204,800) | 2022, current | 5.7 s | Canon's interval timer cannot run with Bulb: sequences past 30 s need an external intervalometer. | [source](https://www.dpreview.com/products/canon/slrs/canon_eosr6ii/specifications) |
| Canon EOS R6 Mark III | Canon RF | 35.9 × 23.9 | 6960×4640 (32.3 MP) | 5.16 | 100–64,000 native (ext. 50–102,800) | 2025, current | 5.2 s | Announced 2025-11-05; little astro field testing yet. IBIS rating and extended ISO unconfirmed. | [source](https://petapixel.com/2025/11/05/the-canon-r6-iii-is-a-hybrid-powerhouse-with-32-5mp-sensor/) |
| Canon EOS R8 | Canon RF | 36 × 24 | 6000×4000 (24.0 MP) | 6.00 | 100–102,400 native | 2023, current | 5.7 s | Budget full frame, no IBIS (irrelevant on a tripod). Max mechanical shutter 1/4000 s. | [source](https://www.dpreview.com/products/canon/slrs/canon_eosr8/specifications) |
| Canon EOS R5 Mark II | Canon RF | 36 × 24 | 8192×5464 (44.8 MP) | 4.39 | 100–51,200 native (ext. 50–102,400) | 2024, current | 4.6 s | High-resolution all-rounder, not an astro specialist. | [source](https://www.dpreview.com/products/canon/slrs/canon_eosr5ii/specifications) |
| Canon EOS R | Canon RF | 36 × 24 | 6720×4480 (30.1 MP) | 5.36 | 100–40,000 native | 2018, discontinued | 5.3 s | Donor body of the EOS Ra; discontinued. | [source](https://www.dpreview.com/products/canon/slrs/canon_eosr/specifications) |
| Canon EOS Ra | Canon RF | 36 × 24 | 6720×4480 (30.1 MP) | 5.36 | 100–40,000 native | 2019, discontinued | 5.3 s | Astro model: ~4x H-alpha transmission, 30x live-view zoom. Discontinued September 2021, no successor. | [source](https://www.canon.co.uk/cameras/eos-ra/) |
| Panasonic Lumix S5 II (and S5 IIX, stills-identical variant) | L-Mount | 35.6 × 23.8 | 6000×4000 (24.0 MP) | 5.93 | 100–51,200 native (ext. ?–204,800) | 2023, current | 5.7 s | Panasonic states Dual Native ISO. S5 IIX is stills-identical. Bulb/interval behaviour unconfirmed. | [source](https://www.dpreview.com/products/panasonic/slrs/panasonic_dcs5ii/specifications) |

What the named sources actually say, since "best" is theirs, not ours:
Capture the Atlas calls the a7 IV "best overall value", the a7 III "best
quality-price", the a7R V "best high-resolution nightscape camera" and the
Z5 II "best budget full-frame"; PetaPixel calls the Z6/Z6 II "best overall
for nightscape"
([fullframe.md](research/fullframe.md#notes-per-camera)).

**Brand quirks worth knowing:**

- *Sony star eater:* a raw spatial filter on multi-second exposures that
  erodes faint stars. Documented in 2016–2017 on the Mark II generation,
  much reduced from the a7 III on
  ([Lonely Speck](https://www.lonelyspeck.com/sony-star-eater-and-how-to-fix-it/);
  [PetaPixel 2018](https://petapixel.com/2018/06/08/sonys-star-eater-problem-has-been-defeated-in-the-a7-iii/)).
  No newer Sony body has a dated, body-specific test in the research.
- *Nikon lossy raw:* can leave faint concentric rings in large stacks; shoot
  lossless raw for stacking
  ([markshelley.co.uk](https://www.markshelley.co.uk/Astronomy/NikonConcentricRings/nikon_lossy_compression.html)).
- *Canon interval timer:* cannot run with Bulb, so sequences of frames longer
  than 30 s need an external intervalometer.
- *Long-exposure noise reduction* shoots an in-camera dark frame after every
  exposure, halving shooting time. Most astrophotographers turn it off and
  stack, or shoot their own darks.
- Read noise and dual-gain switch points differ per body; the best public
  source is [photonstophotos.net](https://www.photonstophotos.net/Charts/RN_e.htm).

## APS-C and Micro Four Thirds bodies

Same criteria, from the APS-C research
([PhotoPills 2026](https://www.photopills.com/articles/best-camera-for-milky-way-photography),
[Capture the Atlas 2026](https://capturetheatlas.com/best-camera-milky-way-photography/),
[Live Science 2026](https://www.livescience.com/technology/best-beginner-cameras-for-astrophotography)).
Canon APS-C is 22.3 × 14.9 mm (1.61×); Sony, Fujifilm and Nikon are about
23.5 × 15.6 mm (1.53×); MFT is 17.3 × 13 mm (2.0×). NPF column: a 16 mm f/1.4
lens (12 mm f/1.4 on MFT, a similar field of view).

| Camera | Mount | Sensor (mm) | Resolution | Pitch (µm) | Native ISO | Launch / status | NPF, 16 mm f/1.4 (MFT: 12 mm f/1.4) | Notes | Source |
|---|---|---|---|---|---|---|---|---|---|
| Fujifilm X-T5 | Fujifilm X | 23.5 × 15.6 | 7728×5152 (39.8 MP) | 3.04 | 125-12800 standard (64-51200 extended) | 2022, current | 4.2 s | 40 MP X-Trans 5 HR, IBIS, built-in intervalometer. No star-eater reports found. | [source](https://www.fujifilm-x.com/en-us/products/cameras/x-t5/specifications/) |
| Fujifilm X-H2 | Fujifilm X | 23.5 × 15.6 | 7728×5152 (39.8 MP) | 3.04 | 125-12800 standard (64-51200 extended) | 2022, current | 4.2 s | Same 40 MP sensor as the X-T5. Pixel Shift is tripod-only and not for astro. | [source](https://www.fujifilm-x.com/en-us/products/cameras/x-h2/specifications/) |
| Fujifilm X-T50 | Fujifilm X | 23.5 × 15.6 | 7728×5152 (39.8 MP) | 3.04 | 125-12800 standard (64-51200 extended) | 2024, current | 4.2 s | X-T5 sensor in a smaller body with IBIS. | [source](https://amateurphotographer.com/latest/photo-news/fujifilm-announce-the-new-40mp-x-t50-with-ibis/) |
| Fujifilm X-S20 | Fujifilm X | 23.5 × 15.6 | 6240×4160 (26.0 MP) | 3.77 | 160-12800 standard (80-51200 extended) | 2023, current | 4.8 s | 26 MP X-Trans 4: larger pixels than the 40 MP bodies. | [source](https://www.fujifilm-x.com/global/products/cameras/x-s20/specifications/) |
| Fujifilm X-T30 III | Fujifilm X | 23.5 × 15.6 | 6240×4160 (26.0 MP) | 3.77 | 160-12800 standard (80-51200 extended) | 2025, current | 4.8 s | Announced 2025-10-23. Shutter range and intervalometer unconfirmed. | [source](https://www.fujifilm-x.com/en-us/news/introducing-fujifilm-x-t30-iii/) |
| Fujifilm X-T30 II | Fujifilm X | 23.5 × 15.6 | 6240×4160 (26.0 MP) | 3.77 | 160-12800 standard (80-51200 extended) | 2021, discontinued | 4.8 s | Discontinued; still common used. No IBIS. | [source](https://www.dpreview.com/products/fujifilm/slrs/fujifilm_xt30ii/) |
| Fujifilm X-M5 | Fujifilm X | 23.5 × 15.6 | 6240×4160 (26.0 MP) | 3.77 | 160-12800 standard (80-51200 extended) | 2024, current | 4.8 s | No IBIS. Shutter range and intervalometer unconfirmed. | [source](https://www.fujifilm-x.com/en-us/products/cameras/x-m5/) |
| Sony a6700 | Sony E | 23.5 × 15.6 | 6192×4128 (25.6 MP) | 3.80 | 100-32000 standard (50-102400 extended) | 2023, current | 4.8 s | IBIS. No dated report of star-eater on this body; community signal mixed and unverified. | [source](https://www.dpreview.com/products/sony/slrs/sony_a6700/specifications) |
| Sony a6400 | Sony E | 23.5 × 15.6 | 6000×4000 (24.0 MP) | 3.92 | 100-32000 standard (extended to 102400 with multi-frame NR) | 2019, current | 4.9 s | No IBIS. Older sensor generation; some community reports of long-exposure filtering. | [source](https://www.neocamera.com/camera/sony/a6400) |
| Sony a6100 | Sony E | 23.5 × 15.6 | 6000×4000 (24.0 MP) | 3.92 | 100-32000 standard (extended to 51200 with multi-frame NR) | 2019, discontinued | 4.9 s | Discontinued 2021; common used. No IBIS. | [source](https://petapixel.com/2021/12/23/sony-suspends-a7c-and-a6600-permanently-ends-a7-ii-and-a6100/) |
| Sony ZV-E10 II | Sony E | 23.5 × 15.6 | 6192×4128 (25.6 MP) | 3.80 | 100-32000 standard (50-102400 extended) | 2024, current | 4.8 s | Electronic shutter only, no IBIS. Vlogging-first. | [source](https://www.dpreview.com/reviews/8510905811/sony-zv-e10-ii-vlogging-camera-review/) |
| Canon EOS R7 | Canon RF | 22.3 × 14.9 | 6960×4640 (32.3 MP) | 3.20 | 100-32000 standard (expandable to 51200) | 2022, current | 4.3 s | 32.5 MP, IBIS, built-in intervalometer and bulb timer. Canon APS-C is 1.61x. | [source](https://www.canon-europe.com/cameras/eos-r7/specifications/) |
| Canon EOS R10 | Canon RF | 22.3 × 14.9 | 6000×4000 (24.0 MP) | 3.72 | 100-32000 standard (expandable to 51200) | 2022, current | 4.8 s | No IBIS. | [source](https://www.canon-europe.com/cameras/eos-r10/specifications/) |
| Canon EOS R50 | Canon RF | 22.3 × 14.9 | 6000×4000 (24.0 MP) | 3.72 | 100-32000 standard (expandable to 51200) | 2023, current | 4.8 s | No IBIS. Best-selling camera in Japan in 2026 (Digital Camera World). Shutter specs unconfirmed. | [source](https://www.canon.co.uk/cameras/eos-r50/specifications/) |
| Canon EOS 90D | Canon EF | 22.3 × 14.9 | 6960×4640 (32.3 MP) | 3.20 | 100-25600 standard (expandable to 51200) | 2019, discontinued | 4.3 s | DSLR, discontinued, no IBIS. EF mount body; also takes EF-S lenses. | [source](https://www.canon-europe.com/cameras/eos-90d/specifications/) |
| Nikon Z50II | Nikon Z | 23.5 × 15.7 | 5568×3712 (20.7 MP) | 4.22 | 100-51200 standard (expandable to 204800) | 2024, current | 5.2 s | 20.9 MP: the largest APS-C pixels here. No IBIS. | [source](https://www.nikonusa.com/p/z50ii/1784/overview) |
| Nikon Z fc | Nikon Z | 23.5 × 15.7 | 5568×3712 (20.7 MP) | 4.22 | 100-51200 standard (expandable to 204800) | 2021, current | 5.2 s | 20.9 MP, no IBIS. | [source](https://www.nikonusa.com/p/z-fc/1671/overview) |
| Nikon Z30 | Nikon Z | 23.5 × 15.7 | 5568×3712 (20.7 MP) | 4.22 | 100-51200 standard (expandable to 204800) | 2022, current | 5.2 s | No IBIS and no viewfinder, so star focus is on the rear screen. | [source](https://www.nikonusa.com/p/z-30/1737/overview) |
| Nikon D7500 | Nikon F | 23.5 × 15.7 | 5568×3712 (20.7 MP) | 4.22 | 100-51200 standard (expandable to ISO 50-1640000 with boost) | 2017, discontinued | 5.2 s | DSLR, discontinued; common used budget astro body. | [source](https://www.nikonusa.com/p/d7500/1581/overview) |
| OM System OM-1 Mark II (MFT) | Micro Four Thirds | 17.3 × 13 | 5184×3888 (20.2 MP) | 3.34 | ISO LOW (~80) to 102400 | 2024, current | 5.9 s | Starry Sky AF, Live Composite and Live Bulb for trails in camera. 8.5-stop IBIS. | [source](https://explore.omsystem.com/us/en/om-1-mark-ii) |
| Panasonic Lumix G9 II (MFT) | Micro Four Thirds | 17.3 × 13 | 5776×4336 (25.0 MP) | 3.00 | 100-25600 standard | 2023, current | 5.5 s | Dual native ISO, 8-stop IBIS. No Starry-Sky-AF equivalent confirmed. | [source](https://www.dpreview.com/reviews/panasonic-lumix-dc-g9-ii-review/) |

Full frame gathers about 2.3× the light of APS-C at the same f-number and
field of view, which is why guides still default to it: "full-frame is still
the safest choice in 2026 for cleaner high-ISO files" (Capture the Atlas,
quoted in [apsc.md](research/apsc.md#guidance-aps-c-vs-full-frame-for-astro)).
APS-C with a fast wide prime remains fully workable, and lens speed matters
more than the body.

## Lenses by format and mount

Focal length is the preset value: the prime's focal length, or a zoom's
wide end. The NPF column puts each lens on one reference body so the lenses
compare directly. Coma notes paraphrase the linked review; "not documented"
means unknown, not absent.

### Full-frame lenses (NPF on a Sony a7 IV, 5.08 µm)

| Lens | Focal (mm) | f/ | Mounts | AF | Infinity stop | NPF on Sony a7 IV (ILCE-7M4) | Coma / stars (review) | Tier | Source |
|---|---|---|---|---|---|---|---|---|---|
| Sigma 14mm F1.4 DG DN Art | 14 | 1.4 | Sony E, L-Mount | AF | no | 6.8 s | Reviewers report coma and astigmatism very well controlled even wide open at f/1.4, with well-defined star points to the corners; some reports of sample variation. [review](https://petapixel.com/2023/06/08/sigma-14mm-f-1-4-dg-dn-art-review-a-nocturnal-monster/) | premium | [source](https://www.sigmaphoto.com/14mm-f1-4-dg-dn-a) |
| Sigma 14-24mm F2.8 DG DN Art | 14–24 | 2.8 | Sony E, L-Mount | AF | not documented | 8.4 s | Reviewed as excellent corner sharpness with well-controlled coma across the zoom range at f/2.8; Digital Camera World and Cameralabs both rate it among the sharpest ultra-wide zooms. [review](https://www.cameralabs.com/sigma-14-24mm-f2-8-dg-dn-art-review/) *Zoom 14–24 mm; preset at the wide end.* | premium | [source](https://www.sigmaphoto.com/14-24mm-f2-8-dg-dn-a) |
| Sigma 20mm F1.4 DG DN Art | 20 | 1.4 | Sony E, L-Mount | AF | not documented | 4.8 s | Capture the Atlas calls it the "best overall lens for Milky Way photography"; Fstoppers' astronomy-focused review found coma extremely well controlled with only slight winging at extreme corners. [review](https://fstoppers.com/originals/sigma-20mm-f14-art-special-astronomy-review-104169) | mid | [source](https://www.sigmaphoto.com/20mm-f1-4-dg-dn-a) |
| Sigma 24mm F1.4 DG DN Art | 24 | 1.4 | Sony E, L-Mount | AF | not documented | 4.0 s | Called out by AstroBackyard as its top pick for Milky Way single-frame shots for its sharpness and light gathering. [review](https://astrobackyard.com/best-milky-way-lens/) | mid | [source](https://www.sigmaphoto.com/24mm-f1-4-dg-dn-a) |
| Sigma 15mm F1.4 DG DN Diagonal Fisheye Art | 15 fisheye | 1.4 | Sony E, L-Mount | AF | no | 6.3 s | Sigma states the design specifically corrects sagittal coma flare for astrophotography; PetaPixel's 2024 review calls the design strong for star points across the 180° field. [review](https://petapixel.com/2024/02/27/sigma-15mm-f-1-4-dg-dn-art-review-wide-weird-and-wonderful/) *Fisheye: NPF assumes a rectilinear lens, so treat it as a centre-of-frame guide.* | premium | [source](https://www.sigmaphoto.com/15mm-f1-4-dg-dn-diagonal-fisheye-a) |
| Sony FE 14mm F1.8 GM | 14 | 1.8 | Sony E | AF | not documented | 7.2 s | Photography Life reports coma essentially eliminated wide open, pinpoint stars to the corners; LensTip measured relatively high astigmatism (~25.7%) increasing off-axis. [review](https://www.lenstip.com/606.7-Lens_review-Sony_FE_14_mm_f_1.8_GM_Coma__astigmatism_and_bokeh.html) | premium | [source](https://www.sony.com/electronics/camera-lenses/sel14f18gm) |
| Sony FE 20mm F1.8 G | 20 | 1.8 | Sony E | AF | not documented | 5.1 s | Capture the Atlas notes it as "lightweight (373g), sharp corners, popular choice" for Milky Way work. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) | mid | [source](https://www.sony.com/electronics/camera-lenses/sel20f18g) |
| Sony FE 24mm F1.4 GM | 24 | 1.4 | Sony E | AF | not documented | 4.0 s | Not independently sourced in this pass; general reputation as a sharp GM prime but no dedicated astro/coma citation captured. | premium | [source](https://www.sony.com/electronics/camera-lenses/sel24f14gm) |
| Sony FE 12-24mm F2.8 GM | 12–24 | 2.8 | Sony E | AF | not documented | 9.8 s | Not independently sourced in this pass for coma-specific ratings; included on spec completeness and Capture the Atlas's zoom recommendations for ultra-wide astro/landscape crossover. *Zoom 12–24 mm; preset at the wide end.* | premium | [source](https://www.sony.com/electronics/camera-lenses/sel1224gm) |
| Nikon NIKKOR Z 14-24mm f/2.8 S | 14–24 | 2.8 | Nikon Z | AF | not documented | 8.4 s | Not independently sourced for coma in this pass; included for spec completeness as Nikon's flagship ultra-wide zoom, widely used for Milky Way landscapes per Nikon's own marketing and Photography Life's review. [review](https://photographylife.com/reviews/nikon-z-14-24-mm-f-2-8-s) *Zoom 14–24 mm; preset at the wide end.* | premium | [source](https://www.nikonusa.com/p/nikkor-z-14-24mm-f28-s/20097/overview) |
| Nikon NIKKOR Z 20mm f/1.8 S | 20 | 1.8 | Nikon Z | AF | not documented | 5.1 s | Mixed reviews: Photography Life/Digital Camera World call coma/astigmatism minimal even wide open; LensTip measured astigmatism at 12.9% ("borderline medium/high") with coma pronounced in corners on some samples. [review](https://www.lenstip.com/587.7-Lens_review-Nikon_Nikkor_Z_20_mm_f_1.8_S_Coma__astigmatism_and_bokeh.html) | mid | [source](https://www.nikonusa.com/p/nikkor-z-20mm-f18-s/20093/overview) |
| Nikon NIKKOR Z 14-30mm f/4 S | 14–30 | 4 | Nikon Z | AF | not documented | 9.9 s | f/4 max aperture limits its use wide open for faint Milky Way detail versus f/2.8 or faster options; included as a lightweight, filter-friendly landscape-astro crossover choice rather than a fast-aperture pick. *Zoom 14–30 mm; preset at the wide end.* | mid | [source](https://www.nikonusa.com/p/nikkor-z-14-30mm-f4-s/20070/overview) |
| Canon RF 15-35mm F2.8L IS USM | 15–35 | 2.8 | Canon RF | AF | not documented | 7.9 s | AstroBackyard's 2026 guide lists it as one of the most versatile Canon lenses for Milky Way and landscape, calling it fast and sharp. [review](https://astrobackyard.com/best-milky-way-lens/) *Zoom 15–35 mm; preset at the wide end.* | premium | [source](https://www.usa.canon.com/shop/p/rf15-35mm-f-2-8l-is-usm) |
| Canon RF 16mm F2.8 STM | 16 | 2.8 | Canon RF | AF | not documented | 7.4 s | f/2.8 max aperture and budget optical design limit low-light astro performance versus faster primes in this list; included as the most affordable/lightest Canon RF wide-angle option, popular as a travel/backup lens. | budget | [source](https://en.canon-cna.com/lenses/rf-16mm-f2-8-stm/specifications/) |
| Canon RF 24mm F1.4L VCM | 24 | 1.4 | Canon RF | AF | not documented | 4.0 s | Space.com's dedicated stargazing-kit review calls it a strong, compact fast-aperture pick for astrophotography. [review](https://www.space.com/stargazing/skywatching-kit/canon-rf-24mm-f-1-4l-vcm-lens-review) | premium | [source](https://www.usa.canon.com/shop/p/rf24mm-f-1-4l-vcm) |
| Canon RF 10-20mm F4L IS STM | 10–20 | 4 | Canon RF | AF | not documented | 13.8 s | f/4 aperture limits use for faint Milky Way detail; included for its extreme field of view (rectilinear ultra-wide) as a specialty landscape-astro option rather than a fast-aperture recommendation. *Zoom 10–20 mm; preset at the wide end.* | premium | [source](https://en.canon-cna.com/lenses/rf-10-20mm-f4l-is-stm/specifications/) |
| Samyang/Rokinon AF 14mm F2.8 | 14 | 2.8 | Sony E, Canon EF, Canon RF, Nikon F | AF | not documented | 8.4 s | Capture the Atlas calls it "best affordable lens" but flags inconsistent quality control across copies. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) | budget | [source](https://www.rokinon.com/products/14mm-f2-8-af-ed-as-if-umc-full-frame) |
| Samyang/Rokinon 24mm F1.4 ED AS IF UMC (manual focus) | 24 | 1.4 | Canon EF, Nikon F, Sony E | MF | yes | 4.0 s | Long-standing reputation among astro-landscape shooters as a well-corrected, affordable fast 24mm; frequently referenced in older Lonely Speck-era astro-lens lists as a coma-favorable Samyang/Rokinon design. [review](https://www.lonelyspeck.com/lonely-specks-ultimate-list-of-best-astrophotography-lenses/) | budget | [source](https://rokinon.com/products/24mm-f1-4-full-frame-wide-angle) |
| Viltrox AF 16mm F1.8 FE | 16 | 1.8 | Sony E, Nikon Z, L-Mount | AF | no | 6.3 s | Reviews vary: phillipreeve.net and PetaPixel found coma control outstanding for the price, matching premium lenses; one reviewer (Silvana Della Camera) found astigmatism visible wide open in corners, improving but not… [review](https://petapixel.com/2023/07/17/viltrox-af-16mm-f-1-8-fe-lens-review-it-has-no-business-being-this-cheap/) | budget | [source](https://viltrox.com/products/viltrox-af-16mm-f1-8-fe) |
| Laowa (Venus Optics) 15mm f/2 Zero-D FF | 15 | 2 | Sony E, Nikon Z, Canon RF, L-Mount | MF | yes | 7.0 s | Capture the Atlas describes it as "manual focus, compact, affordable" among recommended full-frame astro primes; no dedicated numeric coma test captured in this pass. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) | mid | [source](https://www.venuslens.net/product/laowa-15mm-f2/) |
| Laowa (Venus Optics) 12mm f/2.8 Lite Zero-D FF | 12 | 2.8 | Sony E, Nikon Z | AF | not documented | 9.8 s | Fstoppers and DustinAbbott.net's 2025 reviews of the new AF Lite version note strong rectilinear correction (Zero-D) but no dedicated coma/astigmatism numeric test was captured in this pass. [review](https://dustinabbott.net/2025/07/laowa-af-12mm-f2-8-zero-d-review-z-mount/) | mid | [source](https://www.venuslens.net/product/laowa-12mm-f-2-8-lite-zero-d-ff/) |
| Laowa (Venus Optics) 10mm f/2.8 Zero-D FF | 10 | 2.8 | Sony E, Nikon Z, Canon RF, L-Mount | AF | not documented | 11.8 s | PhotoPills' 2026 guide highlights its 130.4° angle of view and minimal distortion; no independent numeric coma test captured in this pass. [review](https://www.photopills.com/articles/best-lens-for-shooting-milky-way) | mid | [source](https://www.venuslens.net/product/laowa-10mm-f-2-8-ff-zero-d/) |
| Irix 15mm f/2.4 Blackstone | 15 | 2.4 | Canon EF, Nikon F, Pentax K, Sony E | MF | yes | 7.4 s | DustinAbbott.net's Blackstone review and PentaxForums rate it well-corrected for coma at f/2.4, a longtime favorite among dedicated night-sky manual-focus shooters for its true infinity click-stop. [review](https://dustinabbott.net/2018/08/irix-15mm-f-2-4-blackstone-edition-review/) *Canon RF listed by the research only 'via adapter/native per Irix lineup'; left out of mounts until confirmed.* | mid | [source](https://www.irixusa.com/irix-15-mm-f-2-4) |
| Tamron 17-28mm F/2.8 Di III RXD | 17–28 | 2.8 | Sony E | AF | not documented | 7.0 s | Capture the Atlas notes it as "lightweight, weather-sealed, affordable"; no independent numeric coma test captured in this pass. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) *Zoom 17–28 mm; preset at the wide end.* | budget | [source](https://www.tamron.com/global/consumer/lenses/a046/) |
| TTArtisan 11mm f/2.8 Fisheye | 11 fisheye | 2.8 | Sony E, Canon RF, Nikon Z, L-Mount | MF | yes | 10.7 s | phillipreeve.net's review notes solid full-frame fisheye correction for the price; used by two photographers in Capture the Atlas's 2026 Milky Way Photographer of the Year winning set per their gear analysis. [review](https://phillipreeve.net/blog/review-ttartisan-11mm-2-8-fisheye/) *Fisheye: NPF assumes a rectilinear lens, so treat it as a centre-of-frame guide.* | budget | [source](https://www.ttartisan.com/?full-frame-lenses%2F62.html=) |
| Viltrox AF 20mm F2.8 FE (Air) | 20 | 2.8 | Sony E, Nikon Z, Fujifilm X | AF | not documented | 5.9 s | Budget f/2.8 design; DustinAbbott.net and OpticalLimits both call it strong value but note it's not as fast as premium f/1.4–f/1.8 primes for faint Milky Way detail. [review](https://opticallimits.com/sony/viltrox-af-20mm-f-2-8-fe-review/) | budget | [source](https://viltrox.com/products/viltrox-af-20mm-f2-8) |
| Samyang/Rokinon AF 18mm F2.8 FE | 18 | 2.8 | Sony E | AF | not documented | 6.6 s | f/2.8 aperture and compact pancake design trade some low-light speed for portability; no dedicated coma test captured in this pass. | budget | [source](https://samyangus.com/products/18mm-f2-8-af-compact-full-frame-sony-e) |
| Canon EF 16-35mm f/2.8L III USM | 16–35 | 2.8 | Canon EF | AF | not documented | 7.4 s | Digital Camera World's 2026 astro buying guide calls it excellent, surpassing predecessors in sharpness, ideal for full-frame astro landscapes — still a popular adapted legacy choice for RF shooters via the EF-RF… [review](https://www.digitalcameraworld.com/buying-guides/best-lenses-for-astrophotography) *Zoom 16–35 mm; preset at the wide end.* | premium | [source](https://www.usa.canon.com/shop/p/ef16-35mm-f-2-8l-iii-usm) |
| Samyang/Rokinon 14mm f/2.8 IF ED UMC (manual focus, legacy EF/F) | 14 | 2.8 | Canon EF, Nikon F | MF | yes | 8.4 s | Historically one of the most-cited budget astro lenses in Lonely Speck-era guides; largely superseded by the AF version for new purchases in 2026 but still in wide use as a used/legacy lens on adapted… [review](https://en.wikipedia.org/wiki/Samyang_14mm_f/2.8_IF_ED_UMC_Aspherical) | budget | [source](https://en.wikipedia.org/wiki/Samyang_14mm_f/2.8_IF_ED_UMC_Aspherical) |
| Sigma 14mm F1.8 DG HSM Art (legacy DSLR) | 14 | 1.8 | Canon EF, Nikon F, Sigma SA | AF | not documented | 7.2 s | Widely cited as merging an ultra-wide 14mm with a bright f/1.8 aperture, though multiple reviews note noticeable coma and astigmatism wide open, more pronounced toward the corners. *source_url points at a Sigma 14mm f/1.4 DG page, not this lens; coma note is lower-confidence.* | premium | [source](https://www.sigmaphoto.com/14mm-f1-4-dg-a) |
| Sony FE 16-35mm F2.8 GM | 16–35 | 2.8 | Sony E | AF | not documented | 7.4 s | WebSearch's 2026 results describe it as "very versatile" and "the best Sony wide-angle zoom lens for shooting the Milky Way" in aggregated buying-guide coverage; no single named review captured with specific coma data… *Zoom 16–35 mm; preset at the wide end.* | premium | [source](https://www.sony.com/electronics/camera-lenses/sel1635gm) |

### APS-C lenses (NPF on a Fujifilm X-T5, 3.04 µm)

| Lens | Focal (mm) | f/ | Mounts | AF | Infinity stop | NPF on Fujifilm X-T5 | Coma / stars (review) | Tier | Source |
|---|---|---|---|---|---|---|---|---|---|
| Tokina atx-i 11-20mm F2.8 CF | 11–20 | 2.8 | Canon EF, Nikon F | AF | not documented | 8.2 s | Manufacturer and retailer copy both describe it as well-suited to astrophotography via low distortion and low light falloff; no independent third-party coma test captured in this pass. *APS-C-format DSLR lens (Tokina); the research JSON had it as full frame. Zoom 11–20 mm; preset at the wide end.* | budget | [source](https://tokinalens.com/product/atx_i_11_20mm_f2_8_cf/) |
| Sigma 10-18mm F2.8 DC DN Contemporary | 10–18 | 2.8 | Sony E, Canon RF, L-Mount, Fujifilm X | AF | not documented | 9.0 s | Capture the Atlas's 2026 guide lists it among recommended APS-C zoom options for Milky Way work, available across four mounts including Fujifilm X. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) *Zoom 10–18 mm; preset at the wide end.* | mid | [source](https://www.sigmaphoto.com/10-18mm-f2-8-dc-dn-c) |
| Sigma 16mm F1.4 DC DN Contemporary | 16 | 1.4 | Sony E, L-Mount, Canon EF-M, Micro Four Thirds, Nikon Z | AF | not documented | 4.2 s | Widely regarded as one of the sharpest fast APS-C primes; frequently recommended for Milky Way work at 24mm-equivalent framing. [review](https://opticallimits.com/sony/sigma-16mm-f-1-4-dc-dn-contemporary-review/) | mid | [source](https://www.sigmaphoto.com/16mm-f1-4-dc-dn-c) |
| Viltrox AF 13mm F1.4 | 13 | 1.4 | Sony E, Fujifilm X, Nikon Z | AF | not documented | 5.1 s | PetaPixel's 2022 review calls it a great lens for the price; no independent numeric coma/astigmatism test captured in this pass. [review](https://petapixel.com/2022/06/20/viltrox-af-13mm-f-1-4-stm-xf-lens-review-great-lens-better-price/) | budget | [source](https://viltrox.com/products/viltrox-af-13mm-f1-4-lens-for-fujifilm-x-mount) |
| Viltrox AF 23mm F1.4 | 23 | 1.4 | Sony E, Fujifilm X, Nikon Z, Canon EF-M | AF | not documented | 2.9 s | Fstoppers' review says it outperforms Fujifilm's own equivalent at a much lower price; not a primary ultra-wide astro pick (23mm/~35mm-equivalent is closer to a standard focal length than a Milky Way wide-field lens),… [review](https://fstoppers.com/originals/fstoppers-reviews-viltrox-23mm-f14-aps-c-dont-buy-fuji-equivalent-504111) | budget | [source](https://viltrox.com/products/viltrox-23mm-f14-xf-mount) |
| Samyang/Rokinon 12mm F2.0 NCS CS | 12 | 2 | Sony E, Fujifilm X, Canon EF-M, Micro Four Thirds | MF | yes | 6.4 s | Capture the Atlas's 2026 APS-C list describes it as its best all-around APS-C option; Samyang/Rokinon's manual primes are generally well regarded for coma control per Lonely Speck's brand-level guidance. [review](https://capturetheatlas.com/best-lenses-milky-way-photography/) | budget | [source](https://www.rokinon.com/products/12mm-f2-0-high-speed-wide-angle) |
| Fujifilm XF 16mm F1.4 R WR | 16 | 1.4 | Fujifilm X | AF | not documented | 4.2 s | Long-standing favorite fast Fujifilm astro prime (24mm-equivalent); no single numeric coma test captured in this pass, but broadly regarded as excellent wide open. | mid | [source](https://www.fujifilm-x.com/en-us/products/lenses/xf16mmf14-r-wr/) |
| Fujifilm XF 14mm F2.8 R | 14 | 2.8 | Fujifilm X | AF | yes | 6.4 s | f/2.8 max aperture is slower than the XF 16mm f/1.4; valued instead for its true manual-focus clutch with hard infinity stop, useful for repeatable astro focus. | mid | [source](https://shopusa.fujifilm-x.com/xf14mmf2-8-xf14mmf2-8/) |
| Fujifilm XF 8-16mm F2.8 R LM WR | 8–16 | 2.8 | Fujifilm X | AF | not documented | 11.2 s | Photography Life's review calls it a professional-grade ultra-wide zoom with field-curvature correction; a premium option at the top of the Fujifilm X wide-zoom line. [review](https://photographylife.com/reviews/fuji-xf-8-16mm-f2-8-r-lm-wr) *Zoom 8–16 mm; preset at the wide end.* | premium | [source](https://www.fujifilm-x.com/en-us/products/lenses/xf8-16mmf28-r-lm-wr/) |
| Fujifilm XF 8mm F3.5 R WR | 8 | 3.5 | Fujifilm X | AF | not documented | 12.7 s | Slower f/3.5 aperture limits Milky Way suitability compared to faster options; included for completeness as Fujifilm's smallest/lightest rectilinear ultra-wide (12mm-equivalent). | mid | [source](https://eshop.fujifilm-x.com/uk/fujinon-xf8mmf3-5-r-wr-camera-lens.html) |
| Sony E 11mm F1.8 | 11 | 1.8 | Sony E | AF | not documented | 6.6 s | DustinAbbott.net's review calls it a "tiny beast" with strong optical performance for its size; widely used as a compact fast APS-C wide-angle for Milky Way work. [review](https://dustinabbott.net/2022/06/sony-e-11mm-f1-8-review/) | mid | [source](https://www.bhphotovideo.com/c/product/1709231-REG/sony_e_11mm_f_1_8_lens.html) |
| Laowa (Venus Optics) 9mm f/2.8 Zero-D | 9 | 2.8 | Sony E, Fujifilm X, Canon EF-M | MF | yes | 10.0 s | Marketed and reviewed as the world's widest rectilinear f/2.8 lens for mirrorless APS-C at launch; Digital Camera World's review notes strong distortion control (Zero-D) though no dedicated coma/astigmatism figure… [review](https://www.digitalcameraworld.com/reviews/laowa-9mm-f28-zero-d-lens-review) | budget | [source](https://www.venuslens.net/product/9mm/) |
| TTArtisan 7.5mm f/2 Fisheye | 7.5 fisheye | 2 | Sony E, Fujifilm X, Canon EF-M, Canon RF, Nikon Z, Micro Four Thirds | MF | yes | 10.2 s | A budget circular-image-style fisheye popular for 180° (150° on MFT) creative Milky Way arcs; no dedicated coma test captured in this pass since fisheye designs are evaluated differently from rectilinear coma testing. *Fisheye: NPF assumes a rectilinear lens, so treat it as a centre-of-frame guide.* | budget | [source](https://www.ttartisan.com/?aps-c-lenses%2F72.html=) |
| Meike 6.5mm f/2 Circular Fisheye | 6.5 fisheye | 2 | Sony E, Fujifilm X, Canon EF-M, Micro Four Thirds | MF | not documented | 11.7 s | Produces a full circular (not full-frame) image with a 190° field of view — a specialty creative/scientific format, not a typical rectilinear Milky Way lens; no coma test applicable in the conventional sense. *Fisheye: NPF assumes a rectilinear lens, so treat it as a centre-of-frame guide. Circular 190° image: NPF is only indicative at the centre.* | budget | [source](https://meikeglobal.com/products/meike-6-5mm-ultra-wide-f-2-0-circular-fisheye-lens-for-sony-a9-a7iii-a7riii-a6500-a6000-a6100-a6300-nex3-nex3n-nex5-nex5t-nex5r-nex6-nex7-a7ii-a7sii-a7rii-mirorrless-cameras) |
| Sirui Sniper 16mm F1.2 AF | 16 | 1.2 | Sony E, Fujifilm X, Nikon Z | AF | not documented | 4.0 s | Very fast f/1.2 aperture is notable for a budget APS-C prime; no dedicated coma/astigmatism test captured in this pass, so optical night-sky performance is unverified beyond general reviews (CineD, Camera Jabber)… | budget | [source](https://store.sirui.com/products/sirui-sniper-series-16-75mm-f1-2-aps-c-frame-autofocus-lens-set) |

### Micro Four Thirds lenses (NPF on an OM System OM-1 Mark II, 3.34 µm)

| Lens | Focal (mm) | f/ | Mounts | AF | Infinity stop | NPF on OM System OM-1 Mark II | Coma / stars (review) | Tier | Source |
|---|---|---|---|---|---|---|---|---|---|
| Laowa (Venus Optics) 7.5mm f/2 MFT | 7.5 | 2 | Micro Four Thirds | MF | yes | 10.7 s | Equivalent to 15mm full-frame field of view; long-standing favorite compact fast MFT wide-angle for astro-landscape work, widely covered in MFT gear guides though no dedicated numeric coma test was captured in this pass. | budget | [source](https://www.venuslens.net/product/laowa-7-5mm-f2/) |
| OM System / Olympus M.Zuiko Digital ED 8mm F1.8 Fisheye PRO | 8 fisheye | 1.8 | Micro Four Thirds | AF | not documented | 9.6 s | Fast f/1.8 aperture on a 16mm-equivalent circular/diagonal fisheye design is popular for MFT astro-landscape shooters wanting an ultra-wide fast option; no dedicated coma test captured in this pass (fisheye designs are… *Fisheye: NPF assumes a rectilinear lens, so treat it as a centre-of-frame guide. source_url is a DPReview page whose slug reads 8mm f/2.8; re-check.* | premium | [source](https://www.dpreview.com/products/om-system-olympus/lenses/oly_8_2p8_fisheye) |
| Panasonic (Leica DG) Leica DG Vario-Summilux 10-25mm F1.7 ASPH | 10–25 | 1.7 | Micro Four Thirds | AF | not documented | 7.5 s | A constant-f/1.7 standard zoom (20–50mm equivalent) rather than an ultra-wide astro prime; included for completeness as a popular fast MFT zoom sometimes used for wider Milky Way framing at its 10mm end. *Zoom 10–25 mm; preset at the wide end.* | premium | [source](https://www.panasonic.com/au/consumer/lumix-cameras-video-cameras/lumix-camera-lenses/lumix-g-lenses/h-x1025.html) |

Full-frame lenses also fit APS-C bodies of the same mount (with the crop);
APS-C lenses on full-frame bodies vignette or force a crop mode.

### By mount

| Mount | Bodies here | Lenses here |
|---|---|---|
| Sony E | a7 IV (ILCE-7M4), a7 III (ILCE-7M3), a7S III (ILCE-7SM3), a7R V (ILCE-7RM5), a7C II (ILCE-7CM2), a1 II (ILCE-1M2), a6700, a6400, a6100, ZV-E10 II | Sigma 14mm F1.4 DG DN Art; Sigma 14-24mm F2.8 DG DN Art; Sigma 20mm F1.4 DG DN Art; Sigma 24mm F1.4 DG DN Art; Sigma 15mm F1.4 DG DN Diagonal Fisheye Art; Sony FE 14mm F1.8 GM; Sony FE 20mm F1.8 G; Sony FE 24mm F1.4 GM; Sony FE 12-24mm F2.8 GM; Samyang/Rokinon AF 14mm F2.8; Samyang/Rokinon 24mm F1.4 ED AS IF UMC (manual focus); Viltrox AF 16mm F1.8 FE; Laowa (Venus Optics) 15mm f/2 Zero-D FF; Laowa (Venus Optics) 12mm f/2.8 Lite Zero-D FF; Laowa (Venus Optics) 10mm f/2.8 Zero-D FF; Irix 15mm f/2.4 Blackstone; Tamron 17-28mm F/2.8 Di III RXD; TTArtisan 11mm f/2.8 Fisheye; Viltrox AF 20mm F2.8 FE (Air); Samyang/Rokinon AF 18mm F2.8 FE; Sony FE 16-35mm F2.8 GM; Sigma 10-18mm F2.8 DC DN Contemporary (aps-c); Sigma 16mm F1.4 DC DN Contemporary (aps-c); Viltrox AF 13mm F1.4 (aps-c); Viltrox AF 23mm F1.4 (aps-c); Samyang/Rokinon 12mm F2.0 NCS CS (aps-c); Sony E 11mm F1.8 (aps-c); Laowa (Venus Optics) 9mm f/2.8 Zero-D (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c); Meike 6.5mm f/2 Circular Fisheye (aps-c); Sirui Sniper 16mm F1.2 AF (aps-c) |
| Nikon Z | Z6 III, Z6 II, Z8, Z f, Z5 II, Z50II, Z fc, Z30 | Nikon NIKKOR Z 14-24mm f/2.8 S; Nikon NIKKOR Z 20mm f/1.8 S; Nikon NIKKOR Z 14-30mm f/4 S; Viltrox AF 16mm F1.8 FE; Laowa (Venus Optics) 15mm f/2 Zero-D FF; Laowa (Venus Optics) 12mm f/2.8 Lite Zero-D FF; Laowa (Venus Optics) 10mm f/2.8 Zero-D FF; TTArtisan 11mm f/2.8 Fisheye; Viltrox AF 20mm F2.8 FE (Air); Sigma 16mm F1.4 DC DN Contemporary (aps-c); Viltrox AF 13mm F1.4 (aps-c); Viltrox AF 23mm F1.4 (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c); Sirui Sniper 16mm F1.2 AF (aps-c) |
| Fujifilm X | X-T5, X-H2, X-T50, X-S20, X-T30 III, X-T30 II, X-M5 | Viltrox AF 20mm F2.8 FE (Air); Sigma 10-18mm F2.8 DC DN Contemporary (aps-c); Viltrox AF 13mm F1.4 (aps-c); Viltrox AF 23mm F1.4 (aps-c); Samyang/Rokinon 12mm F2.0 NCS CS (aps-c); Fujifilm XF 16mm F1.4 R WR (aps-c); Fujifilm XF 14mm F2.8 R (aps-c); Fujifilm XF 8-16mm F2.8 R LM WR (aps-c); Fujifilm XF 8mm F3.5 R WR (aps-c); Laowa (Venus Optics) 9mm f/2.8 Zero-D (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c); Meike 6.5mm f/2 Circular Fisheye (aps-c); Sirui Sniper 16mm F1.2 AF (aps-c) |
| L-Mount | Lumix S5 II (and S5 IIX, stills-identical variant) | Sigma 14mm F1.4 DG DN Art; Sigma 14-24mm F2.8 DG DN Art; Sigma 20mm F1.4 DG DN Art; Sigma 24mm F1.4 DG DN Art; Sigma 15mm F1.4 DG DN Diagonal Fisheye Art; Viltrox AF 16mm F1.8 FE; Laowa (Venus Optics) 15mm f/2 Zero-D FF; Laowa (Venus Optics) 10mm f/2.8 Zero-D FF; TTArtisan 11mm f/2.8 Fisheye; Sigma 10-18mm F2.8 DC DN Contemporary (aps-c); Sigma 16mm F1.4 DC DN Contemporary (aps-c) |
| Canon RF | EOS R6 Mark II, EOS R6 Mark III, EOS R8, EOS R5 Mark II, EOS R, EOS Ra, EOS R7, EOS R10, EOS R50 | Canon RF 15-35mm F2.8L IS USM; Canon RF 16mm F2.8 STM; Canon RF 24mm F1.4L VCM; Canon RF 10-20mm F4L IS STM; Samyang/Rokinon AF 14mm F2.8; Laowa (Venus Optics) 15mm f/2 Zero-D FF; Laowa (Venus Optics) 10mm f/2.8 Zero-D FF; TTArtisan 11mm f/2.8 Fisheye; Sigma 10-18mm F2.8 DC DN Contemporary (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c) |
| Canon EF | EOS 90D | Samyang/Rokinon AF 14mm F2.8; Samyang/Rokinon 24mm F1.4 ED AS IF UMC (manual focus); Irix 15mm f/2.4 Blackstone; Tokina atx-i 11-20mm F2.8 CF (aps-c); Canon EF 16-35mm f/2.8L III USM; Samyang/Rokinon 14mm f/2.8 IF ED UMC (manual focus, legacy EF/F); Sigma 14mm F1.8 DG HSM Art (legacy DSLR) |
| Micro Four Thirds | OM-1 Mark II, Lumix G9 II | Sigma 16mm F1.4 DC DN Contemporary (aps-c); Samyang/Rokinon 12mm F2.0 NCS CS (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c); Meike 6.5mm f/2 Circular Fisheye (aps-c); Laowa (Venus Optics) 7.5mm f/2 MFT (mft); OM System / Olympus M.Zuiko Digital ED 8mm F1.8 Fisheye PRO (mft); Panasonic (Leica DG) Leica DG Vario-Summilux 10-25mm F1.7 ASPH (mft) |
| Nikon F | D850, D750, D7500 | Samyang/Rokinon AF 14mm F2.8; Samyang/Rokinon 24mm F1.4 ED AS IF UMC (manual focus); Irix 15mm f/2.4 Blackstone; Tokina atx-i 11-20mm F2.8 CF (aps-c); Samyang/Rokinon 14mm f/2.8 IF ED UMC (manual focus, legacy EF/F); Sigma 14mm F1.8 DG HSM Art (legacy DSLR) |
| Canon EF-M | — | Sigma 16mm F1.4 DC DN Contemporary (aps-c); Viltrox AF 23mm F1.4 (aps-c); Samyang/Rokinon 12mm F2.0 NCS CS (aps-c); Laowa (Venus Optics) 9mm f/2.8 Zero-D (aps-c); TTArtisan 7.5mm f/2 Fisheye (aps-c); Meike 6.5mm f/2 Circular Fisheye (aps-c) |
| Pentax K | — | Irix 15mm f/2.4 Blackstone |
| Sigma SA | — | Sigma 14mm F1.8 DG HSM Art (legacy DSLR) |

### Coma, astigmatism and focus

- **Coma** smears off-axis stars into comet shapes; **sagittal astigmatism**
  gives them wings. Both are worst wide open and in the corners, and usually
  clean up 1–2 stops down: "a lens that looks messy in the corners at f/1.4
  may clean up nicely at f/2.0–f/2.8"
  ([AstroBackyard](https://astrobackyard.com/best-milky-way-lens/);
  [Lonely Speck](https://www.lonelyspeck.com/a-practical-guide-to-lens-aberrations-and-the-lonely-speck-aberration-test/)).
  Test a lens at several apertures before settling on its astro stop.
- Lonely Speck notes a brand tendency: Samyang/Rokinon manual primes are
  usually well corrected for coma; some older Canon and Nikon fast primes
  were weaker. A tendency, not a guarantee.
- **A real infinity hard stop** makes night focus repeatable. Documented on
  the Irix 15 mm Blackstone, the Fujifilm XF 14 mm (clutch), and most manual
  Samyang, Laowa and TTArtisan lenses. Focus-by-wire lenses need a live-view
  star check every session, then a focus lock or tape.
- **Fisheye NPF** is only a guide for the centre of the frame: the formula
  assumes a rectilinear lens.

## How to choose

1. **Start from the lens, not the body.** Aperture decides how much light
   each second collects; the research's lens guides all rank fast wide primes
   (f/1.4–f/1.8) above slower zooms for faint Milky Way detail.
2. **Pick the widest field you will actually use, then check NPF on your
   body.** Denser sensors trail sooner: the same 20 mm f/1.8 allows 4.2 s on
   the 60 MP a7R V and 7.4 s on the 12 MP a7S III (table above). If NPF is
   short, shoot more frames and stack.
3. **Prefer bodies with a documented astro track record for your needs**
   (star-eater status, lossless raw, a built-in intervalometer that runs long
   exposures) over headline ISO numbers.
4. **Evidence of real use:** in Capture the Atlas's Milky Way Photographer of
   the Year 2026 gear analysis, the Viltrox AF 16 mm f/1.8 was the most-used
   lens among the 25 winning images and the TTArtisan 11 mm fisheye was used
   by two winners ([lenses.md](research/lenses.md#popularity-evidence-and-criteria);
   the analysis page itself returned HTTP 403, so this is from the site's
   corroborating guide).
5. **iPhone:** the Pro line's main camera (14 Pro and later) is the one to
   use; the 18 Pro Max adds f/1.48 and ISO 12,320. Head-to-head reviews do
   not rank iPhones first among phones for astro: Tom's Guide named the Pixel
   9 Pro XL, whose astrophotography mode runs up to 4 minutes
   ([iphone.md §5](research/iphone.md#5-most-popular--evidence-dated-20252026)).
   Stacking many 1 s frames is how this app closes that gap.

## Non-generative AI enhancement (optional, labelled)

ADR-0011, as amended by the owner on 2026-09-27, allows non-generative AI
enhancement as an **optional, labelled step after the deterministic stack**:
AI denoise, sky/foreground masking, and Lightroom-like develop presets or
Python/JSON edit recipes. Purely generative AI that invents content (sky
replacement, added stars, detail "enhance") is not allowed. Originals and the
plain stack are always kept. What is available:

| Option | What it does | ML? | Where it fits | Source |
|---|---|---|---|---|
| **RAW 9 decoder** (`CIRAWFilter.decoderVersion = .version9`, iOS 27) | Apple's Core ML model that demosaics and denoises in one step on the Neural Engine; Apple says it is markedly better at ISO 12,800+ | Yes, non-generative | Optional decode of each ProRAW frame before stacking, or of the finished DNG. Cannot be partly disabled once chosen; needs more memory | [WWDC26 session 305](https://developer.apple.com/videos/play/wwdc2026/305/) |
| **Flat linear decode** (`CIRAWFilter.localToneMapAmount = 0`, `linearSpaceFilter`) | Pulls a near-linear image out of ProRAW before our own stacking | No | Default decode path candidate; deterministic | [Apple docs](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount) |
| **Subject / foreground masks** (Vision `VNGenerateForegroundInstanceMaskRequest`) | Learned class-agnostic foreground mask; the sky is its inverse | Yes, non-generative | Separate sky and foreground so each is stacked or developed on its own | [Apple docs](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) |
| **Sky segmentation models** (DeepLab/MobileNet class, e.g. `fast-skyseg`) | Pixel sky mask robust to trees and ridgelines | Yes, non-generative | Same as above; weights' licence unverified | [opensource.md §5](research/opensource.md#5-skyground-segmentation) |
| **Deterministic horizon mask** (Sequator/Starry Landscape Stacker idea) | Finds the skyline from brightness gradients; user can nudge it | No | Fallback and first version of sky/foreground stacking | [opensource.md §1](research/opensource.md#sequator) |
| **Develop recipe** (JSON, in the spirit of darktable XMP / RawTherapee PP3) | An ordered list of exposure, white balance, curve and mask parameters, replayed on the saved stack | No | Lightroom-like presets that stay reproducible | [opensource.md §6](research/opensource.md#6-mlai-options-for-photo-enhancement-researched-per-the-mid-task-request-adr-0011-scope-note-applies--see-top-of-document) |
| **Desktop AI denoise** (e.g. Lightroom Denoise) | Denoises the exported stack | Yes | Outside the app; not researched here | — |

Precedents: Google's Night Sight uses an on-device CNN only to mask the sky
for darkening and denoising
([Google AI Blog](https://ai.googleblog.com/2019/11/astrophotography-with-night-sight-on.html));
DJI's SuperNight and Insta360's PureVideo are labelled AI denoise
([actioncams.md §4](research/actioncams.md#4-techniques-to-adopt-and-what-avfoundation-cancant-do)).
No permissively licensed, phone-sized low-light RAW denoiser was found as a
ready model, so RAW 9 is the practical on-device option.

## Appendix A: rows left out of the presets

Nothing was dropped silently. These research rows are not presets, and
`config/gear-presets.json` lists them under `excluded`:

| Row | Table | Why it is out |
|---|---|---|
| `iphone-14-pro-max-telephoto` | cameras | No sensor size or pixel pitch from any source (Apple states only 12 MP, 77 mm, f/2.8): cannot form a CameraProfile. |
| `iphone-14-pro-max-telephoto-lens` | lenses | Its camera row is excluded, so there is no sensor to derive the real focal length from. |
| `iphone-13-main` | cameras | iPhone 13: pitch 1.7 µm is known but no equivalent or real focal length is sourced (Apple's page gives only f/1.6, re-checked 2026-09-27), so there is no lens to pair it with. |
| `iphone-13-mini-main` | cameras | iPhone 13 mini: pitch 1.7 µm is known but no equivalent or real focal length is sourced (Apple's page gives only f/1.6, re-checked 2026-09-27), so there is no lens to pair it with. |
| `iphone-13-main-lens` | lenses | No focal length (real or 35 mm-equivalent) from a primary source; Apple's spec page lists only the f-number and 120° FOV. |
| `iphone-13-mini-main-lens` | lenses | No focal length (real or 35 mm-equivalent) from a primary source; Apple's spec page lists only the f-number and 120° FOV. |
| `iphone-13-ultrawide-lens` | lenses | No focal length (real or 35 mm-equivalent) from a primary source; Apple's spec page lists only the f-number and 120° FOV. |
| `ipad-pro-13-m5-main` | cameras | Apple publishes only '12MP Wide, f/1.8'; no sensor size, pixel pitch or focal length, and no stills RAW or Night mode. Not an astro camera. |
| `ipad-pro-13-m5-main-lens` | lenses | No focal length published; camera excluded. |
| `ipad-air-11-m4-main` | cameras | Apple publishes only '12MP Wide, f/1.8'; no sensor size, pixel pitch or focal length, and no stills RAW or Night mode. Not an astro camera. |
| `ipad-air-11-m4-main-lens` | lenses | No focal length published; camera excluded. |
| `moment-tele-58mm` | lenses | Clip-on accessory: no f-number published and no real focal length; it rides on the phone's own aperture. Covered in GEAR-REFERENCE.md instead. |
| `moment-superzoom-example-non-moment` | lenses | ShiftCam 3.5x SuperZoom clip-on: no f-number published. Covered in GEAR-REFERENCE.md instead. |

Renamed ids (also in the JSON under `renamed`): `iphone-13-pro-max-wide` →
`iphone-13-pro-max-main` (and its lens), `rokinon-14-2.4-mf-legacy` →
`samyang-14-2.8-mf-legacy` (the lens is f/2.8), `sigma-10-18-2.8-dc-dn-note`
→ `sigma-10-18-2.8-dcdn`. The Tokina atx-i 11-20 mm moved from full frame to
APS-C (it is an APS-C DSLR lens).

## Appendix B: uncertain values (2026-09-27)

Each is a value the presets or this page use with less than full
confidence, and how to settle it.

| Value | Why uncertain | How to settle |
|---|---|---|
| 18 Pro Max ultra wide 2.22 mm, telephoto 16.31 mm | Derived (measured FOV; Apple's equivalent). The telephoto's FOV implies 16.87 mm | Shoot one ProRAW frame on each and read EXIF FocalLength |
| 18 Pro Max main native pitch 1.22 µm | GSMArena; the EXIF-implied value is 1.24 µm | EXIF of a 48 MP ProRAW frame |
| 18 Pro Max aperture mechanism | Apple states f/1.48–4.0; one PetaPixel report says the sensor stack is fixed f/1.78 with a variable element in front | TechInsights teardown (pending); does not change the presets |
| 12 MP binned pitch for 15/16/17/Air main, 17 ultra wide | 2 × GSMArena's stated 48 MP pitch (quad-Bayer binning) | EXIF of a 12 MP frame from each phone |
| All derived iPhone focal lengths (13 Pro Max, 14 Pro Max, 17 Pro Max, 14–17, e models) | 35 mm-equivalent ÷ pitch-implied crop; validated only on the 16 Pro (within 4 %) and 18 Pro Max | EXIF FocalLength from each model |
| iPhone 13 and 13 mini focal length | Apple's page gives only f/1.6 (re-checked 2026-09-27); "26 mm" is commonly cited but unsourced | EXIF of an iPhone 13 photo, then add the rows |
| iPhone 15 Pro / Pro Max | No sensor rows in the research, though the same 1/1.28" family is likely | GSMArena 15 Pro review |
| Night mode "up to 30 s" | Community-documented; not on any Apple page fetched | — |
| Halide ProRAW capture in 2026 | Its homepage wording is ambiguous | App Store listing |
| iPhone 16 Plus, 14 Plus, 15 Plus hardware | Presumed identical to the base model from Apple's text | GSMArena per model |
| Canon R6 Mark III IBIS and extended ISO | Canon pages returned 403; aggregator only | Canon spec page |
| Sony a7C II IBIS rating; Nikon Z8 extended ISO; Panasonic S5 II bulb/interval | Not confirmed from a primary page | Maker spec pages |
| Fujifilm X-T30 III, X-M5, Canon R50 shutter and intervalometer | Not reached in the research | Maker spec pages |
| Star-eater status of the a7 IV, a1 II, a7C II, a6700 | Inferred from the Mark III trend; no body-specific dated test | A dated test per body |
| Sigma 14 mm f/1.8 DG HSM row | Its source_url is a 14 mm f/1.4 page; coma note from search synthesis | Sigma's page for this lens |
| Olympus 8 mm f/1.8 fisheye row | Its source_url slug reads 8 mm f/2.8 | OM System spec page |
| Irix 15 mm on Canon RF | Research listed it "via adapter/native", so RF is left out | Irix lineup |
| Weights of the Sigma 15 mm fisheye, Sigma 10-18, Samyang 14 mm MF, Sony 16-35 GM | Not found | Maker pages |
| MWPOTY 2026 lens counts | The gear-analysis page returned 403 | Read the page by hand |
| Coma for about a third of lenses | No named review with coma findings found | LensTip or Lonely Speck tests |

## Sources

Every row above links its own source. The research files carry the full
citation lists and what was and was not fetched:
[iphone.md](research/iphone.md), [fullframe.md](research/fullframe.md),
[apsc.md](research/apsc.md), [lenses.md](research/lenses.md),
[iosapps.md](research/iosapps.md), [actioncams.md](research/actioncams.md),
[opensource.md](research/opensource.md),
[iphone-techstack.md](research/iphone-techstack.md). Owner measurements:
[CAPTURE-LIMITS.md](../ios/CAPTURE-LIMITS.md). What the iPhone could do next:
[IPHONE-CAPTURE-ROADMAP.md](../ios/IPHONE-CAPTURE-ROADMAP.md).
