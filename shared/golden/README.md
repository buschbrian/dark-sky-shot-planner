# Golden vectors

Numbers every implementation of the planner must reproduce, within the
tolerances stored in each file. The TypeScript planner is the reference
(ADR-0009 §3).

| File | Written by | Read by |
|---|---|---|
| `night-report.json` | `app/tests/golden-vectors.test.ts` | that test, and SkyCore's parity tests (`ios/Packages/SkyCore`) |
| `gc-horizon.json` | `app/tests/golden-vectors.test.ts` (`gcAltitude`/`gcAzimuth`) | that test, and SkyCore's GC alt/az spot checks |
| `conditions-response.json`, `space-weather-response.json` | `worker/test/golden-response.test.ts`: real Worker output built offline from its recorded fixtures (AirNow rows are the synthetic fixture) | that test (drift check), and SkyCore's `WorkerContractTests` and verdict tests |

The two astronomy files record `astronomy_engine`, the npm version that wrote it. Both
suites fail if it differs from the version they run (npm's
`node_modules/astronomy-engine`, SkyCore's `Sources/CAstronomy/VENDORED.md`).

Regenerate only after an intentional planner or Worker change, and say why in the
commit message:

```bash
UPDATE_GOLDEN=1 npx vitest run app/tests/golden-vectors.test.ts
(cd worker && UPDATE_GOLDEN=1 npx vitest run test/golden-response.test.ts)
```
