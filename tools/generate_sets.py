#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Generate two complete tile image sets for Blaster:
  1. playful_3d  — soft clay/plasticine 3D style, pastel-bright
  2. high_contrast — white on black, Sclera-inspired accessibility style

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/generate_sets.py --set playful_3d [--skip-existing] [--key KEY] [--dry-run] [--batch N]
    python3 tools/generate_sets.py --set high_contrast [--skip-existing] [--key KEY] [--dry-run] [--batch N]
    python3 tools/generate_sets.py --set both [--skip-existing] [--dry-run] [--batch N]

Output:
    tools/tile_sets/playful_3d/{key}.png
    tools/tile_sets/high_contrast/{key}.png

Cost estimate: ~$0.04/image × 473 = ~$19 per set, ~$38 for both.
Time estimate: ~2 hours per set at 15s rate limit sleep.
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations"
PROMPTS_FILE = Path("tools/prompts.json")
VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
OUTPUT_BASE = Path("tools/tile_sets")
MIN_IMAGE_BYTES = 50_000
SLEEP_SECONDS = 15

# ---------------------------------------------------------------------------
# Style definitions
# ---------------------------------------------------------------------------

STYLE_PLAYFUL_3D = (
    "3D clay/plasticine sculpture, soft rounded shapes, gentle lighting, subtle shadows, "
    "pastel-bright colors. Friendly and approachable, like a Pixar prop. "
    "Clean solid-color background, nothing cluttered. "
    "CRITICAL: Absolutely no text, no letters, no numbers, no words, no labels, no signs, "
    "no symbols, no icons, no WiFi arcs, no app elements, no writing of any kind anywhere. "
    "Pure visual sculpture only. Square format. Single clear subject centered."
)

STYLE_HIGH_CONTRAST = (
    "High-contrast accessibility pictogram for non-verbal children. "
    "The entire image is a pure solid #000000 black canvas that bleeds seamlessly "
    "from center to all four edges and corners. There is NO frame, NO border, NO "
    "rounded rectangle inset, NO white outline around the canvas, NO inner panel — "
    "the black is one continuous flat field touching every edge. "
    "ONE giant subject is centered and fills most of the canvas (roughly 80% of "
    "the area), drawn in bold white with thick clean lines and generous filled "
    "shapes. Bold accent colors (bright red, blue, green, yellow, orange) are "
    "encouraged on meaningful parts (e.g. red apple, golden bread, red heart, red "
    "roof) — white on black remains dominant. Simple flat shapes, maximum clarity. "
    "ABSOLUTELY FORBIDDEN, the image MUST NOT contain any of these: any frame or "
    "border around the subject; any rounded rectangle inset; any white outline "
    "around the canvas; any text, letters, numbers, or words; any secondary icons; "
    "any scattered small symbols, stars, sparkles, dots, snowflakes, asterisks, "
    "circles, triangles, or shape clusters in the background; any second copy of "
    "the subject; any wheelchair symbols, WiFi arcs, app/UI elements, currency "
    "symbols, medical accessory icons (clipboards, ambulances, EKG lines), or any "
    "decorative motifs anywhere. The black background is completely uniform and "
    "empty everywhere except for the one centered subject. Square format."
)

STYLES = {
    "playful_3d": STYLE_PLAYFUL_3D,
    "high_contrast": STYLE_HIGH_CONTRAST,
}

# Per-tile subject overrides for tiles where the shared cross-style subject
# (extracted from prompts.json) doesn't translate well to high_contrast — e.g.
# abstract concepts where DALL-E improvises with secondary icons, or cases
# where the shared subject says "clay" / "pastel". Looked up by lowercase key.
HC_SUBJECT_OVERRIDES: dict[str, str] = {
    # next_page / previous_page / question — rendered deterministically by
    # render_hc_basics.py; DALL-E reliably hallucinates frames around the canvas
    # or surrounds the subject with a grid of unrelated icons.
    "food": (
        "A clean white plate seen from a slight angle, holding exactly three "
        "iconic food items: a bright red apple, a golden bread roll, and a "
        "chicken drumstick. Just these three items on the plate, nothing else "
        "anywhere in the image"
    ),
    "body_health": (
        "A single bold white silhouette of a standing person, front view, with "
        "a bright red heart shape on the center of the chest. Just the "
        "silhouette and the red heart, nothing else"
    ),
    "snack": (
        "A simple bold white bowl viewed from the front in profile, with three "
        "or four white twisted pretzel shapes resting inside the bowl. Just "
        "the bowl and the pretzels, nothing else inside the bowl, nothing "
        "around the bowl"
    ),
    "home": (
        "A single iconic house shape: a bold white square base with a triangular "
        "roof on top in bright red, one centered door, and one square window. "
        "Just the one house, nothing else"
    ),
    "popsicle": (
        "ONE single popsicle on a wooden stick, centered. The popsicle body has "
        "three horizontal stripes — bright red on top, bright orange in the "
        "middle, bright yellow on the bottom — with a small white wooden stick "
        "below. Just the one popsicle, nothing else"
    ),
}


def extract_subject(prompt_text: str) -> str:
    """Extract the subject description from an existing prompt.

    Existing prompts look like:
      "AAC pictogram: a child eating food. Flat illustration, white background, ..."
    We want: "a child eating food"
    """
    # Remove the "AAC pictogram: " prefix
    text = re.sub(r"^AAC pictogram:\s*", "", prompt_text, flags=re.IGNORECASE)
    # Remove everything from "Flat illustration" onward (the old style suffix)
    text = re.split(r"\.\s*Flat illustration", text, maxsplit=1)[0]
    # Remove trailing period
    text = text.rstrip(". ")
    return text


def build_prompt(subject: str, style: str) -> str:
    """Combine a subject description with a style prefix."""
    return f"{STYLES[style]} Subject: {subject}."


def generate_image(prompt: str, api_key: str, session: requests.Session) -> bytes | None:
    # gpt-image-1 replaced dall-e-3 (April 2025+). It returns b64_json directly
    # and does not accept a `response_format` parameter. Quality values are
    # low/medium/high/auto; medium ≈ legacy "standard" pricing.
    payload = {
        "model": "gpt-image-1",
        "prompt": prompt,
        "n": 1,
        "size": "1024x1024",
        "quality": "medium",
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    try:
        r = session.post(OPENAI_IMAGE_URL, json=payload, headers=headers, timeout=120)
    except requests.RequestException as e:
        print(f"  [generation error: {e}]")
        return None
    if not r.ok:
        # Surface OpenAI's error body — the previous error-swallowing made
        # a dall-e-3 deprecation invisible across 19 failed prompts.
        try:
            body = r.json().get("error", {}).get("message", r.text[:200])
        except ValueError:
            body = r.text[:200]
        print(f"  [generation error: {r.status_code} {body}]")
        return None
    try:
        b64 = r.json()["data"][0]["b64_json"]
    except (KeyError, IndexError, ValueError) as e:
        print(f"  [response parse error: {e}]")
        return None
    import base64
    try:
        return base64.b64decode(b64)
    except Exception as e:
        print(f"  [base64 decode error: {e}]")
        return None


def run_set(style_name: str, keys: list[str], prompts: dict[str, str],
            api_key: str, skip_existing: bool, dry_run: bool) -> tuple[int, int, list[str]]:
    """Generate one full set. Returns (ok_count, skipped, failed_keys)."""
    out_dir = OUTPUT_BASE / style_name
    out_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    ok_count = 0
    skipped = 0
    failed: list[str] = []

    for i, key in enumerate(keys):
        override = HC_SUBJECT_OVERRIDES.get(key.lower()) if style_name == "high_contrast" else None
        if not override and key not in prompts:
            print(f"  ✗ {key:40s} no prompt — skipping")
            failed.append(key)
            continue

        dest = out_dir / f"{key}.png"

        # Skip read-only files (programmatically generated tiles)
        if dest.exists() and not os.access(dest, os.W_OK):
            skipped += 1
            continue

        if skip_existing and dest.exists() and dest.stat().st_size >= MIN_IMAGE_BYTES:
            skipped += 1
            if skipped <= 5 or skipped % 50 == 0:
                print(f"  → {key:40s} (exists, {dest.stat().st_size // 1024} KB)")
            continue

        subject = override if override else extract_subject(prompts[key])
        prompt = build_prompt(subject, style_name)

        if dry_run:
            print(f"  [DRY] {key:40s} | {subject[:80]}")
            ok_count += 1
            continue

        progress = f"[{i+1}/{len(keys)}]"
        print(f"  ⏳ {progress:10s} {key:40s}", end="", flush=True)
        png_bytes = generate_image(prompt, api_key, session)

        if png_bytes and len(png_bytes) >= MIN_IMAGE_BYTES:
            dest.write_bytes(png_bytes)
            print(f"  ✓ {len(png_bytes) // 1024} KB")
            ok_count += 1
        else:
            print("  FAILED")
            failed.append(key)

        time.sleep(SLEEP_SECONDS)

    return ok_count, skipped, failed


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Blaster tile image sets")
    parser.add_argument("--set", required=True, choices=["playful_3d", "high_contrast", "both"])
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--key", metavar="KEY", action="append", default=None,
                        help="Process only this tile key (repeatable)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--batch", type=int, default=0,
                        help="Process only N tiles (for testing)")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    raw_prompts: dict[str, str] = json.loads(PROMPTS_FILE.read_text())
    # Build case-insensitive lookup: lowercase key → original prompt text
    prompts: dict[str, str] = {}
    for k, v in raw_prompts.items():
        prompts[k.lower()] = v
    # Also keep originals for exact match
    prompts.update(raw_prompts)

    vocab: list[dict] = json.loads(VOCAB_FILE.read_text())
    keys = [tile["key"] for tile in vocab]

    if args.key:
        missing = [k for k in args.key if k not in keys]
        if missing:
            sys.exit(f"Keys not in vocabulary: {missing}")
        keys = list(args.key)
    elif args.batch > 0:
        keys = keys[:args.batch]

    sets_to_run = ["playful_3d", "high_contrast"] if args.set == "both" else [args.set]

    for style_name in sets_to_run:
        print(f"\n{'='*60}")
        print(f"Generating: {style_name} ({len(keys)} tiles)")
        print(f"{'='*60}\n")

        ok, skip, failed = run_set(
            style_name, keys, prompts, api_key,
            skip_existing=args.skip_existing, dry_run=args.dry_run,
        )

        print(f"\n{style_name}: ✓ {ok} generated  → {skip} skipped  ✗ {len(failed)} failed")

        if failed:
            failed_path = OUTPUT_BASE / f"{style_name}_failed.txt"
            failed_path.write_text("\n".join(failed) + "\n")
            print(f"Failed keys: {failed_path}")


if __name__ == "__main__":
    main()
