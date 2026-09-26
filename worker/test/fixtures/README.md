# Worker test fixtures

Tests never touch the network. `test/no-network.ts` replaces the global
`fetch` with one that throws. The Worker only reaches upstreams through an
injected `fetch`, which the tests route to these files by URL
(`scripts/fixture-names.ts`).

| Folder | What | Real or synthetic |
|---|---|---|
| `recorded/` | Real upstream responses, recorded once by `npm run record-fixtures` for cell 38.35, −109.95, window 2026-09-26 00Z–14Z, HMS bbox −125,30,−100,50. See `manifest.json` for the URLs and recording time. `swpc-ovation` is trimmed to lat 30–70, lon 230–270. The two DWD ICON files (`icon_global`, `dwd_icon`) were recorded later, at 2026-09-26 00:17Z for the same cell and window, when ICON replaced HRDPS; their manifest entries carry their own `recorded_utc`. `open-meteo-forecast-minutely_15-ncep_hrrr_conus` (HRRR's native 15-minute series) was recorded at 2026-09-26 20:33Z through the Worker's own handler with "now" pinned to `manifest.recorded_utc`, so its URL is the one the code builds; by then the window was in the past, so its values come from later HRRR runs than the hourly file. | Real |
| `down/` | One "upstream down" response per source. `airnow-ziplatlong.json` is the real keyless 401. `open-meteo-meta.json` is a real error body. `open-meteo-forecast-no-data.json` is the real "no data for this location" answer HRDPS gave for this cell; tests use it for the outside-domain case. The rest carry `"synthetic": true`. | Mixed, flagged per file |
| `synthetic/` | `airnow-ziplatlong.synthetic.json`: AirNow happy path. This machine has no AirNow key, so the rows are invented. The field names follow the replacement `ziplatLong` schema. | Synthetic |

Every file is checked for credentials by `test/fixtures.test.ts`. The
recorder redacts any query parameter that looks like a key.

Re-recording overwrites `recorded/` and `manifest.json`. Tests pin "now" to
`manifest.recorded_utc`, so they keep passing after a re-record. Assertions
on specific values will need updating.
