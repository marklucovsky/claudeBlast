# Cover email — OpenAI

**Purpose:** OpenAI provides the runtime AI integration and were early advocates. Frame the shared deck around what their models do *at runtime* in a genuinely meaningful use case — and acknowledge that early advocacy. Show the product working, the responsible integration, and a warm invitation to keep collaborating.

**Subject line options**
- Where your models became a child's voice: BlasterAI
- BlasterAI update — gpt-4o-mini in a use case worth showing off
- The AAC app you backed early: shipped and eval-tested

---

Hi [Name],

I wanted to share where **BlasterAI** has landed — the free, open-source AAC app for non-verbal children that you were an early advocate for. Thank you for that early belief; it mattered, and I wanted you to see what it turned into.

**Your models are the runtime — they're the child's actual voice.** When a non-verbal child taps `mom` + `eat` + `pizza`, `gpt-4o-mini` turns those tiles into *"Mom, can I have some pizza?"* — a real sentence, not word-salad — and speaks it. Tap the same tile repeatedly and it escalates the urgency, because for a non-verbal child repetition is how they turn up the volume. And when a child needs a word we don't ship, **`gpt-image-1` generates a matching tile on the spot** — styled to their board and refinable — so their vocabulary grows with their world. Two of your models, both in service of one kid getting to say what they mean. It's a use case I think shows them at their best: small, fast, low-cost, and life-changing for the person on the other end.

A few things I think you'll appreciate about the integration:

- **Responsible by construction.** Calls are **stateless** — tiles in, sentence out, no user identity or history stored anywhere. Content safety rails live in the system prompt and are enforced. There's no backend; everything's on-device with the family's own iCloud.
- **Cost that makes it universal.** `gpt-4o-mini` at typical use is **~$0.10–$0.50 per child per month** — which is what lets a free app reach kids priced out of $5K–$15K devices.
- **We measure quality, not vibes.** An in-repo eval harness (subject model `gpt-4o-mini`, judge `gpt-4o`) scores every sentence; it caught and helped us fix an urgency-escalation weakness (**38% → 85%** judge pass rate).

It's shipped across four milestones and headed to a TestFlight pilot with therapists and families. The deck has the full story; **Appendix B** details the runtime pipeline (cache-first, 350ms debounce, conversational context, staleness guard) if you want to see how the calls are wired.

I'd love to keep collaborating — on latency, cost, safety, and whether newer models could make the child's experience even better. And thank you again for backing this early.

Best,
Mark

Mark Lucovsky
blasterai.app · mark@lucovsky.com · github.com/marklucovsky/claudeBlast

---

*Attach: `blaster-deck.pdf`, `blaster-one-pager.pdf`, video 1 (tile→sentence) + video 2 (escalation). Point them to Appendix B for the runtime architecture.*
