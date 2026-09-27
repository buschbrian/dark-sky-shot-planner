# Any astrophotography: owner decisions

**All nine decisions below (D1–D9) are recorded, dated 2026-09-27.** ADR-0013
is Accepted on the strength of them. This file is kept as the record of each
call, its options and its recommendation — not as an open question list.

## D1. Bundle OpenNGC (CC BY-SA 4.0)?

**Decided 2026-09-27:** Yes: bundle OpenNGC as its own separately licensed data file, with attribution (owner).

OpenNGC supplies sizes, magnitudes and common names for NGC and IC objects,
including most of Messier and Caldwell (planning.md §1.3, §1.8). The
share-alike clause attaches to the derived data file, not to the app code.
Anyone may then redistribute that file under CC BY-SA 4.0.

- **a.** Bundle one catalog file under CC BY-SA 4.0 in full, with
  attribution on the credits screen and in `docs/data-licensing.md`.
- **b.** Avoid OpenNGC. Hand-curate positions, which are facts, and take
  sizes and magnitudes from SIMBAD or NED. Their terms for a distributed
  app are unverified (planning.md §1.8).
- **c.** Ship Messier only, which is public domain, and defer everything
  else.

**Recommendation: a.** It is the simplest licensing posture the research
found, and the share-alike obligation stays limited to one data file.

## D2. Include solar at all?

**Decided 2026-09-27:** Exclude solar for now (owner).

The research covers safety: front-mounted, ISO 12312-2 filters, never at
the eyepiece (gear.md §6). It sourced no filter products and no solar
planning data. Solar work also happens in daylight, which the app's
night-first design does not cover.

- **a.** Exclude solar from M13–M19.
- **b.** A safety-gated planning profile only, covering sun position and
  eclipse or transit timing, with a mandatory acknowledgement and no gear
  advice.
- **c.** A full solar profile.

**Recommendation: a.** Revisit it with b, once a sourced filter list and a
safety review exist.

## D3. Smart-telescope control through community bridges?

**Decided 2026-09-27:** "Copy coordinates" always, plus an opt-in ASCOM Alpaca client that talks to a bridge the owner runs; never reverse-engineered protocols or linked community code (owner).

No manufacturer publishes an API (gear.md §1). seestar_alp exposes Alpaca
for the Seestar, and dwarfAlp does for DWARF, with its license unverified.
Both are unofficial and carry no stability guarantee (apps.md §2).

- **a.** Copy coordinates only: works for every brand and needs nothing to
  run.
- **b.** Option a, plus an opt-in Alpaca client that talks to a bridge the
  owner runs (M17).
- **c.** Option b, plus direct reverse-engineered protocols inside the app.

**Recommendation: b, and never c** (ASIAIR raises a ToS concern; apps.md
§2). This decision also needs the device M17 will be tested against, if the
owner has one.

## D4. Tab structure

**Decided 2026-09-27:** Profile switch at the top of Tonight; no sixth tab (recommendation, accepted by default).

The app has five tabs: Tonight, Map, Sky, Spots and Tools. The 2026-09-27
review warns about conditionally hidden tabs on iOS 27 (§A #15).

- **a.** A profile switch at the top of Tonight, persisted, with the
  target browser opening from Tonight.
- **b.** A sixth "Targets" tab.
- **c.** A profile setting that re-labels the existing tabs.

**Recommendation: a.** It keeps one answer-first screen, adds no tab, and
leaves nightscape as the default view. Revisit b only if the target browser
proves to be a destination in its own right.

## D5. How many targets to bundle

**Decided 2026-09-27:** About 200 targets now; about 300 once VizieR terms are verified (recommendation, accepted by default).

The research proposes 150–300, with about 200 as the target, all well
under 1 MB (planning.md §1.9, §7.2).

- **a.** 110: Messier only.
- **b.** About 200: Messier, 60–80 Caldwell, and NGC/IC narrowband
  favourites.
- **c.** 300, adding Sharpless, Abell and Arp once their VizieR terms are
  verified (§1.4–1.7).

**Recommendation: b now, c later.** Option c waits on a licensing check,
not on code.

## D6. Does the web app get the same profiles?

**Decided 2026-09-27:** Web app gets the numbers via shared golden vectors, not the UI yet (recommendation, accepted by default).

The web app is the reference implementation for the astronomy, and
`shared/golden/` is the numbers contract (ADR-0009 §3). It does not read
`conditions-thresholds.json` today. Only iOS computes a verdict.

- **a.** iOS only. The new math is SkyCore-only and outside the golden
  contract.
- **b.** The web ports the numbers (target windows, the Lorentzian, FOV,
  opposition) with golden vectors, but gets no profile UI yet.
- **c.** Full parity, with profiles and a target list on the web.

**Recommendation: b.** It keeps the "numbers match" invariant honest for
everything new, without building two UIs at once.

## D7. Transparency as a deep-sky gate

**Decided 2026-09-27:** Yes: transparency gates deep-sky only, and only when data exists; nightscapes stay advisory (owner).

On 2026-09-26 the owner made transparency advisory, because its only
source, 7Timer, is optional and non-commercial. The research proposes a
`when_available` gate for deep sky only: it gates when present and never
caps the night when missing (planning.md §5.4, departure 1).

- **a.** Keep transparency advisory everywhere. AOD and the smoke column
  carry deep-sky haze.
- **b.** Use the `when_available` gate for the deep-sky profiles.

**Recommendation: b**, but only for personal use. A distributed build must
drop 7Timer or get permission (PLAN.md §Data sources), and then the gate
falls back to AOD and smoke.

## D8. The seeing source for lunar and planetary

**Decided 2026-09-27:** Jet-stream (250 hPa) seeing gates lunar/planetary; 7Timer advisory (recommendation, accepted by default).

- **a.** Gate on the jet-stream proxy (`wind_speed_250hpa`: 111 and 185 km/h
  edges, from 60 and 100 kt; planning.md §5.1). This source is license-clean.
- **b.** Gate on 7Timer seeing, which is non-commercial and optional.

**Recommendation: a.** Show 7Timer seeing as an advisory beside it.

## D9. When to start

**Decided 2026-09-27:** Start after the review fixes (B-2, B-3, B-4, B-5, B-8) land (recommendation, accepted by default).

- **a.** Fix review items B-2 to B-5, P2 #4 and B-8 first, then M13
  (`PLAN-ANY-ASTRO.md` §Before M13).
- **b.** Start M13 in parallel on a separate branch.

**Recommendation: a.** M13 builds directly on the shot window and the verdict
that those findings change.
