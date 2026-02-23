#!/usr/bin/env python3
"""
Generate a contact sheet (grid of tile thumbnails) for visual review.

Usage:
    # Home page tiles:
    python3 tools/contact_sheet.py --page home --output /tmp/contact_home.png

    # All tiles:
    python3 tools/contact_sheet.py --output /tmp/contact_all.png

    # Custom key list (comma-separated):
    python3 tools/contact_sheet.py --keys "apple,banana,orange" --output /tmp/contact.png

    # Compare two sets side-by-side (for ARASAAC vs DALL-E review):
    python3 tools/contact_sheet.py --page home --compare /path/to/dalle/assets \
        --output /tmp/contact_compare.png
"""

import argparse
import json
from pathlib import Path
from typing import Optional

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    import sys
    sys.exit("Missing dependency: pip install pillow")

ASSETS = Path("claudeBlast/Assets.xcassets")
PAGES_JSON = Path("claudeBlast/Resources/pages.json")
VOCAB_JSON = Path("reference/vocabulary/vocabulary.json")

THUMB_SIZE = 160        # px per tile
PADDING = 8             # px between tiles
LABEL_HEIGHT = 24       # px below each tile for key name
HEADER_HEIGHT = 48      # px at top for sheet title
BG_COLOR = (240, 240, 240)
TILE_BG = (255, 255, 255)
LABEL_COLOR = (60, 60, 60)
HEADER_COLOR = (30, 30, 30)
MISSING_COLOR = (220, 60, 60)
COLS = 7                # tiles per row


def get_page_keys(page_name: str) -> list[str]:
    """Return tile keys for a named page from pages.json."""
    if not PAGES_JSON.exists():
        raise FileNotFoundError(f"pages.json not found at {PAGES_JSON}")
    pages = json.loads(PAGES_JSON.read_text())
    for page in pages:
        if page.get("key") == page_name or page.get("displayName") == page_name:
            # pages.json uses "pageTiles" (not "tiles")
            tiles = page.get("pageTiles", page.get("tiles", []))
            return [t["key"] for t in tiles if "key" in t]
    raise ValueError(f"Page '{page_name}' not found in pages.json")


def get_all_keys() -> list[str]:
    """Return all unique tile keys from vocabulary.json."""
    vocab = json.loads(VOCAB_JSON.read_text())
    seen = set()
    keys = []
    for t in vocab:
        k = t["key"]
        if k not in seen:
            seen.add(k)
            keys.append(k)
    return keys


def load_image(key: str, assets_root: Path) -> Optional[Image.Image]:
    """Load tile PNG for key, return None if missing."""
    png = assets_root / f"{key}.imageset" / f"{key}.png"
    if not png.exists():
        return None
    try:
        return Image.open(png).convert("RGBA")
    except Exception:
        return None


def make_tile_cell(img: Optional[Image.Image], label: str,
                   size: int, label_h: int) -> Image.Image:
    """Render one cell: white square with image + label below."""
    cell_h = size + label_h
    cell = Image.new("RGBA", (size, cell_h), TILE_BG + (255,))
    draw = ImageDraw.Draw(cell)

    if img is not None:
        thumb = img.copy()
        thumb.thumbnail((size, size), Image.LANCZOS)
        # Centre in the tile square
        ox = (size - thumb.width) // 2
        oy = (size - thumb.height) // 2
        # Paste with alpha mask
        cell.paste(thumb, (ox, oy), thumb if thumb.mode == "RGBA" else None)
    else:
        # Draw a red X for missing images
        draw.rectangle([4, 4, size - 4, size - 4], outline=MISSING_COLOR, width=2)
        draw.line([4, 4, size - 4, size - 4], fill=MISSING_COLOR, width=2)
        draw.line([size - 4, 4, 4, size - 4], fill=MISSING_COLOR, width=2)

    # Label
    short_label = label if len(label) <= 18 else label[:17] + "…"
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 11)
    except OSError:
        font = ImageFont.load_default()

    # Centre the label
    bbox = draw.textbbox((0, 0), short_label, font=font)
    tw = bbox[2] - bbox[0]
    tx = max(2, (size - tw) // 2)
    draw.text((tx, size + 2), short_label, fill=LABEL_COLOR, font=font)

    return cell


def build_sheet(keys: list[str], assets_root: Path, title: str,
                cols: int = COLS) -> Image.Image:
    """Build a complete contact sheet image."""
    rows = (len(keys) + cols - 1) // cols
    cell_w = THUMB_SIZE + PADDING
    cell_h = THUMB_SIZE + LABEL_HEIGHT + PADDING

    sheet_w = cols * cell_w + PADDING
    sheet_h = HEADER_HEIGHT + rows * cell_h + PADDING

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG_COLOR)
    draw = ImageDraw.Draw(sheet)

    # Header
    try:
        hfont = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
    except OSError:
        hfont = ImageFont.load_default()
    draw.text((PADDING, PADDING), title, fill=HEADER_COLOR, font=hfont)

    # Count missing
    missing_count = 0

    for i, key in enumerate(keys):
        row = i // cols
        col = i % cols
        x = PADDING + col * cell_w
        y = HEADER_HEIGHT + row * cell_h

        img = load_image(key, assets_root)
        if img is None:
            missing_count += 1

        cell = make_tile_cell(img, key, THUMB_SIZE, LABEL_HEIGHT)
        sheet.paste(cell.convert("RGB"), (x, y))

    # Footer: summary
    try:
        sfont = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
    except OSError:
        sfont = ImageFont.load_default()

    summary = f"{len(keys)} tiles  |  {missing_count} missing"
    draw.text((PADDING, sheet_h - 20), summary, fill=LABEL_COLOR, font=sfont)

    return sheet


def build_comparison_sheet(keys: list[str],
                           left_assets: Path, right_assets: Path,
                           left_label: str, right_label: str,
                           title: str) -> Image.Image:
    """Build a side-by-side comparison sheet (left=ARASAAC, right=DALL-E)."""
    # Each row: key label | left image | right image
    row_h = THUMB_SIZE + LABEL_HEIGHT + PADDING
    label_col_w = 140
    img_col_w = THUMB_SIZE + PADDING
    sheet_w = label_col_w + 2 * img_col_w + PADDING
    sheet_h = HEADER_HEIGHT + 30 + len(keys) * row_h + PADDING

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG_COLOR)
    draw = ImageDraw.Draw(sheet)

    try:
        hfont = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
        bfont = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
        kfont = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 11)
    except OSError:
        hfont = bfont = kfont = ImageFont.load_default()

    # Header
    draw.text((PADDING, PADDING), title, fill=HEADER_COLOR, font=hfont)
    # Column headers
    col_y = HEADER_HEIGHT
    draw.text((label_col_w, col_y), left_label, fill=HEADER_COLOR, font=bfont)
    draw.text((label_col_w + img_col_w, col_y), right_label, fill=HEADER_COLOR, font=bfont)

    for i, key in enumerate(keys):
        y = HEADER_HEIGHT + 30 + i * row_h

        # Key label
        short_key = key if len(key) <= 20 else key[:19] + "…"
        draw.text((PADDING, y + THUMB_SIZE // 2 - 8), short_key, fill=LABEL_COLOR, font=kfont)

        # Left image
        left_img = load_image(key, left_assets)
        left_cell = make_tile_cell(left_img, "", THUMB_SIZE, 0)
        sheet.paste(left_cell.convert("RGB"), (label_col_w, y))

        # Right image
        right_img = load_image(key, right_assets)
        right_cell = make_tile_cell(right_img, "", THUMB_SIZE, 0)
        sheet.paste(right_cell.convert("RGB"), (label_col_w + img_col_w, y))

    return sheet


def main():
    parser = argparse.ArgumentParser(description="Generate tile contact sheets")
    parser.add_argument("--page", metavar="NAME",
                        help="Page name from pages.json (e.g. 'home')")
    parser.add_argument("--keys", metavar="K1,K2,...",
                        help="Comma-separated tile keys")
    parser.add_argument("--all", action="store_true", help="All vocabulary tiles")
    parser.add_argument("--assets", default=str(ASSETS),
                        help=f"Assets.xcassets root (default: {ASSETS})")
    parser.add_argument("--compare", metavar="ASSETS2",
                        help="Second assets root to compare side-by-side")
    parser.add_argument("--left-label", default="ARASAAC")
    parser.add_argument("--right-label", default="DALL-E 3")
    parser.add_argument("--cols", type=int, default=COLS)
    parser.add_argument("--output", required=True, metavar="PATH",
                        help="Output PNG path")
    args = parser.parse_args()

    assets_root = Path(args.assets)

    # Determine key list
    if args.page:
        keys = get_page_keys(args.page)
        title = f"Home page tiles  —  ARASAAC  ({len(keys)} tiles)"
        if args.page != "home":
            title = f"'{args.page}' page tiles  ({len(keys)} tiles)"
    elif args.keys:
        keys = [k.strip() for k in args.keys.split(",")]
        title = f"Selected tiles  ({len(keys)} tiles)"
    elif args.all:
        keys = get_all_keys()
        title = f"All vocabulary tiles  ({len(keys)} tiles)"
    else:
        parser.error("Specify --page, --keys, or --all")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if args.compare:
        compare_root = Path(args.compare)
        print(f"Building comparison sheet ({len(keys)} tiles)…")
        sheet = build_comparison_sheet(
            keys, assets_root, compare_root,
            args.left_label, args.right_label,
            f"{args.left_label} vs {args.right_label}  —  {args.page or 'custom'} tiles"
        )
    else:
        print(f"Building contact sheet ({len(keys)} tiles)…")
        sheet = build_sheet(keys, assets_root, title, cols=args.cols)

    sheet.save(out_path)
    print(f"Saved → {out_path}  ({sheet.width}×{sheet.height}px)")


if __name__ == "__main__":
    main()
