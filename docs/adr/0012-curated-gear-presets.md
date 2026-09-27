# ADR-0012: Curated gear presets

**Status:** accepted · **Date:** 2026-09-27

## Context

PLAN.md M10 said gear profiles are "entered by the owner, not scraped".
The exposure tools (NPF, 500 rule, trail length, hyperfocal) need a
camera's sensor size, resolution and pixel pitch and a lens's focal length
and maximum aperture, and typing those in is where mistakes happen. The
iPhone's own camera is also a gear profile (ADR-0011 §4), and Apple
publishes neither its sensor size, pixel pitch nor real focal lengths.

The owner asked for a full reference of the popular iPhone, full-frame and
APS-C astro cameras and their lenses. Research on 2026-09-27
(`docs/gear/research/`) produced cited rows for all of them, and the owner's
own iPhone 18 Pro Max was measured (`docs/ios/CAPTURE-LIMITS.md`).

## Decision

Ship curated, cited presets in `config/gear-presets.json`, bundled into
SkyCore by `ios/scripts/sync-shared.sh` and read by `GearPresets`. They are
a starting point, not a replacement for owner entry:

1. **Presets seed, the owner edits.** Picking a preset fills a
   `CameraProfile` or `LensProfile`; every value stays editable and the
   saved profile is the owner's. M10's "entered by the owner" still holds
   for what is saved.
2. **Researched, never fetched.** The file is compiled by hand from cited
   research and committed. The app never scrapes or downloads gear data at
   runtime, the same rule as `darksky-places.csv` and `sky-events.json`.
3. **Curation rules for every row:**
   - a `source_url` (a spec page, a named review, or a repo file for the
     owner's own measurements) and a `verified_on` date;
   - a `value_basis` note, plus labelled bases for the numbers that are not
     printed by a maker: `sensor_size_basis`, `pixel_pitch_basis`,
     `focal_length_basis` (measured, stated or derived, with the method);
   - measured beats stated beats derived. For iPhones, EXIF from the owner's
     phone wins; sensor millimetres are stated pitch × pixels, and the
     approximate optical-format conversion is kept beside it, labelled
     `optical-format estimate`;
   - nothing is dropped silently: a research row that cannot become a valid
     profile goes in `excluded` with the reason, and a changed id goes in
     `renamed`;
   - iPhone camera modules pair with their built-in lens through
     `pairs_with`; interchangeable bodies and lenses match by mount.
4. **Refresh cadence.** Re-check every `source_url` at least once a year, and
   the iPhone rows each September when new iPhones ship. Update
   `verified_on` only for rows actually re-checked. SkyCore tests fail if a
   row lacks a source or date, if stated pitch and sensor ÷ pixels disagree
   by more than 5 % (unless labelled an estimate), if ids collide or pairs do
   not resolve, or if the iPhone 18 Pro Max main preset stops reproducing the
   8.6 s NPF recorded in CAPTURE-LIMITS.md.
5. **The Tools UI picker comes after the design merge.** A separate branch
   is restyling Tools and Gear; the preset picker is built on top of that
   work, not alongside it. Until then the presets are data and SkyCore API
   only.

The readable companion is `docs/gear/GEAR-REFERENCE.md`, compiled from the
same research, with every row linked to its source and a dated appendix of
uncertain values.

## Consequences

- Gear numbers now have a maintenance cost: stale rows are possible, so each
  shows its `verified_on` date and basis wherever the UI shows a preset
  (ADR-0006's rule that every displayed number carries source and freshness).
- Derived iPhone values (most real focal lengths, binned pitches) are
  labelled as derived until an EXIF read replaces them; the reference's
  appendix lists how to settle each one.
- Adding a camera means a cited row and a passing `swift test`, not a code
  change.

## Alternatives considered

- **Keep owner entry only.** The owner asked for presets instead: owner-only entry pushes spec lookup and
  the pitch arithmetic onto every user.
- **Fetch from a spec database at runtime.** Rejected: licensing is unclear,
  it breaks offline-first, and it would bring back scraping.
