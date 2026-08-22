# ADR-0002: astronomy-engine for all client-side ephemeris

**Status:** accepted · **Date:** 2026-08-22

## Decision

All sun/moon/Galactic-Center math uses
[`astronomy-engine`](https://github.com/cosinekitty/astronomy) (MIT), running
entirely in the browser. No astronomy API is called, ever.

## Alternatives considered

- **SunCalc** — tiny and popular, but its moon position error (tens of arcminutes
  at times) and lack of topocentric correction make it unsuitable for
  minute-level darkness windows and Galactic Center altitude work.
- **Server-side computation** — violates the zero-server architecture.

## Reasoning

`astronomy-engine` implements VSOP87/ELP-derived theory with accuracy of
about one arcminute, supports topocentric (observer-relative) positions,
and exposes the exact primitives we need (`SearchAltitude`, `SearchRiseSet`,
`Illumination`, fixed-RA/Dec horizon conversion for the GC).

## Consequences

~100 kB of astronomy code ships to the client; acceptable against the value
of full offline correctness. Unit tests pin known ephemeris results and edge
cases (summer solstice at 49°N, new/full moon splits).
