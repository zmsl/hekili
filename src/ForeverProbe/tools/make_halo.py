#!/usr/bin/env python3
"""Writes Media/halo64.tga: a 64x64 white rounded-rect whose alpha feathers to 0 over the outer 16 px.

Nine-sliced in game with SetTextureSliceMargins(16, 16, 16, 16): the 32x32 centre is solid (alpha 1), each
edge strip carries the same linear-ish feather profile, and the corners are quarter-circles of that profile
(Euclidean distance to the inner rect), so stretched edges meet the corners without a step.

32-bit uncompressed TGA (type 2), BGRA, 8 alpha bits, bottom-left origin (the image is symmetric)."""
import math
import os
import struct

SIZE = 64
MARGIN = 16          # feather width == nine-slice margin
FEATHER = 15.5       # so the outermost pixel row/column is exactly alpha 0


def alpha_at(px, py):
    inner_lo, inner_hi = MARGIN, SIZE - MARGIN
    dx = max(inner_lo - px, 0.0, px - inner_hi)
    dy = max(inner_lo - py, 0.0, py - inner_hi)
    d = math.hypot(dx, dy)
    t = 1.0 - d / FEATHER
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)   # smoothstep: no visible kink at the inner rect


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "Media", "halo64.tga")
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            a = alpha_at(x + 0.5, y + 0.5)
            row += bytes((255, 255, 255, int(round(a * 255))))   # B G R A
        rows.append(bytes(row))
    with open(out, "wb") as f:
        f.write(header)
        for row in rows:
            f.write(row)
    print("wrote", os.path.normpath(out), 18 + SIZE * SIZE * 4, "bytes")


if __name__ == "__main__":
    main()
