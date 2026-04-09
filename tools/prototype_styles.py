#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Generate style prototype tiles for evaluating Blaster's custom image set direction.

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/prototype_styles.py [--dry-run]

Generates 3 style variations × 4 tiles = 12 images into tools/prototypes/
Then builds a contact sheet (tools/prototypes/contact_sheet.png) for easy comparison.
"""

import json
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

try:
    from PIL import Image
except ImportError:
    Image = None  # contact sheet will be skipped

OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations"
OUT_DIR = Path("tools/prototypes")
SLEEP_SECONDS = 15

# --- Style definitions -------------------------------------------------------

STYLE_COMMON = "No text, no letters, no words, no labels. Square format. Single clear subject centered."

STYLES = {
    "playful_3d": {
        "label": "Playful 3D",
        "prefix": (
            "Modern 3D-rendered AAC symbol in a soft clay/plasticine style. "
            "Rounded shapes, gentle lighting, subtle shadows, pastel-bright palette. "
            "Friendly and approachable, like a Pixar prop. Light solid-color background. "
        ),
    },
    "bold_flat": {
        "label": "Bold Flat",
        "prefix": (
            "Modern flat-design AAC symbol with bold geometric shapes and thick outlines. "
            "Vibrant saturated colors, clean vector look, minimal detail. "
            "Inspired by modern app icon design (Duolingo, Headspace). White background. "
        ),
    },
    "soft_watercolor": {
        "label": "Soft Watercolor",
        "prefix": (
            "Gentle watercolor-style AAC symbol with soft edges and warm tones. "
            "Hand-painted feel, slightly textured, inviting and calming. "
            "Muted but cheerful palette. Off-white paper-like background. "
        ),
    },
    "high_contrast": {
        "label": "High Contrast",
        "prefix": (
            "High-contrast AAC pictogram in the Sclera symbol style. "
            "White simplified figures and objects on a solid black background. "
            "Bold outlines, no shading, no gradients, no color — pure white on black. "
            "Stick-figure people with round heads, minimal detail, maximum clarity. "
            "Designed for visual accessibility. "
        ),
    },
}

# Asset catalog path for current ARASAAC images
ASSETS_DIR = Path("claudeBlast/Assets.xcassets")

# --- Tile subjects ------------------------------------------------------------

TILES = {
    "people": {
        "subject": "a group of three diverse people (adult, child, elderly) standing together, friendly and welcoming",
    },
    "food": {
        "subject": "a plate with colorful food — an apple, a sandwich, and a carrot — arranged appetizingly",
    },
    "playground": {
        "subject": "a colorful playground with a slide, swings, and a climbing frame, fun and inviting",
    },
    "home": {
        "subject": "a cozy house with a triangular roof, round door, two windows, and a little chimney",
    },
}


def generate_image(prompt: str, api_key: str, session: requests.Session) -> bytes | None:
    payload = {
        "model": "dall-e-3",
        "prompt": prompt,
        "n": 1,
        "size": "1024x1024",
        "quality": "standard",
        "response_format": "url",
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    try:
        r = session.post(OPENAI_IMAGE_URL, json=payload, headers=headers, timeout=60)
        r.raise_for_status()
        image_url = r.json()["data"][0]["url"]
    except (requests.RequestException, KeyError, IndexError) as e:
        print(f"  [generation error: {e}]")
        return None
    try:
        img_r = session.get(image_url, timeout=30)
        img_r.raise_for_status()
        return img_r.content
    except requests.RequestException as e:
        print(f"  [download error: {e}]")
        return None


def build_contact_sheet(out_dir: Path) -> None:
    """Build a labeled grid: rows = tiles, columns = current + styles."""
    if Image is None:
        print("\nSkipping contact sheet (pip install Pillow to enable)")
        return

    from PIL import ImageDraw, ImageFont

    tile_keys = list(TILES.keys())
    style_keys = list(STYLES.keys())
    # First column is "Current" (ARASAAC), then each style
    all_columns = ["current"] + style_keys
    col_labels = ["Current (ARASAAC)"] + [STYLES[sk]["label"] for sk in style_keys]

    cell = 400
    label_h = 40
    margin = 8
    cols = len(all_columns)
    rows = len(tile_keys)
    width = cols * (cell + margin) + margin
    height = label_h + rows * (cell + label_h + margin) + margin

    sheet = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
    except Exception:
        font = ImageFont.load_default()

    # Column headers
    for ci, label in enumerate(col_labels):
        x = margin + ci * (cell + margin)
        draw.text((x + cell // 2, 8), label, fill="black", font=font, anchor="mt")

    for ri, tk in enumerate(tile_keys):
        y = label_h + margin + ri * (cell + label_h + margin)

        for ci, col_key in enumerate(all_columns):
            x = margin + ci * (cell + margin)

            if col_key == "current":
                # Load from asset catalog
                img_path = ASSETS_DIR / f"{tk}.imageset" / f"{tk}.png"
            else:
                img_path = out_dir / f"{tk}_{col_key}.png"

            if not img_path.exists():
                # Draw placeholder
                draw.rectangle([x, y, x + cell, y + cell], fill="#f0f0f0", outline="#ccc")
                draw.text((x + cell // 2, y + cell // 2), "N/A", fill="#999", font=font, anchor="mm")
            else:
                thumb = Image.open(img_path).resize((cell, cell), Image.LANCZOS)
                sheet.paste(thumb, (x, y))

            # Row label under first column only
            if ci == 0:
                draw.text((x + cell // 2, y + cell + 4), tk, fill="black", font=font, anchor="mt")

    out_path = out_dir / "contact_sheet.png"
    sheet.save(out_path)
    print(f"\nContact sheet saved: {out_path}")


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    generated = 0
    failed = 0

    for tile_key, tile_info in TILES.items():
        for style_key, style_info in STYLES.items():
            filename = f"{tile_key}_{style_key}.png"
            dest = OUT_DIR / filename

            prompt = f"{style_info['prefix']}{tile_info['subject']}. {STYLE_COMMON}"

            if args.dry_run:
                print(f"[DRY-RUN] {filename}")
                print(f"  {prompt[:120]}...")
                print()
                generated += 1
                continue

            if dest.exists() and dest.stat().st_size > 50_000:
                print(f"→ {filename:40s} (exists, skipping)")
                generated += 1
                continue

            print(f"⏳ {filename:40s} generating…", end="", flush=True)
            png_bytes = generate_image(prompt, api_key, session)

            if png_bytes and len(png_bytes) >= 50_000:
                dest.write_bytes(png_bytes)
                print(f"  ✓ {len(png_bytes) // 1024} KB")
                generated += 1
            else:
                print("  FAILED")
                failed += 1

            time.sleep(SLEEP_SECONDS)

    print(f"\nDone: {generated} generated, {failed} failed")

    if not args.dry_run:
        build_contact_sheet(OUT_DIR)


if __name__ == "__main__":
    main()
