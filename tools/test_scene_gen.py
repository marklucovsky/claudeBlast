#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Fast prompt-iteration harness for AI scene generation + refinement.

Mirrors the production prompts in claudeBlast/Engine/SceneGeneratorService.swift
and SceneRefinerService.swift against the real vocabulary, so scene-construction
prompts can be tuned without building the app. Sibling of test_sentence_prompt.py.

Usage (run from the repo root, with OPENAI_API_KEY set):

  # Generate from a description (positional, file via @path, or stdin):
  python3 tools/test_scene_gen.py "field trip to a farm; kids need to eat, drink, ask for help"
  python3 tools/test_scene_gen.py @/tmp/farm_desc.txt

  # Refine: generate, then apply an instruction to the result and re-report:
  python3 tools/test_scene_gen.py @/tmp/farm_desc.txt --refine "add a fish pond and a creek"

It reports, per page, the tiles split into existing / new-with-metadata /
dropped(hallucinated), plus total tiles and whether every page is reachable from
the home page (mirroring SceneNavigation.ensureReachable, which backfills nav at
runtime — so "unreachable from the model" is expected and handled in-app).
"""
import json
import os
import sys

import requests  # bundles its own CA certs; avoids system-cert SSL issues

VOCAB_PATH = "claudeBlast/Resources/vocabulary.json"
MODEL = "gpt-4o-mini"
HOME_TOKEN = "<home>"

# Caregiver-selectable classes — mirror VocabularyClasses.caregiverSelectable.
CLASSES = [
    "people", "animal", "actions", "describe", "feeling", "social", "food",
    "meals", "fruit", "veggie", "snacks", "drinks", "places", "weather",
    "colors", "shape", "body", "health", "toy", "games", "sports", "play", "art",
]


def load_vocab():
    vocab = json.load(open(VOCAB_PATH))
    return vocab, set(t["key"] for t in vocab)


def vocab_block(vocab):
    by_class = {}
    for t in vocab:
        # Hide structural navigation tiles so the model can't repurpose them as
        # page switchers (mirrors SceneGeneratorService.buildVocabBlock).
        if t["wordClass"] == "navigation":
            continue
        by_class.setdefault(t["wordClass"], []).append(t["key"])
    return "\n".join(f"{wc}: {', '.join(by_class[wc])}" for wc in sorted(by_class))


def generate_system_prompt():
    classes = ", ".join(CLASSES)
    return f"""You are an expert AAC (Augmentative and Alternative Communication) specialist adding today's ACTIVITY VOCABULARY to a child's communication board. The app already supplies the child's familiar core board — pronouns (i, you, he, she, we, they), family, hungry/thirsty, eat→food, drink→drinks, help, bathroom, feelings, yes/no/more/want, and the full people, food, drinks, and body & health pages. Your ONLY job is to infer the topical world of the activity that sits on top of that board.

1. WORLD INFERENCE — From the setting, brainstorm roughly 20-30 common, concrete things a child would actually SEE or DO there: animals, structures, vehicles, tools, plants, scene-specific foods, places, and people-roles. Include the items the therapist named AND the obvious ones they did NOT name. (A farm implies barn, tractor, hay, fence, duck, goat, farmer, egg, etc.) Do not omit or summarize named items.

IMPORTANT — also include the vocabulary at the HEART of the activity even when it is a color, shape, or describing word, and pull the FULL relevant set, not just a couple. A session about colors must include the actual color words (red, orange, yellow, green, blue, purple, pink, black, white, brown, …); a session about shapes the shapes; a session about feelings the feeling words. This subject vocabulary is the point of the scene — never leave it out in favor of only the tools or props around it.

2. STAY TOPICAL — Do NOT include the generic core board the app already provides: no pronouns, no family/people words, no feelings, no generic foods or drinks, no needs (help, eat, drink, bathroom), and no social words (yes, no, more, please). Only include a food/drink if it is specific to THIS activity (e.g. hay or an egg on a farm). Focus on what makes this scene unique.

3. KEEP IT FLAT — Put every topical tile on a SINGLE page. Do NOT split into multiple pages, and do NOT add any navigation, "home", "back", or "next page" tiles. The app lays out the page across swipeable screens and adds the core cluster and category links itself. Return exactly one page.

4. PEOPLE & ROLES — Any people you DO include are activity roles (farmer, fisherman, zookeeper). To the child, adult helpers are simply "teacher" or a named caregiver (e.g. "Miss Cindy") — never clinical terms like "therapist" or "aide". Never create a tile for the child/patient themselves, and never invent generic people words ("child", "kid", "student").

Tile rules:
- Prefer existing tile keys. Before proposing a NEW word, search the vocabulary for an existing word with the same or near-identical meaning and use that instead (e.g. use "teacher", not "therapist"). Only introduce a new word when nothing existing fits.
- A NEW word must be a COMMON, CONCRETE thing with a single clear visual. NEVER make abstract concepts, feelings, or actions into new words.
- Declare every new word ONCE in the top-level "newWords" array with its "displayName" and "wordClass" (one of: {classes}), then reference it by the same "key" in page tiles. Every page-tile key MUST be an existing vocabulary key or a key declared in "newWords".

Return ONLY valid JSON matching this schema exactly - no markdown, no prose:
{{ "name": "string", "description": "string", "homePageKey": "string",
   "newWords": [ {{ "key": "horse", "displayName": "horse", "wordClass": "animal" }} ],
   "pages": [ {{ "key": "string", "tiles": [ {{ "key": "eat", "isAudible": true, "link": "" }} ] }} ] }}"""


def refine_system_prompt(current_scene_json):
    classes = ", ".join(CLASSES)
    return f"""You are an expert AAC specialist refining an existing communication scene for a non-verbal child. The therapist will give an instruction describing a change. Apply ONLY that change.

Here is the CURRENT scene as JSON (each tile lists its key, what it shows, whether it speaks, and any page link):
{current_scene_json}

Rules:
- Return the COMPLETE updated scene, preserving ALL existing pages and tiles (and their page keys) unless the instruction requires modifying or removing them.
- When the instruction introduces concrete things, INFER the obvious related items too (a fish pond implies fish, frog, duck, water; a creek implies bridge, rock). Add a new page if the additions are substantial; otherwise extend an existing page.
- Prefer existing vocabulary keys. Declare any genuinely new concrete word ONCE in the top-level "newWords" array with "displayName" and "wordClass" (one of: {classes}); reference it by the same key.
- Navigation tiles: isAudible=false, link = destination page key.

Return ONLY valid JSON in the same schema as the current scene - no markdown, no prose."""


def call_openai(system, user, max_tokens):
    resp = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}",
            "Content-Type": "application/json",
        },
        json={
            "model": MODEL,
            "temperature": 0.5,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        },
    )
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"]
    return json.loads(content[content.find("{"):content.rfind("}") + 1])


STRUCTURAL_NAV_KEYS = {"next_page", "previous_page", "home"}

# Curated rich Core pages bundled into every scene (mirror SceneNavigation.coreCategories).
CORE_CATEGORIES = [
    {"page": "people", "icon": "people", "classes": ["people"], "cross": []},
    {"page": "food", "icon": "food", "classes": ["food", "meals", "fruit", "veggie", "snacks"], "cross": ["drinks"]},
    {"page": "drinks", "icon": "drinks", "classes": ["drinks"], "cross": ["food"]},
    {"page": "body_health", "icon": "body_health", "classes": ["body", "health"], "cross": []},
]

# Curated core home cluster (mirror SceneNavigation.homeClusterKeys / homeClusterLinks).
HOME_CLUSTER = ["i", "you", "me", "my", "he", "she", "we", "they", "teacher", "mom", "dad", "friend",
                "help", "hungry", "thirsty", "bathroom",
                "happy", "sad", "tired", "hurt", "sick", "scared",
                "yes", "no", "more", "want", "please", "all_done", "look"]
HOME_CLUSTER_LINKS = [("eat", "food"), ("drink", "drinks")]


def simulate_nav(scene, vocab, vocab_keys):
    """Mirror SceneNavigation.scaffold: keep only the model's topical tiles, then
    build the home page (topical + core cluster + category links) and bundle the
    familiar rich Core pages."""
    def is_nav(t):
        return (not t.get("isAudible", True) and (t.get("link") or "")) \
            or t["key"] in STRUCTURAL_NAV_KEYS

    category_keys = {c["page"] for c in CORE_CATEGORIES}
    reserved = set(STRUCTURAL_NAV_KEYS) | category_keys | set(HOME_CLUSTER) | {k for k, _ in HOME_CLUSTER_LINKS}
    topical = []
    for p in scene["pages"]:
        for t in p["tiles"]:
            if is_nav(t) or t["key"] in reserved:
                continue
            reserved.add(t["key"])
            topical.append({"key": t["key"], "isAudible": True, "link": ""})
    if not topical:
        return scene

    page_keys = [p["key"] for p in scene["pages"]]
    home = scene["homePageKey"] if scene["homePageKey"] in page_keys else (page_keys[0] if page_keys else "home")

    by_class = {}
    for t in vocab:
        by_class.setdefault(t["wordClass"], []).append(t["key"])

    home_tiles = list(topical)
    for k in HOME_CLUSTER:
        if k in vocab_keys:
            home_tiles.append({"key": k, "isAudible": True, "link": ""})
    for k, to in HOME_CLUSTER_LINKS:
        if k in vocab_keys:
            home_tiles.append({"key": k, "isAudible": True, "link": to})

    category_pages = []
    for cat in CORE_CATEGORIES:
        if cat["page"] == home:
            continue
        tiles = [k for wc in cat["classes"] for k in by_class.get(wc, [])]
        if not tiles:
            continue
        page_tiles = [{"key": "home", "isAudible": False, "link": HOME_TOKEN}]
        for sib in cat["cross"]:
            if sib != home:
                page_tiles.append({"key": sib, "isAudible": False, "link": sib})
        page_tiles += [{"key": k, "isAudible": True, "link": ""} for k in tiles]
        category_pages.append({"key": cat["page"], "tiles": page_tiles})
        icon = cat["icon"] if cat["icon"] in vocab_keys else cat["page"]
        home_tiles.append({"key": icon, "isAudible": False, "link": cat["page"]})

    home_page = {"key": home, "tiles": home_tiles}
    return {**scene, "homePageKey": home, "pages": [home_page] + category_pages}


def reachable_pages(scene):
    pages = {p["key"]: p for p in scene["pages"]}
    home = scene.get("homePageKey")
    if home not in pages:
        home = scene["pages"][0]["key"] if scene["pages"] else None
    reachable, frontier = set(), [home] if home else []
    while frontier:
        k = frontier.pop()
        if k in reachable or k not in pages:
            continue
        reachable.add(k)
        for t in pages[k]["tiles"]:
            link = t.get("link") or ""
            if link and link != HOME_TOKEN and link in pages:
                frontier.append(link)
    return reachable, set(pages)


def report(raw_scene, vocab, vocab_keys, label):
    nw = {w["key"]: w for w in raw_scene.get("newWords", [])}
    off_taxonomy = [(w["key"], w["wordClass"]) for w in raw_scene.get("newWords", [])
                    if w["wordClass"] not in CLASSES]
    # Report the scene as it will look in-app: flattened + Core categories attached.
    scene = simulate_nav(raw_scene, vocab, vocab_keys)
    total = sum(len(p["tiles"]) for p in scene["pages"])
    print(f"\n=== {label} (after in-app scaffold) ===")
    print(f"SCENE: {scene.get('name')!r}  home={scene.get('homePageKey')!r}  "
          f"pages={len(scene['pages'])}  total_tiles={total}")
    print(f"newWords: {[(w['key'], w['wordClass']) for w in raw_scene.get('newWords', [])]}")
    if off_taxonomy:
        print(f"  NOTE off-taxonomy class (kept, neutral tint): {off_taxonomy}")
    for p in scene["pages"]:
        keys = [t["key"] for t in p["tiles"]]
        nav = [f"{t['key']}->{t['link']}" for t in p["tiles"]
               if not t.get("isAudible", True) and (t.get("link") or "")]
        dropped = [t["key"] for t in p["tiles"]
                   if t["key"] not in vocab_keys and t["key"] not in nw and t["key"] != "home"]
        print(f"  page '{p['key']}' ({len(keys)}): {keys}")
        if nav:
            print(f"     nav: {nav}")
        if dropped:
            print(f"     DROPPED(hallucinated): {dropped}")
    reachable, all_keys = reachable_pages(scene)
    unreachable = all_keys - reachable
    print(f"  NAV: {'all pages reachable OK' if not unreachable else 'UNREACHABLE: ' + str(sorted(unreachable))}")


def read_description(arg):
    if arg == "-":
        return sys.stdin.read().strip()
    if arg.startswith("@"):
        return open(arg[1:]).read().strip()
    return arg


def main():
    args = sys.argv[1:]
    refine_instruction = None
    if "--refine" in args:
        i = args.index("--refine")
        refine_instruction = args[i + 1]
        args = args[:i] + args[i + 2:]
    if not args:
        print(__doc__)
        sys.exit(1)

    description = read_description(args[0])
    vocab, vocab_keys = load_vocab()
    block = vocab_block(vocab)

    user = f"Setting / session description: {description}\n\nAvailable vocabulary by category:\n{block}"
    scene = call_openai(generate_system_prompt(), user, max_tokens=3000)
    report(scene, vocab, vocab_keys, "GENERATED")

    if refine_instruction:
        # Feed the generated scene back as the "current" scene, the way the app
        # serializes a persisted BlasterScene for SceneRefinerService.
        current = json.dumps({
            "name": scene.get("name"),
            "description": scene.get("description"),
            "homePageKey": scene.get("homePageKey"),
            "pages": scene["pages"],
        }, indent=1)
        ruser = (f"Instruction: {refine_instruction}\n\n"
                 f"Available vocabulary by category:\n{block}")
        refined = call_openai(refine_system_prompt(current), ruser, max_tokens=3500)
        report(refined, vocab, vocab_keys, f"REFINED ({refine_instruction!r})")


if __name__ == "__main__":
    main()
