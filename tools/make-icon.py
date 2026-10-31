#!/usr/bin/env python3
"""Draw the 1024x1024 app icon: a heartbeat line that leaves the chart as an arrow.

Only stdlib + Pillow. Run from the repo root; writes straight into the asset catalog.
iOS masks the corners itself, so the source stays square and full-bleed.
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024
OUT = pathlib.Path(__file__).resolve().parent.parent / "HealthSync/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

INK = (245, 245, 247)
GREEN = (48, 209, 88)
STROKE = 32

# one continuous trace: flat, one QRS spike, then it climbs out of the chart
WHITE_PATH = [(56, 664), (250, 664), (298, 664), (348, 782), (420, 300), (492, 806), (546, 664), (742, 664)]
GREEN_PATH = [(742, 664), (884, 268)]
MARGIN = STROKE // 2


def gradient():
    """Vertical charcoal gradient with a slight top-left light, no blobs."""
    y = np.linspace(0, 1, SIZE)[:, None]
    top, bottom = np.array([30, 30, 35]), np.array([9, 9, 11])
    img = (top * (1 - y) + bottom * y)[:, None, :].repeat(SIZE, axis=1).astype(np.uint8)
    x = np.linspace(0, 1, SIZE)[None, :, None]
    light = (1 - np.clip((x + y) * 0.85, 0, 1)) ** 2 * 18      # corner light, not an orb
    return Image.fromarray(np.clip(img + light, 0, 255).astype(np.uint8))


def rounded(draw, points, colour, width=STROKE, cap_end=True):
    pts = [(int(x), int(y)) for x, y in points]
    draw.line(pts, fill=colour, width=width, joint="curve")
    for p in pts[:-1] if not cap_end else pts:       # a capped tip would poke through the arrowhead
        draw.ellipse([p[0] - width // 2, p[1] - width // 2,
                      p[0] + width // 2, p[1] + width // 2], fill=colour)


def main():
    img = gradient()
    d = ImageDraw.Draw(img)
    (x0, y0), (x1, y1) = GREEN_PATH

    rounded(d, WHITE_PATH, INK)
    rounded(d, [GREEN_PATH[0], (x1 - (x1 - x0) * 0.10, y1 - (y1 - y0) * 0.10)],
            GREEN, cap_end=False)                    # the triangle is the tip

    vx, vy = x1 - x0, y1 - y0
    n = (vx * vx + vy * vy) ** 0.5
    ux, uy = vx / n, vy / n
    px, py = -uy, ux
    tip = (x1 + ux * 6, y1 + uy * 6)
    back = (tip[0] - ux * 132, tip[1] - uy * 132)
    half = 86
    d.polygon([(int(a), int(b)) for a, b in
               [tip, (back[0] + px * half, back[1] + py * half), (back[0] - px * half, back[1] - py * half)]],
              fill=GREEN)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
