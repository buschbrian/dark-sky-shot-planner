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

## Smoke forecast units (NWS NDGD ImageServer)

**The source is RAP-Smoke, not HRRR-Smoke.** The NWS NDGD ImageServers
`air_quality/ndgd_smoke_vert_1hr_avg_time` and
`air_quality/ndgd_smoke_sfc_1hr_avg_time` serve the RAP 03Z-run smoke
forecast (NWS SCN 22-42, effective 2022-06-28): 13 km model, regridded to the
5.079 km NDGD grid, drawn as 2.66 km Web Mercator pixels. One issue a day,
ingested about 04:25Z, covering 03Z Day 1 to 06Z Day 3. Values are
**instantaneous** at the start of each hourly slice, despite "1hr_avg" in the
name. The services' unit text is left over from the retired HYSPLIT product
and is wrong.

| Layer | Raw unit | Shown unit | Conversion |
|---|---|---|---|
| `…_vert_…` (column-integrated mass density, RAP `COLMD`) | kg/m² | mg/m² | × 1e6 |
| `…_sfc_…` (mass density at 8 m AGL, RAP `MASSDEN`) | kg/m³ | µg/m³ | × 1e9 |

Smoke AOD at 550 nm ≈ 0.0045 × column (mg/m²), the model's fixed 4.5 m²/g
mass extinction (Ye et al. 2021); it reproduces RAP/HRRR `AOTK` exactly.

**Evidence** (fetched 2026-09-25, NDGD issue 2026-09-25 03Z). The NDGD GRIB2
files (`tgftp.nws.noaa.gov/…/DC.ndgd/GT.aq/AR.conus/ds.smoke{c,s}01.bin`) are
coded discipline 0, category 20, parameter 1 (kg m⁻²) and 0 (kg m⁻³ at 8 m),
generating process 105 (RAP), product template 4.0 (instantaneous). Against
raw RAP 03Z from `noaa-rap-pds`, the median NDGD/RAP ratio over 20,000 CONUS
cells is 1.000 for both layers (r = 0.88–0.99). Point pairs, in converted
units, with `identify` at slice start + 30 min:

| Layer | Point | Valid (UTC) | identify | NDGD GRIB2 | RAP 03Z | HRRR 00Z |
|---|---|---|---|---|---|---|
| column (mg/m²) | Sierra fire cell, CA (38.28, −119.69) | 09-25 03Z | 209 | 209 | 220 | 166 |
| column | Hawthorne, NV (38.42, −118.40) | 09-26 03Z | 105 | 106 | 109 | 74.7 |
| column | Great Basin NP (39.005, −114.22) | 09-26 03Z | 1.03 | 1.07 | 1.14 | 1.03 |
| column | Millcreek, UT (40.69, −111.83) | 09-25 03Z | 2.47 | 2.47 | 2.57 | 3.64 |
| surface (µg/m³) | Hawthorne, NV | 09-26 03Z | 38.2 | 36.8 | 33.9 | 36.2 |
| surface | Sierra fire cell | 09-26 06Z | 27.3 | 27.3 | 30.1 | 19.6 |
| surface | Great Basin NP | 09-26 03Z | 0.28 | 0.28 | 0.28 | 0.32 |

Median identify/RAP ratio across 16 pairs per layer: 0.96 (column), 0.99
(surface). The spread comes from regridding and from `identify` returning a
neighbouring 5 km cell (nearest-neighbour). HRRR is a different model and
confirms the scale only.

**Query rules.** Pass `time` = slice start + 30 min (slice ends are inclusive,
so an on-the-hour time returns the previous hour). Never omit `time`: the
service then returns every slice. `value` is a string. There is no NoData
value; outside the domain `identify` returns 0, which must be treated as
unavailable, not clean air.

The Worker makes one `identify` per layer with `time` set to the whole
request window (start and end in epoch ms). It reads `properties.Values` in
the order of `catalogItems`, keeps `idp_subset = conus` items only, and keys
each value by `idp_validtime`, keeping the newest issue per hour. Checked
2026-09-25 against per-slice calls at slice start + 30 min: 14/14 equal.
Cells outside a conservative lower-48 box (24–50° N, 125–66° W) are answered
as unavailable without a request, because of the 0-for-NoData rule above.

**Thresholds** (set 2026-09-26 in `config/conditions-thresholds.json`). The
smoke column gates the verdict: good ≤ 10, marginal ≤ 40 mg/m², worst hour in
the window. With a summer background AOD of about 0.05, those edges match the
AOD factor's 0.10 and 0.25. At Galactic Center culmination from Utah
(airmass 2.6–2.9, loss Δm = 1.086·τ·X), AOD 0.10 costs about 0.4 stop of
Milky Way signal and 0.25 about one stop. Near-surface smoke is an advisory
only: valley inversions trap smoke under a clear sky, and smoke aloft dims
the sky over clean surface air.

Sources: [NWS SCN 22-42](https://www.weather.gov/media/notification/pdf2/scn22-42_hysplit_smoke_model_change_aaa.pdf),
[NCEP ON388 Table A](https://www.nco.ncep.noaa.gov/pmb/docs/on388/tablea.html),
[Ye et al. 2021](https://acp.copernicus.org/articles/21/14427/2021/).

## Freshness

Every layer's manifest carries a publication date; one uniform convention
(fresh / aging / stale / unavailable; ADR-0006) turns that date into the
status shown next to each number. Failed feeds show last known good values
with their age, never blanks.
