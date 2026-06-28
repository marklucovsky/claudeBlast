#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Montage a tile set directory into labeled contact sheets for fast visual QA.

Reads tools/tile_sets/<set>/*.png, lays them out in a labeled grid, and writes
paginated sheets so many tiles can be scanned in a single image. Safe to run
while a generation job is still writing the directory (unreadable files skip).

Usage:
    python3 tools/montage_set.py --set classic --out /tmp/classic_sheet
    # → /tmp/classic_sheet_01.png, _02.png, ...
"""

import argparse
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    import sys
    sys.exit("pip install pillow")

THUMB = 150
LABEL_H = 20
PAD = 6
COLS = 6
ROWS = 6  # 36 tiles per sheet


def load_font(size: int):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True)
    ap.add_argument("--out", required=True, help="output path prefix")
    ap.add_argument("--cols", type=int, default=COLS)
    ap.add_argument("--rows", type=int, default=ROWS)
    args = ap.parse_args()

    src = Path("tools/tile_sets") / args.set
    pngs = sorted(src.glob("*.png"))
    if not pngs:
        import sys
        sys.exit(f"No PNGs in {src}")

    per_sheet = args.cols * args.rows
    cell_w = THUMB + PAD
    cell_h = THUMB + LABEL_H + PAD
    font = load_font(13)
    sheet_count = 0

    for start in range(0, len(pngs), per_sheet):
        chunk = pngs[start:start + per_sheet]
        sheet_count += 1
        sheet_w = args.cols * cell_w + PAD
        sheet_h = args.rows * cell_h + PAD
        sheet = Image.new("RGB", (sheet_w, sheet_h), (245, 245, 247))
        draw = ImageDraw.Draw(sheet)
        for i, png in enumerate(chunk):
            r, c = divmod(i, args.cols)
            x = PAD + c * cell_w
            y = PAD + r * cell_h
            try:
                im = Image.open(png).convert("RGBA")
            except Exception:
                continue  # mid-write or corrupt — skip
            im.thumbnail((THUMB, THUMB), Image.LANCZOS)
            bg = Image.new("RGB", (THUMB, THUMB), (255, 255, 255))
            bg.paste(im, ((THUMB - im.width) // 2, (THUMB - im.height) // 2),
                     im if im.mode == "RGBA" else None)
            sheet.paste(bg, (x, y))
            draw.text((x + 2, y + THUMB + 3), png.stem, fill=(40, 40, 40), font=font)
        out = f"{args.out}_{sheet_count:02d}.png"
        sheet.save(out)
        print(f"wrote {out} ({len(chunk)} tiles)")

    print(f"{sheet_count} sheet(s), {len(pngs)} tiles total")


if __name__ == "__main__":
    main()
