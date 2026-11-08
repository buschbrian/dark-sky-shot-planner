# ADR-0011: Patch mapping, test tooling, and HTTPS trust dependencies

**Status:** accepted · **Date:** 2026-11-08

## Decision

Use MapLibre GL JS 6.16.0, Vite 6.4.5, Vitest 5.0.5, and certifi 2026.10.19
to remove the affected dependency versions identified by the five critical
dependency alerts. Vitest 5 no longer depends on Tinypool; the latter must
remain absent from this lock rather than be forced to an unsupported major
through an override.

Use MapLibre's named exports and import its module worker as a Vite `?url`
asset. Register that URL before creating the map. This emits a versioned worker
beside the application assets and respects the configured Pages base path.
The library's inferred sibling-worker URL is not a supported Vite deployment:
it produced worker 404s in development and no emitted worker in the build.

## Compatibility and verification

MapLibre 6 requires WebGL2. The text-first interface remains usable when the
map cannot initialize; astronomy, keyboard controls, and URL state must not
depend on a map. The project already targets ES2022 and CI Node 22.23.4 meets
the new test-tooling engine requirement. Explicit Node types replace a
transitive type inclusion on which the older Vitest setup happened to rely.

Browser tests select system Chromium through the documented executable-path
variable. The new runtime checks verify worker/PMTiles loading without console
or page errors, including under the production Pages prefix, and preserve the
answer when WebGL is unavailable. The fixture pipelines and existing PMTiles
format are unchanged. No generated data, source licenses, astronomy method,
publication gate, or live dataset changes are part of this decision.

## Evidence and limits

- [MapLibre sanitizer advisory](https://github.com/maplibre/maplibre-gl-js/security/advisories/GHSA-jrc7-96c5-q579)
- [MapLibre 6 migration notes](https://github.com/maplibre/maplibre-gl-js/releases/tag/v6.0.0)
- [Vitest migration guidance](https://vitest.dev/guide/migration/)

The application disables attribution controls and has no popup HTML sink;
this fix removes the affected library version without asserting that the
current interface exposed a working exploit. Version/audit checks establish
dependency remediation, while browser checks establish integration behavior.
Neither deploys the site or proves untested device/GPU combinations.
