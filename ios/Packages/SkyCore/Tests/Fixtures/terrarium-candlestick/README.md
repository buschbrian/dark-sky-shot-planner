# Terrarium tiles around Candlestick Camp (test fixture)

The 25 AWS Terrain Tiles (terrarium PNG, z12, x 794–798, y 1572–1576) that
cover a 16 km ray march around Candlestick Camp (38.374031, −109.965416).
`CandlestickDEMValidationTests` computes the skyline from them and compares it
with the ArcGIS Skyline measurement in `config/horizon-profiles/candlestick-camp.csv`
(PLAN M9: within 0.5° RMS). Recorded unmodified on 2026-09-26 from
`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`;
each tile is the byte-for-byte download.

16 km is enough: with the same march run to 60 km over z12 tiles, no azimuth's
skyline lay beyond 15.8 km.

## Attribution

Terrain tiles by Mapzen, hosted on the AWS Open Data Registry
(<https://registry.opendata.aws/terrain-tiles/>). United States 3DEP (formerly
NED) and global GMTED2010 and SRTM terrain data courtesy of the U.S.
Geological Survey. Full source list:
<https://github.com/tilezen/joerd/blob/master/docs/attribution.md>.
