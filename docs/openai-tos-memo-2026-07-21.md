<!-- SPDX-License-Identifier: Apache-2.0 -->
# OpenAI ToS compliance memo — sentence caching + iCloud sync (A3, 2026-07-21)

**Question.** BlasterAI caches OpenAI-generated sentences locally and syncs them across a family's
devices through the family's **own** iCloud (CloudKit private database). Is storing and syncing
generated outputs this way within OpenAI's terms, and is it consistent with our public
"no external backend / stateless API" claim? Companion to the A2 claims audit
(`docs/claims-audit-2026-07-20.md`) and the cache design note (`docs/cache-policy.md`).

**Short answer.** Yes. The customer owns the outputs, API data is not trained on by default, the
cache lives entirely within the customer's own trust boundary (their key, their iCloud), and no
BlasterAI-operated backend is involved. Two low-priority hardening items noted below.

## Architecture facts that frame the analysis
- **Bring-your-own-key (BYOK).** The family or therapist supplies their **own** OpenAI API key
  (stored in the iOS Keychain). In OpenAI's terms, *they* are the "Customer" — outputs are generated
  under their account, not ours.
- **Endpoint.** The sentence provider calls **Chat Completions** (`/v1/chat/completions`) — a
  `messages` array in, `choices` out (`OpenAISentenceProvider.swift`). Not the Responses API,
  Assistants, or Conversations.
- **Storage boundary.** Cached outputs live in SwiftData on-device, syncing only through the
  family's **private** CloudKit database. There is no BlasterAI-operated server in the path. The
  cache never crosses out of the customer's own iCloud/account boundary; it does not span unrelated
  families.

## Findings

### 1. Output ownership — storing/syncing is the customer's right
OpenAI's terms: *"as between Customer and OpenAI … Customer retains all ownership rights in Input
and owns all Output,"* and OpenAI *"assigns … all right, title, and interest in Output"* to the
Customer. Storing those outputs and replicating them across the Customer's own devices is ordinary
use of content the Customer owns. **No conflict.** [1][2]

Nuance OpenAI flags: *"output may not be unique and other users may receive similar output,"* and the
ownership assignment doesn't extend to other users' output. This is a **non-issue** for our cache —
we only ever store and re-serve **this** customer's own outputs to **this** customer's own devices;
we never redistribute one customer's output to another.

### 2. Cross-device / cross-child serving within a family is not redistribution
A cached sentence generated in one child's session may be served on a sibling's device or for a
different child **within the same family iCloud**. All of that is under the **same** OpenAI account
(same BYOK key = same Customer) and the same private CloudKit database — i.e. use by the Customer of
the Customer's own owned output, on the Customer's own storage. It is **not** distribution to a third
party. (The per-family private-database scoping is what keeps this true; the cache does not leak
across families.)

### 3. Training / data-use posture — opted out by default
*"As of March 1, 2023, data sent to the OpenAI API is not used to train or improve OpenAI models
(unless you explicitly opt in),"* and organizations are opted out of data-sharing by default. We do
not opt in. **Nothing to change.** [3]

### 4. OpenAI-side retention is transient and separate from our cache
By default OpenAI generates **abuse-monitoring logs** retained **up to 30 days** (may contain
prompts/responses), unless longer retention is legally required; after that they're removed. This is
OpenAI-side, transient, and **orthogonal** to our caching — it is not "our backend" and does not
change the analysis. Zero-Data-Retention (which excludes content from abuse logs) requires OpenAI
pre-approval and is not available to unapproved BYOK consumers, so it is not an option we can rely
on. [3]

### 5. Consistency with the public "no external backend / stateless API" claim
The claim holds precisely:
- **"No external backend"** — true. Caching is local + the family's **own** iCloud; there is no
  BlasterAI-operated server. iCloud is Apple infrastructure the family already owns, not a
  BlasterAI backend.
- **"Stateless API calls"** — true at the level we mean it: each OpenAI request carries only tiles +
  short rolling context and no BlasterAI-side identity or persistence. The **cache** is our own
  local/iCloud state, not OpenAI-side state and not our backend. A2 wording already reflects this
  ("no identity, no history stored by us"). Recommend keeping A2/A3 phrasing aligned: *state lives
  on the family's device/iCloud, never on a BlasterAI server.*

## Recommendations
- **No blocking changes.** Current behavior is compliant.
- **(Low) Explicit `store: false` if/when we adopt the Responses API.** On Chat Completions (what we
  use today) `store` defaults to **false**, so no stored-completions are created. The Responses API
  defaults `store` to **true** (persists ≥30 days for the stored-completions feature). If we ever
  migrate endpoints, set `store: false` explicitly to avoid unintended OpenAI-side persistence. [4]
- **(Low) One-line privacy-copy note.** Optionally state in the privacy page that generated sentences
  are cached on-device and synced via the family's own iCloud — it's already implied by "on-device
  data," but making the cache explicit pre-empts any "where do outputs live?" question from a
  technical reviewer. Mirror the A2 phrasing.

## Sources
- [1] [OpenAI Terms of Use](https://openai.com/policies/row-terms-of-use/)
- [2] [OpenAI Services Agreement](https://openai.com/policies/services-agreement/)
- [3] [Data controls in the OpenAI platform](https://developers.openai.com/api/docs/guides/your-data)
- [4] [API data usage policies](https://platform.openai.com/docs/data-usage-policies) / Responses API `store` default (Data controls guide)

*Not legal advice — an engineering compliance read for internal use, current as of 2026-07-21.*
