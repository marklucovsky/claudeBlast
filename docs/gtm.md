# Blaster AAC — Go-to-Market Plan
## Living Document

### Why This Exists
Blaster is an open-source, AI-powered AAC app. The goals — in order:
1. Get this into the hands of families who need it.
2. Build a community of therapists who love it and want to shape its future.
3. Maybe even create a business around it.

This doc captures our market understanding, positioning, and the multiple paths we're considering for getting there.

---

### The Problem We're Solving

**Most children who need AAC don't have it.**

- ~1.5-2 million children under 18 in the US could benefit from AAC
- **~50,000-75,000 new children per year** enter the AAC pipeline in the US. Breakdown:
  - Autism: ~30,000-45,000 (120-150K diagnosed/yr, 25-30% minimally verbal)
  - Childhood apraxia of speech: ~6,000-15,000
  - Cerebral palsy: ~2,000-3,500
  - Down syndrome: ~800-1,500
  - Other (intellectual disability, TBI, rare conditions): ~4,500-11,000
- Globally: tens of millions, with nearly zero AAC access in low/middle-income countries

**These numbers are growing.** Autism prevalence has 4x'd in 20 years (1 in 150 in 2000 → 1 in 36 in 2020, CDC ADDM data) with no sign of plateauing. The proportion of autistic children who are minimally verbal (~25-30%) has stayed stable, so the absolute number grows proportionally. Net effect: **total new AAC-needing children is growing ~5-8% annually.** Other conditions (CP, Down syndrome) are stable. The growth is almost entirely autism-driven — a combination of broader diagnostic criteria, better screening in underserved communities, and possible genuine increase.

**Only 10-25% of people who could benefit from AAC actually have access** (Beukelman & Light, widely cited across AAC literature). That means 1.1-1.8 million underserved children in the US alone.

**Why the gap exists:**
1. **Cost.** Dedicated AAC devices run $5,000-$15,000. Even iPad apps cost $100-$300/year.
2. **Wait times.** Medicaid approval for speech-generating devices takes 3-18 months, varies wildly by state.
3. **SLP shortage.** Fewer than 5% of the ~210,000 SLPs in the US specialize in AAC.
4. **Myths.** Persistent belief that AAC will prevent natural speech development (research says the opposite).
5. **Demographic disparities.** Access correlates heavily with income, race, and geography.

---

### Competitive Landscape

#### Pricing (as of early 2025 — verify for current)

| App | Price | Notes |
|-----|-------|-------|
| Proloquo (AssistiveWare) | ~$100/yr subscription | Dominant iOS AAC. 200K+ users. Transitioned from $249.99 one-time (Proloquo2Go) |
| TouchChat HD (PRC-Saltillo) | $299.99 one-time | Often bundled with dedicated devices ($5K-$9K) |
| TD Snap (Tobii Dynavox) | ~$300/yr subscription | Or bundled with dedicated devices ($5K-$15K+) |
| LAMP Words for Life | $299.99 one-time | Motor planning approach |
| GoTalk NOW | $79.99-$99.99 | Budget option |
| Avaz AAC | ~$100/yr subscription | Notable for Android support, 20+ languages |
| CoughDrop | $6/mo | Web-based, partially open source (AGPLv3) |
| **Blaster** | **Free** | **Open source (Apache 2.0)** |

Dedicated AAC hardware devices: $5,000-$15,000+. Insurance/Medicaid often only covers dedicated devices, not iPad + app combos.

#### What's Wrong with the Status Quo

**Cost barrier.** A family choosing between groceries and a $300 AAC app isn't really choosing. Insurance processes take 6-12 months. Many families give up.

**Complexity.** Apps ship with 5,000-10,000+ vocabulary items. Require SLP expertise to customize. Hours of manual setup before a child can use them. This is backwards — the tool should work out of the box.

**Lock-in.** No vocabulary portability between apps. No interoperability standard adopted at scale. Switch apps and you start over. OpenAAC's Open Board Format exists but adoption is glacial. Blaster attacks this directly: scenes are serialized JSON that can be shared via text message, AirDrop, or hosted on a web page for any Blaster device to download. Vocabulary and tile images can flow freely across the entire Blaster user/therapist community.

**Outdated UX.** Circa-2012 design language. Clip-art aesthetics. Stigma-inducing for older kids and teens. These apps look like they were designed before smartphones existed — because they were.

**Robotic output.** Sentence output is typically concatenated words, not natural language. "I want eat pizza" instead of "Mom, can I have some pizza?" This is a solvable problem now. Nobody's solved it.

**No analytics.** Minimal usage tracking for parents/therapists to understand communication patterns and growth.

#### Open Source AAC Landscape

- **CoughDrop** — only production-quality open-source AAC (AGPLv3, Rails+Ember). Web-based, functions as open-core commercial SaaS. Not native iOS.
- **OpenAAC** — standards initiative (Open Board Format), not an app. Good intent, slow adoption.
- **No native iOS open-source AAC app exists.** Blaster would be first.
- **Symbol sets:** ARASAAC (free, CC BY-NC-SA, 15K+ symbols), Mulberry (CC BY-SA, ~3,500 symbols). Blaster currently uses ARASAAC + some DALL-E generated images.

#### AI in AAC

**No major AAC app has shipped LLM-based sentence generation.** Existing "AI" in AAC means traditional next-word prediction — a completely different thing.

- **Fluent AAC** is an early-stage startup building AI-first AAC. Worth watching.
- The AAC community is split on AI: therapists want it to reduce setup burden, but some advocates worry about AI "speaking for" the user.
- Blaster's approach threads this needle: AI constructs natural sentences from the child's own tile selections. The child chooses the words. AI makes them sound natural. The child is always in control.
- **Blaster's other AI secret sauce: scene generation.** A therapist types "feelings for a 5-year-old working on frustration vs anger" and gets a complete, ready-to-use scene in 30 seconds — pages, tiles, navigation, all wired up. No hand-selecting from a 500-tile vocabulary. This alone saves hours of SLP setup time per child. No other AAC tool does this. /* maybe even worth noting here that the friction to create is gone along with any friction to share with other therapists/patients */

---

### Blaster's Positioning

**What we are:** A free, open-source AAC app that uses AI to turn tile selections into natural sentences. iPad + iPhone. Privacy-first (no backend, no data harvesting). Modern SwiftUI design.

**What makes us different:**

| Differentiator | Details |
|---------------|---------|
| **Free** | $0. No subscription, no one-time fee, no in-app purchases. |
| **Open source (Apache 2.0)** | Anyone can fork, adapt, translate. Permissive license enables commercial and non-commercial use. |
| **AI sentence generation** | Tiles → natural, age-appropriate sentences. Not word concatenation. First AAC app to ship this. |
| **AI scene generation** | Therapist describes a goal in plain English → complete scene with pages, tiles, and navigation in 30 seconds. Hours of setup → minutes. |
| **Shareable scenes & vocabulary** | Scenes are portable JSON. Text them, AirDrop them, host them on a webpage. Tile images can be shared across the community. Zero lock-in. |
| **Privacy-first** | SwiftData + iCloud only. API calls stateless. No backend. No analytics platform. No data harvesting. |
| **Modern UX** | SwiftUI, iOS 26+. Designed in 2026, not 2012. |
| **Repetition as intensity** | Repeated tile combos escalate emotional urgency. The child's "volume knob." No other AAC does this. |
| **AI-optional** | Blaster supports direct word-level speech (tap tile = speak word) with zero AI in the child's path. AI sentence expansion is an additional mode. AI can serve only the therapist layer if that's where the value lies. |

**The cost argument is devastating:** A family can take a surplus iPhone, install Blaster for free, and have a functional AAC device for the cost of AI API calls (~$0.10-0.50/month with gpt-4o-mini for typical usage). Compare to $5,000-$15,000 for a dedicated device or $100-$300/year for a commercial app. And if on-device models (Apple Intelligence) prove viable, the API cost drops to zero.

---

### API Key Strategy

The BYOK (Bring Your Own Key) model has real friction for non-technical parents. Here's our current understanding and plan:

**Current state:** OpenAI has no official BYOK program for mobile apps. Their guidance says API keys should never be in client code, but a large ecosystem of BYOK apps (MacGPT, Petey, OpenCat, TypingMind) exists without penalty. It's unsupported but tolerated.

**Key provisioning UX:** Getting an OpenAI API key is an 8-12 step, 5-10 minute process. Pain points: platform.openai.com vs chatgpt.com confusion, credit card required (no free API tier), key shown only once, developer-oriented UI. Non-technical parents will need hand-holding.

**What we'll build:**
- Move API key from UserDefaults to iOS Keychain (security requirement before any release)
- In-app visual setup guide with screenshots
- Deep link to platform.openai.com/api-keys
- Paste-from-clipboard button
- Immediate key validation with friendly error messages
- Cost estimation display ("typical usage: $0.10-0.50/month")

**What we'll explore:**
- **OpenAI project-scoped keys** (mid-2024+): users can restrict a key to gpt-4o-mini only, with spending caps. We should guide parents to do this.
- **OpenAI accessibility/nonprofit credits**: case-by-case, worth pursuing post-launch
- **Apple Intelligence / Foundation Models (iOS 26)**: If on-device models can handle sentence generation (a relatively simple task: combine 1-4 tiles into an age-appropriate sentence), this eliminates the API key entirely — zero friction, zero cost, full privacy, works offline. **This is the #1 investigation priority.** If viable, BYOK OpenAI becomes the fallback/power-user option.

---

### Launch Paths

We're not defaulting to "put it on the App Store and hope." Three phases:

#### Phase 1: TestFlight Pilot (Validation)
- Distribute via TestFlight to a small cohort of SLPs and educators (5-10)
- No Xcode required for testers — they just accept a TestFlight invite and install
- Rapid iteration cycles based on clinical feedback
- Focus: vocabulary fit, UX for children, therapeutic value, scene generation usefulness
- **Goal:** Convince ourselves (and the pilot cohort) that Blaster is ready for broader release
- **ARASAAC images are fine for TestFlight** — no money changes hands, not publicly listed. Very low licensing risk.

#### Phase 2: Community + Academic Launch (The Real Launch)
This is where Blaster reaches the world. Likely happens in parallel:

**Community-driven distribution:**
- Partner with parent advocacy organizations, special education networks, school districts
- Present at conferences: ASHA Convention, Closing the Gap, ATIA
- Leverage parent communities: Facebook AAC groups (10K-50K+ members), Instagram #AAC, Reddit r/AAC
- School district IT departments could deploy via MDM
- Therapists from the pilot cohort become evangelists

**Academic / research partnerships:**
- Partner with university SLP programs for formal efficacy studies
- "Open-source AI-powered AAC" is a publishable research topic
- Published research drives clinical adoption more than marketing ever could

**Possibly with OpenAI support:** If we can secure accessibility credits or a partnership for key provisioning, this dramatically reduces the API key friction for new users.

#### Phase 3: App Store (Free)
- Publish on iOS App Store as a free app alongside Phase 2, or slightly after
- Requires: Apple Developer account ($99/yr), App Store review compliance, privacy policy, age rating
- Pre-requisites: Face ID gate on admin, resolve image licensing (custom DALL-E set or ARASAAC permission), finalize API key onboarding UX
- Distribution advantage: families can find it directly. "Free AAC app" is a powerful search term.
- By this point, community and academic channels are already driving awareness

**Why this sequence:** Therapist endorsement is the #1 driver of AAC adoption. If SLPs recommend Blaster, families will find it. If they don't, App Store presence is irrelevant. Phase 1 earns that endorsement. Phases 2+3 amplify it.

---

### Funding Landscape (Context for Positioning)

Understanding how AAC is funded helps us position Blaster:

- **Medicaid** covers speech-generating devices as durable medical equipment, but the approval process is brutal (3-18 months, varies by state). Medicaid generally covers dedicated devices, not iPad apps.
- **Private insurance** is highly variable. Many plans exclude or create barriers for AAC.
- **IDEA (schools)** requires districts to provide assistive technology via IEPs, but federal funding has never exceeded ~15% of the promised 40%. Districts pick the cheapest option that checks the box.
- **Out of pocket** is common. Families fundraise, apply to grants (e.g., AAC device lending libraries), or go without.

**Blaster's angle:** We don't need to navigate insurance. We don't need purchase orders. A therapist can recommend Blaster and a family can have it running on their existing iPad or old iPhone in 10 minutes. This bypasses the entire funding bottleneck.

---

### Key Organizations & Channels

| Organization | Why They Matter |
|-------------|-----------------|
| **ASHA** (American Speech-Language-Hearing Association) | Professional body for SLPs. Conference is the event. |
| **ISAAC** (International Society for AAC) | Global AAC research community |
| **RESNA** (Rehabilitation Engineering & Assistive Technology Society) | AT certification and standards |
| **Communication First** | Non-speaking-led advocacy org. Important voice. |
| **PrAACtical AAC** | Influential SLP blog. A mention here reaches thousands of practitioners. |
| **AAC Language Lab** | PRC-Saltillo's education arm, but widely used resources |
| **Parent Facebook groups** | 10K-50K+ members in major AAC groups. Word of mouth is king. |

---

### Risks & Concerns

**"AI speaking for the user" criticism.** The AAC community has valid concerns about AI autonomy. Blaster's defense is multi-layered:
- The child selects tiles (the intent), AI constructs natural language (the expression). The child is always in control of *what* they say. AI only helps with *how* it sounds.
- Blaster supports a direct speech mode — tap a tile, hear the word. Zero AI in the child's communication path. AI sentence expansion is an additional mode, not the only mode.
- AI can serve only the therapist layer (scene generation, vocabulary curation) if that's where the value lies for a particular child.
- This distinction matters and we need to communicate it clearly.

**API key friction.** Non-technical parents setting up an OpenAI API key is real friction. See the API Key Strategy section for our mitigation plan. Apple Intelligence / on-device models may eliminate this entirely.

**Offline capability.** Children need to communicate everywhere, including places without internet. Current architecture requires API for sentence generation. Cache helps (frequent phrases work offline), but first-use and novel combinations need connectivity. On-device models (Apple Intelligence, MLX) are the long-term answer. Direct word-level speech works offline today.

**Image licensing.** ARASAAC is CC BY-NC-SA 4.0.
- **TestFlight:** Very low risk. No money changes hands, not publicly listed. Several precedents.
- **App Store (free):** Gray area. Multiple free AAC apps (LetMeTalk, CBoard, AraBoard) already use ARASAAC on the App Store. Worth emailing ARASAAC (arasaac@aragon.es) for explicit permission — they have a track record of supporting AAC apps.
- **Clean path:** Generate full custom DALL-E set using existing `tools/generate_dalle.py`. 473 images at ~$0.04-0.08 each = $20-40. Zero licensing ambiguity, unique visual identity. This was always the plan.
- **Fallback:** Mulberry Symbols (CC BY-SA 4.0, ~3,500 symbols) — no NonCommercial restriction.

**SLP gatekeeping.** If SLPs don't endorse Blaster, adoption will be limited regardless of how good it is. The TestFlight pilot (Phase 1) directly addresses this.

---

### Open Questions & Proposals

**What's the minimum feature set for the TestFlight pilot?**
Proposal: We're close. Need: stable child grid (have it), sentence engine (have it), basic scene editing (have it), persistent data (have it), Face ID on admin (not started but small). Nice-to-have: import/export (so pilot therapists can share scenes with each other). The main gap is polish and stability, not features.

**How do we recruit pilot therapists?**
Proposal: Start with personal network — anyone who works with non-verbal children professionally. Then expand via: ASHA community forums, university SLP program contacts, PrAACtical AAC blog outreach, AAC-focused Facebook groups (post asking for beta testers). 5-10 is the right cohort size for a first pilot.

**Should we pursue Apple's accessibility program?**
Proposal: Yes, after Phase 1. Apple has developer programs for accessibility apps, and Blaster fits squarely. This could help with App Store featuring, marketing support, and possibly TestFlight capacity.

**On-device LLM for offline sentence generation?**
Proposal: Investigate Apple Intelligence / Foundation Models framework on iOS 26 as the #1 priority. Blaster's sentence generation task is relatively simple (combine 1-4 word tiles into a natural sentence given age context). If the on-device model can handle this, it eliminates the API key requirement, cost, privacy concern, and offline limitation in one stroke. Keep BYOK OpenAI as the power-user / higher-quality fallback.

**What conferences/events should we target?**
Proposal: ASHA Convention (Nov 2026, likely), Closing the Gap (Oct 2026, Minneapolis area typically), ATIA (Jan 2027, Orlando typically). For 2026, realistic targets are ASHA and Closing the Gap if we have a solid pilot by mid-2026.

**Do we need a website?**
Proposal: Yes, but minimal. A single-page landing site: what Blaster is, link to App Store, link to GitHub, setup guide for API key, link to TestFlight for pilot participants. GitHub README is not enough — families need a non-technical entry point. GitHub Pages or similar is fine. A hosted scene library (where therapists upload and share scenes) is a later-phase feature.

---

### Appendix: Discussion Log

*(Newest first)*

**2026-03-13 — GTM doc iteration, research deep-dives**
- Added annual incidence data: ~50,000-75,000 new children/year enter the AAC pipeline in the US, growing 5-8% annually (driven by autism diagnosis rates).
- Researched ARASAAC licensing: TestFlight is very low risk. Multiple free apps already use ARASAAC on App Store. Email arasaac@aragon.es for explicit permission; generate DALL-E custom set ($20-40) as the clean path.
- Researched OpenAI BYOK: no official program, but large ecosystem of tolerated BYOK apps. Key mitigations: Keychain storage, project-scoped keys, spending caps, in-app setup guide. Apple Intelligence / on-device models identified as #1 investigation priority — could eliminate API key requirement entirely.
- Elevated AI scene generation as a key differentiator ("therapist describes goal → complete scene in 30 seconds").
- Added scene/vocabulary sharing as positioning point — portable JSON, text/AirDrop/web sharing, zero lock-in.
- Added "AI-optional" as differentiator — direct word-level speech mode means AI can be limited to therapist layer only.
- Restructured launch paths into phases: Phase 1 (TestFlight pilot for validation) → Phase 2 (community + academic as the real launch) → Phase 3 (App Store alongside Phase 2).
- Converted open questions into proposals with specific recommendations.
- *GTM impact: Major revision incorporating all inline feedback and research findings.*

**2026-03-09 — GTM doc created, initial market research**
- Compiled competitive landscape: Proloquo ~$100/yr, TouchChat $299, TD Snap ~$300/yr, dedicated devices $5K-$15K. Blaster is free.
- Key stat: only 10-25% of children who could benefit from AAC have access. 1.1-1.8M underserved kids in the US.
- No native iOS open-source AAC app exists. Blaster would be first.
- No major AAC app has shipped LLM-based sentence generation. Blaster's AI approach is genuinely novel.
- Agreed on multiple launch paths rather than defaulting to App Store. Therapist pilot likely the most impactful first step.
- Revenue is not a motivator. Open source mission drives distribution strategy.
- *GTM impact: Initial doc created covering landscape, positioning, launch paths, risks.*
