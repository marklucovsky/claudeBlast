#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Deterministic high-contrast renderer for tiles where DALL-E reliably fails:

- Nav arrows: get surrounded by a grid of accessibility/payment/wheelchair icons.
- Question glyph: gets stylized into rings/spirals or framed with secondary glyphs.
- "food" composition: hallucinates extra arcs, bones, donuts, frames.

These shapes are simple enough to draw directly with PIL primitives.

Output:
    tools/tile_sets/high_contrast/next_page.png
    tools/tile_sets/high_contrast/previous_page.png
    tools/tile_sets/high_contrast/question.png
    tools/tile_sets/high_contrast/food.png
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path("tools/tile_sets/high_contrast")
SIZE = 1024
BG = (0, 0, 0)
FG = (255, 255, 255)

RED = (220, 40, 40)
GREEN = (60, 160, 70)
BROWN = (110, 65, 30)
BREAD_FACE = (235, 180, 90)
BREAD_HIGHLIGHT = (255, 215, 140)
DRUMSTICK_FACE = (200, 130, 60)
DRUMSTICK_HIGHLIGHT = (235, 180, 100)
BONE_WHITE = (245, 245, 240)

FONT_CANDIDATES = [
    ("/System/Library/Fonts/Helvetica.ttc", 1),   # try Bold first
    ("/System/Library/Fonts/Helvetica.ttc", 0),
    ("/System/Library/Fonts/HelveticaNeue.ttc", 9),
    ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
    ("/System/Library/Fonts/ArialHB.ttc", 0),
]


# --- arrows -----------------------------------------------------------------

def arrow_polygon(direction: str):
    cx, cy = SIZE // 2, SIZE // 2
    shaft_half_h = 110
    head_half_h = 280
    head_w = 360
    shaft_len = 540

    if direction == "right":
        tail_x = cx - shaft_len // 2 - head_w // 2
        head_base_x = cx + shaft_len // 2 - head_w // 2
        tip_x = head_base_x + head_w
        return [
            (tail_x, cy - shaft_half_h),
            (head_base_x, cy - shaft_half_h),
            (head_base_x, cy - head_half_h),
            (tip_x, cy),
            (head_base_x, cy + head_half_h),
            (head_base_x, cy + shaft_half_h),
            (tail_x, cy + shaft_half_h),
        ]
    tail_x = cx + shaft_len // 2 + head_w // 2
    head_base_x = cx - shaft_len // 2 + head_w // 2
    tip_x = head_base_x - head_w
    return [
        (tail_x, cy - shaft_half_h),
        (head_base_x, cy - shaft_half_h),
        (head_base_x, cy - head_half_h),
        (tip_x, cy),
        (head_base_x, cy + head_half_h),
        (head_base_x, cy + shaft_half_h),
        (tail_x, cy + shaft_half_h),
    ]


def render_arrow(direction: str, out_path: Path):
    img = Image.new("RGB", (SIZE, SIZE), BG)
    ImageDraw.Draw(img).polygon(arrow_polygon(direction), fill=FG)
    img.save(out_path)
    print(f"wrote {out_path}")


# --- question glyph ---------------------------------------------------------

def load_bold_font(size: int) -> ImageFont.FreeTypeFont:
    for path, idx in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size, index=idx)
        except (OSError, IndexError):
            continue
    raise SystemExit("No suitable bold sans-serif font found")


def render_question(out_path: Path):
    img = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)
    font = load_bold_font(720)
    # stroke_width thickens the glyph so it reads as truly bold even if the
    # font weight available isn't quite black.
    bbox = draw.textbbox((0, 0), "?", font=font, anchor="lt", stroke_width=24)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    cx = (SIZE - w) // 2 - bbox[0]
    cy = (SIZE - h) // 2 - bbox[1]
    draw.text((cx, cy), "?", fill=FG, font=font, stroke_width=24, stroke_fill=FG)
    img.save(out_path)
    print(f"wrote {out_path}")


# --- food composition -------------------------------------------------------

def _outline(draw, shape_fn, *args, **kwargs):
    shape_fn(*args, fill=kwargs["fill"], outline=FG, width=10)


def render_food(out_path: Path):
    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)

    # White plate — horizontal ellipse near the vertical center; items will
    # rest on its top half so they read as "on the plate."
    plate_cx, plate_cy = SIZE // 2, 660
    plate_w, plate_h = 880, 220
    d.ellipse([plate_cx - plate_w // 2, plate_cy - plate_h // 2,
               plate_cx + plate_w // 2, plate_cy + plate_h // 2],
              fill=FG, outline=FG)

    items_baseline = plate_cy - 30  # vertical center of items, on the plate

    # Apple — left
    apple_cx, apple_cy = 290, items_baseline
    apple_r = 165
    d.ellipse([apple_cx - apple_r, apple_cy - apple_r,
               apple_cx + apple_r, apple_cy + apple_r],
              fill=RED, outline=FG, width=10)
    # stem
    d.rectangle([apple_cx - 10, apple_cy - apple_r - 50,
                 apple_cx + 10, apple_cy - apple_r + 10], fill=BROWN)
    # leaf
    d.polygon([
        (apple_cx + 10, apple_cy - apple_r - 25),
        (apple_cx + 105, apple_cy - apple_r - 65),
        (apple_cx + 65, apple_cy - apple_r + 5),
    ], fill=GREEN, outline=FG)

    # Bread roll — middle (oval, smaller than apple/drumstick so it nests)
    bread_cx, bread_cy = SIZE // 2, items_baseline + 20
    bw, bh = 175, 115
    d.ellipse([bread_cx - bw, bread_cy - bh, bread_cx + bw, bread_cy + bh],
              fill=BREAD_FACE, outline=FG, width=10)
    # surface highlight slits
    for offset in (-65, 0, 65):
        d.line([(bread_cx + offset - 25, bread_cy - 25),
                (bread_cx + offset + 25, bread_cy - 25)],
               fill=BREAD_HIGHLIGHT, width=10)

    # Drumstick — right side of plate.
    # Egg/teardrop-shaped meat (chicken-thigh proportion) drawn as a
    # vertical ellipse, with a stubby white bone rising straight up from
    # the top, capped by a knuckle ball.
    drum_cx = 800
    meat_top = items_baseline - 80
    meat_bottom = items_baseline + 220
    meat_half_w = 145
    # Meat as a tall ellipse with a small upward narrowing
    d.ellipse([drum_cx - meat_half_w, meat_top,
               drum_cx + meat_half_w, meat_bottom],
              fill=DRUMSTICK_FACE, outline=FG, width=10)
    # meat highlight on the upper-left
    d.ellipse([drum_cx - 95, items_baseline - 30,
               drum_cx - 25, items_baseline + 30],
              fill=DRUMSTICK_HIGHLIGHT, outline=None)

    # Bone shaft — vertical rectangle rising straight from the top of meat
    bone_half_w = 35
    bone_top = meat_top - 150
    d.rectangle([drum_cx - bone_half_w, bone_top + 40,
                 drum_cx + bone_half_w, meat_top + 35],
                fill=BONE_WHITE, outline=FG, width=6)
    # Knuckle ball on top of bone
    d.ellipse([drum_cx - 65, bone_top - 30,
               drum_cx + 65, bone_top + 90],
              fill=BONE_WHITE, outline=FG, width=8)

    img.save(out_path)
    print(f"wrote {out_path}")


# --- main -------------------------------------------------------------------

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    render_arrow("right", OUT_DIR / "next_page.png")
    render_arrow("left", OUT_DIR / "previous_page.png")
    render_question(OUT_DIR / "question.png")
    render_food(OUT_DIR / "food.png")


if __name__ == "__main__":
    main()
