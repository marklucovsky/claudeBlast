<!-- SPDX-License-Identifier: Apache-2.0 -->
# Sentence cache — key + eviction policy (A3, 2026-07-21)

Design note for the `SentenceCache` correctness work. Companion to the ToS memo
(`docs/openai-tos-memo-2026-07-21.md`). Implementation: `CacheKeyPolicy`,
`SentenceCacheManager`, `SentenceCache`.

## Why

The cache previously keyed purely on the sorted tile combination. That is wrong along three axes,
all of which matter now that the cache is CloudKit-synced across a family's devices:

1. **Model/prompt changes served stale sentences forever.** Nothing in the key or storage
   reflected *which model* or *which prompt version* produced an entry, so a fix like the escalation
   rewrite would keep re-serving pre-fix sentences with no way to invalidate short of "clear all".
2. **Grade collisions.** The system prompt embeds the child's grade (`{grade}`), so grade changes
   the sentence — but the key ignored it. Two children of different grades sharing an iCloud could
   be served each other's grade-mismatched sentence.
3. **Unbounded growth** in CloudKit.

## Key format

`CacheKeyPolicy.key(tileKeys:grade:)` →

```
<modelID>/v<promptVersion>/g<grade>#<sorted,comma,tile,keys>
```

e.g. `gpt-4o-mini/v1/g2#eat,pizza`. Tiles are deduplicated + sorted, so selection order never
matters. The `<modelID>/v<promptVersion>` prefix is the **`versionToken`**, stamped onto each entry
(`SentenceCache.keyVersion`). Grade is *inside the key* but *excluded from the version token* — it
is a legitimate parallel entry (multiple grades coexist), not a staleness signal.

`CacheKeyPolicy.modelID` is also the single source of truth for the request model in
`OpenAISentenceProvider`, so the model that generated an entry and the model recorded in its key can
never silently diverge.

## Versioning procedure

To invalidate every cached sentence after a cache-affecting prompt/rubric change (or a model swap):

1. Bump `CacheKeyPolicy.promptVersion` (or change `modelID`).
2. That changes `versionToken`, so:
   - **new** lookups miss the old entries (different key) and regenerate;
   - **old** entries now have a mismatched `keyVersion` and are swept — automatically at next launch
     (`evictStale`) and on demand from Admin (`pruneStaleVersions`), without waiting for the TTL.

Only bump the version for changes that should invalidate cached *content*. Escalation-prompt changes
do **not** need a bump: escalated variants are never cached (both lookup and store are guarded by
`repetition == 0` in `SentenceEngine`), so only the base, non-escalated sentence is ever stored.

## Eviction policy

`SentenceCacheManager.evictStale(now:maxAge:maxCount:)` runs once per launch (in `App.init`, after
CloudKit dedup) and:

1. deletes any **unpinned** entry that is **version-stale** (`keyVersion != versionToken`) or
   **expired** (`now − lastUsed > maxAge`);
2. if unpinned survivors still exceed `maxCount`, **LRU-evicts** the overflow (oldest `lastUsed`
   first, tie-break lowest `hitCount`).

Defaults (`CacheKeyPolicy`): **`maxAge` = 180 days**, **`maxCount` = 2000**. Pinned entries are
always exempt and are never counted against the cap.

`pruneStaleVersions()` is the TTL-independent, on-demand version-only sweep, surfaced in Admin →
Logs as **"Clear Stale (N)"**, which appears only when version-stale entries exist. The existing
**"Flush All"** (`flushAll()`) is retained.

## Notes / deferred

- `SentenceCache.audioData` (only ever written `""`, never read anywhere) is a **dead field** and
  the one true removal candidate. `created`, by contrast, is **not** vestigial — it is read by
  `CloudKitDedupReconciler.dedupeSentenceCache` as the tie-breaker when two synced duplicates share
  a `hitCount` (keep the newer). Removing a field must happen **before** CloudKit Production
  promotion (after promotion the schema is additive-only, one-way). Since the container is still in
  the **Development** environment, that is the correct window — see the pre-promotion
  schema-hardening pass (backlog item B): audit every model with whole-codebase usage checks, drop
  the genuinely dead props, reset the CloudKit **Development** environment once, then promote a clean
  schema. Field removal itself is a lightweight SwiftData migration (no `SchemaMigrationPlan` exists;
  removals drop the column automatically).
- Legacy entries written before `keyVersion` existed default to `""`, which never equals the current
  `versionToken` → they are treated as stale and swept on the first sweep. Correct: they predate the
  versioning scheme and their provenance is unknown.
