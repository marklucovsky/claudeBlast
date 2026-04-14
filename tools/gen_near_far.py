#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Programmatic generator for near/far distance tiles.

Uses 3D extrusion style matching the Playful 3D set: offset dark copies
behind each shape for depth, soft shadows, clay-like shading.

    near — two extruded clay spheres directly touching
    far  — extruded one-point-perspective road to a tiny 3D house at horizon
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = Path("tools/tile_sets/playful_3d")
SIZE = 1024

BG = (245, 230, 210)
SKY = (185, 215, 240)
GROUND_FACE = (230, 215, 185)
GROUND_EDGE = (200, 180, 150)

ROAD_FACE = (155, 155, 160)
ROAD_EXTRUDE = (110, 110, 115)
ROAD_HILIGHT = (185, 185, 190)
LANE = (255, 250, 210)

RED_EXTRUDE = (150, 45, 45)
RED_FACE = (222, 95, 95)
RED_MID = (240, 135, 130)
RED_HILIGHT = (255, 210, 200)

BLUE_EXTRUDE = (45, 85, 145)
BLUE_FACE = (95, 150, 210)
BLUE_MID = (135, 185, 235)
BLUE_HILIGHT = (210, 235, 255)

HOUSE_WALL_FACE = (240, 225, 190)
HOUSE_WALL_SIDE = (200, 185, 150)
HOUSE_ROOF_FACE = (195, 85, 65)
HOUSE_ROOF_SIDE = (150, 60, 45)
HOUSE_DOOR = (120, 70, 40)
HOUSE_WINDOW = (200, 225, 240)

EXTRUDE_DX = 16
EXTRUDE_DY = 20
SHADOW_BLUR = 22


def shadow_layer(img: Image.Image, box, opacity=100, blur=20, shape="ellipse"):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if shape == "ellipse":
        d.ellipse(box, fill=(0, 0, 0, opacity))
    else:
        d.polygon(box, fill=(0, 0, 0, opacity))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius=blur)))


def draw_sphere_3d(img: Image.Image, cx: int, cy: int, r: int,
                   extrude, face, mid, highlight):
    """Draw a 3D extruded clay sphere with multiple shading layers."""
    # Ground shadow
    shadow_layer(
        img,
        [cx - r + 20, cy + r - 8, cx + r + 28, cy + r + 30],
        opacity=120, blur=SHADOW_BLUR,
    )
    d = ImageDraw.Draw(img)
    # Extrude (dark offset copy behind)
    d.ellipse([cx - r + EXTRUDE_DX, cy - r + EXTRUDE_DY,
               cx + r + EXTRUDE_DX, cy + r + EXTRUDE_DY], fill=extrude)
    # Main sphere body
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=face)
    # Mid-tone layer (upper-left bias for lighting)
    inset = int(r * 0.18)
    d.ellipse([cx - r + inset, cy - r + inset,
               cx + r - inset - 16, cy + r - inset - 16], fill=mid)
    # Specular highlight (bright spot upper-left)
    hr = int(r * 0.28)
    hx = cx - int(r * 0.30)
    hy = cy - int(r * 0.30)
    # Soft highlight via blurred white circle
    hl_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(hl_layer).ellipse(
        [hx - hr, hy - hr, hx + hr, hy + hr],
        fill=highlight + (200,),
    )
    img.alpha_composite(hl_layer.filter(ImageFilter.GaussianBlur(radius=12)))
    # Tiny bright dot
    dot_r = int(r * 0.08)
    d2 = ImageDraw.Draw(img)
    d2.ellipse([hx - dot_r + 8, hy - dot_r + 8,
                hx + dot_r + 8, hy + dot_r + 8],
               fill=(255, 255, 255, 220))
    # Dark outline for definition
    d2.ellipse([cx - r, cy - r, cx + r, cy + r], outline=extrude, width=3)


def render_near(out_path: Path):
    img = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    r = 210
    gap = -25
    cy = SIZE // 2 + 30
    cx_left = SIZE // 2 - r - gap // 2
    cx_right = SIZE // 2 + r + gap // 2
    # Blue behind, red in front (overlapping = touching)
    draw_sphere_3d(img, cx_right, cy, r,
                   BLUE_EXTRUDE, BLUE_FACE, BLUE_MID, BLUE_HILIGHT)
    draw_sphere_3d(img, cx_left, cy, r,
                   RED_EXTRUDE, RED_FACE, RED_MID, RED_HILIGHT)
    img.convert("RGB").save(out_path)
    print(f"wrote {out_path}")


def shift_pts(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def render_far(out_path: Path):
    img = Image.new("RGBA", (SIZE, SIZE), SKY + (255,))
    d = ImageDraw.Draw(img)
    horizon = int(SIZE * 0.50)

    # Ground with extruded edge
    d.rectangle([0, horizon + 8, SIZE, SIZE], fill=GROUND_EDGE)
    d.rectangle([0, horizon, SIZE, SIZE - 8], fill=GROUND_FACE)

    vp_x = SIZE // 2
    vp_y = horizon
    road_bw = 250  # half-width at bottom
    road_tw = 12   # half-width at top

    road_pts = [
        (vp_x - road_bw, SIZE),
        (vp_x + road_bw, SIZE),
        (vp_x + road_tw, vp_y),
        (vp_x - road_tw, vp_y),
    ]

    # Road shadow
    shadow_layer(img, shift_pts(road_pts, 10, 12), opacity=70, blur=18, shape="poly")

    # Road extrude (dark offset)
    d.polygon(shift_pts(road_pts, 6, 8), fill=ROAD_EXTRUDE)
    # Road face
    d.polygon(road_pts, fill=ROAD_FACE)
    # Road highlight strip along top edge
    d.line([road_pts[3], road_pts[2]], fill=ROAD_HILIGHT, width=3)

    # Shoulder stripes (extruded edge lines)
    for side in (-1, 1):
        for i in range(3):
            t = i / 3
            bw = road_bw + 20 + i * 8
            tw = road_tw + 2 + i * 1
            stripe = [
                (vp_x + side * bw, SIZE),
                (vp_x + side * (bw + 12), SIZE),
                (vp_x + side * (tw + 2), vp_y),
                (vp_x + side * tw, vp_y),
            ]
            c = GROUND_EDGE if i > 0 else ROAD_EXTRUDE
            d.polygon(stripe, fill=c)

    # Lane dashes with extrusion
    def lerp(a, b, t):
        return a + (b - a) * t
    n = 8
    for i in range(n):
        t1 = (i + 0.15) / n
        t2 = (i + 0.75) / n
        cy1 = lerp(SIZE, vp_y, t1)
        cy2 = lerp(SIZE, vp_y, t2)
        w1 = lerp(12, 1, t1)
        w2 = lerp(12, 1, t2)
        dash_pts = [
            (vp_x - w1, cy1), (vp_x + w1, cy1),
            (vp_x + w2, cy2), (vp_x - w2, cy2),
        ]
        # Dash extrude
        d.polygon(shift_pts(dash_pts, 3, 4), fill=(200, 195, 150))
        d.polygon(dash_pts, fill=LANE)

    # 3D house at vanishing point
    hx, hy = vp_x + 8, vp_y - 12
    hw, hh = 36, 30

    # House shadow
    shadow_layer(img, [hx - hw - 4, hy + 4, hx + hw + 8, hy + 16],
                 opacity=80, blur=6)

    # House side wall (extrude)
    side_pts = [
        (hx + hw, hy - hh), (hx + hw + 10, hy - hh + 6),
        (hx + hw + 10, hy + 6), (hx + hw, hy),
    ]
    d.polygon(side_pts, fill=HOUSE_WALL_SIDE)

    # House front wall
    d.rectangle([hx - hw, hy - hh, hx + hw, hy], fill=HOUSE_WALL_FACE)
    d.rectangle([hx - hw, hy - hh, hx + hw, hy], outline=HOUSE_WALL_SIDE, width=2)

    # Roof extrude
    roof_top = (hx, hy - hh - 24)
    roof_left = (hx - hw - 8, hy - hh)
    roof_right = (hx + hw + 8, hy - hh)
    roof_extrude_top = (hx + 8, hy - hh - 20)
    roof_extrude_right = (hx + hw + 16, hy - hh + 6)
    d.polygon([roof_top, roof_right, roof_extrude_right, roof_extrude_top],
              fill=HOUSE_ROOF_SIDE)
    # Roof face
    d.polygon([roof_top, roof_left, roof_right], fill=HOUSE_ROOF_FACE)
    d.polygon([roof_top, roof_left, roof_right], outline=HOUSE_ROOF_SIDE, width=2)

    # Door
    d.rectangle([hx - 7, hy - 18, hx + 7, hy], fill=HOUSE_DOOR)
    # Window
    d.rectangle([hx + 13, hy - 20, hx + 25, hy - 10], fill=HOUSE_WINDOW)
    d.rectangle([hx + 13, hy - 20, hx + 25, hy - 10], outline=HOUSE_WALL_SIDE, width=1)

    img.convert("RGB").save(out_path)
    print(f"wrote {out_path}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    render_near(OUT_DIR / "near.png")
    render_far(OUT_DIR / "far.png")


if __name__ == "__main__":
    main()
