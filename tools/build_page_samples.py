#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build the bundled "page sample" collections for Blaster — tight, single-page
topical tile sets (Space, Dinosaurs, Vehicles) offered as ready-made examples in
the Add-Page flow. Unlike scene starters, a page sample is JUST the relevant
tiles (no core-board scaffold).

Each page also mints a representative "page_link" tile (key page_<id>,
wordClass page_link) with its own thematic icon, so the collection can be
referenced from any board as a silent navigation tile.

Emits readable Resources/pagesample_<id>.json + Resources/starterart_<key>.png
sidecars (shared naming with the scene starters so one loader resolves both) +
Resources/page_samples.json manifest.

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/build_page_samples.py            # generate art + emit bundles
    python3 tools/build_page_samples.py --dry-run  # validate + plan, no API
"""

import argparse
import io
import json
import sys
import time
from pathlib import Path

import generate_sets as gs

try:
    import requests
except ImportError:
    sys.exit("pip install requests")
try:
    from PIL import Image
except ImportError:
    sys.exit("pip install pillow")

VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
RES_DIR = Path("claudeBlast/Resources")
ART_RECORD_DIR = Path("tools/tile_sets/starter")  # shared master cache
MEDIA_TYPE = "application/vnd.claudeblast.page+json"
VERSION = "1.0.0"
ART_STYLE = "playful_3d"
SLEEP_SECONDS = 15

# Each page: ordered topical keys + per-new-word (wordClass, displayName, subject).
# `icon` is the page_link tile's thematic image subject. Existing-vocab keys in
# `page` are referenced (no art generated); everything else is a new word.
PAGES = [
    {
        "id": "space",
        "title": "Space",
        "goal": "Space and space travel: rockets, astronauts, planets, stars, the moon and sun, and other things you see in outer space.",
        "blurb": "Rockets, planets, astronauts, and the stars.",
        "icon": "a fun outer-space scene with a ringed planet, bright stars, and a rocket",
        "new": {
            "rocket": ("object", "Rocket", "a cartoon rocket ship blasting off with flames"),
            "astronaut": ("people", "Astronaut", "a friendly astronaut in a white spacesuit and helmet"),
            "planet": ("object", "Planet", "a ringed planet like Saturn, purple and blue"),
            "star": ("object", "Star", "a single bright yellow five-point star"),
            "moon": ("object", "Moon", "a pale grey crescent moon"),
            "sun": ("object", "Sun", "a bright smiling yellow sun with rays"),
            "comet": ("object", "Comet", "a comet with a glowing tail streaking across"),
            "alien": ("object", "Alien", "a friendly little green alien with big eyes"),
            "spaceship": ("object", "Spaceship", "a silver flying-saucer spaceship"),
            "telescope": ("object", "Telescope", "a telescope on a tripod pointed up at the sky"),
            "satellite": ("object", "Satellite", "a space satellite with solar panels"),
            "galaxy": ("object", "Galaxy", "a purple and blue spiral galaxy of stars"),
        },
        "page": ["rocket", "astronaut", "planet", "star", "moon", "sun",
                 "comet", "alien", "spaceship", "telescope", "satellite", "galaxy"],
    },
    {
        "id": "dinosaurs",
        "title": "Dinosaurs",
        "goal": "Dinosaurs: common dinosaurs a child knows, plus fossils, eggs, and a volcano.",
        "blurb": "T-Rex, triceratops, fossils, and a volcano.",
        "icon": "a fun dinosaur scene with a friendly green dinosaur and a volcano",
        "new": {
            "dinosaur": ("object", "Dinosaur", "a friendly green cartoon dinosaur"),
            "trex": ("object", "T-Rex", "a friendly Tyrannosaurus Rex dinosaur, green, standing"),
            "triceratops": ("object", "Triceratops", "a triceratops dinosaur with three horns"),
            "stegosaurus": ("object", "Stegosaurus", "a stegosaurus dinosaur with plates on its back"),
            "pterodactyl": ("object", "Pterodactyl", "a pterodactyl flying dinosaur with wings"),
            "brontosaurus": ("object", "Brontosaurus", "a long-necked brontosaurus dinosaur"),
            "raptor": ("object", "Raptor", "a small velociraptor dinosaur"),
            "fossil": ("object", "Fossil", "a dinosaur skeleton fossil"),
            "volcano": ("object", "Volcano", "an erupting volcano with orange lava"),
            "dino_egg": ("object", "Dino Egg", "a large spotted dinosaur egg"),
        },
        "page": ["dinosaur", "trex", "triceratops", "stegosaurus", "pterodactyl",
                 "brontosaurus", "raptor", "fossil", "volcano", "dino_egg"],
    },
    {
        "id": "vehicles",
        "title": "Vehicles",
        "goal": "Vehicles that go: cars, trucks, buses, trains, planes and boats, plus emergency vehicles like a fire truck, ambulance, and police car.",
        "blurb": "Cars, trains, planes, and emergency vehicles.",
        "icon": "a fun scene with a red car, a fire truck, and an airplane",
        "new": {
            "car": ("object", "Car", "a red cartoon car, side view"),
            "truck": ("object", "Truck", "a blue delivery truck, side view"),
            "bus": ("object", "Bus", "a yellow school bus, side view"),
            "train": ("object", "Train", "a colorful train engine, side view"),
            "airplane": ("object", "Airplane", "a passenger airplane flying"),
            "boat": ("object", "Boat", "a small sailboat on blue water"),
            "bicycle": ("object", "Bicycle", "a child's bicycle, side view"),
            "helicopter": ("object", "Helicopter", "a helicopter with a spinning top rotor"),
            "fire_truck": ("object", "Fire Truck", "a red fire truck with a ladder"),
            "ambulance": ("object", "Ambulance", "a white ambulance with a red cross and lights"),
            "police_car": ("object", "Police Car", "a police car with blue lights on top"),
        },
        "page": ["car", "truck", "bus", "train", "airplane", "boat", "bicycle",
                 "helicopter", "fire_truck", "ambulance", "police_car"],
    },
]


def write_sidecar(key: str, png_bytes: bytes) -> None:
    im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    im.thumbnail((512, 512), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, format="PNG", optimize=True)
    (RES_DIR / f"starterart_{key}.png").write_bytes(out.getvalue())


def gen_art(key: str, subject: str, api_key: str, session, dry: bool) -> None:
    """Generate (or reuse cached master) p3d art for `key` and write its sidecar."""
    if dry:
        print(f"  [DRY] {key:14s} | {subject}")
        return
    master = ART_RECORD_DIR / f"{key}.png"
    if master.exists() and master.stat().st_size >= gs.MIN_IMAGE_BYTES:
        png = master.read_bytes()
        print(f"  → {key:14s} (cached master)")
    else:
        prompt = gs.build_prompt(subject, ART_STYLE)
        print(f"  ⏳ {key:14s}", end="", flush=True)
        png = None
        for attempt in range(4):
            png = gs.generate_image(prompt, api_key, session)
            if png and len(png) >= gs.MIN_IMAGE_BYTES:
                break
            wait = 10 * (attempt + 1)
            print(f"  retry {attempt+1} in {wait}s…", end="", flush=True)
            time.sleep(wait)
        if not png or len(png) < gs.MIN_IMAGE_BYTES:
            sys.exit(f"\n  FAILED to generate {key} after retries")
        master.write_bytes(png)
        print(f"  ✓ {len(png)//1024} KB")
        time.sleep(SLEEP_SECONDS)
    write_sidecar(key, png)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    vocab_keys = {t["key"] for t in json.loads(VOCAB_FILE.read_text())}
    api_key = gs.os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    ART_RECORD_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    manifest = []

    for page in PAGES:
        print(f"\n=== {page['id']} ({page['title']}) ===")
        icon_key = f"page_{page['id']}"

        # Art for new words + the page_link icon.
        for key in page["page"]:
            if key in vocab_keys:
                print(f"  · {key:14s} (existing vocab — referenced)")
                continue
            if key not in page["new"]:
                sys.exit(f"{page['id']}: '{key}' not in vocab and not declared new")
            gen_art(key, page["new"][key][2], api_key, session, args.dry_run)
        gen_art(icon_key, page["icon"], api_key, session, args.dry_run)

        # Readable bundle: new-word tile defs (+ the page_link tile) and the
        # ordered topical page. Art is resolved from sidecars at load time.
        tiles = [{"key": k, "wordClass": wc, "displayName": dn}
                 for k, (wc, dn, _) in page["new"].items() if k not in vocab_keys]
        tiles.append({"key": icon_key, "wordClass": "page_link", "displayName": page["title"]})

        bundle = {
            "@type": MEDIA_TYPE,
            "version": VERSION,
            "id": page["id"],
            "title": page["title"],
            "goal": page["goal"],
            "pageKey": page["id"],
            "iconKey": icon_key,
            "tiles": tiles,
            "page": page["page"],
        }
        if not args.dry_run:
            out = RES_DIR / f"pagesample_{page['id']}.json"
            out.write_text(json.dumps(bundle, indent=2) + "\n")
            print(f"  wrote {out} ({len(page['page'])} tiles + icon)")

        manifest.append({
            "id": page["id"], "title": page["title"], "blurb": page["blurb"],
            "goal": page["goal"], "bundle": f"pagesample_{page['id']}",
            "iconKey": icon_key,
        })

    if not args.dry_run:
        (RES_DIR / "page_samples.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"\n✓ wrote manifest {RES_DIR / 'page_samples.json'}")
    print("\nDone.")


if __name__ == "__main__":
    main()
