# Golden vectors

Numbers every implementation of the planner must reproduce, within the
tolerances stored in each file. The TypeScript planner is the reference
(ADR-0009 §3).

| File | Written by | Read by |
|---|---|---|
| `night-report.json` | `app/tests/golden-vectors.test.ts` | that test, and SkyCore's parity tests (`ios/Packages/SkyCore`) |
| `night-report.json` → `horizon_cases` | the same test, `planNight` with a terrain `horizon` (M9); each case names its profile under `config/horizon-profiles/` | that test, and SkyCore's `GoldenHorizonParityTests` |
| `gc-horizon.json` | `app/tests/golden-vectors.test.ts` (`gcAltitude`/`gcAzimuth`) | that test, and SkyCore's GC alt/az spot checks |
| `sky-events.json` | `app/tests/sky-events-golden.test.ts`: `buildSkyEvents` for 9 places and nights, the raw numbers under each item, and the verdict text at a fixed UTC offset | that test, and SkyCore's `SkyEventsParityTests` (counts, titles, provenance and text exact) |
| `tonight.json` | by hand: which night is "tonight" at a given instant and place (review B-2), and the darkness end behind "last night (ended 5:43 AM)" | `app/tests/tonight.test.ts` (`tonightIso`, `darknessEnd`) and SkyCore's `NightDateTests` (`NightDate.current`, `darknessEnd`) |
| `conditions-response.json`, `space-weather-response.json` | `worker/test/golden-response.test.ts`: real Worker output built offline from its recorded fixtures (AirNow rows are the synthetic fixture) | that test (drift check), and SkyCore's `WorkerContractTests` and verdict tests |

The three astronomy files record `astronomy_engine`, the npm version that wrote it. Both
suites fail if it differs from the version they run (npm's
`node_modules/astronomy-engine`, SkyCore's `Sources/CAstronomy/VENDORED.md`).

Regenerate only after an intentional planner or Worker change, and say why in the
commit message:

```bash
UPDATE_GOLDEN=1 npx vitest run app/tests/golden-vectors.test.ts
UPDATE_GOLDEN=1 npx vitest run app/tests/sky-events-golden.test.ts   # also after editing config/sky-events.json
(cd worker && UPDATE_GOLDEN=1 npx vitest run test/golden-response.test.ts)
```
