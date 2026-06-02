#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Phase 1: Download ARASAAC pictograms for all Blaster vocabulary tiles.

Usage:
    python3 tools/download_arasaac.py [--dry-run] [--skip-existing]

Reads claudeBlast/Resources/vocabulary.json, searches the ARASAAC API for each
word, and downloads the PNG into the correct Assets.xcassets imageset.
Auto-creates missing imageset directories (with Contents.json) so new
vocabulary entries don't have to be hand-bootstrapped.

ARASAAC license: CC BY-NC-SA 4.0 (non-commercial use only).
"""

import argparse
import json
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

API_BASE = "https://api.arasaac.org/api/pictograms/en"
PIC_STATIC = "https://static.arasaac.org/pictograms"  # {id}/{id}_500.png
ASSETS = Path("claudeBlast/Assets.xcassets")
VOCAB = Path("claudeBlast/Resources/vocabulary.json")

# Per-key search overrides.  Keys that normalise poorly or are multi-word
# phrases where the full phrase gives better ARASAAC results.
OVERRIDES: dict[str, str] = {
    # Navigation
    "next_page": "next",
    "previous_page": "previous",
    # Multi-word social phrases
    "i_dont_know": "don't know",
    "i_love_you": "love you",
    "nice_to_meet": "meet",
    "whats_up": "hello",
    "no_way": "no",
    "oh_my": "surprised",
    "be_quiet": "quiet",
    # People
    "school_people": "school",
    # Actions
    "line_up": "line",
    "dress_up": "dress",
    "brush_teeth": "teeth",
    "wash_hair": "hair",
    "wash_hands": "hands",
    # Food (brand/compound names)
    "Graham_Cracker": "cracker",
    "Goldfish_Cracker": "fish cracker",
    "Snack_Bar": "snack bar",
    # Places
    "bowling_alley": "bowling",
    "grocery_store": "supermarket",
    "living_room": "living room",
    "dining_room": "dining room",
    # Drinks
    "chocolate_milk": "chocolate milk",
    "iced_tea": "iced tea",
    "ice_cubes": "ice",
    # Snacks
    "fruit_snack": "fruit snack",
    # Meals
    "hot_dog": "hot dog",
    "peanut_butter": "peanut butter",
    # Veggies
    "green_beans": "green beans",
    # Health
    "sore_throat": "sore throat",
    # Sports/Games
    "video_game": "video game",
    # Weather (trailing-underscore variants - normalise strips the _, but
    # explicit here for clarity)
    "cold_": "cold",
    "cool_": "cool",
    # Describe (trailing underscore or double underscore variants)
    "cold__": "cold",
    "hot_": "hot",
    "clean_": "clean",
    "okay_": "okay",
    "hard_": "hard",
    "back_": "back",
    "funny_": "funny",
    "dry_": "dry",
    "light_": "light",
    "old_": "old",
    "right_": "right",
    "orange_": "orange",
    # Colors
    "don't": "not",
    # Core grammar (vocab additions in Core-First worktree).
    # First pass overrides were too clever and all collided on ARASAAC's
    # generic "pronoun"-keyword pictogram (id 6480 = "he"). Empirically
    # confirmed via direct API probe: the plain words work better for
    # i/me/it (English ARASAAC uses the same picto for I/me; "it" is
    # distinct). For "for", "in order to" routes to the preposition picto.
    # For "out", "outside" avoids matching "extinct"/sentinel results.
    "me": "I",        # ARASAAC: English I/me share id 6632
    "all_done": "finished",
    "out": "outside",
    "for": "in order to",
    "backyard": "garden",  # ARASAAC's "backyard" matches a compost bin (id 36611)
}


def ensure_imageset(dest_dir: Path, key: str) -> None:
    """Create the .imageset directory + Contents.json if missing.
    Mirrors Xcode's default imageset shape so the asset catalog picks up
    the new key on the next build.
    """
    if dest_dir.exists():
        return
    dest_dir.mkdir(parents=True)
    contents = {
        "images": [{"filename": f"{key}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (dest_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def normalize(key: str) -> str:
    """Strip trailing underscores and replace internal underscores with spaces."""
    return key.rstrip("_").replace("_", " ")


def search_arasaac(word: str, session: requests.Session) -> int | None:
    """Return the ARASAAC pictogram ID for *word*, or None if not found."""
    url = f"{API_BASE}/search/{requests.utils.quote(word)}"
    try:
        r = session.get(url, timeout=10)
        if r.ok:
            data = r.json()
            if isinstance(data, list) and data:
                return data[0]["_id"]
    except (requests.RequestException, KeyError, ValueError) as e:
        print(f"  [search error for '{word}': {e}]")
    return None


def download_png(pid: int, dest: Path, session: requests.Session) -> bool:
    """Download pictogram *pid* at 500px and write to *dest*. Returns True on success."""
    url = f"{PIC_STATIC}/{pid}/{pid}_500.png"
    try:
        r = session.get(url, timeout=20)
        r.raise_for_status()
        if len(r.content) < 1000:
            print(f"  [suspiciously small PNG: {len(r.content)} bytes, skipping]")
            return False
        dest.write_bytes(r.content)
        return True
    except requests.RequestException as e:
        print(f"  [download error for pid {pid}: {e}]")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Download ARASAAC pictograms for Blaster")
    parser.add_argument("--dry-run", action="store_true", help="Search but don't download")
    parser.add_argument("--skip-existing", action="store_true",
                        help="Skip tiles that already have a non-zero PNG")
    args = parser.parse_args()

    if not VOCAB.exists():
        sys.exit(f"Vocabulary file not found: {VOCAB}")
    if not ASSETS.exists():
        sys.exit(f"Assets directory not found: {ASSETS}")

    vocab: list[dict] = json.loads(VOCAB.read_text())
    print(f"Loaded {len(vocab)} tiles from vocabulary")

    not_found: list[str] = []
    skipped: list[str] = []
    ok_count = 0

    session = requests.Session()
    session.headers.update({"User-Agent": "BlasterAAC/1.0 (open-source AAC app)"})

    for tile in vocab:
        key: str = tile["key"]
        word_class: str = tile.get("wordClass", "")

        # Determine search term
        term = OVERRIDES.get(key) or normalize(key)

        dest_dir = ASSETS / f"{key}.imageset"
        dest_png = dest_dir / f"{key}.png"

        # Skip check
        if args.skip_existing and dest_png.exists() and dest_png.stat().st_size > 1000:
            skipped.append(key)
            print(f"→  {key:35s}  (skipped, exists)")
            continue

        # Auto-create the imageset directory for new vocabulary entries.
        # Safe no-op when the directory already exists.
        ensure_imageset(dest_dir, key)

        # Search
        pid = search_arasaac(term, session)
        if pid is None:
            # Fallback: try just the first word
            fallback = term.split()[0] if " " in term else None
            if fallback:
                pid = search_arasaac(fallback, session)

        if pid is None:
            not_found.append(key)
            print(f"✗  {key:35s}  [{word_class}] no result for '{term}'")
        else:
            label = f"✓  {key:35s}  [{word_class}] → id {pid}  ('{term}')"
            if args.dry_run:
                print(label + "  [dry-run]")
                ok_count += 1
            else:
                success = download_png(pid, dest_png, session)
                if success:
                    print(label)
                    ok_count += 1
                else:
                    not_found.append(key)

        time.sleep(0.15)  # be polite to ARASAAC servers

    # Summary
    print()
    print("=" * 60)
    print(f"Done.  ✓ {ok_count} downloaded  →  {len(skipped)} skipped  ✗ {len(not_found)} not found")

    if not_found:
        nf_path = Path("not_found.txt")
        nf_path.write_text("\n".join(not_found) + "\n")
        print(f"Not-found keys written to: {nf_path}")
        print()
        print("Manual fallback: visit https://www.arasaac.org/pictograms/search")
        print("and search for each word listed in not_found.txt")

    if skipped:
        print(f"\nSkipped {len(skipped)} tiles with existing images (--skip-existing).")


if __name__ == "__main__":
    main()
