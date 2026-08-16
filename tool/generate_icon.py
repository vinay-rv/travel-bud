#!/usr/bin/env python3
"""Draws the Packmate app icon.

A duffel bag with a checkmark on it: "packed, nothing left behind". Colours
come from the app's own palette (lib/theme/app_theme.dart).

Everything is drawn at 4x and downsampled, which is cheaper than fighting
PIL's lack of antialiasing on shapes.

    python3 tool/generate_icon.py

Writes assets/icon/icon.png (full-bleed, for iOS and legacy Android) and
assets/icon/icon_foreground.png (transparent, for Android adaptive icons).
Run `dart run flutter_launcher_icons` afterwards to regenerate the platform
icon sets.
"""

import os
from PIL import Image, ImageDraw

S = 1024          # final size
SS = 4            # supersampling factor
W = S * SS        # working size

CANVAS = (10, 12, 17, 255)        # #0A0C11
PERIWINKLE = (140, 166, 255, 255)  # #8CA6FF
MINT = (95, 227, 192, 255)         # #5FE3C0

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def px(v):
    """Scale a coordinate expressed in 1024-space up to the working canvas."""
    return int(round(v * SS))


def draw_glow(img):
    """Soft periwinkle bloom in the top-left, echoing the app background.

    Computed per-pixel on a small canvas and scaled up: stacking ellipses
    leaves visible rings, and a per-pixel pass at full size is far too slow.
    """
    n = 128
    small = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    pixels = small.load()
    cx, cy, r = n * 0.32, n * 0.28, n * 0.62
    for y in range(n):
        for x in range(n):
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r
            if dist >= 1:
                continue
            alpha = int(40 * (1 - dist) ** 2)
            pixels[x, y] = PERIWINKLE[:3] + (alpha,)
    img.alpha_composite(small.resize((W, W), Image.LANCZOS))


def draw_mark(d, dy=0):
    """The bag + checkmark, centred horizontally. [dy] nudges it vertically."""
    # Handle: an arc rising out of the bag's top edge.
    hx0, hx1 = px(392), px(632)
    hy0, hy1 = px(300 + dy), px(536 + dy)
    d.arc([hx0, hy0, hx1, hy1], start=180, end=360,
          fill=PERIWINKLE, width=px(38))

    # Body: a soft-cornered duffel.
    d.rounded_rectangle(
        [px(232), px(404 + dy), px(792), px(796 + dy)],
        radius=px(76),
        fill=PERIWINKLE,
    )

    # Checkmark, knocked out of the body in the app's "packed" colour.
    stroke = px(54)
    pts = [(px(392), px(604 + dy)),
           (px(474), px(688 + dy)),
           (px(640), px(516 + dy))]
    d.line(pts, fill=MINT, width=stroke, joint="curve")
    # Round off the two open ends; PIL only rounds joints, not caps.
    for x, y in (pts[0], pts[2]):
        d.ellipse([x - stroke // 2, y - stroke // 2,
                   x + stroke // 2, y + stroke // 2], fill=MINT)


def build_full():
    img = Image.new("RGBA", (W, W), CANVAS)
    draw_glow(img)
    # Nudge up so the mark sits on the optical centre, not the maths one.
    draw_mark(ImageDraw.Draw(img), dy=-56)
    return img.resize((S, S), Image.LANCZOS)


def build_foreground():
    """Android adaptive foreground: transparent, mark inside the safe zone.

    The outer 1/4 of an adaptive icon can be cropped, so the mark is scaled to
    ~62% and centred.
    """
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(img), dy=-40)
    mark = img.resize((int(S * 0.62), int(S * 0.62)), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    offset = (S - mark.width) // 2
    canvas.alpha_composite(mark, (offset, offset))
    return canvas


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_full().save(os.path.join(OUT_DIR, "icon.png"))
    build_foreground().save(os.path.join(OUT_DIR, "icon_foreground.png"))
    print("wrote icon.png and icon_foreground.png to", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()
