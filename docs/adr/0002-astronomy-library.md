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

> **Amendment 2026-09-25 (refraction and frame conventions):** fixed-star
> positions (the GC) are precessed from J2000 to the true equator of date
> (`Rotation_EQJ_EQD`) before `Horizon()`, which expects of-date coordinates.
> Astronomical darkness is the sun's centre at a geometric −18°, the standard
> twilight definition and what `SearchAltitude` computes. Moonrise and moonset
> are the top limb with standard refraction (`SearchRiseSet`), the moment the
> moon's light enters or leaves the sky. GC altitude, its peak, the 12°
> threshold, and SkyCore's GC rise/set are geometric (no refraction), kept
> deliberately: at 12–25° refraction lifts the GC only 0.04–0.08°, below the
> 0.1° display precision and far inside the threshold's own slack (it is a
> haze heuristic, not an optical limit), so refracting it would churn the
> golden files for no visible change. Anything drawn where the camera sees it
> (the iOS AR overlay) uses apparent, refracted positions. The moon-up state
> that seeds `moonUpIntervals` follows the rise/set rule too: up iff the most
> recent `SearchRiseSet` event was a rise. Fixed 2026-09-25; it used the
> refracted centre above 0°, so a seed in the ~1.5 minutes between the two
> while the moon was rising (about 0.1% of nights) missed a moon-up interval.
