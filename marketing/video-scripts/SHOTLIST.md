# BlasterAI — recording shot list (run sheet)

Operational, exact capture plan. Captions below are the **verified** live output from a
real First Look run (see the deck's slides 7 & 11) — not the earlier representative
guesses in `01-*.md`. Record in the order here; cut into the 5 videos + sizzle in post.

---

## 0 · One-time setup (do once, before any clip)

- **Device:** the configured physical iPad (warmer than the simulator; real taps + TTS).
- **Orientation:** **landscape** for Clips A–E (matches the grid + admin UI). Clip F (iPhone) is portrait. The sizzle gets a vertical center-crop in post.
- **Real AI, not mock:** set `OPENAI_API_KEY` so sentences are live (scheme env var, or paste the key in-app). Confirm you're NOT on the Mock provider.
- **Voice:** Admin → Voice → pick an **Enhanced or Premium** voice (big quality jump). Test one sentence.
- **Profile:** the **Sandbox** (system) profile so no real child data shows.
- **Art set:** **Playful-3D** (default) for Clips A, B, D, E. Clip C shows the swap.
- **Build:** Release (hides the debug breadcrumb) so the grid is clean.
- **Screen:** full brightness, **True Tone OFF** (consistent color), **Do Not Disturb ON** (no banners), audio **not** on silent.
- **Recording:** iOS Screen Recording (Control Center). Quiet room so TTS is clean. **Don't** talk over the TTS — narrate in gaps or via captions.
- **Crop plan (applies to every TileScript clip):** in post, crop out the iOS **status bar** (clock/battery + red rec dot), the **TileScript HUD pill** ("Command X/4 …" bottom-center), the **"Script finished · Dismiss"** toast, and the tiny **grid-info badge** ("13×5 · 65/pg …").

---

## Clip A — First Look  →  Videos 1 (tile→sentence) **and** 2 (escalation)

**One take covers both.** Driver: TileScript **"First Look"** (`demo_basic.yaml`). Landscape.
Trigger: caregiver menu → TileScript → **First Look → Run**. Let it play hands-free.

| # | On screen | 🔊 Spoken (verified) | Burn-in caption |
|---|-----------|----------------------|-----------------|
| A1 | Home grid, hold ~2s | — | *A child's board. Every tile is a word.* |
| A2 | taps `grandpa` → `playground` | **"Grandpa, let's go to the playground!"** | 🔊 "Grandpa, let's go to the playground!" |
| A3 | adds `lemonade` (tray grows) | **"Grandpa, let's go to the playground and get some lemonade!"** | *Tiles are additive — the sentence grows.* |
| A4 | **replay ↻** (badge ↻1) | **"Grandpa, I really want to go to the playground and get some lemonade — right now!"** | *Repeat = the volume knob. It escalates.* |
| A5 | taps `mom` → `stomachache` | **"Mom, I have a stomachache. I need help!"** | 🔊 "Mom, I have a stomachache. I need help!" |
| A6 | adds `bathroom` | **"Mom, I have a stomachache. Can I go to the bathroom?"** | *Real needs, spoken instantly.* |

**Cut into two videos in post:**
- **Video 1 (tile→sentence, 45–60s):** A1 → A2 → A3, then A5 → A6. The "aha" is A2 — give it air.
- **Video 2 (repetition→escalation, 40–50s):** A3 (base) → A4 (escalated). Grow the tray text / push teal on the escalation so muted viewers feel the crescendo. End card: *"We measured this — escalation quality 38% → 85%, baseline locked in the repo."*

---

## Clip B — Scene generation  →  Video 3 (therapist superpower)

**Live** (typing the goal IS the wow — do not pre-fill). Landscape. 60–75s.

1. Admin → **Scenes → New Scene**. *Caption: Today therapists hand-pick from 5,000–10,000+ items.*
2. Type slowly, readable: **"feelings for a 5-year-old working on frustration vs anger"**.
3. **Generate** → progress state (tighten in edit so it feels like seconds).
4. Scene preview appears — pages, tiles, images, navigation. *Caption: A complete scene in seconds.*
5. Scroll the pages. *Caption: Fully editable before you accept.*
6. **Accept** → scene editor → switch to child grid showing the new board. *Caption: Idea → usable board in under a minute.*
7. Show the **export/share** affordance. *Caption: Portable JSON — share by message or AirDrop. Zero lock-in.*

Use a **real** generated result — don't fake it. Keep the admin chrome visible so it reads as a real tool.

---

## Clip C — Art-set swap  →  Video 4, segment A

Driver: TileScript **"Classic Tiles Showcase"** (`demo_food.yaml`). Landscape.
It orders food, then **flips the whole board Playful-3D → Classic** and restores at the end.

- Let it run; the beat that matters is the **live redraw of the same board in a different art set**. *Caption: Same vocabulary, a different look.*
- Optional insert for the 4-style montage: `../assets/prototypes/style_sheet_4.png` (Classic · Playful-3D · ARASAAC · High-Contrast). *Caption those four names.*

---

## Clip D — Single-word mode  →  Video 4, segment B

Driver: TileScript **"Single Word Mode"** (`demo_wordmode.yaml`). Landscape.
**Pre-req:** the **"Tide Pools"** sample scene must be loaded (the script activates it, but confirm it exists).

- It taps `crab`, `fish`, `seahorse`, … each **speaks a single word** and pushes to the **FIFO strip**. Keep the strip visible so older words scroll off — that's the classic-AAC signal.
- *Caption: AI is optional — classic single-word AAC, no AI at all.*

---

## Clip E — Caregiver layer  →  Video 4 intro (record right before C/D)

**Live.** Landscape. This is the trust beat for skeptical clinicians.

1. **Long-press Home** → Face ID / PIN gate (show the gate exists; **blur/omit the digits**). *Caption: A caregiver layer the child never sees.*
2. Profile settings — name / age / voice / vocabulary size / **mode toggle**. *Caption: Per-child voice, words, and mode.*
3. **Flip AI Sentences → Single Words** and hold on it. *Caption: AI when it helps. Rock-solid AAC always.*  ← the objection-defusing beat; don't rush it.

---

## Clip F — Two devices, one voice  →  Video 5 (the human hook)

**Staged real-world**, portrait, 30–40s. Priority for the top of the sizzle.

- iPad on the kitchen counter → cut to a phone coming out of a pocket in a store aisle → child taps → **the phone speaks**. *Caption: The iPad stays home. Any iPhone becomes the child's voice.*
- Same child, same words, same scenes — synced through the family's own iCloud. Shoot with a real parent + child if possible, or a clear staged reenactment.

---

## Post-production

- **Intro/outro cards** (3s each), deck colors: intro = BlasterAI wordmark (AI in **teal**) on the navy gradient + "A voice for non-verbal children"; outro = "blasterai.app · Free · Open source · mark@lucovsky.com".
- **Captions on every spoken line + every therapist action** (assume muted).
- **Filenames:** `blasterai-01-tile-to-sentence.mp4`, `-02-escalation`, `-03-scene-generation`, `-04-personalization`, `-05-two-devices`.
- **Exports:** 1080p per video + a **90s sizzle** (highlights of 1–4, one narration line per beat) and a vertical **1080×1920** crop of the sizzle for messaging apps. Sizzle opens with Clip F.
- **Sanity check:** no real child names, no API keys on screen, TTS clean, HUD/toast/status-bar cropped.
</content>
