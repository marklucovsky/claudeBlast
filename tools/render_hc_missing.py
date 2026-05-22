#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Render the shared high-contrast missing-image placeholder.

When a tile has no high_contrast artwork (e.g. the 18 core grammar tiles
added in the Core-First worktree), TileImageResolver falls back to this
single image rather than generating bespoke HC art. Visual: solid black
background with a bold white "?" centered, plus a small red accent dot
to signal "art still pending" without breaking the HC aesthetic.

Output:
    tools/tile_sets/high_contrast/hc_missing.png
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_FILE = Path("tools/tile_sets/high_contrast/hc_missing.png")
SIZE = 1024
BG = (0, 0, 0)
FG = (255, 255, 255)
ACCENT = (220, 40, 40)

FONT_CANDIDATES = [
    ("/System/Library/Fonts/Helvetica.ttc", 1),
    ("/System/Library/Fonts/Helvetica.ttc", 0),
    ("/System/Library/Fonts/HelveticaNeue.ttc", 9),
]


def load_font(target_px: int) -> ImageFont.FreeTypeFont:
    for path, index in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, target_px, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)

    # Bold white "?" centered, sized to fill ~60% of the canvas.
    font = load_font(int(SIZE * 0.62))
    text = "?"
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx = (SIZE - tw) // 2 - bbox[0]
    cy = (SIZE - th) // 2 - bbox[1]
    d.text((cx, cy), text, fill=FG, font=font)

    # Small red accent dot in the lower-right quadrant: signals "art
    # pending" without intruding on the question mark's silhouette.
    r = SIZE // 32
    cx2, cy2 = SIZE - SIZE // 8, SIZE - SIZE // 8
    d.ellipse((cx2 - r, cy2 - r, cx2 + r, cy2 + r), fill=ACCENT)

    img.save(OUT_FILE, "PNG", optimize=True)
    print(f"Wrote {OUT_FILE} ({OUT_FILE.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
