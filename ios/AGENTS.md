# iOS field companion — Agent Routing

Scoped instructions for `ios/`. The repo-wide rules in `../AGENTS.md` still
apply; this file adds what is specific to the native app. Keep it under 80
lines. Why the app exists and what it may do: ADR-0009. The build order and
feature specs: `../docs/ios/PLAN.md` (work milestone by milestone, in order).

## Layout (target — create as milestones land)

```
ios/
  project.yml              XcodeGen spec; the .xcodeproj is generated, never committed
  Packages/SkyCore/        Swift package, no UIKit/SwiftUI imports
    Sources/CAstronomy/    vendored astronomy-engine C port (MIT), unmodified
    Sources/SkyCore/       planner, sky positions, verdict, calculators, models
    Tests/SkyCoreTests/    golden parity + unit tests
  App/                     SwiftUI app target: views, sensors, persistence
  Widgets/                 WidgetKit extension
```

## Working on X → read Y

| Working on | Read first |
|---|---|
| Mac toolchain, disk space, SSD | `../docs/ios/MAC-SETUP.md` |
| Astronomy in SkyCore | ADR-0002, ADR-0009 §3, `../app/src/astronomy/planner.ts` (reference) |
| Anything shown with a number | ADR-0006 (freshness), `../app/src/freshness.ts` |
| Conditions / go-no-go verdict | `../docs/ios/PLAN.md` §Verdict, `../config/conditions-thresholds.json` |
| Talking to the Worker | ADR-0010, `../worker/` response types |
| Map layers | ADR-0003, ADR-0004, ADR-0005 |
| Land manager text | ADR-0004 and invariant 6: never "you may camp here" |

## Verify

```bash
cd ios/Packages/SkyCore && swift test                 # logic + golden parity; test count must be > 0
cd ios && xcodegen generate                            # after any project.yml change
xcodebuild test -project ios/DarkSky.xcodeproj -scheme DarkSky \
  -destination 'platform=iOS Simulator,name=iPhone 17'  # app + UI tests (any sim: xcrun simctl list)
```

Tests use Swift Testing (`import Testing`), never XCTest: SkyCore must build
and test with the Command Line Tools alone (`docs/ios/MAC-SETUP.md`). Prefer
the owner's iPhone over the simulator (256 GB Mac). Name the command you
ran before calling work done. Sensor features (AR,
compass, GPS, background refresh) cannot be proven in the simulator: say so
explicitly and list what the owner should check on the phone.

## Invariants (iOS-specific; the repo-wide six still hold)

1. **Numbers match the web app.** `../shared/golden/night-report.json` is the
   contract; SkyCore tests read it with its own tolerances. Never loosen a
   tolerance to make a test pass — fix the port.
2. **Thresholds live in `../config/`, not in Swift.** The GC altitude
   threshold, freshness windows, and verdict thresholds are loaded from the
   shared config (bundled at build time) so web and iOS cannot drift.
3. **Offline-first.** Every screen renders from cache with its age when there
   is no network. Nothing blocks on a fetch; nothing shows a spinner forever.
4. **Missing never reads as good.** A null cloud/smoke/AQI value renders as
   "unavailable", never 0 (0% cloud and AQI 0 both read as "perfect").
5. **Field mode is real.** In red mode, no white or blue pixel anywhere,
   including the AR overlay, map, alerts, and keyboard-adjacent chrome, and
   brightness controls stay reachable with one hand.
6. **Precise coordinates stay on the device.** Anything sent to the Worker is
   rounded to 0.05° (ADR-0010). Saved spots sync only via the owner's iCloud.
7. **No keys in the app.** Keyed sources go through the Worker.

## Don't

- Commit the generated `.xcodeproj`, `DerivedData`, or signing identities.
- Add a third-party dependency without a line in PLAN.md saying why (MapLibre
  and the vendored C astronomy are pre-approved).
- Replace the C astronomy with SwiftAA or a hand port (ADR-0009 alternatives).
- Compute a "go" verdict that hides its inputs: the limiting factor is always
  shown next to the verdict.
