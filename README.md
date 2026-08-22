# Dark-Sky Shot Planner

**One question: is this spot dark, legal, and clear tonight?** — for Milky
Way photography in the U.S. Mountain West.

Darkness, legal access, and sky conditions for one place on one night,
answered text-first:

- **X minutes of moon-free astronomical darkness** — the intersection of the
  sun-below-−18° window with the moon-down window. The number nobody else
  surfaces well.
- Galactic Center peak altitude and time, with an honest "out of season"
  answer in winter.
- Land manager from USGS PAD-US — who manages it, never "you may camp here."
- Cloud-cover forecast over the moon-free window (Open-Meteo, keyless).
- Every number carries its source and its age.

Zero server: a static site (MapLibre + PMTiles on GitHub Pages) plus Python
pipelines that run in GitHub Actions and publish static artifacts. All
astronomy is computed client-side; weather is fetched client-side on demand.

## Quickstart

```bash
uv sync --group dev && uv run python -m pytest tests/   # pipelines + tests (offline)
npm install && npm run dev                              # http://localhost:5173
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for real data builds and AOI extension.

## Architecture

```
GitHub Actions (scheduled + manual)
  Python pipelines
    fetch source data -> clip to AOI -> normalize -> emit PMTiles / JSON
                                                        |
                                        committed artifacts (data/out/)
                                                        |
GitHub Pages  <---- static site build (Vite) ---------- +
    MapLibre GL JS + PMTiles protocol
    client-side astronomy (astronomy-engine, no API)
    client-side weather fetch on demand (Open-Meteo, keyless)
```

## Documentation

- [`docs/data-licensing.md`](docs/data-licensing.md) — every source, its
  license, and the sources we refuse to use (Falchi 2016, Lorenz).
- [`docs/methods.md`](docs/methods.md) — exactly how each displayed number is
  computed.
- [`docs/adr/`](docs/adr/) — architecture decision records.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — local pipelines, extending the AOI.

## License

MIT — see [LICENSE](LICENSE).
