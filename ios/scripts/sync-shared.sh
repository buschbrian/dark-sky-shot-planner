#!/usr/bin/env bash
# Copy repo-root files that SkyCore bundles. SwiftPM resources must live inside
# the package, so these are copies; SharedFilesTests fails `swift test` when a
# copy drifts from its original.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="$root/ios/Packages/SkyCore/Sources/SkyCore/Resources"
for f in app-config.json conditions-thresholds.json horizon-profiles/candlestick-camp.csv; do
  mkdir -p "$(dirname "$dest/$f")"
  cp "$root/config/$f" "$dest/$f"
  echo "synced config/$f -> ${dest#"$root"/}/$f"
done
