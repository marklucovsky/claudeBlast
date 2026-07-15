# BlasterAI — demo materials

Everything needed to pitch BlasterAI to three audiences from **one shared deck**, with per-audience cover emails doing the tailoring: **therapist prospects**, **Anthropic** (development funder), and **OpenAI** (runtime provider & early advocate).

## Brand & naming

- **Name:** **BlasterAI** (one word) — the formal product name, matching the domain **`blasterai.app`**.
- **Wordmark:** styled `Blaster` + `AI`, with the "AI" in the coral accent (`.ai` class in `deck/theme.css`). Used on the deck cover, section dividers, one-pager title, and video intro/outro cards.
- **Short form:** "**Blaster**" is fine as the everyday/spoken nickname (esp. in video narration) once "BlasterAI" is established — it's a nickname, not a competing mark. Written pitch materials use "BlasterAI" for consistency.
- **Trademark note:** "Blaster" alone is crowded (Sound Blaster, B'laster, an existing `blaster.ai` dev-tools platform, many `*Blaster` tools); don't assume the bare word is ownable. "BlasterAI" in the AAC/assistive-communication lane is the defensible mark — a quick attorney clearance is wise before the App Store listing.

## Contents

```
marketing/
├── deck/
│   ├── blaster-deck.md        # single integrated pitch deck (Marp)
│   └── theme.css              # BlasterAI-branded Marp theme (16:9)
├── one-pager/
│   ├── blaster-one-pager.md   # A4 leave-behind (Marp)
│   └── onepager-theme.css     # A4-portrait variant of the theme
├── video-scripts/
│   ├── 00-overview.md         # recording guide + shot list + sizzle-cut plan
│   ├── 01-tile-to-sentence.md # Demo 1
│   ├── 02-repetition-escalation.md  # Demo 2
│   ├── 03-scene-generation.md # Demo 3
│   └── 04-personalization-and-art.md
├── cover-emails/
│   ├── therapists.md          # clinical framing
│   ├── anthropic.md           # build + evaluation-rigor framing
│   └── openai.md              # runtime + early-advocacy framing
├── assets/
│   ├── prototypes/            # style-study renders (used in the deck)
│   └── screenshots/           # captured app stills/recordings (populated during capture)
├── render.sh                  # deck → PDF/HTML (+ `png` for per-slide images)
├── capture.sh                 # simulator boot/screenshot/record helper
└── build/                     # rendered output (gitignored)
```

## Rendering

Requires Node (`brew install node`) and Google Chrome (Marp uses it for PDF/PNG export).

```bash
./render.sh          # deck → build/blaster-deck.pdf + .html
./render.sh png      # also per-slide PNGs → build/png/

# one-pager (A4 portrait, needs both theme files registered):
npx @marp-team/marp-cli --theme-set deck/theme.css one-pager/onepager-theme.css \
  --allow-local-files one-pager/blaster-one-pager.md --pdf -o build/blaster-one-pager.pdf
```

The deck is authored in Marp Markdown so it stays version-controlled and diffable. Import the `.md` into Keynote/Google Slides only if you need to hand-tune; otherwise present the PDF/HTML directly.

## Demo videos

Four short, captioned videos (see `video-scripts/`), each mapped to a deck callout. Capture is hands-free via the app's built-in **TileScript** playback (`claudeBlast/Resources/Scripts/*.yaml`) so tap timing is smooth and repeatable. Use `capture.sh` to boot the simulator and record. For **real AI sentences**, set `OPENAI_API_KEY` in the app scheme before recording (otherwise the Mock provider returns fake text).

Assemble a **90-second sizzle cut** from the four once captured — that's the version that goes at the top of each cover email.

## The three-audience strategy

One deck, one narrative (problem → product → AI depth → evaluation rigor → therapist value → privacy → traction → ask), with **audience-specific appendix slides** (A: market, B: AI architecture & eval, C: dev workflow with Claude, D: privacy detail). Each cover email points its reader to the appendix and the demo videos that land hardest for them:

| Audience | Lead with | Videos to feature | Appendix |
|----------|-----------|-------------------|----------|
| Therapists | Clinical time-savings, AI-optional | 1 (tile→sentence), 3 (scene gen) | A |
| Anthropic | Built-with-Claude, eval rigor | 2 (escalation → eval numbers) | B, C |
| OpenAI | Runtime as the child's voice, responsible integration | 1, 2 | B |

## Source of truth

Numbers and claims are grounded in the repo: `docs/prd.md`, `docs/gtm.md`, `docs/plan-2026-06-16.md`, and the eval baseline under `claudeBlastTests/Eval/`. If those change, update the deck and one-pager to match.
