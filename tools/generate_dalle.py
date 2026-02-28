#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Phase 2: Generate custom tile artwork via DALL-E 3 for all Blaster vocabulary tiles.

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/generate_dalle.py [--dry-run] [--skip-existing] [--key KEY]

    --dry-run       Print prompts without making API calls or writing files
    --skip-existing Skip tiles that already have a non-placeholder PNG (>50 KB)
    --key KEY       Process only this single tile key (for retries / spot fixes)

Reads tools/prompts.json for per-word prompts.
Writes PNGs to claudeBlast/Assets.xcassets/{key}.imageset/{key}.png

Cost estimate: ~$0.04/image × 470 ≈ $19 total (DALL-E 3 standard 1024×1024).

IMPORTANT: Never commit API keys.  Always pass via OPENAI_API_KEY env var.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

ASSETS = Path("claudeBlast/Assets.xcassets")
PROMPTS_FILE = Path("tools/prompts.json")
VOCAB_FILE = Path("reference/vocabulary/vocabulary.json")

OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations"

# Quality gate: images smaller than this are likely blank / error responses
MIN_IMAGE_BYTES = 50_000

# Rate limit: DALL-E 3 allows 5 images/minute on Tier 1, 50/min on Tier 2.
# 15-second sleep is conservative and safe for all tiers.
SLEEP_SECONDS = 15


def generate_image(prompt: str, api_key: str, session: requests.Session) -> bytes | None:
    """Call DALL-E 3 and return PNG bytes, or None on failure."""
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

    # Download the PNG from the returned URL
    try:
        img_r = session.get(image_url, timeout=30)
        img_r.raise_for_status()
        return img_r.content
    except requests.RequestException as e:
        print(f"  [download error: {e}]")
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate DALL-E 3 tile artwork for Blaster")
    parser.add_argument("--dry-run", action="store_true", help="Print prompts, no API calls")
    parser.add_argument("--skip-existing", action="store_true",
                        help="Skip tiles with existing PNG > MIN_IMAGE_BYTES")
    parser.add_argument("--key", metavar="KEY",
                        help="Process only this single tile key (for retries)")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY environment variable not set.\n"
                 "  export OPENAI_API_KEY=sk-...")

    if not PROMPTS_FILE.exists():
        sys.exit(f"Prompts file not found: {PROMPTS_FILE}")
    if not VOCAB_FILE.exists():
        sys.exit(f"Vocabulary file not found: {VOCAB_FILE}")
    if not ASSETS.exists():
        sys.exit(f"Assets directory not found: {ASSETS}")

    prompts: dict[str, str] = json.loads(PROMPTS_FILE.read_text())
    vocab: list[dict] = json.loads(VOCAB_FILE.read_text())

    # Build ordered key list from vocabulary (preserves word-class grouping)
    keys = [tile["key"] for tile in vocab]
    if args.key:
        if args.key not in keys:
            sys.exit(f"Key '{args.key}' not found in vocabulary")
        keys = [args.key]

    missing_prompts = [k for k in keys if k not in prompts]
    if missing_prompts:
        print(f"WARNING: {len(missing_prompts)} keys have no prompt in prompts.json:")
        for k in missing_prompts:
            print(f"  {k}")
        print("Add entries to tools/prompts.json for these keys before running.\n")

    ok_count = 0
    skipped_count = 0
    failed: list[str] = []

    session = requests.Session()

    for key in keys:
        if key not in prompts:
            failed.append(key)
            continue

        dest_dir = ASSETS / f"{key}.imageset"
        dest_png = dest_dir / f"{key}.png"

        if not dest_dir.exists():
            print(f"✗  {key:40s}  imageset directory missing — skipping")
            failed.append(key)
            continue

        # Skip-existing check
        if args.skip_existing and dest_png.exists() and dest_png.stat().st_size >= MIN_IMAGE_BYTES:
            skipped_count += 1
            print(f"→  {key:40s}  (skipped, PNG exists {dest_png.stat().st_size // 1024} KB)")
            continue

        prompt = prompts[key]

        if args.dry_run:
            print(f"[DRY-RUN] {key:40s}")
            print(f"          {prompt[:100]}...")
            ok_count += 1
            continue

        print(f"⏳  {key:40s}  generating…", end="", flush=True)
        png_bytes = generate_image(prompt, api_key, session)

        if png_bytes is None:
            print("  FAILED")
            failed.append(key)
        elif len(png_bytes) < MIN_IMAGE_BYTES:
            print(f"  FAILED (only {len(png_bytes)} bytes — likely blank)")
            failed.append(key)
        else:
            dest_png.write_bytes(png_bytes)
            print(f"  ✓  {len(png_bytes) // 1024} KB")
            ok_count += 1

        time.sleep(SLEEP_SECONDS)

    # Summary
    print()
    print("=" * 60)
    print(f"Done.  ✓ {ok_count} generated  →  {skipped_count} skipped  ✗ {len(failed)} failed")

    if failed:
        failed_path = Path("failed_dalle.txt")
        failed_path.write_text("\n".join(failed) + "\n")
        print(f"\nFailed keys written to: {failed_path}")
        print("Re-run with --key <KEY> to retry individual tiles.")
        print("Consider refining the prompt in tools/prompts.json for failed words.")


if __name__ == "__main__":
    main()
