<!-- SPDX-License-Identifier: Apache-2.0 -->
# Architecture backlog

Cross-cutting design work to schedule. Each is a stub to expand into its own note
+ worktree when picked up. See also [scene-identity.md](scene-identity.md).

---

## 1. CloudKit: dev sandbox → production schema  ⚠️ highest risk

**Why it's scary:** CloudKit has separate **Development** and **Production**
environments. We build against Development, where the schema is auto-created from
the SwiftData model. Shipping requires **promoting the schema to Production** in
the CloudKit Dashboard — and once in Production, schema changes are
**additive-only, effectively forever**:

- ❌ cannot delete or rename record types or fields
- ❌ cannot change a field's type
- ❌ cannot add uniqueness (we already avoid `@Attribute(.unique)` — CloudKit-incompat)
- ✅ can add new record types, new fields, new indexes

**Implications / to-do before first Production deploy:**
- **Freeze the model as much as possible first.** Every current model
  (`ChildProfile`, `BlasterScene`, `SentenceCache`, `LoggedUtterance`,
  `MetricEvent`, `RecordedScript`, …) should be reviewed as if its field names and
  types are permanent. Land the [scene-identity](scene-identity.md) `id`/`version`
  fields *before* Production, not after.
- **All properties optional or defaulted; relationships have inverses.** Verify the
  whole model still satisfies SwiftData+CloudKit constraints.
- **Indexes/queryable fields** must be enabled per-field in the Dashboard for any
  field we query in Production — they don't come for free from Development.
- **Test against Production with a real iCloud account** before launch; the sandbox
  masks issues (esp. around first-sync, account state, and quota).
- **Migration story is code-side + additive.** New app versions must keep reading
  old records. No destructive migrations.
- **Reset semantics stay as designed:** reset = local wipe, **preserve** cloud
  (never per-object delete in reset); per-word delete is the explicit cloud-delete
  path; DEBUG defaults iCloud OFF. (Already the intended behavior — re-verify.)
- **Schema-split container** (DeviceProfile in a `cloudKitDatabase: .none`
  "DeviceLocal" config; everything else flips local↔CloudKit per `icloud_enabled`)
  must be exercised in both states against Production.

**Deliverable when picked up:** a pre-flight checklist + a Production dry-run on a
throwaway iCloud account, gating the App Store submission.

---

## 2. Sentence-cache lifetime & invalidation

Today `SentenceCache` is keyed by the order-independent sorted tile combo, with a
`hitCount`, and no expiry. Open questions:

- **TTL / staleness:** should entries expire? A cached sentence can go stale when
  the prompt, model, child age, or a tile's `displayName` changes.
- **Invalidation triggers:** bump/clear the cache on prompt-template change, model
  change, or per-child profile edits (age → grammar level).
- **Bounds:** size cap + eviction policy (LRU by `hitCount`/recency) so it can't
  grow unbounded, especially once it syncs via CloudKit.
- **Scope:** already `+childID`-keyed; confirm that's the right granularity.
- **Interaction with escalation:** repetition escalation must not be short-circuited
  by a cache hit (verify the cache key / escalation path don't collide).

---

## 3. Sentence generation — refinement & flagging

Give caregivers a feedback loop on generated sentences (they're the audience for the
text):

- **Flag** a sentence as wrong / awkward / inappropriate, inline from the tray.
- **Refine:** regenerate with a nudge, or hand-edit and pin an override for that
  tile combo (writes to cache as a caregiver-authored result).
- **Close the loop with the eval harness:** flagged cases become fixtures /
  regression cases; recurring flags inform prompt tuning. (Ties into the existing
  Tier-1/Tier-2 eval harness.)
- **Safety:** flagging is also the report path for anything that trips the content
  rails in practice.

---

*Add new cross-cutting items here as stubs; promote to a dedicated note + worktree
when scheduled.*
