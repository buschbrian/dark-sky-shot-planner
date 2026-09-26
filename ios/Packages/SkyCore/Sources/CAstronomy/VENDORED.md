# Vendored: astronomy-engine C port

| | |
|---|---|
| Upstream | https://github.com/cosinekitty/astronomy |
| Tag | `v2.1.19` (commit `61dc07020aaa6885d2c7f688a4d82beaf6edb9ef`), the same version as the web app's npm `astronomy-engine` |
| License | MIT, `LICENSE` in this folder (copied from the repo root at the tag) |
| Retrieved | 2026-09-25 |

| File here | Upstream path at the tag | sha256 |
|---|---|---|
| `astronomy.c` | `source/c/astronomy.c` | `388920479d819713963ffd0f8ab0677944f66c6c94239ceddddd3b0d5d064432` |
| `include/astronomy.h` | `source/c/astronomy.h` | `83a31011957c2b87e22f0828820f370f1a495aa4d51357bb57d714cde839dc00` |
| `LICENSE` | `LICENSE` | `690dd98cb13ba4db77c6327deea852a816892bb9debbad5943405c66972f8023` |

Both source files are byte-for-byte unmodified; the header sits in
`include/` only because SwiftPM exposes a C target's public headers from
there. Source URLs:
`https://raw.githubusercontent.com/cosinekitty/astronomy/v2.1.19/<path>`.

To upgrade: bump the web app's `astronomy-engine` first, fetch the same tag
here, update this table, and rerun both golden suites.

Thread safety: the library's only mutable globals are the user-star table
(`Astronomy_DefineStar`), the Delta-T hook (`Astronomy_SetDeltaTFunction`)
and the Pluto cache. SkyCore calls none of them and never asks for Pluto, so
its calls are safe from any thread.
