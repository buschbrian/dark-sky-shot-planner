# Dark Sky: weekend report, 2026-09-25 to 2026-09-27

For Brian. Everything below is on the local branch `local/ios-integration`
(worktree `~/Developer/wt-dark-sky-next`); nothing from the iOS work is
pushed. The conditions Worker is the one thing deployed. Companion
documents: `docs/ios/CAPABILITIES.md` (the capability table),
`docs/business/APP-STORE-AND-MONEY-2026-09-27.md` (the full App Store and
money research, with sources), and `docs/ios/PLAN.md` §Log.

## Where it stands

The app runs on your iPhone 18 Pro Max with five tabs: Tonight (with Week
inside it), Map, Sky, Spots and Tools. It plans a night from real
astronomy plus a four-model forecast, draws the map and an AR sky,
captures and stacks on the phone, and keeps working offline. It has been
tested hard in the simulator and lightly on the phone, **but not yet at a
dark site**. That is the single biggest gap: until you check the verdict,
the compass/AR alignment and a real-sky stack in the field, the accuracy
claims are design claims.

One thing with a date on it: the app is signed by a **free Personal Team**,
so the copy on your phone expires on **2026-10-03** (7-day profile). It
stops opening then until it is reinstalled from this Mac. The paid Apple
Developer Program ($99/yr) removes that and is required for TestFlight.

## What was done

In numbers, since Friday: 244 commits; 243 Swift files (+43,000 lines);
the Worker (+21,600 lines including fixtures); 42 docs (+25,000 lines).
Tests: 482 SkyCore tests, 47 app unit tests, 67 UI tests.

**Friday.** The iOS plan and the stateless Worker design were written and
merged on GitHub (PR #9, ADR-0009 and ADR-0010), with golden vectors
exported from the web planner.

**Saturday.**
- **SkyCore**, the shared Swift engine: astronomy matching the web app to
  the golden vectors (M1), the verdict (M4), week outlook (M5), map and AR
  geometry (M6/M7), terrain horizon from elevation data, checked against
  the surveyed Candlestick Camp skyline at 0.494° RMS (M9), and gear,
  NPF/500-rule, stacking and timelapse maths (M10).
- **The conditions Worker**, deployed to
  `dark-sky-conditions.brisk-delta-c382.workers.dev`: Open-Meteo HRRR, GFS,
  ICON and ECMWF, air quality, smoke (RAP-Smoke, HMS), AirNow, 7Timer! and
  space weather, with run-aware refresh, ETags/304s and HRRR 15-minute
  data. Measured: cold 1.8 s, warm 0.12 s, 304 in 0.12 s.
- **The app**: shell and five tabs; Tonight, Week, Map (MapLibre), Sky
  (AR over the camera, compass and gyro), Spots (saved places, 7-night
  check, background alerts, widget) and Tools (calculators and gear).
  First install on your phone.
- **Housekeeping**: the Mac went from 20 GB free to about 38 GB, then
  through a scare at 1.9 GB during the six-agent run, back to about 20 GB.
  PR #10 (Mac prompts) merged; PR #11 (doc corrections) opened.

**Sunday.**
- **Shot window (M11)**: the usable window for a target at a place,
  terrain included, with the 15-minute HRRR data feeding the verdict.
  **Now Tonight's main answer**: usable time in the site's zone, ridge
  clearance, what limits it, then Save plan, Show on map, Find in sky. The
  verdict describes the window you select.
- **Sky events**: eclipses, supermoons, Milky Way season, meteor showers,
  on Tonight with "Plan this" and badges on Week rows.
- **Moon-up nights** read "Moon up" the same way everywhere, with "No
  moon-free Milky Way window" and "Find the next suitable night" instead
  of a red No-go.
- **Map**: USGS Topo, Imagery and Dark relief basemaps, your location,
  offline areas; then a full-screen map with a bottom sheet (about 80 % of
  the screen is map), your target's line by default with Sun/Moon/GC as an
  optional Compare, one colour per body, labels that never overlap,
  long-press "Plan here?" with Undo, centre on pin, honest smoke wording,
  and sample data (light pollution, land manager) labelled once and never
  used in an answer.
- **Sky**: star field, constellations, a Metal simulated sky, and compass
  calibration (figure-8 guide, alignment on the Moon or a star).
- **Capture (M12)**: measured the phone's real limits first (1 s per frame
  on the main camera, ProRAW), then sequences with star registration and
  stacking, originals always kept. Then the product-review fixes: Start,
  Stop and Cancel in a fixed bottom bar; honest exposure and 12/48 MP
  labels; a "How to shoot" guide with an Apple Camera path and a Dark Sky
  path; a results view with "Save image" first; star trails that follow
  the design from Sky. Tested indoors on the phone only.
- **Field mode**: red over the whole window, remembered across relaunch,
  with a brightness slider in thumb reach; the red dock now sits below
  every screen instead of covering its bottom rows. A design system (`DESIGN.md`)
  under every screen.
- **Refresh**: Tonight, Week and Spots refresh when the Worker says new
  model data is due, not on a fixed timer.
- **Decisions recorded**: ADR-0011 (iPhone capture; non-generative
  enhancement allowed, generative not), ADR-0012 (curated gear presets),
  ADR-0013 (any astrophotography, including deep-sky with telescopes;
  decisions D1–D9 in `docs/deepsky/OWNER-DECISIONS.md`).
- **Research and docs**: the gear reference (also published as a page and
  in your vault), the deep-sky plan, `CAPABILITIES.md`, a first-outing
  guide, a glossary, a Help/About spec, and today's App Store research.

**Reviews and their state.** Three independent reviews ran this weekend
(the periodic review, the Fable review and the product review). Every
periodic and Fable finding (B-1 to B-9) is fixed except the sample map
data, which needs the `data-refresh.yml` run. Of the product review's ten
items, 1, 2, 4, 6, 7 and 10 are done, 3 is done on the Map only, and 5, 8
and 9 are open (listed below).

## What remains, and how each is proven done

**Your field checks.** Only you can do these; each has a pass line to
record in `PLAN.md` §Log and flip the "Field-tested" cell in
`CAPABILITIES.md`.

| Check | Done when |
|---|---|
| Verdict against the sky | One night at a dark site: the app's verdict and usable window, noted before dark, match what the sky did (clouds, smoke, moon), written in §Log with the build |
| Compass and AR alignment | After the figure-8 guide, the Moon or a bright star sits within 2° of its marker, away from the car, recorded with the heading accuracy shown |
| Shot window against the ridge | At Candlestick (or any saved spot), the Galactic Center clears the ridge within about 5 minutes of the app's time |
| A real-sky stack | A 9-frame ProRAW run on a tripod gives "aligned on stars" for most frames, and "Save image" puts it in Photos |
| Red mode in the dark | Every tab readable at low brightness, no white flashes, after force-quitting and reopening in red |
| Offline | With the phone in airplane mode at the site: the saved area's map draws, Tonight shows the saved forecast with its age |
| Background alert | A Go alert arrives for a saved spot on a good night (best-effort by design; note if it doesn't) |

**Code still to do.** Each ends with a test or a measurable check.

| Item | Done when |
|---|---|
| "Show on map" should set the map's target and time | A UI test: Show on map from Tonight lands on the map with that target's line at the planned time |
| Sky warning when you are away from the planning site | A UI test with a simulated location 50 km from the planned place shows the mismatch notice |
| Gear preset picker, including "This iPhone" | A UI test picks a camera and lens from the presets and the NPF result changes to match |
| One colour per body in charts and Sky | Charts and Sky markers read `CelestialStyle`; a unit test compares the colours on all three |
| Red-mode contrast and 44 pt targets everywhere | A contrast test over the red tokens (secondary text ≥ 4.5:1) and a UI audit that every button is ≥ 44 pt |
| Help/About, credits and privacy link | The About page shows version, the first-outing guide, glossary, data status, credits for every source in `data-licensing.md`, and a privacy-policy link |
| Saved plans, Calendar export, a calendar with moon and darkness | A saved plan appears in a list after relaunch; "Add to Calendar" creates an event with the window's times; the calendar shows moon phase and darkness per day |
| Real light-pollution and land-manager data | `data-refresh.yml` runs (needs your go-ahead and the Earthdata token); `data-status.json` says `real` for both |
| Device-only UI tests | Xcode signs the UI-test runner for your phone, and `CaptureLifecycleTests` runs on the device |
| M13 activity profiles (lunar, planetary, deep-sky) | Per `docs/deepsky/PLAN-ANY-ASTRO.md`: each profile's golden cases pass, and Tonight's headline changes with the chosen activity |

## Upgrades worth considering

Ordered roughly by value for the effort.

1. **An on-device free forecast.** WeatherKit (500k calls a month included
   with the paid membership) or NWS for a free tier, keeping the
   multi-model view for paying users (see the money section).
2. **Live Activity and Dynamic Island** for a capture run and for the
   shot-window countdown, so the phone can stay locked in your pocket.
3. **App Intents**: "Is tonight good at Candlestick?" in Siri and
   Shortcuts, a Control Center button for red mode, and a Focus filter
   that turns red mode on at night.
4. **Focus help from the stars**: use the star-size measure (HFR) the
   capture code already has to find infinity focus automatically.
5. **Deep-sky (ADR-0013)**: OpenNGC targets, the Lorentzian moon-avoidance
   rule, seeing for planets, and copying coordinates to a telescope app,
   with Alpaca handoff as an opt-in later.
6. **Spots across devices**: iCloud sync (the About page still has a
   disabled toggle for this) and a shareable plan file.
7. **A real map data refresh** on a schedule, and vector basemaps if
   offline areas grow large.
8. **Aurora**: a Kp alert for northern trips, since the space-weather feed
   is already in the Worker.
9. **Non-generative enhancement** (allowed by ADR-0011's amendment): a
   licensed on-device denoise model, labelled and optional, validated on
   real night frames first.

## App Store and making money

Full research, with a source for every claim:
`docs/business/APP-STORE-AND-MONEY-2026-09-27.md`. The short version:

**Getting listed.** Nothing about it is hard, but several things are
missing.
- **Membership**: $99/yr. As an individual, "Brian Busch" is the seller.
  For "Dust & Starlight" to show, it must be a legal entity (a Utah LLC is
  $59, then $18/yr) with a D-U-N-S number and a working website on its own
  domain; Apple doesn't accept DBAs. Enrolling as an individual now and
  converting later is allowed.
- **Missing in the repo**: an app icon, a privacy manifest
  (`PrivacyInfo.xcprivacy`), `ITSAppUsesNonExemptEncryption = NO`, a
  privacy policy and support page with an in-app link, a credits screen,
  and hiding the sample map layers and the dead iCloud toggle in release
  builds.
- **Name**: a bare "Dark Sky" is risky. Apple owned the Dark Sky weather
  app, and DarkSky International uses the name. Pick a distinct store name.
- **Review**: about 90 % of submissions are reviewed within 24 hours. The
  "Go / No-go" wording should say it is for photography, not a safety
  forecast.

**Data licences are the real blocker.** Any paid, subscription, ad-backed
or even promotional release is commercial use.
- **Open-Meteo**: needs a paid plan, $29/month for 1M calls or $99/month
  for 5M. The Worker has to move to the customer endpoint with a key, and
  the app's direct fallback to the free Open-Meteo API has to go.
- **7Timer!**: non-commercial only; turn it off (the Open-Meteo jet-stream
  proxy covers seeing).
- **The NPF rule**: its author asks for consent before commercial use.
  Ask, or lead with a rule derived from pixel size and focal length.
- USGS, NOAA, NASA, MapLibre and the star catalogs are fine with credit.

**Running cost** if every user gets live data: about $40/month at 100
daily users, about $110 at 1,000, about $400 at 10,000 (assumptions in the
research). Apple's cut is 15 % under the Small Business Program.

**Recommended model: a free app plus one "live conditions" subscription.**
- Free: everything computed on the phone (darkness, Moon, Galactic Center,
  Sky, tools, capture, the map and offline areas). It costs nothing to run.
- Subscription: the multi-model forecasts, smoke, Week verdicts, spot
  alerts and the verdict widget, for example $19.99/year or about
  $2.49/month with a one-week free trial.
- Why: the data cost only grows with paying users, it breaks even at about
  26 subscribers, and it needs no ads or tracking. The free app can also
  point to Dust & Starlight workshops and prints (sold outside Apple's
  in-app purchase, with no commission).
- Fallback: $9.99 up front, like PhotoPills and TPE, with WeatherKit as a
  cheaper backup if sales stall.
- The closest rival, DarkScout, charges $39.99/year.

**A path from here to v1.0**, each step with a check that proves it:

| Step | Proven when |
|---|---|
| Choose seller (individual or LLC) and store name | Recorded as an ADR |
| Enroll ($99) | Xcode shows a paid team and an "Apple Distribution" identity |
| Store hygiene (icon, privacy manifest, encryption key, hide samples) | The release build contains `Assets.car` and `PrivacyInfo.xcprivacy`; Xcode's privacy report lists the three API reasons |
| Licences (Open-Meteo key, 7Timer! off, no free fallback, NPF settled) | The Worker's health check shows the customer endpoint; no `api.open-meteo.com` in release code |
| Privacy policy, support page, credits | Both URLs load from the D&S site and open from About |
| TestFlight, you and a few friends | "Build 1 available to internal testers" in App Store Connect |
| Field validation | The field checks above are recorded in §Log |
| Public TestFlight | "Beta App Review approved" |
| Subscription (StoreKit 2), Paid Apps Agreement, tax, bank, Small Business Program | The agreement shows Active and a purchase/restore test passes |
| Store listing and submit | "Ready for Distribution" |

## Decisions for you

1. Enroll in the Apple Developer Program, as yourself or as a Dust &
   Starlight LLC.
2. A store name that isn't a bare "Dark Sky".
3. Free with a subscription, or paid up front.
4. Whether to run `data-refresh.yml` for real light-pollution and PAD-US
   data.
5. Whether to write to the Société Astronomique du Havre about the NPF
   rule.
6. PR #11 on GitHub is still open for you to merge.
