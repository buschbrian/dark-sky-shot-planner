"""Pure-Python PNG encoding for raster tiles (no Pillow dependency).

Emits 8-bit RGB truecolor PNGs, deterministic byte-for-byte, which is what
the golden tests assert.
"""

from __future__ import annotations

import struct
import zlib


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def encode_png_rgb(width: int, height: int, pixels: list[list[tuple[int, int, int]]]) -> bytes:
    """pixels[row][col] with row 0 at the top of the image."""
    if len(pixels) != height or any(len(row) != width for row in pixels):
        raise ValueError("pixel array does not match width/height")

    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0 (None)
        for r, g, b in row:
            raw.extend((r & 0xFF, g & 0xFF, b & 0xFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            _chunk(b"IHDR", ihdr),
            _chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
            _chunk(b"IEND", b""),
        ]
    )
