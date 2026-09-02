#!/usr/bin/env bash
# Build everything the site serves from data/out, and say what it is.
#
# Two kinds of artifact end up in data/out:
#   real     - committed to git by .github/workflows/data-refresh.yml
#              (light pollution needs the BLACKMARBLE_TOKEN secret; see
#              docs/credentials-setup.md). Kept as-is when present.
#   fixture  - built here from the offline samples under tests/fixtures/
#              whenever no real artifact is committed. Synthetic coverage of
#              a tiny box; fine for boot and tests, meaningless in the field.
#
# config.json and the dark-sky places layer are always rebuilt: both derive
# from files in this repository and need no network or credential.
#
# The result is recorded in data/out/data-status.json so the client can
# label fixture layers instead of presenting them as real coverage.
#
# Usage: scripts/build-data.sh            (from anywhere in the checkout)
set -euo pipefail
cd "$(dirname "$0")/.."

out=data/out
mkdir -p "$out"

is_committed() { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }

uv run python -m pipelines.shared.cli --out "$out"
uv run python -m pipelines.darksky_places.cli build \
  --csv config/darksky-places.csv --out "$out/darksky_places"

if is_committed "$out/light_pollution/manifest.json"; then
  light_pollution=real
else
  uv run python -m pipelines.light_pollution.cli build \
    --grid tests/fixtures/radiance-grid.json --publication-date 2024-12-01 \
    --out "$out/light_pollution"
  light_pollution=fixture
fi

if is_committed "$out/padus/manifest.json"; then
  land_ownership=real
else
  uv run python -m pipelines.padus.cli \
    --input tests/fixtures/padus-sample.geojson --publication-date 2024-06-01 \
    --out "$out/padus"
  land_ownership=fixture
fi

built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$out/data-status.json" <<JSON
{
  "built_utc": "$built_utc",
  "layers": {
    "light_pollution": "$light_pollution",
    "land_ownership": "$land_ownership",
    "darksky_places": "real"
  }
}
JSON

echo "data/out: light_pollution=$light_pollution land_ownership=$land_ownership darksky_places=real"
