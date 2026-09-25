# ADR-0010: One stateless Cloudflare Worker for live conditions

**Status:** accepted · **Date:** 2026-09-25

## Context

The brief required zero server: static site, keyless client-side fetches,
no per-user state anywhere. That held while the only live feed was one
Open-Meteo cloud-cover call. The field companion (ADR-0009) needs more:
cloud layers from more than one model, smoke and aerosol data, air quality,
seeing and transparency, and space weather. Some of those sources need an API
key (EPA AirNow). Some have no CORS for the web app (7Timer). Some return raw
grids that need clipping and unit conversion (the SWPC aurora grid is about
1 MB; HRRR-Smoke values need calibrating). Model run times live on a separate
metadata endpoint (Open-Meteo). And fanning out to six hosts from a phone on
one bar of LTE at 9 p.m. is slow and fragile.

## Decision

Add **one Cloudflare Worker** (`worker/`, TypeScript) that aggregates and
normalizes live conditions for a point and time range. It runs the same way
the owner's Blaumeux dashboard Worker does: Workers Builds deploys, gated on
the repo's verify step.

The Worker is **stateless with respect to users**, which is the part of
"zero server" that actually mattered:

1. **No per-user data.** No accounts, no saved spots, no device tokens, no
   request logging beyond Cloudflare's platform defaults. Saved plans live
   on the phone and in the owner's iCloud (ADR-0009 §4).
2. **Coordinates are rounded before they leave the phone** (to 0.05°, about
   5 km, which is finer than any source it queries). Photographers guard their
   spots, and a precise lat/lon has no business in a weather request.
3. **Keys live in Worker secrets only.** The repo stays credential-free and
   CI stays keyless: Worker tests run against recorded fixtures, as the
   pipelines do (AGENTS.md invariants 2 and 4).
4. **Caching is by rounded cell and model run**, using the Workers Cache API
   (and KV only for slow global products such as space weather). No data
   outlives its source's freshness window.
5. **Every value keeps its provenance.** Each field in the response carries
   `source`, `model` (where there is one), `model_run_utc` (where published),
   and `fetched_utc`, so the client can apply ADR-0006 freshness unchanged.
   The Worker normalizes units and shapes. It never averages sources
   together silently. Disagreement between models is shown, not hidden.
6. **Clients degrade, never depend.** If the Worker is down, iOS and web fall
   back to direct keyless calls where one exists (Open-Meteo), otherwise show
   the last known value with its age. The astronomy never touches the Worker.

### Push alerts are *not* in this decision

"Notify me when Saturday turns good" would need device tokens and saved
plans on the server, which breaks point 1. v1 uses on-device background
refresh plus local notifications (ADR-0009), and says in the UI when it
last checked. Apple documents `BGAppRefreshTask` as opportunistic: it only
has an earliest start time, it depends on usage patterns, and it never runs
for a force-quit app. So this is expected to be the first thing to fall
short. When it does, server push (Worker cron + APNs) gets its own ADR that
has to justify the state it adds. The smallest version holds one device token
and the rounded cells of the saved spots, and nothing else.

## Alternatives considered

- **Stay strictly zero-server.** Keyless CORS sources cover clouds, AOD/PM2.5,
  HMS and HRRR smoke, and space weather. They don't cover AirNow (keyed), 7Timer
  (no CORS), model run times without a second call per model, or a single fast
  request from the field.
- **A GitHub Actions pipeline for everything.** Right for slow products (the
  light-pollution annual composite already works this way), wrong for data
  that changes hourly.
- **A conventional backend with a database.** Buys alerts at the cost of
  holding users' locations. Not worth it for one user.

## Consequences

- The brief's §3 "zero server" becomes "zero *stateful* server." The static
  site still deploys and works with the Worker absent.
- There is now something that can go down, so the Worker has a `/health`
  endpoint and the clients show when it is unreachable (as "unavailable"
  under ADR-0006, never as a blank).
- Each new upstream source gets a row in `docs/data-licensing.md` before any
  code fetches it, including whether its terms allow use in a distributed app.
