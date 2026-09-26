#!/usr/bin/env bash
# Copy repo-root files that SkyCore bundles. SwiftPM resources must live inside
# the package, so these are copies; SharedFilesTests fails `swift test` when a
# copy drifts from its original.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="$root/ios/Packages/SkyCore/Sources/SkyCore/Resources"
cp "$root/config/app-config.json" "$dest/app-config.json"
echo "synced config/app-config.json -> ${dest#"$root"/}"
