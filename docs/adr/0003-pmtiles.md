# ADR-0003: PMTiles v3 for both raster and vector tiles

**Status:** accepted · **Date:** 2026-08-22

## Decision

All map data ships as PMTiles v3 archives: raster PNG tiles for light
pollution, gzip-compressed MVT vector tiles for PAD-US land ownership.

## Alternatives considered

- **ZXY tile directories on Pages** — hundreds of thousands of small files;
  slow to deploy, slow to clone, and GitHub Pages file-count limits loom.
- **MBTiles + server** — requires a backend; violates zero-server.
- **GeoJSON in the browser for PAD-US** — the AOI-wide dataset is far too
  large to ship and parse as GeoJSON.

## Reasoning

PMTiles is a single-file archive with byte-range random access via HTTP
Range requests — exactly what static hosting supports. One artifact per
layer means one checksum per layer in the manifest, which makes provenance
verification trivial.

## Consequences

The pipelines implement a minimal pure-Python MVT encoder and PNG writer so
golden tests need no compiled dependencies. Coordinates outside a tile's
extent are valid MVT and are render-clipped by MapLibre; per-tile polygon
simplification is deferred (documented in methods.md).
