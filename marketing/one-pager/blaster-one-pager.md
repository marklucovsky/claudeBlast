---
marp: true
theme: blaster-onepager
title: 'BlasterAI — one-pager'
author: 'Mark Lucovsky'
description: 'BlasterAI — an AI voice for non-verbal children. Free, open source, privacy-first AAC.'
size: a4p
paginate: false
---

# Blaster<span class="ai">AI</span>
## A voice for non-verbal children — free, open source, privacy-first

<div class="cols">
<div>

### The problem
**~1 million+** U.S. children have complex communication needs and could benefit from AAC (Augmentative & Alternative Communication) — part of ~4–5M Americans of all ages. National access data is scarce, but the gaps are stark and unequal — device access swings from **32% to 84%** by family race in minimally-verbal autism. Dedicated devices cost **$5K–$15K**; the leading apps run **$250–$300** (one-time or subscription); only **~2%** of speech-language pathologists specialize in AAC; and funding — approval plus appeals — often stretches **6–12 months**. Roughly **35–55K** new children become AAC candidates every year.

### What BlasterAI does
A **free App Store app** (iPad & iPhone) for child *and* caregiver. A child taps picture tiles; BlasterAI generates and **speaks a natural, age-appropriate sentence** — `mom` + `eat` + `pizza` → *"Mom, can I have some pizza?"* — not word-salad. Repeated taps escalate urgency, because repetition is a non-verbal child's volume knob. Add a new word and BlasterAI **generates a matching tile**; describe a goal and it builds a **complete, editable, shareable board in seconds**. A parent's iPhone becomes the child's voice on the go.

### Why it's different
- **Open-source and SwiftUI-native** (Apache 2.0) — inspectable, forkable
- **No major AAC app builds full sentences from selected tiles with an LLM** — BlasterAI does
- **AI grows the vocabulary** — generates tile art and whole scenes on demand
- **AI is optional** — classic single-word mode works with no AI at all

</div>
<div>

### Built with rigor
- **Evaluation harness** in-repo: a deterministic checker + an LLM judge score every sentence. It caught a weakness in urgency escalation; the fix moved judge pass rate **38% → 85%** and deterministic checks **0% → 100%** — a locked, reproducible baseline.

### Privacy is the architecture
- **No backend.** Data lives on-device (SwiftData), syncing only through the family's own iCloud.
- **Stateless AI calls** — tiles in, sentence out; no identity or history stored by us.
- **Keychain-stored keys**, Face ID + PIN gated admin.
- **Fully auditable** — open source, nothing hidden.

### The technology
- SwiftUI + SwiftData, **iOS 26+**, iPad & iPhone
- Runtime: **OpenAI `gpt-4o-mini`** (sentences) + **`gpt-image-1`** (tiles); cache-first, so typical use is **well under $1/mo**
- Built end-to-end with **Claude Code**
- ~52K lines of Swift, shipped and headed to a pilot

### Status & ask
Shipped: trust/onboarding, scene generation, eval-tested quality, demo tooling. **Next: a TestFlight pilot with real therapists and families.** We're seeking pilot partners and continued support from **Anthropic** (build + evaluation rigor) and **OpenAI** (runtime).

</div>
</div>

<span class="cap">blasterai.app · Mark Lucovsky · support@blasterai.app · github.com/marklucovsky/claudeBlast · Apache 2.0</span>
