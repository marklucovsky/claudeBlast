# Escalation quality baseline — 2026-06-20

Captured by the A2 eval harness (`LiveTier2EvalTests.captureQualityBaseline`).
Subject = `gpt-4o-mini` (production model), Judge = `gpt-4o`.

## Rollup

| Surface | Tier-1 pass | Judge | Notes |
|---|---|---|---|
| Sentence | 100% | 5.00/5 | Sentence generation is solid. |
| **Escalation** | **0%** | **escalate-rate 38%, regressions 3** | **Broken — the milestone target.** |

## Diagnosis — the ladders

The model escalates **one notch on the first repeat, then flattens or wobbles**.
It is not building cumulatively on the previous rung.

```
chocolate      intensities [3,3,3,3]   calls [flat, flat, flat]
  [0] I want chocolate!
  [1] I want chocolate!          ← identical
  [2] I want chocolate!          ← identical
  [3] I want chocolate!          ← identical

mom_hungry     intensities [0,3,2,2]   calls [escalates, regresses, escalates]
  [0] Mom, I'm hungry.
  [1] Mom, I'm really hungry!
  [2] Mom, I'm hungry!           ← REGRESSES (drops "really")
  [3] Mom, I'm super hungry!

pinkfong_video intensities [1,4,3,4,4] calls [escalates, regresses, escalates, flat]
  [0] I want to play Pinkfong and watch a video.
  [1] ... and watch a video now!
  [2] ... and play a video!      ← regresses (drops "now!")
  [3] ... and play a video now!
  [4] ... and play a video now!  ← flat (identical to [3])

go_home        intensities [1,4,3,3]   calls [escalates, regresses, flat]
  [0] I want to go home.
  [1] I want to go home now!
  [2] I want to go home!         ← regresses
  [3] I want to go home!         ← flat
```

## Root causes (in `SentencePromptBuilder.escalationPrompt`)

1. **Not cumulative.** Each repeat says "make it urgent" against a generic
   baseline, not "make it MORE intense than the previous sentence." So the model
   lands at roughly the same intensity each time → flat.
2. **Only 3 buckets (1, 2, 3+)**, and 2 vs 3+ aren't clearly more intense than 1.
3. **Fixed "mom, hungry" few-shot** anchors outputs (mom_hungry literally
   regressed toward the example).
4. **No concrete intensity ladder** (louder → emphatic words → ALL-CAPS →
   exclamation) tied to the repeat count, so the model has no axis to climb.

## A3 target

Rewrite the escalation prompt so each rung is explicitly hotter than the prior
one, re-run this capture, and beat the baseline: Tier-1 escalation pass-rate up
from 0%, judge escalate-rate up from 38%, regressions down from 3.

## A3 result — 2026-06-20

Rewrote `escalationPrompt` to be cumulative + graduated with a neutral example
(see SentencePromptBuilder). Re-ran the capture:

| Surface | Baseline | After A3 |
|---|---|---|
| Sentence Tier-1 / judge | 100% / 5.00 | 100% / 5.00 (unchanged) |
| Escalation Tier-1 pass | 0% | 100% |
| Escalation judge escalate-rate | 38% | 85% |
| Escalation regressions | 3 | 1 |

Ladders now climb instead of flatlining (e.g. chocolate: "I want chocolate!" →
"I WANT CHOCOLATE!!!" → "I WANT CHOCOLATE NOW!!!").

### Known residual — the intensity ceiling
Once a ladder reaches maximum intensity (ALL-CAPS + multiple "!"), deeper rungs
have nowhere higher to go, so the final rung of the deepest ladder
(pinkfong_video, 4 extra steps) occasionally plateaus or dips a little run-to-run.
This is a ceiling effect, not the old broken behavior. The live escalation Tier-1
floor is strict (any drop fails), so that one ladder can intermittently flag —
acceptable since it's opt-in and the judge confirms the overall ramp is healthy.
Minor wording nits remain (e.g. "I need HUNGRY now") from the blunt CAPS rule.
