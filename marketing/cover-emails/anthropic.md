# Cover email — Anthropic

**Purpose:** Anthropic funds the development. Frame the shared deck around what they care about: real, safe, evaluated AI in a high-stakes human context — built end-to-end with Claude Code. Show impact and rigor; express gratitude without groveling.

**Subject line options**
- What your support built: BlasterAI, an AI voice for non-verbal kids
- BlasterAI update — shipped, eval-tested, and headed to a pilot
- Claude Code built this: a free AAC app for non-verbal children

---

Hi [Name],

I wanted to share where **BlasterAI** is — the free, open-source AAC app for non-verbal children that your support has made possible. Short version: it's shipped across four milestones, it's eval-tested, and it's headed for a TestFlight pilot with real therapists and families.

Two things I think will resonate with you specifically.

**1. It was built end-to-end with Claude Code.** Planning, implementation, code review, and the full git lifecycle — worktrees, commits, PRs — all run through Claude. It's ~52K lines of Swift across four shipped milestones, built by a very small team moving fast. This is a real, in-the-wild example of Claude Code carrying a nontrivial product from idea to shippable.

**2. We took evaluation seriously — because we had to.** This app becomes a child's voice, so "seems fine" isn't good enough. BlasterAI ships with an **evaluation harness**: a deterministic Tier-1 checker plus a Tier-2 LLM judge that score every generated sentence against a rubric. It caught a genuine weakness — the model wasn't escalating urgency when a child repeats a tile — we fixed the prompt, and the harness *proved* the fix: judge pass rate **38% → 85%**, deterministic checks **0% → 100%**, with a locked, reproducible baseline in the repo. That's the loop I think matters most for putting AI in front of vulnerable users, and I'd genuinely welcome your feedback on it.

The deck tells the whole story — the problem (~1M+ U.S. kids could use AAC, and access is deeply unequal), the product, and the trajectory. **Appendix B** goes deep on the AI architecture and the eval harness, and **Appendix C** on how the whole thing is built with Claude.

Mostly, though: **thank you.** This exists because Anthropic backed it, and it's going to give real kids a voice. I'd love to walk you through it live sometime, and to hear where you'd push on the evaluation and safety side.

With gratitude,
Mark

Mark Lucovsky
blasterai.app · mark@lucovsky.com · github.com/marklucovsky/claudeBlast

---

*Attach: `blaster-deck.pdf`, `blaster-one-pager.pdf`, video 2 (repetition→escalation — it ends on the eval numbers). Point them to Appendix B & C.*
