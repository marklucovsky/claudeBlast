# Video 4 — Personalization & art sets (built around the real child)

**Goal:** Show that BlasterAI meets each child where they are: AI sentences *or* classic single-word AAC, a caregiver layer invisible to the child, and swappable art so the same vocabulary can look right for any kid. Reassures therapists that AI is *optional* and the fundamentals are solid.
**Length:** 45–60s · **Orientation:** portrait · **Drivers:** `demo_wordmode.yaml` (single-word segment), `demo_food.yaml` (art swap segment).

---

## Storyboard

| Time | Screen | Action | Caption (burned-in) | Voiceover |
|------|--------|--------|---------------------|-----------|
| 0:00 | Intro card | — | **Built around the real child** | — |
| 0:04 | Caregiver menu | Long-press Home → PIN/Face ID gate → admin | *A caregiver layer the child never sees — Face ID + PIN gated.* | "Behind a long-press, there's a whole caregiver layer the child never sees." |
| 0:11 | Profile settings | Show name/age/voice/vocabulary-size/mode toggle | *Per-child: voice, vocabulary size, and interaction mode.* | "Every child gets their own profile — their voice, their words." |
| 0:18 | Mode toggle | Flip **AI Sentences → Single Words** | *Toggle: AI sentences, or classic single-word AAC.* | "AI is optional. Flip to classic single-word mode and BlasterAI works like the AAC you already know." |
| 0:24 | Child grid (word mode) | Tap `crab`, `fish`, `seahorse` — each speaks + adds to the FIFO strip | 🔊 *crab · fish · seahorse* | "Each tap speaks a word — no AI, just fast, reliable communication." |
| 0:32 | Art set switch | Back to admin → change art set; show the same board redraw | *Same vocabulary, a different look.* | "And the art meets the child too." |
| 0:38 | Style montage | Cross-fade the same tiles across Classic → Playful-3D → ARASAAC → High-Contrast | *Classic · Playful-3D · ARASAAC · High-Contrast* | "Classic line-art, playful 3D, ARASAAC, high-contrast for low vision — same words, whichever style fits." |
| 0:48 | Reassurance card | — | *AI when it helps. Rock-solid AAC always.* | "Powerful AI when it helps — and a rock-solid AAC board when it doesn't." |
| 0:54 | Outro card | — | **blasterai.app · Free · Open source** | — |

---

## Notes for the editor
- The **mode toggle at 0:18 is the trust beat** for skeptical clinicians — "AI is optional" defuses the biggest objection. Hold on it.
- For the art montage (0:38), you can use `style_sheet_4.png` (in `../assets/prototypes/` — Classic / Playful-3D / ARASAAC / High-Contrast, the four real sets) as an insert, or better, record the live in-app redraw of one board across sets via `demo_food.yaml` (which switches `classic` → `playful`).
- Blur/omit any real PIN entry — show the gate exists, not the digits.
- Single-word mode: make the **FIFO strip** visible so viewers see older words scroll off. That's the classic-AAC signal.

## The one line if someone only reads the caption
> *AI sentences or classic single words, a hidden caregiver layer, and five art styles — the same vocabulary, shaped to each child.*
