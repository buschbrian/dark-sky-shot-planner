# ADR-0005: Radiance-to-display mapping

**Status:** accepted · **Date:** 2026-08-22

## Decision

VNP46A4 radiance (nW/cm²/sr) is mapped to display colors by a piecewise-
linear ramp over six breakpoints (0 → 0.25 → 1 → 5 → 20 → 60 nW/cm²/sr),
stored in `config/app-config.json`. The raster tiles, the legend, and the
text label for a sampled point are all generated from this single source of
truth.

## Alternatives considered

- **Falchi 2016 atlas classes** — forbidden; see data-licensing.md.
- **Perceptual (log/cube-root) mapping** — smoother, but the breakpoints
  chosen already span two orders of magnitude and categorical labels
  ("Pristine dark sky" vs "Urban core") communicate better to a photographer
  deciding whether to drive.

## Consequences

Breakpoints are a judgment call, tunable without touching code. Because the
mapping is shared, a legend/tile mismatch is structurally impossible. The
low-res grid shipped for point lookups carries the same year label as the
tiles so staleness is always visible.
