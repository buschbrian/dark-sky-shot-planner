# ADR-0008: Sky events — computed vs. curated, and the visibility rule

**Status:** accepted · **Date:** 2026-09-06

## Context

The app answers one question about one night. Users also want the next
question: *what else is happening in the sky around this date, from here?* —
the thing a monthly almanac gives you, except an almanac is written for a
generic mid-northern observer and gets the interesting parts wrong for a
specific spot.

Some of that is derivable from ephemeris. Some of it is not: a meteor
shower's radiant and active dates, a park's festival weekend, a comet's
discovery. Those come from human sources.

## Decision

### 1. Computed and curated are separate, and the boundary is "is it derivable?"

**Computed** (`app/src/astronomy/events.ts`, astronomy-engine only, pure
functions over a location and a `±30`-day window):

- Moon quarter phases (`SearchMoonPhase` 0/90/180/270).
- Oppositions of Mars/Jupiter/Saturn (`SearchRelativeLongitude(body, 0)`) and
  greatest elongations of Mercury/Venus (`SearchMaxElongation`), labelled
  morning or evening.
- Moon–planet pairings, one per lunar pass, with an occultation test.
- Zodiacal-light windows.
- Equinoxes and solstices (`Seasons`).

**Curated** (`config/sky-events.json`): id, name, kind
(`meteor_shower` | `festival` | `comet` | `other`), `active_from`,
`active_to`, `peak_utc`, `zhr`, radiant RA/Dec, `location`, `notes`,
`source_url`, `verified_on`.

Nothing that can be computed is stored, and nothing stored is a computed
result. A curated row never contains a "best viewing time": that is a
function of where the reader is standing, and the app computes it.

### 2. The curated file follows the dark-sky-places contract

Same rules as `config/darksky-places.csv`, for the same reasons:

- **Every row carries `source_url` and `verified_on`.** A row whose fact could
  not be confirmed carries `verified_on: null` and is rendered
  "curated — unverified", not silently trusted. The 2026 Leonid and Geminid
  peak dates ship that way.
- **No scraping.** The cited pages are read by a human and the fact is typed
  in. In-The-Sky, EarthSky, arXiv and NPS pages are cited, never fetched by
  the app or by a pipeline.
- **Peak times are UTC**, always, with an explicit `Z`. Local time is a
  rendering concern; a stored local time is a bug waiting for a timezone.
- **Malformed rows are dropped and reported**, never thrown. A typo in a
  curated list must not cost the user the computed events.

The file is bundled at build time rather than published through a pipeline
into `data/out/`: it is small, it is versioned next to the code that reads
it, it needs no build step to exist, and — unlike the map layers — it has no
tiling or clipping stage that would justify one.

### 3. Visibility rule: a radiant must clear 10° during darkness at the observer

A meteor shower is listed with a full verdict only when its radiant rises
above **10°** during astronomical darkness at the selected location. Below
that the airmass and any real foreground swallow the rate, and quoting a ZHR
would be a lie. Showers that fail the test are still listed, labelled
"below horizon here" — hiding them invites the user to go looking elsewhere
for a shower that is not visible from Utah at all.

For each shower the app computes, at the observer: the radiant window inside
darkness, the peak altitude and its time, the Moon's illuminated fraction and
which part of the radiant window it spoils, and — when a night inside the
active range beats the peak night by more than half an hour of moonless
radiant time — that better night.

### 4. Two separations, deliberately

*Amended 2026-09-24 (PR #6 review): the printed separation is topocentric, the
occultation trigger is 1.3°, and pairings are found per lunar pass.*

Moon–planet pairings are **found** geocentrically and **reported**
topocentrically. An hourly geocentric scan splits the window into lunar passes
(one per planet per ~month, so a ±30-day window can hold two); within each
pass the app reports the closest *observable* approach and prints the
separation seen from the observer at that instant. Printing the geocentric
minimum next to a local clock time was wrong by up to a degree — lunar
parallax — which is exactly the scale of a close pairing. The geocentric
minimum of the same pass is kept on the result for reference.

The occultation test is **topocentric** and bound to the same pass. A
geocentric minimum below **1.3°** (lunar semidiameter plus horizontal
parallax) runs it; anything wider cannot occult from anywhere on Earth. The
app then computes the topocentric minimum at the observer, compares it to the
Moon's actual angular radius at that instant, and says whether it happens
here, when it ends, how high the Moon is, and whether it is in daylight — a
reappearance with the Moon 1° up needs a flat eastern horizon, and saying so
is the useful part. A geocentric minimum below 0.27° (the Moon's mean
semidiameter) means an occultation somewhere on Earth; when it misses from
here, the app says so.

A pairing is offered as something to go and watch only when both bodies are
above 5°, the topocentric separation is under 5°, and the Sun is below −6° at
the observer.

### 5. Zodiacal light is seasonal and northern-hemisphere only

Checked one hour before astronomical dawn in the **autumn morning** season
(Aug–Nov) and one hour after astronomical dusk in the **spring evening**
season (Feb–Apr), on the northern-hemisphere calendar. A night qualifies when
the Moon is down or under 15% lit; consecutive nights collapse into ranges.
South of the equator the function returns nothing rather than invert the
months on a guess — the AOI is the U.S. Mountain West.

## Alternatives considered

- **Fetch an events API.** Rejected: violates the zero-server, no-astronomy-API
  architecture (ADR-0002), and would put a network dependency in front of the
  one part of the app that works offline.
- **Scrape a meteor-shower calendar.** Rejected for the same reason we do not
  scrape DarkSky International: no license to redistribute, and a scraper is a
  silent liability the moment the page changes.
- **Store per-shower "best viewing times".** Rejected: wrong for every observer
  but the author, and it is exactly the computation this app exists to do.
- **A pipeline that publishes the curated file into `data/out/`.** Rejected as
  ceremony: no clipping, no tiling, no external fetch — nothing a pipeline
  would add except a build step that can fail.

## Consequences

- The curated file needs re-verification. `verified_on` is the freshness
  signal and it is shown next to every curated line; the 2026 rows are dated
  events and go stale on purpose.
- The `±30`-day sweep costs roughly 0.2 s of ephemeris per render. It runs
  after the headline answer is already on screen, so the number the user came
  for is never held up by it.
- Adding a shower means adding a row and a source URL, not writing code.
- A curated event can peak outside the window while already running inside it
  (the Taurids, most of the autumn). Those are listed, dated by their peak,
  with the active range spelled out in the verdict.
