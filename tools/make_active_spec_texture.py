#!/usr/bin/env python3
"""Writes src/Hekili/Textures/ActiveSpec.tga: the options tree's active-spec marker, a 256x16 rounded rectangle (near
the tree row's shape, so the corners stay round when stretched) with a vertical gradient in the Now ring's gold
(GoldRing.tga's palette: light gold at the top, dark amber at the bottom), half transparent so the row's text stays
readable. Stdlib only; run from the repository root."""

import struct

W, H, R = 256, 16, 6  # size and corner radius in pixels
TOP, BOTTOM = (255, 224, 120), (160, 96, 16)  # GoldRing.tga's bright and mid golds
ALPHA = 150  # the fill's opacity (0-255)
SAMPLES = 4  # per axis: anti-aliased corners


def inside(x, y):
    # distance test against the nearest corner circle; the straight edges are always in
    cx = min(max(x, R), W - R)
    cy = min(max(y, R), H - R)
    return (x - cx) ** 2 + (y - cy) ** 2 <= R * R


def main():
    rows = bytearray()
    for y in range(H):
        t = y / (H - 1)
        r, g, b = (round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(W):
            hits = sum(
                inside(x + (i + 0.5) / SAMPLES, y + (j + 0.5) / SAMPLES)
                for i in range(SAMPLES)
                for j in range(SAMPLES)
            )
            rows += bytes((b, g, r, round(ALPHA * hits / SAMPLES**2)))
    # uncompressed true colour, 32 bpp, 8 alpha bits, top-left origin
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
    with open("src/Hekili/Textures/ActiveSpec.tga", "wb") as f:
        f.write(header + rows)


if __name__ == "__main__":
    main()
