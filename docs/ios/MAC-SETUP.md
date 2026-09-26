# Mac setup: iOS development on a 256 GB MacBook + external SSD

Written 2026-09-26 from research into Apple docs, Apple Developer Forums
(including Apple DTS answers), and 2026 developer reports. Items marked
*unverified* could not be confirmed from an Apple source. Check them on the
machine and correct this file.

## The short version

| Thing | Size | Can it live on the SSD? |
|---|---|---|
| Command Line Tools (`xcode-select --install`) | ~2 GB | No (fixed location), but small |
| Xcode 27 app | ~9 GB installed (~2–3 GB .xip download) | **Yes**, works in practice though Apple doesn't document it |
| iOS platform component (build support + simulator, arm64) | **~8–10 GB** | **No.** Required even to build for a physical iPhone |
| iOS DeviceSupport (first time the iPhone connects) | 1–5 GB per iOS version | No, but delete old versions |
| DerivedData (build products, compilation cache) | 5–30 GB and growing | **Yes**, the biggest win |
| The repo, node_modules, archives | varies | **Yes** |

So the internal disk needs roughly **20 GB for the unavoidable pieces plus
30–40 GB of headroom** for installs and updates (a .xip expands to 2–3×
its size). Everything that grows goes on the SSD.

Xcode 27 (released 2026-09-14) **requires macOS Tahoe 26.6 or later** on
Apple silicon. Update macOS first. It is also a large download, so clean
up before starting.

## Phase 1: no Xcode needed yet

Milestones M0–M1 are mostly the `SkyCore` Swift package (pure Swift + the
vendored astronomy C code). That builds and tests with the **Command Line
Tools alone**, with one condition: tests must use **Swift Testing**
(`import Testing`). XCTest is not included in the Command Line Tools.

```bash
xcode-select --install          # ~2 GB
cd /Volumes/Dev/dark-sky-shot-planner/ios/Packages/SkyCore
swift test                      # confirm the output reports a NON-ZERO test count
```

Known 2026 trap (*unverified with Swift 6.4*): with Command Line Tools only,
`swift test` can build, exit 0, and **run zero tests** because
`Testing.framework` isn't on the default search path. If that happens:

```bash
FW=$(dirname "$(find /Library/Developer/CommandLineTools -name Testing.framework -maxdepth 6 | head -1)")
swift test -Xswiftc -F"$FW" -Xlinker -rpath -Xlinker "$FW"
```

Also with Swift 6.4, the default build system can print harmless linker
warnings about missing `CommandLineTools/Developer/...` paths.
`swift test --build-system native` silences them.

This lets the astronomy port (M1) and its golden-vector parity tests
happen before any big download.

## Phase 2: free up internal space

Look before deleting anything:

```bash
# Biggest folders in your home directory and Library
du -sh ~/* ~/Library/* 2>/dev/null | sort -h | tail -25
du -sh ~/Library/Developer/* ~/Library/Caches/* 2>/dev/null | sort -h | tail -15
```

Also see **System Settings → General → Storage**, which has per-category
totals and a Developer category that can delete Xcode caches.

Highest-yield items, roughly in order:

1. **Time Machine local snapshots** (often the hidden part of "System Data"):
   ```bash
   tmutil listlocalsnapshots /
   tmutil thinlocalsnapshots / 999999999999 4
   ```
2. **iCloud: Optimize Mac Storage**: System Settings → Apple Account →
   iCloud (and Desktop & Documents in iCloud if you use it). In Photos:
   Settings → iCloud → Optimize Mac Storage.
3. **Old Xcode / simulator leftovers**, if Xcode was ever installed:
   ```bash
   xcrun simctl runtime list
   xcrun simctl runtime delete --notUsedSinceDays 30 --dry-run   # preview, then drop --dry-run
   xcrun simctl delete unavailable
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   rm -rf ~/Library/Developer/CoreSimulator/Caches/*
   rm -rf ~/Library/Caches/org.swift.swiftpm
   ```
   Also delete all but the newest folder in `~/Library/Developer/Xcode/iOS DeviceSupport/`.
   Apple has an unresolved bug that can leave orphaned simulator runtimes
   (9–85 GB) under `/System/Library/AssetsV2/` that can't be deleted with SIP
   on. If Storage shows huge "System Data" after the steps above, that's the
   likely cause.
4. **Homebrew**: `brew cleanup --prune=all && brew autoremove`.
5. **Docker**, if installed: `docker system prune -a --volumes`, and cap or
   move its disk image in Docker Desktop settings.
6. **node_modules**: `npx npkill`, and `npm cache clean --force`.

## Phase 3: the external SSD

- **Drive:** a USB4 / Thunderbolt NVMe SSD (~3.5 GB/s on Apple silicon) is
  ideal. USB 3.2 Gen 2 (~1 GB/s) is fine for builds. Don't pay extra for
  "USB 3.2 Gen 2x2": Apple silicon runs it at Gen 2 speed. Prefer a drive
  with TRIM support.
- **Format:** Disk Utility → **APFS** (case-insensitive, which is the default).
  Never exFAT/FAT for development. Name it `Dev` so the paths below work as
  written.
- **Spotlight:** exclude `/Volumes/Dev/DerivedData` in System Settings →
  Spotlight → Search Privacy.
- **Time Machine:** exclude `DerivedData`. Do back up the repo, although
  GitHub already has everything that's pushed.
- **Always plug the SSD in before opening Xcode or a terminal build.** Unplugging
  mid-build can corrupt DerivedData. The fix is deleting DerivedData, which is
  harmless.

Put the repo on it:

```bash
cd /Volumes/Dev
git clone https://github.com/buschbrian/dark-sky-shot-planner.git
```

## Phase 4: Xcode (when the app target starts, M0 app part / M2)

Two options. Choose based on how much internal space Phase 2 recovered.

**A. Xcode internal (most reliable), if you have ~40 GB free after cleanup.**
Install from the Mac App Store (it always goes to `/Applications` and
auto-updates). Moving it would only save ~9 GB anyway.

**B. Xcode on the SSD, if space is still tight.** Don't use the App Store.
```bash
brew install xcodesorg/made/xcodes
xcodes install --latest --directory /Volumes/Dev/
sudo xcode-select -s /Volumes/Dev/Xcode.app
sudo xcodebuild -runFirstLaunch
```
(Or download the Apple-silicon `.xip` from developer.apple.com/download/all
and expand it on the SSD with `xip -x`.) If the SSD is ever unplugged,
`git`, `swift`, and `xcrun` stop working until you switch back:
`sudo xcode-select -s /Library/Developer/CommandLineTools`.

Either way, then:

1. **First launch: add only the iOS platform** (Settings → Components). Skip
   watchOS, tvOS, visionOS, and the optional Metal toolchain. One iOS
   runtime only. This ~8–10 GB is unavoidable, since Apple bundles device-build
   support with the simulator.
2. **Settings → Locations:** Derived Data → Custom →
   `/Volumes/Dev/DerivedData`. Archives → `/Volumes/Dev/Archives`.
   Or from the terminal:
   ```bash
   defaults write com.apple.dt.Xcode IDECustomDerivedDataLocation /Volumes/Dev/DerivedData
   ```
3. **Known issue with external DerivedData** (reported Jan 2026, unresolved):
   running a *framework* test target on "My Mac" inside Xcode can fail with
   "Cannot find executable for CFBundle … .xctest". App builds to the iPhone
   are not affected. Workaround: run SkyCore tests from the terminal
   (`swift test`), which this project does anyway.
4. **Prefer your iPhone over the simulator** for everyday runs, since it's
   where the sensors are. Keep one simulator device for UI tests and delete the
   rest (`xcrun simctl delete unavailable`).
5. `brew install xcodegen` (see PLAN.md M0).

## Monthly hygiene

```bash
xcrun simctl delete unavailable
xcrun simctl runtime delete --notUsedSinceDays 60
rm -rf ~/Library/Caches/org.swift.swiftpm ~/Library/Developer/CoreSimulator/Caches/*
rm -rf /Volumes/Dev/DerivedData/*
tmutil thinlocalsnapshots / 999999999999 4
brew cleanup --prune=all
```

After each iOS update on the phone, delete the older folders in
`~/Library/Developer/Xcode/iOS DeviceSupport/`.

## Sources

Apple: [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/),
[Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components),
[Free up storage space on Mac](https://support.apple.com/en-us/102624).
Apple Developer Forums threads 813056, 817687, 812321, 812992 (DTS answers on
external drives, platform support, DerivedData, runtimes).
[xcodes CLI](https://github.com/XcodesOrg/xcodes) (`--directory`).
SwiftPM issue [#10557](https://github.com/swiftlang/swift-package-manager/issues/10557)
(Command Line Tools and Swift Testing).
Eclectic Light Co. on USB 3.2 Gen 2x2 and Thunderbolt port types on Apple silicon.
