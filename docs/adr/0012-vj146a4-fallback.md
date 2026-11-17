# ADR-0012: VJ146A4 fallback read directly from LAADS

**Status:** accepted · **Date:** 2026-11-17

## Decision

The light-pollution fetch tries, for the requested year and then the year
before, VNP46A4 (Suomi NPP) and then VJ146A4 (NOAA-20). The first product and
year with every AOI tile on LAADS wins. VNP46A4 still goes through
`blackmarblepy`; VJ146A4 is downloaded and read in `pipelines/light_pollution/fetch.py`
with `h5py`, using the same band (`NearNadir_Composite_Snow_Free`), fill and
quality-255 masking, and pixel-centre clip that `blackmarblepy` applies to
VNP46A4. The staged grid records the product and year used; the manifest
source name, publication date, and tile attribution come from it.

## Context

Suomi NPP stopped delivering data on 2026-11-02, so a full 2026 VNP46A4 annual
may never be published. VJ146A4 is the same Black Marble algorithm on the
continuing satellite, on the same tile grid and LAADS collection (5200), under
the same NASA CC0 terms. `blackmarblepy` (v2026.06.1) only knows the four VNP46
products and derives the product from each file name, so it cannot fetch
VJ146A4. Annual composites also publish around March of the following year,
so the January–March refreshes ask for a year that does not exist yet.

## Alternatives considered

- **Year fallback on VNP46A4 only** — smallest change, but freezes the layer
  at 2025 once Suomi NPP data ends.
- **Wait for `blackmarblepy` to add NOAA-20** — no timeline; the refresh would
  fail every month meanwhile.
- **Prefer VJ146A4 first** — switches the published layer between satellites
  while VNP46A4 still exists; deferred until VNP46A4 stops appearing.

## Consequences

This supersedes the earlier "fetch through `blackmarblepy`, not hand-rolled
requests" guidance for VJ146A4 only. The direct reader must be kept in step
with `blackmarblepy`'s VNP46A4 handling. If the published layer switches
product, the tiles shift slightly (different sensor and overpass) and the
manifest says so. When `blackmarblepy` gains VJ146 support, the direct reader
can be removed.
