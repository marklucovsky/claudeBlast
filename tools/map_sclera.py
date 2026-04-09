#!/usr/bin/env python3
"""Map Sclera symbol filenames to Blaster vocabulary tile keys."""

import json
import os
import sys
from collections import defaultdict
from pathlib import Path

VOCAB_PATH = Path(__file__).parent.parent / "claudeBlast" / "Resources" / "vocabulary.json"
SCLERA_DIR = Path(__file__).parent / "sclera" / "english"
OUTPUT_PATH = Path(__file__).parent / "sclera_mapping.json"

# Manual synonym/transform table: tile_key -> list of Sclera base names to try
SYNONYMS = {
    "grandma": ["grandmother", "grandma"],
    "grandpa": ["grandfather", "grandpa"],
    "mom": ["mother", "mom", "mama"],
    "dad": ["father", "dad", "daddy"],
    "fries": ["chips", "fries", "french fries"],
    "tv": ["television", "tv"],
    "soccer": ["football  soccer", "soccer", "football"],
    "brush_teeth": ["brush teeth", "toothbrush"],
    "wash_hands": ["wash hands", "hand washing"],
    "wash_hair": ["wash hair", "hair washing"],
    "ice_cubes": ["ice cubes", "ice cube"],
    "chocolate_milk": ["chocolate milk", "chocolatemilk"],
    "iced_tea": ["iced tea", "ice tea"],
    "fruit_snack": ["fruit snack", "fruit snacks"],
    "goldfish_cracker": ["goldfish cracker", "goldfish"],
    "graham_cracker": ["graham cracker", "graham"],
    "hot_dog": ["hot dog", "hotdog"],
    "peanut_butter": ["peanut butter"],
    "video_game": ["video game", "videogame", "game console"],
    "green_beans": ["green beans", "green bean"],
    "nice_to_meet": ["nice to meet you", "nice to meet"],
    "i_love_you": ["i love you"],
    "i_dont_know": ["i don't know", "i dont know"],
    "excuse_me": ["excuse me"],
    "thank_you": ["thank you", "thanks"],
    "youre_welcome": ["you're welcome", "youre welcome"],
    "be_quiet": ["be quiet", "quiet", "silence"],
    "no_way": ["no way"],
    "whats_up": ["what's up", "whats up"],
    "uh_oh": ["uh oh", "oops"],
    "oh_my": ["oh my", "oh my god"],
    "don't": ["don't", "dont", "not allowed"],
    "line_up": ["line up", "queue"],
    "dress_up": ["dress up", "disguise"],
    "play": ["play", "playing"],
    "playdoh": ["playdoh", "play doh", "play dough", "modelling clay"],
    "polish_nails": ["polish nails", "nail polish", "nail varnish"],
    "sore_throat": ["sore throat"],
    "stomach": ["stomach", "belly", "tummy"],
    "stomachache": ["stomachache", "stomach ache", "tummy ache", "bellyache"],
    "toothache": ["toothache", "tooth ache"],
    "headache": ["headache", "head ache"],
    "bowling_alley": ["bowling alley", "bowling"],
    "snack_bar": ["snack bar"],
    "grocery_store": ["grocery store", "grocery", "supermarket"],
    "living_room": ["living room", "livingroom"],
    "dining_room": ["dining room", "diningroom"],
    "body_health": ["body health", "body"],
    "colors_shapes": ["colors shapes", "colours shapes"],
    "play_activities": ["play activities"],
    "next_page": ["next page", "next"],
    "previous_page": ["previous page", "previous"],
    "school_people": ["school people"],
    "cold_": ["cold", "chilly"],
    "cold__": ["cold", "freezing"],
    "clean_": ["clean", "tidy"],
    "cool_": ["cool"],
    "dry_": ["dry"],
    "funny_": ["funny"],
    "hard_": ["hard", "difficult"],
    "hot_": ["hot", "warm"],
    "light_": ["light", "bright"],
    "nice": ["nice", "kind"],
    "old_": ["old", "elderly"],
    "okay_": ["okay", "ok"],
    "right_": ["right", "correct"],
    "back_": ["back", "return"],
    "orange_": ["orange"],
    "cereal": ["cereals", "cereal"],
    "grapes": ["grapes", "grape"],
    "blueberries": ["blueberries", "blueberry"],
    "crackers": ["crackers", "cracker"],
    "pretzels": ["pretzels", "pretzel"],
    "nuggets": ["nuggets", "nugget", "chicken nuggets", "chicken nugget"],
    "pancakes": ["pancakes", "pancake"],
    "eggs": ["eggs", "egg"],
    "blocks": ["blocks", "block", "building blocks"],
    "cards": ["cards", "card", "playing cards"],
    "crayons": ["crayons", "crayon"],
    "markers": ["markers", "marker"],
    "paints": ["paints", "paint"],
    "bubbles": ["bubbles", "bubble", "soap bubbles"],
    "scissors": ["scissors", "scissor"],
    "cars": ["cars", "car", "toy car"],
    "bassketball": ["basketball"],  # typo in vocab
    "tricycle": ["tricycle", "Bicycle tricycle"],
    "trampoline": ["trampoline"],
    "snacks": ["snacks", "snack"],
    "sports": ["sports", "sport"],
    "games": ["games", "game"],
    "places": ["places", "place"],
    "drinks": ["drinks", "drink"],
    "meals": ["meals", "meal"],
    "fruit": ["fruit"],
    "veggie": ["veggie", "vegetable", "vegetables"],
    "milkshake": ["milkshake", "milk shake"],
    "soda": ["soda", "soft drink", "lemonade fizzy"],
    "yogurt": ["yogurt", "yoghurt"],
    "email": ["email", "e-mail", "mail"],
    "ipad": ["ipad", "tablet"],
    "therapy": ["therapy", "therapist"],
    "speech": ["speech", "talking"],
    "student": ["student", "pupil"],
    "church": ["church"],
    "airport": ["airport"],
    "farm": ["farm"],
    "store": ["store", "shop"],
    "mall": ["mall", "shopping mall", "shopping centre"],
    "restaurant": ["restaurant"],
    "library": ["library"],
    "lake": ["lake"],
    "ocean": ["ocean", "sea"],
    "zoo": ["zoo"],
    "pool": ["pool", "swimming pool"],
    "camp": ["camp", "camping"],
    "park": ["park"],
    "beach": ["beach"],
    "applesauce": ["applesauce", "apple sauce"],
}


def load_vocabulary():
    with open(VOCAB_PATH) as f:
        data = json.load(f)
    return data


def load_sclera_files():
    """Return dict: lowercase_basename_no_ext -> actual_filename"""
    files = {}
    for fname in os.listdir(SCLERA_DIR):
        if not fname.lower().endswith(".png"):
            continue
        base = fname[:-4]  # strip .png
        files[base.lower()] = fname
    return files


def find_match(key, sclera_lower_map, sclera_bases_lower):
    """Try matching strategies in order. Return (sclera_filename, strategy) or (None, None)."""

    # Strategy 1: Exact match (case-insensitive)
    if key.lower() in sclera_lower_map:
        return sclera_lower_map[key.lower()], "exact"

    # Strategy 2: Underscores to spaces
    spaced = key.replace("_", " ")
    if spaced.lower() in sclera_lower_map:
        return sclera_lower_map[spaced.lower()], "underscore_to_space"

    # Strategy 3: Synonyms
    if key in SYNONYMS:
        for syn in SYNONYMS[key]:
            if syn.lower() in sclera_lower_map:
                return sclera_lower_map[syn.lower()], f"synonym:{syn}"

    # Strategy 4: Partial/contains match - find Sclera files where the base name
    # exactly equals our key (already tried) or our key is a standalone word in the filename
    # Only match short filenames to avoid false positives
    key_lower = key.replace("_", " ").lower()
    best = None
    best_len = 999
    for base_lower, fname in sclera_lower_map.items():
        # Skip variant files (prefer base over _1, _2 etc.)
        if any(base_lower.endswith(f"_{i}") for i in range(1, 20)):
            continue
        # The Sclera base must start with our key as a word
        if base_lower == key_lower:
            return fname, "partial_exact"
        if base_lower.startswith(key_lower + " ") and len(base_lower) < best_len:
            best = fname
            best_len = len(base_lower)
    if best and best_len < len(key_lower) + 15:  # don't match overly long names
        return best, "partial_startswith"

    return None, None


def main():
    vocab = load_vocabulary()
    sclera_files = load_sclera_files()

    # Build lowercase lookup: base_no_ext_lower -> filename
    sclera_lower_map = {}
    for fname in os.listdir(SCLERA_DIR):
        if not fname.lower().endswith(".png"):
            continue
        base = fname[:-4]
        key_lower = base.lower()
        # Prefer non-variant files (no _N suffix)
        is_variant = any(key_lower.endswith(f"_{i}") for i in range(1, 20))
        if key_lower not in sclera_lower_map or not is_variant:
            sclera_lower_map[key_lower] = fname

    sclera_bases_lower = set(sclera_lower_map.keys())

    mapping = {}
    matched = []
    unmatched = []
    strategy_counts = defaultdict(int)

    for tile in vocab:
        key = tile["key"]
        word_class = tile.get("wordClass", "unknown")
        fname, strategy = find_match(key, sclera_lower_map, sclera_bases_lower)
        if fname:
            mapping[key] = fname
            matched.append((key, fname, strategy, word_class))
            strategy_counts[strategy] += 1
        else:
            mapping[key] = None
            unmatched.append((key, word_class))

    # Write output
    with open(OUTPUT_PATH, "w") as f:
        json.dump(mapping, f, indent=2, sort_keys=True)

    # Print summary
    print(f"\n{'='*60}")
    print(f"Sclera Mapping Summary")
    print(f"{'='*60}")
    print(f"Total tiles:    {len(vocab)}")
    print(f"Matched:        {len(matched)} ({100*len(matched)/len(vocab):.1f}%)")
    print(f"Unmatched:      {len(unmatched)} ({100*len(unmatched)/len(vocab):.1f}%)")
    print(f"\nMatches by strategy:")
    for strat, count in sorted(strategy_counts.items(), key=lambda x: -x[1]):
        print(f"  {strat:30s} {count}")

    print(f"\n{'='*60}")
    print(f"Unmatched keys by wordClass ({len(unmatched)} total):")
    print(f"{'='*60}")
    by_class = defaultdict(list)
    for key, wc in unmatched:
        by_class[wc].append(key)
    for wc in sorted(by_class.keys()):
        keys = sorted(by_class[wc])
        print(f"\n  {wc} ({len(keys)}):")
        for k in keys:
            print(f"    - {k}")

    print(f"\nMapping written to: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
