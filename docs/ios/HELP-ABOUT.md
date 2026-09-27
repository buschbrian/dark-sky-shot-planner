# In-app Help/About content spec

What the app's Help/About destination should contain. This is a content
spec for the app team, not the page itself: `ios/App/About/AboutScreen.swift`
currently holds only the disabled iCloud sync toggle (`SyncSection`), pushed
from the bottom of Tools. The 2026-09-27 product review (§10) calls this "a
disabled iCloud setting plus developer setup requirements" and asks for a
real Help/About destination instead.

## Sections, in order

1. **App version.** Marketing version + build number (`CFBundleShortVersionString`
   / `CFBundleVersion`), and which Worker the app is pointed at (from
   `Local.xcconfig` today — surface it read-only, never editable here). Useful
   for the owner to match a field report to a build, the way `docs/ios/PLAN.md`
   §Log already records build revisions.

2. **First-outing guide.** The content of `docs/ios/FIRST-OUTING.md`,
   rendered in-app rather than linked out, since there's no signal at a dark
   site to fetch it. Keep it in sync with that file — copy source, not a
   second hand-written version.

3. **Glossary.** The content of `docs/ios/GLOSSARY.md` as a searchable or
   alphabetical list, each term expandable. This is what "tap-to-explain"
   throughout the app should point at — a term like "moon-free minutes" or
   "transparency" inline on Tonight should link here, not repeat its own
   explanation.

4. **Data status.** What's real vs. sample/fixture right now, in plain
   language — not a repeat of the on-map provenance badges, but the same
   facts gathered in one place: light pollution and land-ownership (PAD-US)
   map layers are sample fixtures until `data-refresh.yml` runs with a real
   token (README "What the site shows"; product review §4); which Worker
   endpoints are healthy (`/health`); when each was last checked. Read
   `data-status.json` and the Worker's `/health` live where possible; state
   plainly when a check itself is stale or unreachable, the same freshness
   convention the rest of the app uses (ADR-0006).

5. **Storage used.** How much space Dark Sky is using on the phone, broken
   into roughly what a user would recognize: offline map areas (from
   `OfflineAreas`, which already tracks a byte estimate per saved area —
   `ios/App/Map/MapOffline.swift`), and saved captures (frames + stacks
   under Files → On My iPhone → Dark Sky → Captures). This does not exist
   today; it needs a small aggregation pass over both stores. A "Manage
   captures" or "Manage offline areas" action from here would close a real
   gap — nothing today lets an owner see or reclaim that space without
   leaving the app.

6. **Credits and licenses.** Every source and its license from
   `docs/data-licensing.md`, in the form users are used to seeing in an iOS
   About/Acknowledgements screen: source name, what it supplies, license,
   and required credit line. This includes the sky-view catalogs (Bright
   Star Catalogue, d3-celestial constellation figures, IAU star names),
   the basemaps (USGS The National Map, AWS Terrain Tiles) once merged, and
   the live data sources (Open-Meteo, NOAA RAP-Smoke/HMS/SWPC, EPA AirNow).
   Keep this generated from — or at minimum reviewed against —
   `docs/data-licensing.md` directly, so a new source can't ship without
   also appearing here.

7. **Privacy.** State plainly: **"Spots are saved on this iPhone."** This
   replaces the current disabled-iCloud wording, which frames the absence of
   sync as a setting rather than a fact. Also state, in the same place:
   precise coordinates never leave the phone except as the rounded 0.05°
   cell (about 5 km) sent to the Worker for weather/conditions — the same
   privacy line `LocationSheet` already shows when choosing a place
   (`ios/App/Location/LocationSheet.swift`) — and that there is currently no
   sync, backup or export, so a lost or reset phone loses saved spots and
   plans. That last point is a real gap the product review calls out
   (§10: "Add explicit spot/plan export before treating the phone as the
   only durable copy of valuable notes") — this section is the honest
   place to say so until an export exists, not to promise one prematurely.

## What changes in the current screen

- Keep `SyncSection` (the disabled iCloud toggle) exactly as it is — it's
  accurate today (CloudKit sync isn't built) — but move it under this
  expanded page rather than have it stand alone as the entire About screen.
- Replace the toggle's footer text, which currently reads "Not set up yet:
  spots live on this phone...", with the Privacy section above so the same
  fact ("Spots are saved on this iPhone") appears once, prominently, instead
  of buried in a disabled-toggle footnote.
- Nothing above requires new data sources or new network calls except the
  optional live `/health` and `data-status.json` reads in Data status,
  which should degrade to "last known" with an age, the same way every
  other conditions number in the app already does on a failed fetch.
