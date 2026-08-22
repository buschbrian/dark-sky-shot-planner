# Methods: how every displayed number is computed

Written for a skeptical reader. No claims beyond what the math supports.

## Moon-free astronomical darkness (the headline number)

1. **Astronomical darkness window.** We find the two instants when the sun's
   *topocentric* altitude crosses −18°: descending in the evening, ascending
   in the morning (`astronomy-engine`, `SearchAltitude` on an observer at the
   location, sea level). Below −18°, sunlight contributes negligibly to sky
   brightness — this is the standard definition of astronomical night.
   If no crossing occurs (high latitude around summer solstice), we say "no
   astronomical darkness on this date at this location" and stop.
2. **Moon-below-horizon windows.** Moonrise and moonset are topocentric
   apparent-rise/set events including refraction (`SearchRiseSet`). We build
   every moon-up interval overlapping the dark window from a state probe 12 h
   before dusk.
3. **Intersection.** Moon-free darkness = dark window minus moon-up time,
   computed as explicit sub-intervals. The headline minutes are the length of
   that intersection; if the moon splits the night, each piece is listed.

Accuracy follows `astronomy-engine` (~1′ for sun/moon positions), which is
minutes-level in window boundaries — well inside photographic relevance.

## Galactic Center visibility

The Galactic Center (Sgr A*) is treated as a fixed star at RA 17h45m40.04s,
Dec −29°00′28.1″. Altitude/azimuth across each moon-free window are sampled
every 5 minutes; the reported peak is the maximum sample (±2–3 arcmin
positionally, ±~3 minutes temporally). **Usability threshold:** peaks below
the configured minimum (default 12°) are labeled not usefully photographable:
at low altitude you look through more atmosphere and extinction dims Sgr A*
severely. The threshold is configurable because it is a judgment, not physics.

If the GC never climbs above the horizon during darkness (roughly November–
February at Mountain West latitudes), the app says so plainly.

## Moon illumination

`Illumination(Moon)` phase fraction at the midpoint of the moon-free peak
window. Displayed as a percentage; it contextualizes the headline number but
is never itself the answer.

## Sky brightness ("how dark is this spot?")

A downsampled VIIRS VNP46A4 radiance grid (0.25° cells, nearest-neighbor)
published by the light-pollution pipeline is sampled at your point and mapped
to a label via the same breakpoints that color the tiles (ADR-0005).
**This is an annual composite average** — the label shows the source year so
staleness is visible. It cannot see clouds, fireworks, or last month's new
subdivision.

## Land manager

PAD-US polygons normalized to eight manager classes (ADR-0004). The name
shown is who manages the land per PAD-US — it is a boundary dataset, not a
permission system. Access rules, hours, and permits come from the managing
agency; the UI links to them rather than asserting anything.

## Cloud forecast

Open-Meteo hourly total cloud cover for the point, averaged over the
moon-free window(s). Fetched live in your browser with no key; carries its
own attribution and model-run freshness in the provenance panel.

## Freshness

Every layer's manifest carries a publication date; one uniform convention
(fresh / aging / stale / unavailable; ADR-0006) turns that date into the
status shown next to each number. Failed feeds show last known good values
with their age, never blanks.
