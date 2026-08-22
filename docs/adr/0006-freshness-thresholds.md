# ADR-0006: Freshness thresholds

**Status:** accepted · **Date:** 2026-08-22

## Decision

One freshness convention applies to every layer: **fresh**, **aging**,
**stale**, **unavailable**, with per-layer day thresholds in
`config/app-config.json` under `freshness_days`. The client mirrors the
pipeline logic (`app/src/freshness.ts`) and renders age next to every number.
A failed feed shows the last known good value with its age — never a blank.

## Alternatives considered

- **Per-layer ad-hoc wording** — drifts, and teaches users nothing transferable
  between layers.
- **Hiding stale data** — dishonest; a 2024 light-pollution composite shown in
  2026 is two years old and the user must see that.

## Consequences

Thresholds are annual-composite-paced for light pollution (fresh < ~13
months), PAD-US update-cycle-paced (~6.5 months), curated-list-paced (90
days) for dark-sky places, and hours-scale for weather. Changing a threshold
is a config edit plus one test update, not a code hunt.
