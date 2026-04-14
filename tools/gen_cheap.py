#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Programmatic generator for the "cheap" tile.

DALL-E repeatedly hallucinates WiFi symbols onto coin surfaces. This script
renders a simple 3D-extruded gold coin with a dollar sign plus a green
checkmark — matching the Playful 3D set palette.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT_DIR = Path("tools/tile_sets/playful_3d")
SIZE = 1024

BG = (245, 230, 210)
COIN_FACE = (245, 200, 60)
COIN_EDGE = (205, 155, 30)
COIN_HILIGHT = (255, 240, 170)
COIN_INNER = (225, 170, 40)
SYMBOL = (160, 110, 20)

CHECK_FACE = (110, 200, 110)
CHECK_EDGE = (55, 140, 60)
CHECK_HILIGHT = (200, 240, 200)

SHADOW_BLUR = 22
EXTRUDE = (14, 20)


def shadow_ellipse(img, box, opacity=110, blur=20):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=(0, 0, 0, opacity))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius=blur)))


def draw_coin(img, cx, cy, r):
    shadow_ellipse(img, [cx - r + 20, cy + r - 10, cx + r + 30, cy + r + 32],
                   opacity=120, blur=SHADOW_BLUR)
    d = ImageDraw.Draw(img)
    # Edge extrude
    d.ellipse([cx - r + EXTRUDE[0], cy - r + EXTRUDE[1],
               cx + r + EXTRUDE[0], cy + r + EXTRUDE[1]], fill=COIN_EDGE)
    # Main coin face
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=COIN_FACE)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=COIN_EDGE, width=6)
    # Inner ring (coin rim)
    inner_r = int(r * 0.82)
    d.ellipse([cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r],
              outline=COIN_INNER, width=4)
    # Soft top-left highlight
    hl_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    hr = int(r * 0.55)
    ImageDraw.Draw(hl_layer).ellipse(
        [cx - r + 40, cy - r + 40,
         cx - r + 40 + hr, cy - r + 40 + hr],
        fill=COIN_HILIGHT + (140,),
    )
    img.alpha_composite(hl_layer.filter(ImageFilter.GaussianBlur(radius=25)))
    # Dollar sign
    d2 = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
            int(r * 1.1),
        )
    except Exception:
        font = ImageFont.load_default()
    text = "$"
    bbox = d2.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    # Extruded shadow of symbol
    d2.text((cx - tw // 2 - bbox[0] + 6, cy - th // 2 - bbox[1] + 10),
            text, fill=COIN_EDGE, font=font)
    d2.text((cx - tw // 2 - bbox[0], cy - th // 2 - bbox[1]),
            text, fill=SYMBOL, font=font)


def draw_checkmark(img, cx, cy, scale=1.0):
    """Draw a 3D extruded checkmark centered at (cx, cy)."""
    s = scale
    # Three-point path: left top, valley (bottom), right top (higher, further out)
    # Remember PIL y increases downward.
    path = [
        (cx - int(120 * s), cy - int(30 * s)),   # left start (upper-left)
        (cx - int(40 * s),  cy + int(70 * s)),   # valley (bottom center)
        (cx + int(160 * s), cy - int(160 * s)),  # right tip (upper-right, higher)
    ]
    stroke = int(56 * s)
    # Shadow
    shadow_ellipse(img,
                   [cx - int(180 * s), cy + int(70 * s),
                    cx + int(200 * s), cy + int(120 * s)],
                   opacity=90, blur=18)
    d = ImageDraw.Draw(img)
    # Extrude pass
    ext_path = [(x + EXTRUDE[0], y + EXTRUDE[1]) for x, y in path]
    d.line(ext_path, fill=CHECK_EDGE, width=stroke, joint="curve")
    # Rounded end caps for extrude
    for x, y in ext_path:
        d.ellipse([x - stroke // 2, y - stroke // 2,
                   x + stroke // 2, y + stroke // 2], fill=CHECK_EDGE)
    # Face pass
    d.line(path, fill=CHECK_FACE, width=stroke, joint="curve")
    for x, y in path:
        d.ellipse([x - stroke // 2, y - stroke // 2,
                   x + stroke // 2, y + stroke // 2], fill=CHECK_FACE)
    # Top highlight along the upper edge of the right leg
    hl_stroke = max(6, stroke // 8)
    # Offset the two segments slightly up-left for a highlight ridge
    d.line([
        (path[0][0] + 4, path[0][1] - int(stroke * 0.35)),
        (path[1][0] + 4, path[1][1] - int(stroke * 0.35)),
    ], fill=CHECK_HILIGHT, width=hl_stroke)
    d.line([
        (path[1][0] + 4, path[1][1] - int(stroke * 0.35)),
        (path[2][0] + 4, path[2][1] - int(stroke * 0.35)),
    ], fill=CHECK_HILIGHT, width=hl_stroke)


def render(out_path: Path):
    img = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    # Coin on the left
    draw_coin(img, 370, 520, 210)
    # Checkmark on the right
    draw_checkmark(img, 730, 500, scale=1.0)
    img.convert("RGB").save(out_path)
    print(f"wrote {out_path}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    render(OUT_DIR / "cheap.png")


if __name__ == "__main__":
    main()
