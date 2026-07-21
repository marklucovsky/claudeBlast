<!-- SPDX-License-Identifier: Apache-2.0 -->
# Claims-accuracy audit — deck & site (A2, 2026-07-20)

**Purpose.** Worklist item **A2** (`docs/plan-2026-07-19.md`): tighten deck/site claims so a
technical reader (Anthropic / OpenAI) can't catch an overclaim. The eval harness is a
**dev-time** evaluation (test target), **not** a runtime quality gate — several lines implied
runtime scoring. Same rigor as the commissioned privacy review.

## Ground truth (what actually runs)

| Layer | Reality | Source |
|---|---|---|
| **Runtime safety rails** | Child-persona + "Never generate sexual, violent, or adult content", sent on **every** API call. These are model *instructions*, **not** a code-level output filter. | `claudeBlast/Resources/sentence_prompt.json:2,4` |
| **Runtime scoring** | **None.** No score/judge/validate/filter between generation and TTS — output is spoken as returned. | `claudeBlast/Engine/SentenceEngine.swift` (no such path) |
| **Eval harness** | Dev-time only (test target). Tier-1 = deterministic checks; its safety check is a **3-fragment net** (`"make love"`, `"kill you"`, `"porn"`) with a code comment that nuanced safety is the judge's job. Tier-2 = `gpt-4o` judge vs. rubric. Opt-in, reproducible. | `claudeBlastTests/Eval/Tier1Scorers.swift:32-34`, `EvalHarness.swift` |
| **The numbers** | 38%→85% (judge) and 0%→100% (Tier-1) are real, and are the **escalation** sub-metric on a locked baseline — *not* overall sentence accuracy. | `claudeBlastTests/Eval/BASELINE.md` |

**One-line takeaway:** the prompt rails ARE runtime; the *scoring* is not. Every claim must say
which it means.

## Audit table (claim → location → verdict → applied wording)

| # | Claim (verbatim, before) | Location | Verdict | Applied wording |
|---|---|---|---|---|
| 1 | "…a Tier-1 deterministic checker plus a Tier-2 LLM judge that **score every sentence** against a rubric." | deck `blaster-deck.md:279` | **Overclaim** — reads as runtime, per-utterance | "…that **score our sentence generations in a test suite** against a rubric." |
| 2 | "…a deterministic checker plus an LLM judge — **scores every sentence**." | site `index.html:95` | **Overclaim** (mirror of #1) | "…**scores our sentence generations in a test suite.**" |
| 3 | "…and gets **measured** for quality." | deck `:210` | Ambiguous — reads runtime | "…and **whose quality we measure in an eval harness**." |
| 4 | "…**hard** content rails in the system prompt (…), **enforced** and eval-checked." | deck `:539` | Tighten — "enforced" = model instruction, no runtime filter; "eval-checked" = 3-fragment net + judge | "…content rails in the system prompt (…) **sent on every call**, with a deterministic safety net + judge **in eval**." |
| 5 | "…the evaluation rigor that **makes AI safe to put in a child's hands**." | deck `:461` | Soft — blends dev-eval with runtime safety | "…the evaluation rigor **behind putting AI in a child's hands**." |
| 6 | "…evaluation harness that **scores sentence quality**." | site `about/index.html:42`, `faq/index.html:59` | Mild — "in-repo" present | "…scores sentence quality **in a test suite**." |
| — | "Escalation quality — judge pass rate" 38%→85% + subject/judge footnote | deck `:286-300`, site `:97` | **Substantiated & already well-labeled** | *no change* |

All six edits landed 2026-07-20 (deck = this repo; site = `~/src/blasterai-site`).

## Open follow-up — the "refine" middle ground (Mark, 2026-07-20)

A2's open question asked whether to add a **hard runtime Tier-1 gate** on live output before TTS
(which would upgrade some claims from "eval-checked" to "enforced"). Mark's steer: **not** a hard
gate — a **"refine"** affordance instead, modeled on the art-refine flow (re-render a tile with
feedback), extended to the sentence/quality side.

- **Shape:** a **sticky "refine"** on a set (art set / sentence outcomes) — a caregiver-facing way
  to nudge and improve a generation, persisting the correction, that **complements and feeds the
  eval harness** rather than silently gating output.
- **Why it's the honest middle:** it improves real-world outcomes *and* generates labeled
  refinement data that strengthens the test suite — without claiming a runtime gate that doesn't
  exist. Keeps deck/site wording ("eval-checked", not "runtime-enforced filter") accurate while a
  genuine quality-improvement loop grows.
- **Status:** design idea only; **not** built this session. Own future worktree. Natural companion
  to the scene-gen eval extension and the promoted-tiles work.
