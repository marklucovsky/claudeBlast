#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Render the `colors` and `shape` page-category tiles.

`colors`: grid of all sphere colors, mini.
`shape`: trio of circle + square + triangle in extruded 3D, mini.

Same warm cream background and shadow conventions as the per-tile renderers.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

# Reuse renderers from sibling modules.
import sys
sys.path.insert(0, str(Path(__file__).parent))
from render_color_spheres import render_sphere, COLORS, BG, W as TILE_W  # noqa
from render_shapes import shape_mask, shade, SHAPE_COLORS  # noqa


def thumb(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def crop_to_subject(img: Image.Image, pad: int = 30) -> Image.Image:
    """Crop down to the non-background area, plus pad."""
    arr = np.array(img.convert("RGB"))
    bg = np.array(BG)
    diff = np.any(np.abs(arr.astype(int) - bg.astype(int)) > 8, axis=-1)
    ys, xs = np.where(diff)
    if not len(xs):
        return img
    x0, x1 = max(0, xs.min() - pad), min(arr.shape[1], xs.max() + pad)
    y0, y1 = max(0, ys.min() - pad), min(arr.shape[0], ys.max() + pad)
    return img.crop((x0, y0, x1, y1))


def render_colors_tile() -> Image.Image:
    """5×3 grid of mini spheres, warm-cream background, soft drop shadow band."""
    canvas = Image.new("RGB", (TILE_W, TILE_W), BG)
    cell = 180
    cols, rows = 5, 3
    margin_x = (TILE_W - cols * cell) // 2
    margin_y = (TILE_W - rows * cell) // 2

    keys = list(COLORS.keys())
    for i, k in enumerate(keys[: cols * rows]):
        sphere = crop_to_subject(render_sphere(COLORS[k]))
        mini = thumb(sphere, cell)
        col, row = i % cols, i // cols
        x = margin_x + col * cell
        y = margin_y + row * cell
        canvas.paste(mini, (x, y))
    return canvas


def render_shape_tile() -> Image.Image:
    canvas = Image.new("RGB", (TILE_W, TILE_W), BG)
    picks = ["circle", "square", "triangle"]
    cell = 320
    gap = 30
    total_w = cell * len(picks) + gap * (len(picks) - 1)
    x0 = (TILE_W - total_w) // 2
    y0 = (TILE_W - cell) // 2

    for i, name in enumerate(picks):
        mask = shape_mask(name)
        full = shade(mask, SHAPE_COLORS[name])
        cropped = crop_to_subject(full)
        mini = thumb(cropped, cell)
        x = x0 + i * (cell + gap)
        canvas.paste(mini, (x, y0))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="tools/tile_sets/playful_3d_v2")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    img = render_colors_tile()
    img.save(out / "colors.png")
    print(f"  wrote {out}/colors.png")

    img = render_shape_tile()
    img.save(out / "shape.png")
    print(f"  wrote {out}/shape.png")


if __name__ == "__main__":
    main()
