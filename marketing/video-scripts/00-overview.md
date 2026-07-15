# BlasterAI demo videos — overview & recording guide

Four short videos, each self-contained, each mapping to a callout in the deck. Keep them **short and captioned** — most viewers (and busy execs at Anthropic/OpenAI) watch muted.

> **Brand voice.** The name is **BlasterAI** — use it on the **wordmark, intro/outro cards, and first on-screen mention**. In **spoken narration**, "**Blaster**" is the natural short form ("Blaster speaks…" flows; "BlasterAI speaks…" is clunky). So where a voiceover line below says "BlasterAI," the narrator may simply say "Blaster." Domain everywhere: **blasterai.app**.

| # | Video | Length | Deck callout | Primary audience |
|---|-------|--------|--------------|------------------|
| 1 | Tile → sentence | 45–60s | Demo 1 | Everyone (the "aha") |
| 2 | Repetition → escalation | 40–50s | Demo 2 | Everyone; AI depth for OpenAI/Anthropic |
| 3 | Scene generation (therapist) | 60–75s | Demo 3 | Therapists |
| 4 | Personalization & art sets | 45–60s | "Built around the real child" | Therapists |
| 5 | Two devices, one voice (iPhone on the go) | 30–40s | "Two devices, one voice" | Everyone (the emotional hook) |

**Video 5 — the iPhone scenario — is a priority beat, not an afterthought.** The story: the iPad lives at home (family room, lunch table), but out in the world — the grocery store, Costco, grandma's house — the child doesn't have to carry it, because **a parent's iPhone becomes their voice** the moment they need it. Same child, same words, same scenes, synced through the family's own iCloud. Shoot this one with a real parent + child if possible (or a clear staged reenactment): iPad on the kitchen counter → cut to a phone coming out of a pocket in a store aisle → child taps → phone speaks. It's the most human moment in the set and belongs near the top of the sizzle cut.

> **Demo/slide alignment:** the deck's Demo 1 text (`grandpa` + `playground` → "Can I go to the playground with Grandpa?", then `lemonade`) is drawn from `demo_basic.yaml`. Keep captions matched to whatever the live model actually says on the day. Demo 2 (escalation) is **not** in a shipped TileScript — record it live with repeated taps, or we author a short `demo_escalation.yaml` first. Demo 3 (scene generation) is live by design (typing the goal is the wow).

**A 90-second "sizzle" cut** (highlights from 1–4, wall-to-wall captions, one line of narration per beat) is worth assembling once the four are captured — that's the version that goes at the top of the cover emails.

---

## Recording setup (consistent across all four)

**Device / capture**
- iPad Pro 11" simulator *or* a physical iPad (physical looks warmer — real taps, real audio). Prefer physical for the sizzle cut.
- Simulator recording: `xcrun simctl io booted recordVideo --codec h264 out.mov` (Cmd-R in Simulator also works).
- Physical iPad: iOS Screen Recording (Control Center). Use an external mic room, quiet, so TTS is clean.
- Record **portrait** for phone-friendly sharing of the sizzle, **landscape** for the therapist scene-generation flow (more room for the admin UI). Keep each individual video in one orientation.

**Look**
- Fresh install / Sandbox profile so no real child data shows.
- Default **Playful-3D** art set (except video 4, which shows the swap).
- Full brightness, True Tone off for consistent color.
- Hide the debug breadcrumb (Release build) so the child grid is clean.

**Hands-free capture with TileScript.** The app has a built-in record/playback engine (`docs/tilescript.md`). The three shipped scripts in `claudeBlast/Resources/Scripts/` already drive most of these flows — use playback so tap timing is smooth and repeatable instead of fumbling live:
- `demo_basic.yaml` → backbone of **Video 1**
- `demo_wordmode.yaml` → single-word segment of **Video 4**
- `demo_food.yaml` → art-set swap segment of **Video 4**

Set `audio: on` and `tileWait: .human` / `sentenceWait: .human` (already set) so the pacing feels like a real child, not a robot.

**Audio.** Let the app's TTS play for real — it's the point. Pick an **Enhanced or Premium** iOS voice in Admin → Voice before recording (big quality jump over the default). Do NOT narrate over the TTS; narrate in the gaps or via captions.

**Captions.** Burn in captions for every spoken sentence and every action ("Therapist types the goal…"). Assume muted playback. Keep a consistent lower-third style.

---

## Shared intro/outro (3s each)

- **Intro card:** BlasterAI wordmark (with the "AI" in coral) on the deck's navy gradient → "A voice for non-verbal children."
- **Outro card:** "blasterai.app · Free · Open source" + `mark@lucovsky.com`.

Produced cards live in the deck theme colors so videos and slides feel like one set.

---

## Post-production checklist
- [ ] Captions on every spoken line + every therapist action
- [ ] No real child names / no API keys visible on screen
- [ ] TTS audible and clean (Enhanced/Premium voice)
- [ ] Consistent intro/outro cards
- [ ] Export 1080p (individual) + a vertical 1080×1920 crop of the sizzle for messaging apps
- [ ] File names: `blasterai-01-tile-to-sentence.mp4`, etc.
