# ADR-0009: A native iOS field companion, and a wider scope contract

**Status:** accepted · **Date:** 2026-09-25

## Context

The brief's scope contract was one question — *is this spot dark, legal, and
clear tonight?* — answered by a static website. That answer is right, and
the web app answers it well. But the real workflow on a shoot night still
means juggling five or six apps: PhotoPills for the Milky Way position and
AR, Astrospheric or Clear Outside for cloud layers and seeing, an AQI app for
smoke, a Kp app for aurora, a weather app for dew point and wind, and a notes
app for exposure settings. The goal of this project is now to collapse that
into one place, on the device that is actually in the field: an iPhone.

Several of those jobs cannot be done well in a browser: Night AR needs the
camera, compass and motion sensors fused at 60 fps; "tell me when Saturday
turns good" needs background refresh and notifications; "what does tonight
look like" wants a Home Screen widget; and the field has no signal, so the
app must work fully offline once planned. The owner builds on an M4 MacBook,
so Xcode and a native toolchain are available.

## Decision

### 1. Scope contract, amended

> **Should I go shoot tonight — and if so, where, when, and how?**

The original question stays at the core and stays answer-first. The new
words each admit one family of features, and nothing else:

| Word | Admits |
|---|---|
| *should I go* | Live conditions (cloud layers, smoke/AOD/AQI, seeing and transparency, dew and wind, aurora) and one explainable go / marginal / no-go verdict |
| *where* | Saved spots, the dark-sky and light-pollution layers, land manager, terrain horizon |
| *when* | Moon-free darkness (still the headline number), Galactic Center / Milky Way timing, sky events, the week-ahead outlook, and alerts when a saved night turns good |
| *how* | Night AR, map planner lines (azimuths over terrain), and exposure calculators for the owner's own gear |

Still out of scope: social features, photo galleries, image processing,
turn-by-turn navigation, a general planetarium, and a trip planner.
"Where to camp" stays out: PAD-US is still a boundary dataset, never a
permission system.

### 2. A native SwiftUI app in `ios/`, beside the web app, in the same repo

- **SwiftUI, Swift 6 language mode, iOS 18 deployment target.** It is
  one person's app on one person's phone, so the target can move up freely.
- **The web app stays.** It is the shareable, desktop, no-install view and
  the reference implementation of the astronomy. The iOS app is a peer, not
  a replacement. Both read the same `config/` files.
- **Logic lives in a Swift package (`ios/Packages/SkyCore`)** with no UIKit
  or SwiftUI imports, so `swift test` runs it on macOS in seconds and a
  future watchOS or widget target reuses it. The app target is UI, sensors,
  and persistence only.

### 3. Astronomy: the astronomy-engine C port, verified against the web app

astronomy-engine (already the web app's library, ADR-0002) ships a C port as
a single `astronomy.c`/`astronomy.h` pair under the same MIT license. SkyCore
vendors it as a C target (`CAstronomy`) and wraps it in Swift. The two apps
then run the *same algorithms*, not two libraries that roughly agree.

Parity is enforced, not assumed: `shared/golden/night-report.json` is written
by the TypeScript planner (`app/tests/golden-vectors.test.ts`) and read by
SkyCore's tests with the tolerances recorded in the file. A disagreement is a
bug in the port until proven otherwise.

### 4. Persistence: on-device, synced through the owner's own iCloud

Saved spots, plans, gear profiles and cached forecasts live in SwiftData,
optionally synced with CloudKit's private database. No server holds per-user
state (see ADR-0010 for the one server that exists, and why it is stateless).

### 5. Offline is a requirement, not a feature

Dark sites have no signal. Everything the app computes (astronomy, AR, the
calculators) works offline by construction. Everything it fetches is cached
with its fetch time and shown with its age under the freshness rules
(ADR-0006) when the phone is offline. Map regions for saved spots are
downloadable. "Last updated 3 h ago, before you lost signal" is an honest
answer; a spinner is not.

## Alternatives considered

- **Installable PWA only.** Builds from Windows and reuses everything, but iOS
  gives web apps weak background execution, no widgets, and fragile
  camera+motion AR. The things that make this better than six apps are
  exactly the things a PWA does badly.
- **Capacitor wrapper around the web app.** Gets onto the App Store cheaply,
  but the hard features (AR, widgets, background refresh) would be native
  plugins anyway, which leaves us with two UI stacks bridged by strings.
- **React Native / Expo.** Cloud builds from Windows were the draw; with a Mac
  available that advantage is gone, and the AR path is still native modules.
- **SwiftAA or a hand port for the astronomy.** SwiftAA uses different
  algorithms (Meeus/AA+), so the two apps would disagree by minutes near the
  edges. That is exactly the number this project exists to get right. A hand
  port is a second implementation to keep in sync forever.
- **Run the TypeScript planner in JavaScriptCore.** Keeps one codebase, but
  puts a JS bridge on the AR hot path and makes Swift tests awkward.

## Consequences

- The brief's §1 scope paragraph is superseded by §1 above. Its §3 "zero
  server" rule is narrowed by ADR-0010. Every other rule stands, including
  provenance on every number, the Falchi/Lorenz ban, keyless CI, and the
  "never assert you may camp here" rule.
- Two UI codebases. They are allowed to differ in presentation, never in
  numbers: shared config and shared golden vectors are the contract.
- Xcode work happens on the Mac. CI for `ios/` runs on a macOS GitHub
  runner (`swift test` for SkyCore first, and `xcodebuild test` once the app
  target exists). Windows development continues to cover `app/`,
  `pipelines/`, and `worker/`.
- The plan and build order live in `docs/ios/PLAN.md`; agent instructions for
  working in `ios/` live in `ios/AGENTS.md`.
