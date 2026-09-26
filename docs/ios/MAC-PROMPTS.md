# Prompts for the Mac

Copy-paste prompts for Claude Code on the M4 MacBook, in order. Each prompt
stands alone: it says what to read, what to do, where to stop and ask, and
what "done" looks like. Run one per session (or `/clear` between them) so
each starts with a clean context.

| # | Prompt | Needs the repo? | Changes anything? |
|---|---|---|---|
| 1 | Disk and toolchain audit | No | No, read-only |
| 2 | Free up internal space | No | Yes, each deletion confirmed by you |
| 3 | External SSD, repo, Command Line Tools | No (it clones it) | Yes, nothing erased without you |
| 4 | M0: SkyCore package | Yes | Branch + PR |
| 5 | M1: astronomy parity | Yes | Branch + PR |
| 6 | Xcode install + M1b app scaffold | Yes | Installs Xcode, branch + PR |
| 7 | Continue the plan (reuse for every later milestone) | Yes | Branch + PR |
| W | Windows side track: M3 Worker | Yes (Windows) | Branch + PR |

## Where things stand (2026-09-26, on the Mac)

Read this before running any prompt below. Several of them are already done
or superseded.

- **Prompts 1–2: done.** 20 GB → 38 GB free; see `~/Desktop/mac-space-audit.md`.
- **Prompt 3: partly done, partly changed.** The Command Line Tools work
  (Swift 6.4). The repo stays in `~/Developer/dark-sky-shot-planner`; the SSD
  is only for DerivedData, archives and optionally Xcode (MAC-SETUP.md Phase 3).
  No SSD had been connected yet.
- **Prompts 4–5 (M0, M1): already built on the Mac,** before these prompts
  existed. Don't rebuild them. The owner asked to keep the iOS and Worker work
  **local** (commits on local branches, no push, no PRs, no CI, no deploys)
  until the local build is solid. The combined state is the local branch
  `local/ios-integration` (worktree `~/Developer/wt-dark-sky-next`): SkyCore
  M0 + M1 (golden parity green), the M1b project scaffold (unbuilt: needs
  Xcode), and the Worker (M3, offline tests green, not deployed).
- **Prompt W: superseded.** The Worker was built on the Mac. Don't run W on
  Windows. What's left for M3 is the owner's pre-deploy decisions
  (PLAN.md §Worker), the AirNow secret, and the deploy.
- **When "keep it local" is lifted:** open PRs against `main` one at a time
  (M0 → M1 → Worker → the rest), each from `main`, never stacked.
- **Next on the Mac:** prompt 6 (Xcode + M1b), then prompt 7. Both apply to the
  local branches above until the owner says to push.

Before prompt 1, on the Mac: install Claude Code if it isn't there. Then
sign in to GitHub yourself (`gh auth login`, or GitHub Desktop), since
Claude shouldn't handle your credentials. Prompts 1–3 work in any folder,
including a new empty one.

The files these prompts reference are on `main` at
<https://github.com/buschbrian/dark-sky-shot-planner>. Until the repo is
cloned (prompt 3), open this file on GitHub and copy from there.

---

## 1 — Disk and toolchain audit (read-only)

```text
I'm setting up this 256 GB M4 MacBook for iOS development with Xcode 27,
possibly with an external SSD. Before anything is installed or deleted, I
want a clear picture of the machine. This task is READ-ONLY: do not
delete, move, install, or change any setting. Only run commands that
inspect.

Background (from my project's research, 2026-09-26):
- Xcode 27 needs macOS Tahoe 26.6 or later on Apple silicon.
- The iOS platform component (~8–10 GB) must live on the internal disk even for
  iPhone-only builds. Xcode.app itself (~9 GB), DerivedData, archives, and
  repos can live on an external APFS SSD.
- The internal disk should keep ~20 GB for the unmovable pieces plus 30–40
  GB of free headroom.

Report on:
1. Machine: macOS version (`sw_vers`), chip, total and free space on the
   internal disk (`df -h /`), and whether macOS needs updating for Xcode 27.
2. Toolchain: are the Command Line Tools installed (`xcode-select -p`), is
   any Xcode installed and where, `swift --version`, Homebrew present, `gh`
   present and authenticated (`gh auth status`, and just report, don't log
   in), git identity set.
3. Space: the biggest folders in my home directory and in ~/Library
   (`du -sh ~/* ~/Library/* 2>/dev/null | sort -h | tail -25`), then drill
   into the top few. Specifically check: ~/Library/Developer (and its
   Xcode, CoreSimulator subfolders), ~/Library/Caches, Time Machine local
   snapshots (`tmutil listlocalsnapshots /`), simulator runtimes if any
   (`xcrun simctl runtime list`), Homebrew cache, Docker, node_modules folders,
   and iCloud/Photos local libraries. If macOS blocks a folder (privacy
   prompt / Operation not permitted), skip it and list it. Don't ask me
   for Full Disk Access.
4. External drives: `diskutil list external` and, for each, name, size,
   format (APFS or not), and connection if you can tell.

Deliverable: a short report with a table of the top space users (path,
size, what it is, safe to remove? yes/no/ask). Then a recommended
cleanup list ordered by space recovered, labelled as (a) safe caches that
regenerate, (b) needs my decision, and (c) don't touch. End with how much
space the (a) list would free, and whether I can reach 40 GB free without
touching category (b). Save the report as ~/Desktop/mac-space-audit.md.
```

---

## 2 — Free up internal space (every deletion confirmed)

```text
Read ~/Desktop/mac-space-audit.md (from the previous audit session). Help me
free up internal disk space on this 256 GB Mac so there's at least 40 GB
free before installing Xcode 27.

Rules:
- Work one category at a time. For each: show the exact paths and sizes,
  say what regenerates and what doesn't, then WAIT for my yes before
  deleting. My yes covers only that category.
- Never delete anything in Documents, Desktop, Downloads, Pictures, Photos,
  Movies, Music, or iCloud Drive yourself. For those, tell me what's big and
  let me decide in Finder.
- Never use sudo to delete, never touch /System, and never disable SIP. If
  there are orphaned simulator runtimes under /System/Library/AssetsV2 that
  can't be removed (a known Apple bug), just report them.
- Prefer the official tools where one exists: `tmutil thinlocalsnapshots /
  999999999999 4`, `xcrun simctl runtime delete`, `xcrun simctl delete
  unavailable`, `brew cleanup --prune=all`, `brew autoremove`,
  `docker system prune`, `npm cache clean --force`.
- For settings only I should change (iCloud "Optimize Mac Storage", Photos
  "Optimize Mac Storage", System Settings > General > Storage
  recommendations), give me the exact click path instead.

Start with the safe regenerating caches (Time Machine local snapshots,
Xcode DerivedData/caches if present, SwiftPM cache, Homebrew, npm), then
move to anything that needs my decision.

Done when: free space is at least 40 GB, or you've shown me everything left
and I've decided. Append a "Cleanup results" section to
~/Desktop/mac-space-audit.md with before/after free space and what was removed.
```

---

## 3 — External SSD, repo, and Command Line Tools

```text
Set up this Mac for my dark-sky-shot-planner project using an external SSD
for everything that grows. Read the plan's setup guide first:
https://github.com/buschbrian/dark-sky-shot-planner/blob/main/docs/ios/MAC-SETUP.md
(Phases 1 and 3). Follow it. Where this prompt and the guide disagree, ask me.

Steps:
1. Find the external SSD (`diskutil list external`, `diskutil info`). It
   should be APFS and ideally named "Dev". If it is NOT APFS, STOP: tell
   me what's on it and how to reformat it in Disk Utility, because erasing is
   my call, not yours. If it's APFS but named differently, ask whether to
   rename it or adapt the paths.
2. Create /Volumes/Dev/DerivedData and /Volumes/Dev/Archives.
3. Don't clone or move the repo: it stays in ~/Developer/dark-sky-shot-planner.
   Check `gh auth status` (if it fails, stop and tell me to sign in).
4. If the Command Line Tools aren't installed, run `xcode-select --install`
   and tell me to click through the installer dialog. Don't install full
   Xcode yet; that's a later prompt.
5. Verify the toolchain: `swift --version`, and confirm `Testing.framework`
   exists somewhere under /Library/Developer/CommandLineTools. Report the path.
6. Tell me the click paths to exclude /Volumes/Dev/DerivedData from Spotlight
   and from Time Machine (System Settings), and wait while I do it.
7. If macOS is older than Tahoe 26.6, tell me. Don't start the update.

Done when: the SSD folders exist, `git status` is clean on main, and the
Command Line Tools work. Summarize what's ready.
```

---

## 4 — M0: SkyCore package (Command Line Tools only)

**Already done on this Mac; see "Where things stand".** Kept for a fresh
machine. SkyCore's `Package.swift` already carries the Command Line Tools
test fix (MAC-SETUP.md Phase 1).

```text
Start milestone M0 of the iOS field companion.

Read first, in this order: AGENTS.md, ios/AGENTS.md, docs/ios/PLAN.md
(the whole thing, then focus on M0), docs/ios/MAC-SETUP.md (Phase 1),
docs/adr/0009-native-ios-field-companion.md, and shared/golden/README.md.
Follow AGENTS.md and ios/AGENTS.md exactly.

Build M0 as specified in PLAN.md:
- Create a branch off main (e.g. feat/ios-m0-skycore).
- ios/Packages/SkyCore: a Swift package with a `CAstronomy` C target (vendor
  astronomy.c / astronomy.h from cosinekitty/astronomy at v2.1.19, the same
  version as the web app's `astronomy-engine` npm package; check
  package.json/package-lock.json to confirm). Include its LICENSE and a short
  README noting the version and source URL. Leave the C files unmodified. Add
  a `SkyCore` Swift target that imports it, and a test target using Swift
  Testing (`import Testing`), never XCTest.
- One real smoke test through the C layer (e.g. the Sun's altitude for a
  known place and time, checked against the web app's astronomy-engine
  result, which you can compute with node in this repo).
- .github/workflows/ios.yml: macOS runner, `swift test` in the package.
- There's no full Xcode on this Mac, only the Command Line Tools. That's
  intended.

Verify: `cd ios/Packages/SkyCore && swift test` passes AND the output reports
a non-zero number of tests. If it runs zero tests, apply the workaround in
MAC-SETUP.md Phase 1, and make the fix reproducible (a script or documented
command) rather than something only this session knows.

Finish: add an entry to PLAN.md §Log (date, what landed, anything
surprising), commit with a clear message, push, and open a PR against main.
Report the PR link and the exact test command and output summary. Don't
merge it; I'll review.
```

---

## 5 — M1: astronomy parity

**Already done on this Mac; see "Where things stand".**

```text
Continue the iOS field companion with milestone M1: SkyCore astronomy
parity.

Read: AGENTS.md, ios/AGENTS.md, docs/ios/PLAN.md (M1 and §Log),
docs/adr/0002-*.md, docs/adr/0009-*.md, app/src/astronomy/planner.ts (the
reference implementation), app/tests/planner.test.ts, and
shared/golden/night-report.json + its README. First check that M0 is merged
into main (git log / gh pr list). If it isn't, stop and tell me.

Do M1 exactly as PLAN.md specifies, on a new branch off main:
- Port planNight and its helpers to Swift over CAstronomy, keeping the same
  structure and names where Swift allows, so the two stay reviewable side by
  side.
- Load config/app-config.json (GC threshold) as a bundled package resource.
  Don't hardcode it.
- A parity test that reads shared/golden/night-report.json directly from the
  repo path (not a copy) and checks every case within the tolerances stored
  in the file. Never loosen a tolerance to pass: if a case fails, find out
  why and explain it to me.
- Add the alt/az series, the Milky Way band points, and rise/set/transit
  azimuths described in M1, with tests that spot-check against the web
  app's astronomy-engine (compute expected values with node here).

Verify: `swift test` passes with a non-zero test count, including all 8
golden cases. Also run `npx vitest run` to confirm the web side is untouched.

Finish: PLAN.md §Log entry, commit, push, PR against main with the test
summary. Don't merge.
```

---

## 6 — Install Xcode, then M1b app scaffold

```text
Time to install Xcode and start the app shell: milestone M1b.

Read: ios/AGENTS.md, docs/ios/PLAN.md (M1b and §Log),
docs/ios/MAC-SETUP.md (Phase 4 in full), and ~/Desktop/mac-space-audit.md.
Check that M1 is merged into main, or, while the owner has the work kept
local, that `swift test` is green on `local/ios-integration`. If neither,
stop and tell me.

Part A: Xcode.
1. Check free internal space and macOS version. Xcode 27 needs macOS Tahoe
   26.6+.
2. Recommend option A (Xcode internal, via the App Store) or option B
   (Xcode on /Volumes/Dev via the `xcodes` CLI) based on actual free space,
   using MAC-SETUP.md's rule of thumb. Explain in two lines and wait for my
   pick.
3. Walk me through the install. I'll do anything that needs my Apple ID or
   password myself. After install: `sudo xcodebuild -runFirstLaunch`
   (tell me to run sudo commands myself if you can't), add ONLY the iOS
   platform (arm64), and set DerivedData to /Volumes/Dev/DerivedData and
   Archives to /Volumes/Dev/Archives.
4. Confirm: `xcodebuild -version`, `xcode-select -p`, the iOS platform
   installed, and free internal space afterwards. Record these in
   ~/Desktop/mac-space-audit.md.

Part B: M1b, on a new branch off main, as PLAN.md specifies:
- `brew install xcodegen`; ios/project.yml with App, Widgets, and UI-test
  targets depending on the local SkyCore package; the generated .xcodeproj
  stays gitignored; team and bundle ID go in a gitignored Local.xcconfig
  (tell me what to put there; I'll fill in my team ID).
- Add the MapLibre Native SPM dependency (≥ 6.31) as specified.
- The app launches to a placeholder that shows one real SkyCore number
  (tonight's moon-free minutes for a hardcoded test location). Proof that
  the whole chain works.

Verify: `xcodegen generate` and `xcodebuild build` pass. Then tell me the
steps to run it on my iPhone (trust the developer certificate, turn on
Developer Mode). That part I do by hand, so list what I should see.

Finish: PLAN.md §Log (including Xcode version and disk space after) and a
local commit. Push and open a PR only if I've lifted "keep it local";
otherwise tell me the branch and commit. Don't merge.
```

---

## 7 — Continue the plan (reuse for M2 onward)

```text
Continue the iOS field companion plan.

Read AGENTS.md, ios/AGENTS.md, and docs/ios/PLAN.md, especially §Log.
Then work out the next milestone: the first one whose "Done when" isn't
recorded as met in §Log AND whose predecessor is merged into main, or green
on `local/ios-integration` while the work is kept local (check with
git log and gh pr list). Tell me which milestone you're starting and why,
in two lines, and wait for my go.

Then:
- Read every ADR, config file, and reference implementation the milestone
  and the routing tables point to before writing code.
- New branch off main. Build exactly what the milestone specifies. If the
  plan is wrong or out of date, say so and propose an edit to PLAN.md
  rather than silently doing something else. Anything that changes a
  settled decision needs a new ADR (don't re-litigate the existing ones).
- Verify with the commands in ios/AGENTS.md (plus `npx vitest run` if you
  touched anything shared with the web app). Name exactly what you ran.
- For anything only a real phone at a real dark site can prove (sensors,
  AR, GPS, background refresh, field mode brightness), write an "Owner
  checks" list for me instead of claiming it works.
- Keep the Mac tidy: if free internal space is under 30 GB at the end, tell
  me and suggest the MAC-SETUP.md monthly hygiene commands.

Finish: PLAN.md §Log entry and a local commit. Push and open a PR against
main (with a summary, the verification output, and the owner checks) only if
I've lifted "keep it local"; otherwise report the same in chat. Don't merge.
```

---

## W — Windows side track: M3 Worker

**Superseded: the Worker was built on the Mac (see "Where things stand").
Don't run this.** Kept for reference.

```text
Build milestone M3 of docs/ios/PLAN.md: the stateless conditions Worker.

Read: AGENTS.md, docs/ios/PLAN.md (§Data sources, §Worker, M3),
docs/adr/0010-stateless-conditions-worker.md, docs/adr/0006-*.md,
docs/data-licensing.md (the "Proposed" table), and
config/conditions-thresholds.json. For how I usually structure Workers,
look at V:\Developer\blaumeux-dashboard (wrangler config, Workers Builds,
Vitest setup), but don't copy its product logic.

Build worker/ on a new branch off main, as M3 specifies: TypeScript,
Wrangler, Vitest with recorded upstream fixtures (tests never touch the
network), 0.05° coordinate rounding enforced server-side, every field
carrying source / model / model_run_utc / fetched_utc, and "unavailable"
for anything missing, never 0. Include one "upstream down" fixture per
source. Use the AirNow ziplatLong path, not the retired latLong one. Do the
HRRR-Smoke unit calibration step and write the evidence into
docs/methods.md. Keep smoke non-gating until that's done.

Secrets: the Worker needs an AirNow API key. Don't create accounts or
handle keys yourself. Tell me where to register and the exact
`wrangler secret put` command, and I'll run it. Don't deploy without
asking me first.

Verify: `npm test` in worker/ passes offline, plus the repo's existing
checks. Move each source you actually use from the "Proposed" table into
the main table in docs/data-licensing.md. PLAN.md §Log entry, commit,
push, PR. Don't merge.
```
