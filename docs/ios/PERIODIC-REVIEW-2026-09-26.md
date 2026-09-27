# Periodic review for the coordinating Opus session

Reviewed 2026-09-26, evening, before Brian's field testing. This is a review handoff, not a merge approval. No application source was changed. The branches are moving; compare these revisions before acting on a finding.

## Scope and evidence

| Work | Revision inspected | Scope |
|---|---|---|
| Integrated app | `local/ios-integration` / `3f6835d` | Simulator installation and bounded XCTest attempt; unresolved field findings |
| Shot window / conditions | `local/ios-shot` / `4226c93` | Core calculation, forecast consumption, revalidation, card, full SkyCore tests and an additional regression probe |
| Capture | `local/ios-capture` / `025f094` | Capture lifecycle, stopping, stack execution, storage and device-report evidence; static review |
| Design | `local/ios-design` / `ea8f3f1`, then `c537e0a` | Field state and shared screen controls; not a complete visual acceptance pass |
| Sky, events, basemaps | `e23f778`, `af88dcb`, `af23c71` | Change inventory and focused inspection; owners still had substantial uncommitted UI work |

The integrated revision does **not** contain the new shot, capture, events, Sky or design work. A simulator result for integration cannot approve their combined behavior. Capture's detector/tests, Sky calibration UI, events wiring and basemap UI were actively changing and were not treated as completed work.

Positive evidence: shot timing has explicit flat/stepped terrain cases, known-star rise checks and a Candlestick case; the full shot-branch SkyCore suite passed **310 tests in 45 suites**. The client uses an **exact cell/window cache match** for its ETag, and a 304 preserves the original forecast body and its embedded ages. The capture branch preserves original frames and includes a local device capability report. These are useful foundations for field diagnosis.

## Required findings

### 1. P1 — The new 15-minute forecasts do not participate in the shot verdict

**Branch:** shot, `4226c93`.

`ios/Packages/SkyCore/Sources/SkyCore/Verdict.swift:269` evaluates `f.series`; `:378` samples that series' `values`. Dew-point spread likewise uses the hourly series. The new native forecast is stored separately in `WorkerField.series15Min`. `ConditionsRevalidation.swift:37` offers `finestPoints`, but no application or verdict consumer calls it at the reviewed revision.

This affects the Worker's near-term **gust, temperature/dew-point and related fields**, not cloud cover: clouds are not among the native 15-minute fields listed by this implementation. A short gust can be present in the response and cache yet absent from the shot's limiting factor.

**Reproduced:** reuse `ShotVerdictTests`' May 6 Candlestick shot and good hourly gusts (8 km/h); add an otherwise fresh HRRR `series15Min` covering 06:00–08:00Z with a 90 km/h sample at 06:45Z, inside the shot. The native data is present, but the gust assessment reports **8 km/h, good**; the overall verdict remains **marginal**, instead of no-go. Both expected-value assertions failed. The probe is isolated from working branches at `/private/tmp/darksky-periodic-shot-proof/ios/Packages/SkyCore/Tests/SkyCoreTests/PeriodicReviewTests.swift`; a portable copy is below.

**Change requested:** choose forecast cadence in the shared verdict input path, with explicit coverage, provenance, null and freshness rules, then let both charts and verdicts use it. Pair temperature and dew point at matching times. Test a fine-resolution spike, an unavailable/null fine series, and the handoff to hourly data. Do not merely replace hourly points with a concatenation and reuse an unweighted mean: unequal sample spacing would weight the short interval more heavily.

### 2. P1 — Leaving Capture during a run has no explicit owner or cleanup policy

**Branch:** capture, `025f094`; confirmed from control flow, not reproduced with a physical camera.

`ios/App/Capture/CaptureScreen.swift:55` calls `model.disappear()`, but `CaptureModel.swift:130` immediately returns while the phase is running. The run is an unstructured task (`:217`), so leaving the view does not cancel it. Back navigation remains available. The completion path restores the global idle-timer flag (`:226`) but never calls `engine.stop()` or `stopSensors()` for an off-screen run. There is also no scene-phase/interruption handling in this capture implementation.

Separately, Stop during acquisition still proceeds to `stack(...)` (`:312`). Stacking is a detached task (`:348`); its Stop button is disabled (`CaptureScreen.swift:285`) and `StackBuilder` has no cancellation checks. Stopping a long session therefore can immediately begin substantial CPU/storage work that the user cannot stop from this screen.

**Change requested:** give the run one explicit lifetime. Either keep it in an app-owned session that remains visible/recoverable, or stop when leaving; in either case, drain already requested frame writes, preserve the originals, and deterministically release camera, motion, timers and idle-timer ownership. Define whether Stop means "finish acquisition and stack" or "stop work" in the UI; support cancellable stacking if it means the latter. Handle camera interruption/background transitions explicitly.

**Device acceptance:** start a short sequence, navigate back during countdown and acquisition, then return; repeat while stacking and while locking/unlocking the phone. Verify that only the intended run exists, the camera indicator goes off when finished, frames remain accessible, controls recover, and idle sleep works again. This review does not establish an indefinite leak or a device crash; it establishes the missing lifecycle paths that need that test.

### 3. P2 — Field mode still resets on process relaunch; brightness access is missing

**Branches:** integration and reviewed design revisions.

`ios/App/Shared/AppState.swift:30` reads `UserDefaults["FieldMode"]` once. The field toggle changes only that in-memory property; no code writes the preference. After enabling red mode, terminating and reopening the process restores the normal palette unless an external launch default has been supplied. A restart at a dark site can therefore surprise the user with the normal interface. The design refresh does not fix this state issue.

Persist the preference when it changes and verify a genuine process relaunch, not just tab navigation. The app also still lacks the one-hand brightness control required by `ios/AGENTS.md:66`; the palette toggle alone does not implement that requirement. Verify the brightness behavior on-device, including restoration of any screen brightness the app temporarily changes.

## Earlier findings still present in integration

- **P2 — Measured skyline applied over too large an area.** `TerrainHorizon.swift:277` still uses a 1,000 m radius to identify Candlestick. `SpotDetail` uses that predicate both to offer the saved measured profile and to compare a computed skyline against it. A nearby point is not necessarily the same observer location, especially near relief. Associate reference data with its surveyed observer; label any deliberate reuse and restrict the RMS comparison to the matching site.
- **P2 — Go alerts can describe an elapsed shooting window.** `SpotWeekPlanner.swift:62` includes the night containing "now"; before noon this can be the previous evening. `ios/App/Alerts/SpotRefresh.swift:98` filters only Go and previously notified IDs. Gate notification eligibility on a remaining usable window, not merely a night label, and test after dawn before noon with a valid cached Go forecast.

## Optional design follow-up

`ShotWindow.best` and the chart show the longest window, while `nightForVerdict` (`ShotWindow.swift:166`) evaluates **all** windows. `ShotText` does mention additional windows, so this is not hidden data, but a poor shorter interval can produce no-go beside a clear longest interval. Consider a verdict per selectable window, or make the combined scope explicit beside the verdict. Preserve the conservative whole-set assessment if that is the intended decision rule; document it so future agents do not "fix" it inconsistently.

`CAPTURE-LIMITS.md` links to a PLAN log containing exposure, cadence and stack benchmark results. That M12 log was not present in the reviewed capture or integration PLAN. Before presenting capture as field-ready, bring the actual test evidence into the integration log (including frame dimensions, EXIF, frame interval, peak memory/temperature and failures). The capability probe by itself is not an end-to-end sequence test.

## Verification record

- **Passed:** shot-branch SkyCore, 310 tests / 45 suites. Log: `/private/tmp/darksky-periodic-shot-tests.log`.
- **Reproduced regression:** one added probe failed with two assertions: gust 8 instead of 90 km/h; overall marginal instead of no-go. Existing package source was unchanged. Log: `/private/tmp/darksky-periodic-proof.log`.
- **Passed simulator test:** `SkyTests.testSimulatedViewListsTargetsForVoiceOver`, 80.436 seconds, on the integrated app in a dedicated, previously unused iPhone 18 Pro Max / iOS 27.0 simulator. This exercises app launch, Sky navigation, simulated mode and accessible targets.
- **Incomplete simulator checks:** the overall run reached its 360-second limit during `SpotsTests.testMeasuredCandlestickProfile`, after opening the editor and starting spot entry. Neither Tonight check (offline conditions and normal/red screenshot tour) ran. The limit includes package resolution/build and runner startup; this is **not evidence of a Spots assertion failure or an app hang**. No full UI pass or completed screenshot tour is claimed. Log: `/private/tmp/darksky-periodic-ui.log`; result bundle `/private/tmp/darksky-periodic-ui.xcresult` may be incomplete because the outer timeout stopped xcodebuild. No additional environment repair or retry was attempted.
- **Not established here:** real camera output/registration quality, compass accuracy, battery drain, thermal behavior, offline-map completeness, or acceptance of the newly combined branches on the owner's phone. No phone was connected or modified for this review.

## Suggested next step for Opus

Resolve the near-term verdict input and capture lifetime issues, land the completed branches in small groups, then name the exact installed commit for Brian's field session. Keep the first field session short: verify stored location/night/skyline, force quit and reopen in red mode, confirm cached forecast ages offline, check compass alignment away from the car, and run a short capture with a deliberate Stop before starting a long sequence. Record expected versus observed results and the build revision with each report.

This document is available in the shared integration worktree. It has not been sent as a live message to a separate Opus session.

## Portable regression probe

Add this as a temporary test beside `ShotVerdictTests.swift` on `4226c93`, then run `swift test --filter PeriodicReviewTests`. The review ran it in an archived copy under `/private/tmp`, leaving the owner's worktree untouched. It intentionally fails until the native-series consumption is implemented.

```swift
import Foundation
import Testing
@testable import SkyCore

struct PeriodicReviewTests {
    @Test func nativeGustSpike() throws {
        typealias F = ShotVerdictTests
        let shot = try F().shot()
        let response = F.response(clouds: F.clearingLate) { fields in
            var gust = fields["wind_gust"]!
            gust.series15Min = [WorkerSeries(
                model: "hrrr", upstreamModel: nil, modelRunUTC: F.at(0),
                fetchedUTC: F.at(1.5), status: .ok, reason: nil, lastGoodUTC: nil,
                values: (0...8).map { i in
                    WorkerPoint(t: F.at(6 + Double(i) / 4), v: i == 3 ? 90 : 8)
                })]
            fields["wind_gust"] = gust
        }
        let snapshot = ConditionsSnapshot(response: response, fetchedUTC: F.at(1.5))
        #expect(snapshot.nearTerm("wind_gust")?.values.map { $0.v ?? 0 }.max() == 90)
        #expect(shot.best!.start < F.at(6.75) && shot.best!.end > F.at(6.75))
        let verdict = try shot.verdict(conditions: response, config: .bundled(), now: F.now)
        #expect(verdict.factor("wind_gust")?.value == 90)
        #expect(verdict.level == .noGo)
    }
}
```
