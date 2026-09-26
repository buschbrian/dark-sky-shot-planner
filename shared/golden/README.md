# Golden vectors

Numbers every implementation of the planner must reproduce, within the
tolerances stored in each file. The TypeScript planner is the reference
(ADR-0009 §3).

| File | Written by | Read by |
|---|---|---|
| `night-report.json` | `app/tests/golden-vectors.test.ts` | that test, and SkyCore's parity tests (`ios/Packages/SkyCore`) |

Regenerate only after an intentional planner change, and say why in the
commit message:

```bash
UPDATE_GOLDEN=1 npx vitest run app/tests/golden-vectors.test.ts
```
