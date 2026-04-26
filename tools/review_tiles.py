#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Review workflow for generated tile image sets.

Commands:
    # Build contact sheets (pages of 20 tiles) for visual review
    python3 tools/review_tiles.py sheets --set playful_3d

    # Build contact sheets for a specific wordClass
    python3 tools/review_tiles.py sheets --set playful_3d --category people

    # Flag tiles that need regeneration (adds to reject list)
    python3 tools/review_tiles.py reject --set playful_3d --keys playground,home,teacher

    # Show current reject list
    python3 tools/review_tiles.py status --set playful_3d

    # Regenerate only rejected tiles
    python3 tools/review_tiles.py regen --set playful_3d

    # Accept tiles (remove from reject list)
    python3 tools/review_tiles.py accept --set playful_3d --keys playground,home

    # Compare a single tile across all sets + current ARASAAC
    python3 tools/review_tiles.py compare --key playground

Workflow:
    1. Generate full set:     python3 tools/generate_sets.py --set playful_3d --skip-existing
    2. Build review sheets:   python3 tools/review_tiles.py sheets --set playful_3d
    3. Open tools/tile_sets/playful_3d/review/ in Finder and visually scan
    4. Flag bad tiles:        python3 tools/review_tiles.py reject --set playful_3d --keys eat,playground,school
    5. Regenerate flagged:    python3 tools/review_tiles.py regen --set playful_3d
    6. Re-review and repeat until clean
"""

import argparse
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install Pillow")

VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
ASSETS_DIR = Path("claudeBlast/Assets.xcassets")
OUTPUT_BASE = Path("tools/tile_sets")
TILES_PER_SHEET = 20  # 4 columns × 5 rows


def load_vocab() -> list[dict]:
    return json.loads(VOCAB_FILE.read_text())


# ---------------------------------------------------------------------------
# Generation tracking
# ---------------------------------------------------------------------------

def generations_file(set_name: str) -> Path:
    return OUTPUT_BASE / set_name / "generations.json"


def load_generations(set_name: str) -> list[dict]:
    gf = generations_file(set_name)
    if gf.exists():
        return json.loads(gf.read_text()).get("generations", [])
    return []


def save_generations(set_name: str, gens: list[dict]) -> None:
    gf = generations_file(set_name)
    gf.parent.mkdir(parents=True, exist_ok=True)
    gf.write_text(json.dumps({"generations": gens}, indent=2) + "\n")


def record_generation(set_name: str, keys: list[str], description: str = "") -> int:
    """Append a new generation entry. Returns the new generation id."""
    gens = load_generations(set_name)
    new_id = max((g["id"] for g in gens), default=0) + 1
    gens.append({
        "id": new_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "description": description,
        "keys": sorted(keys),
    })
    save_generations(set_name, gens)
    return new_id


def get_generation_keys(set_name: str, gen_id: int | None = None, latest: bool = False) -> list[str] | None:
    """Return the keys for a specific generation, or None if no filter."""
    if gen_id is None and not latest:
        return None
    gens = load_generations(set_name)
    if not gens:
        return []
    if latest:
        return gens[-1]["keys"]
    for g in gens:
        if g["id"] == gen_id:
            return g["keys"]
    print(f"WARNING: generation {gen_id} not found. Available: {[g['id'] for g in gens]}")
    return []


def open_path(path: Path) -> None:
    """Open a file or directory in the OS default handler."""
    if platform.system() == "Darwin":
        subprocess.run(["open", str(path)])
    elif platform.system() == "Linux":
        subprocess.run(["xdg-open", str(path)])
    else:
        print(f"Open manually: {path}")


def reject_file(set_name: str) -> Path:
    return OUTPUT_BASE / set_name / "rejected.json"


def load_rejects(set_name: str) -> dict:
    """Returns {key: {"reason": str, "attempts": int}}"""
    rf = reject_file(set_name)
    if rf.exists():
        return json.loads(rf.read_text())
    return {}


def save_rejects(set_name: str, rejects: dict) -> None:
    rf = reject_file(set_name)
    rf.write_text(json.dumps(rejects, indent=2) + "\n")


def cmd_sheets(args):
    """Build contact sheets for visual review."""
    vocab = load_vocab()
    set_dir = OUTPUT_BASE / args.set
    review_dir = set_dir / "review"
    review_dir.mkdir(parents=True, exist_ok=True)

    if args.category:
        vocab = [t for t in vocab if t.get("wordClass") == args.category]

    rejects = load_rejects(args.set)
    keys = [t["key"] for t in vocab]
    total = len(keys)

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
        font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 14)
    except Exception:
        font = ImageFont.load_default()
        font_small = font

    cell = 256
    label_h = 30
    cols = 4
    margin = 6

    for page_idx in range(0, total, TILES_PER_SHEET):
        page_keys = keys[page_idx:page_idx + TILES_PER_SHEET]
        rows = (len(page_keys) + cols - 1) // cols
        width = cols * (cell + margin) + margin
        height = rows * (cell + label_h + margin) + margin

        sheet = Image.new("RGB", (width, height), "white")
        draw = ImageDraw.Draw(sheet)

        for i, key in enumerate(page_keys):
            col = i % cols
            row = i // cols
            x = margin + col * (cell + margin)
            y = margin + row * (cell + label_h + margin)

            img_path = set_dir / f"{key}.png"
            if img_path.exists():
                try:
                    thumb = Image.open(img_path).convert("RGB").resize((cell, cell), Image.LANCZOS)
                    sheet.paste(thumb, (x, y))
                except Exception:
                    draw.rectangle([x, y, x + cell, y + cell], fill="#f0f0f0", outline="#ccc")
                    draw.text((x + cell // 2, y + cell // 2), "ERR", fill="red", font=font, anchor="mm")
            else:
                draw.rectangle([x, y, x + cell, y + cell], fill="#f0f0f0", outline="#ccc")
                draw.text((x + cell // 2, y + cell // 2), "MISSING", fill="#999", font=font, anchor="mm")

            # Label
            label = key
            if key in rejects:
                label = f"[REJECT] {key}"
                draw.rectangle([x, y + cell, x + cell, y + cell + label_h], fill="#ffcccc")
            draw.text((x + cell // 2, y + cell + 4), label, fill="black", font=font_small, anchor="mt")

        cat_suffix = f"_{args.category}" if args.category else ""
        page_num = page_idx // TILES_PER_SHEET + 1
        sheet_path = review_dir / f"sheet{cat_suffix}_{page_num:03d}.png"
        sheet.save(sheet_path)
        print(f"  {sheet_path.name}: {len(page_keys)} tiles")

    print(f"\nReview sheets: {review_dir}/")
    print(f"Total: {total} tiles across {(total + TILES_PER_SHEET - 1) // TILES_PER_SHEET} sheets")


def cmd_reject(args):
    """Add tiles to the reject list."""
    rejects = load_rejects(args.set)
    keys = [k.strip() for k in args.keys.split(",")]
    reason = args.reason or "text/visual issue"
    for key in keys:
        if key in rejects:
            rejects[key]["attempts"] = rejects[key].get("attempts", 1) + 1
            rejects[key]["reason"] = reason
        else:
            rejects[key] = {"reason": reason, "attempts": 1}
    save_rejects(args.set, rejects)
    print(f"Rejected {len(keys)} tiles in {args.set}: {', '.join(keys)}")
    print(f"Total rejects: {len(rejects)}")


def cmd_accept(args):
    """Remove tiles from the reject list."""
    rejects = load_rejects(args.set)
    keys = [k.strip() for k in args.keys.split(",")]
    removed = 0
    for key in keys:
        if key in rejects:
            del rejects[key]
            removed += 1
    save_rejects(args.set, rejects)
    print(f"Accepted {removed} tiles. Remaining rejects: {len(rejects)}")


def cmd_status(args):
    """Show reject list status."""
    rejects = load_rejects(args.set)
    set_dir = OUTPUT_BASE / args.set
    generated = len(list(set_dir.glob("*.png")))
    vocab = load_vocab()

    print(f"Set: {args.set}")
    print(f"Generated: {generated} / {len(vocab)} tiles")
    print(f"Rejected: {len(rejects)} tiles")
    if rejects:
        print()
        for key, info in sorted(rejects.items()):
            attempts = info.get("attempts", 1)
            reason = info.get("reason", "")
            print(f"  {key:30s} attempts={attempts}  reason={reason}")


def cmd_regen(args):
    """Regenerate rejected tiles by calling generate_sets.py for each."""
    rejects = load_rejects(args.set)
    if not rejects:
        print("No rejected tiles to regenerate.")
        return

    keys = list(rejects.keys())
    print(f"Regenerating {len(keys)} rejected tiles for {args.set}...")

    # Delete existing files so generate_sets.py will recreate them
    set_dir = OUTPUT_BASE / args.set
    for key in keys:
        img = set_dir / f"{key}.png"
        if img.exists():
            img.unlink()
            print(f"  Deleted {key}.png")

    # Call generate_sets.py for each key
    for key in keys:
        print(f"\n  Regenerating: {key}")
        result = subprocess.run(
            [sys.executable, "tools/generate_sets.py", "--set", args.set, "--key", key],
            capture_output=False,
        )
        if result.returncode != 0:
            print(f"  WARNING: generation failed for {key}")

    print(f"\nDone. Run 'review_tiles.py sheets --set {args.set}' to re-review.")


def cmd_compare_sheet(args):
    """Side-by-side contact sheet: v1 (current p3d) vs v2 (new candidate set).

    Filterable by --category (wordClass) or --keys (comma-separated).
    Default v1 source is ../claudeBlast main worktree's TileImageSets/p3d_*.png.
    Default v2 source is tools/tile_sets/{--set}/{key}.png.
    """
    vocab = load_vocab()
    if args.category:
        vocab = [t for t in vocab if t.get("wordClass") == args.category]
    if args.keys:
        wanted = {k.strip() for k in args.keys.split(",")}
        vocab = [t for t in vocab if t["key"] in wanted]

    # Generation filter
    gen_id = getattr(args, "generation", None)
    is_latest = getattr(args, "latest", False)
    gen_keys = get_generation_keys(args.set, gen_id, is_latest)
    if gen_keys is not None:
        vocab = [t for t in vocab if t["key"] in gen_keys]

    if not vocab:
        print("No matching tiles.")
        return

    v1_dir = Path(args.v1_dir)
    v2_dir = OUTPUT_BASE / args.set
    out_dir = OUTPUT_BASE / args.set / "review"
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
        font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
        font_header = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 28)
    except Exception:
        font = ImageFont.load_default()
        font_small = font
        font_header = font

    cell = 320
    label_w = 220
    label_h = 36
    margin = 10
    rows_per_sheet = 8
    row_h = cell + margin
    header_h = 60

    sheet_w = label_w + 2 * (cell + margin) + margin
    sheet_h = header_h + rows_per_sheet * row_h + margin

    keys = [t["key"] for t in vocab]
    total = len(keys)
    sheets_n = (total + rows_per_sheet - 1) // rows_per_sheet

    cat_suffix = f"_{args.category}" if args.category else ""

    for sheet_i in range(sheets_n):
        page_keys = keys[sheet_i * rows_per_sheet : (sheet_i + 1) * rows_per_sheet]
        actual_h = header_h + len(page_keys) * row_h + margin
        sheet = Image.new("RGB", (sheet_w, actual_h), "white")
        draw = ImageDraw.Draw(sheet)

        # Header row
        draw.text((label_w + margin + cell // 2, 18),
                  "v1 (current p3d)", fill="black", font=font_header, anchor="mt")
        draw.text((label_w + 2 * margin + cell + cell // 2, 18),
                  f"v2 ({args.set})", fill="black", font=font_header, anchor="mt")

        for i, tile in enumerate([t for t in vocab if t["key"] in page_keys]):
            key = tile["key"]
            wc = tile.get("wordClass", "")
            y = header_h + i * row_h

            # Label
            draw.text((margin, y + cell // 2 - 12), key, fill="black",
                      font=font, anchor="lm")
            draw.text((margin, y + cell // 2 + 14), wc, fill="#666",
                      font=font_small, anchor="lm")

            # v1 image
            v1_path = v1_dir / f"p3d_{key}.png"
            x = label_w + margin
            _paste_or_placeholder(sheet, draw, v1_path, x, y, cell, font)

            # v2 image
            v2_path = v2_dir / f"{key}.png"
            x = label_w + 2 * margin + cell
            _paste_or_placeholder(sheet, draw, v2_path, x, y, cell, font)

        out_path = out_dir / f"compare{cat_suffix}_{sheet_i + 1:03d}.png"
        sheet.save(out_path)
        print(f"  {out_path}")

    print(f"\n{total} tiles compared across {sheets_n} sheet(s).")
    print(f"Output: {out_dir}/")

    if getattr(args, "open", False):
        open_path(out_dir)


def _paste_or_placeholder(sheet, draw, path, x, y, cell, font):
    if path.exists():
        try:
            thumb = Image.open(path).convert("RGB").resize((cell, cell), Image.LANCZOS)
            sheet.paste(thumb, (x, y))
            return
        except Exception:
            pass
    draw.rectangle([x, y, x + cell, y + cell], fill="#f0f0f0", outline="#ccc")
    draw.text((x + cell // 2, y + cell // 2), "MISSING", fill="#999",
              font=font, anchor="mm")


def cmd_compare(args):
    """Build a comparison strip for one tile across all sets + ARASAAC."""
    key = args.key
    cell = 512
    margin = 10
    label_h = 40

    sources = [
        ("Current (ARASAAC)", ASSETS_DIR / f"{key}.imageset" / f"{key}.png"),
        ("Playful 3D", OUTPUT_BASE / "playful_3d" / f"{key}.png"),
        ("High Contrast", OUTPUT_BASE / "high_contrast" / f"{key}.png"),
    ]
    # Add Sclera if available
    sclera_path = Path(f"tools/sclera/english/{key}.png")
    if sclera_path.exists():
        sources.insert(2, ("Sclera (Original)", sclera_path))

    cols = len(sources)
    width = cols * (cell + margin) + margin
    height = label_h + cell + label_h + margin

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
    except Exception:
        font = ImageFont.load_default()

    sheet = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(sheet)

    for ci, (label, path) in enumerate(sources):
        x = margin + ci * (cell + margin)
        draw.text((x + cell // 2, 8), label, fill="black", font=font, anchor="mt")

        if path.exists():
            try:
                thumb = Image.open(path).convert("RGB").resize((cell, cell), Image.LANCZOS)
                sheet.paste(thumb, (x, label_h))
            except Exception:
                draw.rectangle([x, label_h, x + cell, label_h + cell], fill="#f0f0f0")
                draw.text((x + cell // 2, label_h + cell // 2), "ERR", fill="red", font=font, anchor="mm")
        else:
            draw.rectangle([x, label_h, x + cell, label_h + cell], fill="#f0f0f0", outline="#ccc")
            draw.text((x + cell // 2, label_h + cell // 2), "N/A", fill="#999", font=font, anchor="mm")

    draw.text((width // 2, label_h + cell + 8), key, fill="black", font=font, anchor="mt")

    out = OUTPUT_BASE / f"compare_{key}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"Comparison saved: {out}")


def main():
    parser = argparse.ArgumentParser(description="Tile image review workflow")
    sub = parser.add_subparsers(dest="command", required=True)

    p_sheets = sub.add_parser("sheets", help="Build review contact sheets")
    p_sheets.add_argument("--set", required=True)
    p_sheets.add_argument("--category", help="Filter by wordClass")

    p_reject = sub.add_parser("reject", help="Flag tiles for regeneration")
    p_reject.add_argument("--set", required=True)
    p_reject.add_argument("--keys", required=True, help="Comma-separated tile keys")
    p_reject.add_argument("--reason", default="", help="Why rejected")

    p_accept = sub.add_parser("accept", help="Remove tiles from reject list")
    p_accept.add_argument("--set", required=True)
    p_accept.add_argument("--keys", required=True, help="Comma-separated tile keys")

    p_status = sub.add_parser("status", help="Show reject list")
    p_status.add_argument("--set", required=True)

    p_regen = sub.add_parser("regen", help="Regenerate rejected tiles")
    p_regen.add_argument("--set", required=True)

    p_compare = sub.add_parser("compare", help="Compare one tile across all sets")
    p_compare.add_argument("--key", required=True)

    p_csheet = sub.add_parser(
        "compare-sheet",
        help="v1-vs-v2 contact sheet, filterable by wordClass, keys, or generation",
    )
    p_csheet.add_argument("--set", required=True, help="v2 set under tools/tile_sets/")
    p_csheet.add_argument("--category", help="Filter by wordClass")
    p_csheet.add_argument("--keys", help="Comma-separated tile keys")
    p_csheet.add_argument("--generation", type=int, help="Filter to a specific generation id")
    p_csheet.add_argument("--latest", action="store_true", help="Filter to the most recent generation")
    p_csheet.add_argument("--open", action="store_true", help="Open the review folder after building")
    p_csheet.add_argument(
        "--v1-dir",
        default="../claudeBlast/claudeBlast/TileImageSets",
        help="Directory containing v1 p3d_*.png files",
    )

    p_gen = sub.add_parser("gen", help="Record a new generation of changed tiles")
    p_gen.add_argument("--set", required=True, help="Tile set name")
    p_gen.add_argument("--keys", required=True, help="Comma-separated tile keys in this generation")
    p_gen.add_argument("--description", default="", help="What changed in this generation")

    args = parser.parse_args()

    if args.command == "sheets":
        cmd_sheets(args)
    elif args.command == "reject":
        cmd_reject(args)
    elif args.command == "accept":
        cmd_accept(args)
    elif args.command == "status":
        cmd_status(args)
    elif args.command == "regen":
        cmd_regen(args)
    elif args.command == "compare":
        cmd_compare(args)
    elif args.command == "compare-sheet":
        cmd_compare_sheet(args)
    elif args.command == "gen":
        keys = [k.strip() for k in args.keys.split(",")]
        gen_id = record_generation(args.set, keys, args.description)
        print(f"Recorded generation {gen_id}: {len(keys)} keys")
        print(f"  {generations_file(args.set)}")


if __name__ == "__main__":
    main()
