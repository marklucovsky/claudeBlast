#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Programmatic generator for left/right direction tiles.

DALL-E fails reliably at rendering a clear "highlighted arrow pointing in a
specific direction" — it confuses left/right and inserts hallucinated icons.
This script renders the pair directly with PIL in a 3D-extruded style that
matches the Playful 3D set: soft warm background, chunky arrow shapes with
offset shadowing for depth, one arrow brightly highlighted per tile.

Output:
    tools/tile_sets/playful_3d/left.png   (yellow LEFT arrow + grey right)
    tools/tile_sets/playful_3d/right_.png (yellow RIGHT arrow + grey left)
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = Path("tools/tile_sets/playful_3d")
SIZE = 1024

BG = (245, 230, 210)          # warm peach, matches playful_3d palette
POST_FACE = (200, 160, 110)
POST_SIDE = (160, 120, 80)
POST_HILIGHT = (230, 200, 160)

YELLOW_FACE = (255, 210, 60)
YELLOW_SIDE = (200, 150, 20)
YELLOW_HILIGHT = (255, 245, 180)

GREY_FACE = (200, 200, 200)
GREY_SIDE = (130, 130, 130)
GREY_HILIGHT = (230, 230, 230)

EXTRUDE = (14, 18)
SHADOW_OFFSET = (18, 32)
SHADOW_BLUR = 16


def arrow_polygon(cx: int, cy: int, width: int, body_h: int, direction: str):
    head_h = int(body_h * 1.9)
    head_w = int(head_h * 0.85)
    half_w = width // 2
    half_bh = body_h // 2
    half_hh = head_h // 2

    if direction == "right":
        bl = cx - half_w
        br = cx + half_w - head_w
        tip = cx + half_w
        return [
            (bl, cy - half_bh),
            (br, cy - half_bh),
            (br, cy - half_hh),
            (tip, cy),
            (br, cy + half_hh),
            (br, cy + half_bh),
            (bl, cy + half_bh),
        ]
    # left
    br = cx + half_w
    bl = cx - half_w + head_w
    tip = cx - half_w
    return [
        (br, cy - half_bh),
        (bl, cy - half_bh),
        (bl, cy - half_hh),
        (tip, cy),
        (bl, cy + half_hh),
        (bl, cy + half_bh),
        (br, cy + half_bh),
    ]


def shift(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def draw_shadow(img: Image.Image, pts):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(shift(pts, *SHADOW_OFFSET), fill=(0, 0, 0, 90))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=SHADOW_BLUR))
    img.alpha_composite(layer)


def draw_arrow(img: Image.Image, cx: int, cy: int, width: int, body_h: int,
               direction: str, face, side, highlight):
    pts = arrow_polygon(cx, cy, width, body_h, direction)
    draw_shadow(img, pts)
    d = ImageDraw.Draw(img)
    d.polygon(shift(pts, *EXTRUDE), fill=side)
    d.polygon(pts, fill=face)
    # Top-of-body highlight strip
    d.line([pts[0], pts[1]], fill=highlight, width=8)
    # Dark outline for definition
    d.polygon(pts, outline=side)


def draw_post(img: Image.Image):
    cx = SIZE // 2
    half_w = 28
    top, bottom = 150, 900
    # shadow
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle(
        [cx - half_w + SHADOW_OFFSET[0], top + SHADOW_OFFSET[1],
         cx + half_w + SHADOW_OFFSET[0], bottom + SHADOW_OFFSET[1]],
        fill=(0, 0, 0, 70),
    )
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius=SHADOW_BLUR)))
    d = ImageDraw.Draw(img)
    d.rectangle([cx - half_w + EXTRUDE[0], top + EXTRUDE[1],
                 cx + half_w + EXTRUDE[0], bottom + EXTRUDE[1]],
                fill=POST_SIDE)
    d.rectangle([cx - half_w, top, cx + half_w, bottom], fill=POST_FACE)
    d.line([(cx - half_w, top), (cx - half_w, bottom)], fill=POST_HILIGHT, width=5)
    # Base
    d.ellipse([cx - 90, 880, cx + 90, 950], fill=POST_SIDE)
    d.ellipse([cx - 80, 870, cx + 80, 930], fill=POST_FACE)


def render(direction: str, out_path: Path):
    img = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    draw_post(img)

    arrow_w = 680
    body_h = 150
    upper_y, lower_y = 340, 660

    if direction == "left":
        draw_arrow(img, SIZE // 2, upper_y, arrow_w, body_h, "left",
                   YELLOW_FACE, YELLOW_SIDE, YELLOW_HILIGHT)
        draw_arrow(img, SIZE // 2, lower_y, arrow_w, body_h, "right",
                   GREY_FACE, GREY_SIDE, GREY_HILIGHT)
    else:
        draw_arrow(img, SIZE // 2, upper_y, arrow_w, body_h, "right",
                   YELLOW_FACE, YELLOW_SIDE, YELLOW_HILIGHT)
        draw_arrow(img, SIZE // 2, lower_y, arrow_w, body_h, "left",
                   GREY_FACE, GREY_SIDE, GREY_HILIGHT)

    img.convert("RGB").save(out_path)
    print(f"wrote {out_path}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    render("left", OUT_DIR / "left.png")
    render("right", OUT_DIR / "right_.png")


if __name__ == "__main__":
    main()
