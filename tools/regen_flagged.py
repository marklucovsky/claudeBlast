#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Regenerate flagged p3d tiles with audit-informed prompts.

Reads improved prompts inline, generates via DALL-E 3, writes to
tools/tile_sets/playful_3d_v2/, records a generation, and rebuilds
the HTML review page.
"""

import json
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

sys.path.insert(0, str(Path(__file__).parent))
from generate_sets import STYLES, generate_image, SLEEP_SECONDS, MIN_IMAGE_BYTES  # noqa

OUTPUT_DIR = Path("tools/tile_sets/playful_3d_v2")
STYLE = "playful_3d"

# Audit-informed prompts: each addresses the specific issue flagged.
# Format: key → full prompt subject (STYLE_PLAYFUL_3D prefix applied automatically).
IMPROVED_PROMPTS = {
    # --- Pronouns: add a bold pointing arrow to distinguish from generic figure ---
    "they": (
        "Three clay figurine children standing together as a group, "
        "a large bold blue arrow arcs over all three pointing down at the group, "
        "indicating 'them/they'. Simple cream background"
    ),
    "she": (
        "A clay figurine girl character with long hair, half-body, "
        "with a bold pink arrow pointing directly at her from the side, "
        "indicating the pronoun 'she'. Simple cream background"
    ),
    "boy": (
        "A clay figurine boy character with short hair, half-body facing forward, "
        "clearly masculine features, wearing a blue t-shirt. Simple cream background"
    ),
    "he": (
        "A clay figurine boy character with short hair, half-body, "
        "with a bold blue arrow pointing directly at him from the side, "
        "indicating the pronoun 'he'. Simple cream background"
    ),
    "mine": (
        "A clay figurine child hugging a bright red ball tightly against their chest "
        "with both arms wrapped around it possessively, bold arrow pointing from child to ball, "
        "indicating ownership 'mine'. Simple cream background"
    ),

    # --- Abstract verbs: specific action-oriented depictions ---
    "want": (
        "A clay figurine child reaching forward with both hands outstretched toward "
        "a bright shiny toy on a high shelf just out of reach, yearning expression. "
        "Simple cream background"
    ),
    "turn": (
        "A bold 3D clay curved arrow doing a 180-degree U-turn, like a road turn arrow, "
        "bright blue color with rounded clay texture. Simple cream background"
    ),
    "get": (
        "A clay figurine child reaching up and grabbing a bright ball off a shelf, "
        "one hand on the ball pulling it toward themselves. "
        "Simple cream background"
    ),
    "close": (
        "A clay figurine child pushing a large colorful door closed with both hands, "
        "the door is almost shut with just a small gap of light visible. "
        "Simple cream background"
    ),
    "have": (
        "A clay figurine child standing proudly holding up a bright red apple in one hand "
        "at chest height, showing it off, pleased expression. "
        "Simple cream background"
    ),
    "hurt": (
        "A clay figurine child with a visible bandage on one knee and a small red mark, "
        "grimacing in pain and holding the hurt knee with both hands. "
        "Simple cream background"
    ),
    "need": (
        "A clay figurine child with an empty plate in front of them, looking up with "
        "pleading eyes and both hands open palms-up in a begging gesture. "
        "Simple cream background"
    ),
    "see": (
        "A clay figurine child with one hand above eyes in a visor/lookout pose, "
        "eyes wide open, two bold yellow dotted lines radiating outward from the eyes "
        "like a line of sight. Simple cream background"
    ),
    "stand": (
        "A clay figurine child standing perfectly straight and tall at attention, "
        "arms at sides, next to a clay chair to show contrast of standing vs sitting. "
        "Simple cream background"
    ),
    "wear": (
        "A clay figurine child actively pulling on a bright red sweater over their head, "
        "the sweater halfway on, showing the action of putting clothes on. "
        "Simple cream background"
    ),
    "guess": (
        "A clay figurine child with a big question mark hovering above their head, "
        "one finger pointing up, eyes looking up at the question mark, pondering expression. "
        "Simple cream background"
    ),
    "lose": (
        "A clay figurine child looking sad and confused with empty hands turned palms-up, "
        "a faded transparent outline of a lost toy next to them showing it's gone. "
        "Simple cream background"
    ),
    "try": (
        "A clay figurine child straining with effort to push a large heavy boulder, "
        "leaning forward with both hands on the rock, determined expression, "
        "showing exertion and attempt. Simple cream background"
    ),
    "use": (
        "A clay figurine child holding a big crayon and drawing on paper, actively using the tool, "
        "colorful marks visible on the paper. Simple cream background"
    ),

    # --- Social expressions ---
    "maybe": (
        "A clay figurine child with a tilted head, one hand up showing a flat palm "
        "in a 'so-so' balancing gesture, uncertain expression, "
        "a large bold question mark to one side. Simple cream background"
    ),
    "whats_up": (
        "A clay figurine child giving a casual wave with one hand raised, "
        "head tilted with a friendly curious smile, relaxed standing pose. "
        "Simple cream background"
    ),
    "nice_to_meet": (
        "Two clay figurine children shaking hands warmly, both smiling, "
        "seen from the front, handshake clearly visible at center of frame. "
        "Simple cream background"
    ),
    "youre_welcome": (
        "A clay figurine child with one hand on chest and a warm gentle smile, "
        "slight bow of the head, gracious welcoming gesture. "
        "Simple cream background"
    ),
    "how_are_you": (
        "Two clay figurine children facing each other, one waving hello with a warm smile, "
        "the other with a thumbs up responding positively. "
        "Simple cream background"
    ),
    "i_love_it": (
        "A clay figurine child with both hands on cheeks, huge delighted smile, "
        "eyes sparkling with excitement, a bright red heart floating above their head. "
        "Simple cream background"
    ),

    # --- Places: distinctive architectural details ---
    "mall": (
        "A clay diorama of a shopping mall — a wide two-story building with multiple "
        "colorful store windows, a central glass entrance with an awning, "
        "tiny shopping bags visible in the windows. Simple cream background"
    ),
    "restaurant": (
        "A clay diorama of a small restaurant with a bold fork-and-knife sign on the front, "
        "a checkered tablecloth visible through the window, warm lighting from inside. "
        "Simple cream background"
    ),
    "pool": (
        "A clay diorama of a bright blue rectangular swimming pool seen from above at an angle, "
        "with a small diving board on one end and wavy blue water surface. "
        "Simple cream background"
    ),

    # --- Drinks ---
    "iced_tea": (
        "A tall clear 3D clay glass filled with amber-brown iced tea, clearly visible ice cubes "
        "floating in it, a tea bag string hanging over the rim, a lemon slice on the glass edge. "
        "Simple cream background"
    ),

    # --- Fruit ---
    "orange": (
        "A single round 3D clay orange fruit with vivid saturated orange color, "
        "a small green leaf attached to the stem on top, dimpled citrus texture. "
        "Simple cream background"
    ),

    # --- Descriptors ---
    "ugly": (
        "A clay figurine child looking at a lumpy messy clay blob sculpture on a table "
        "and making a disgusted scrunched-nose face, one hand pushing it away. "
        "Simple cream background"
    ),
    "hard_": (
        "A clay figurine child trying hard to bend a thick steel bar with both hands, "
        "straining with effort, the bar staying rigid and unbent — depicting 'hard' as in difficult. "
        "Simple cream background"
    ),
    "dumb": (
        "A clay figurine child with a confused blank expression, shoulders shrugged, "
        "both palms up in an 'I don't know' gesture. Simple cream background"
    ),
    "better": (
        "Two clay objects side by side: a small wilted flower on the left and a tall bright "
        "blooming flower on the right, with a bold green upward arrow between them "
        "pointing from small to tall, indicating improvement. Simple cream background"
    ),
    "worse": (
        "Two clay objects side by side: a nice shiny apple on the left and a brown bruised "
        "apple on the right, with a bold red downward arrow between them "
        "pointing from good to bad, indicating decline. Simple cream background"
    ),
    "low": (
        "A clay figurine child crouching down very low to the ground, knees bent deeply, "
        "with a bold downward arrow next to them pointing to the floor, "
        "indicating 'low' position. Simple cream background"
    ),
    "around": (
        "A bold 3D clay circular arrow going all the way around in a complete loop/orbit, "
        "bright green color with rounded clay texture, clearly showing 'around/surrounding'. "
        "Simple cream background"
    ),
}


def build_prompt(subject: str) -> str:
    return f"{STYLES[STYLE]} Subject: {subject}."


def main():
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        sys.exit("Set OPENAI_API_KEY")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()

    keys = list(IMPROVED_PROMPTS.keys())
    total = len(keys)
    ok = 0
    failed = []

    print(f"Regenerating {total} flagged tiles → {OUTPUT_DIR}/\n")

    for i, key in enumerate(keys):
        dest = OUTPUT_DIR / f"{key}.png"
        prompt = build_prompt(IMPROVED_PROMPTS[key])

        print(f"  [{i+1}/{total}] {key:25s}", end="", flush=True)
        data = generate_image(prompt, api_key, session)

        if data and len(data) >= MIN_IMAGE_BYTES:
            dest.write_bytes(data)
            print(f" ✓ ({len(data) // 1024} KB)")
            ok += 1
        else:
            print(f" ✗ (failed)")
            failed.append(key)

        if i < total - 1:
            time.sleep(SLEEP_SECONDS)

    print(f"\nDone: {ok}/{total} succeeded, {len(failed)} failed.")
    if failed:
        print(f"Failed: {', '.join(failed)}")

    # Record generation
    from review_tiles import record_generation  # noqa
    succeeded_keys = [k for k in keys if k not in failed]
    if succeeded_keys:
        gen_id = record_generation("playful_3d_v2", succeeded_keys,
                                   f"audit-flagged regen: {len(succeeded_keys)} tiles")
        print(f"Recorded generation {gen_id}")


if __name__ == "__main__":
    main()
