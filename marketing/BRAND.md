# BlasterAI — brand guide

The single source of truth for BlasterAI's visual identity. The pitch deck, the
one-pager, the future `blasterai.app` site, and (next) the app should all draw
from this. Direction: **"Modern AI"** — *intelligent, human, forward-thinking.*
Deep neutrals for clarity; teal + green accents for innovation, progress, trust.

---

## Name & wordmark

- **Product name:** **BlasterAI** (one word). Matches the domain **`blasterai.app`**.
- **Short form:** "**Blaster**" is the sanctioned everyday/spoken nickname (especially
  in video narration) once "BlasterAI" is established. Written materials use "BlasterAI".
- **Wordmark:** `Blaster` + `AI`, where the **"AI" is the teal accent**. On dark
  backgrounds the "AI" uses a brighter teal for contrast (see below). Rendered in
  code as `Blaster<span class="ai">AI</span>`; the `.ai` class carries the color.
- **Typeface:** **Inter** (weights 400/500/600/700/800). Headings 700–800, body 400,
  emphasis 700. Loaded from Google Fonts in the deck theme; use Inter everywhere.

### Trademark note
"Blaster" alone is crowded (Sound Blaster, B'laster, an existing `blaster.ai`
dev-tools platform, many `*Blaster` tools) — do **not** assume the bare word is
ownable. "BlasterAI" in the AAC / assistive-communication lane is the defensible
mark. A quick attorney clearance is wise before the App Store listing.

---

## Color palette ("Modern AI", concept #2)

### Core swatches

| Role | Hex | Token | Usage |
|------|-----|-------|-------|
| **Teal Accent** | `#14B8A6` | `--brand-accent` | **Primary accent** — CTAs, key highlights, emphasis, wordmark "AI", primary stat |
| **Blue Accent** | `#3B82F6` | `--brand-accent-2` | Secondary actions & **links**; the secondary stat |
| **Success** | `#22C55E` | `--brand-green` | Success states / positive metrics (e.g. the "85%" after-stat) |
| **Warning** | `#EAB308` | `--brand-gold` | Highlight bars (blockquote), warnings |
| **Error** | `#EF4444` | `--brand-error` | Errors (reserved; unused in deck) |
| **Text Primary** | `#0F172A` | `--brand-ink` | Primary text & dark surfaces |
| **Text Secondary** | `#475569` | `--brand-ink-soft` | Secondary text, captions, **footer** |
| **Surface** | `#FFFFFF` | `--brand-bg` | Page background |
| **Background** | `#F8FAFC` | `--brand-bg-tint` | Soft panels, blockquote, table zebra |

### Teal scale (for depth — dividers, tints)
`50 #F0FDFA · 100 #CCFBF1 · 200 #99F6E4 · 300 #5EEAD4 · 400 #2DD4BF · 500 #14B8A6 · 600 #0D9488 · 700 #0F766E · 800 #115E59 · 900 #134E4A`

### Blue scale
`50 #EFF6FF · 100 #DBEAFE · 200 #BFDBFE · 300 #93C5FD · 400 #60A5FA · 500 #3B82F6 · 600 #2563EB · 700 #1D4ED8 · 800 #1E40AF · 900 #1E3A8A`

### Usage rules (from the concept sheet)
- **Teal = primary** accent for CTAs and key highlights.
- **Blue = secondary** actions and links.
- **Green = reserved** for success states and positive metrics.
- Deep neutrals provide clarity and sophistication.
- All key text/UI combinations should meet **WCAG AA**.

---

## Surfaces

- **Cover (title):** dark gradient `#0F172A → #111827 → #134E4A` (navy → teal-dark,
  echoing the "teal-glow" hero). Wordmark "AI" = **teal-400 `#2DD4BF`**. Subtitle =
  teal-200 `#99F6E4`. Caption = slate-400 `#94A3B8`.
- **Section dividers (statement slides):** deep-teal gradient `#0F766E → #115E59 →
  #134E4A`. White text; kicker/caption = teal-200 `#99F6E4`; wordmark "AI" =
  **teal-300 `#5EEAD4`**. **No footer/page-number chrome** on these slides.
- **Content slides:** white surface, `#0F172A` text, teal emphasis, `#F8FAFC` panels.
  Footer in `--brand-ink-soft`; page number bottom-right.

### Wordmark "AI" color by background
| Background | "AI" color |
|---|---|
| Light (content / one-pager title) | teal-500 `#14B8A6` |
| Dark navy (cover) | teal-400 `#2DD4BF` |
| Deep teal (divider) | teal-300 `#5EEAD4` |

---

## Where this lives

- **Deck theme:** `marketing/deck/theme.css` (`@theme blaster`) — the canonical
  implementation of every token and rule above.
- **One-pager theme:** `marketing/one-pager/onepager-theme.css` — imports the deck
  theme, overrides only sizes for A4 portrait.
- **Render:** `marketing/render.sh` (needs Node + Chrome).

## App alignment — TODO (next session)
The app UI and asset accent colors were built before this brand direction. A
follow-up pass should align the app to the "Modern AI" palette + "BlasterAI"
naming (app display name, accent/tint colors, wordmark). Tracked for a dedicated
code session after the demo-materials work lands.
