<!-- SPDX-License-Identifier: Apache-2.0 -->
# CloudKit multi-device duplication — root cause & fix design

**Status:** implemented (builds clean), **pending the on-device two-device test**. Surfaced
2026-07-15 by the two-device iCloud sniff test (both devices crashed leaving onboarding).
Blocks enabling iCloud by default and blocks the Production schema promotion until the
device test passes. See [architecture-backlog.md](architecture-backlog.md) §1.

## Root cause

`BootstrapLoader.needsBootstrap()` gates seeding on a **local `UserDefaults` flag**
(`bootstrapInstalled`) — per-device, never synced. So every fresh device seeds its own
full copy of the ~492-tile vocabulary + Core-First scene + All-Tiles scene + (via
`ProfileMigration`) the Sandbox/Legacy profiles. When two such devices enable iCloud,
SwiftData assigns each record its **own** persistent identifier, so same-logical-key
records from different devices become **distinct CloudKit records** — genuine duplicates
of *everything*. In-load dedup (`BootstrapLoader.swift:152`) only dedups within one JSON
file; it does nothing across devices. No `@Attribute(.unique)` is possible (CloudKit-incompat).

## Symptoms

- **Crash (fixed):** `Dictionary(uniqueKeysWithValues:)` traps on the duplicate key
  (`actions`). 25 sites crash-proofed to `uniquingKeysWith` (keeps first). Un-bricks the app.
- **Silent corruption (the real damage), from the audit:**
  - **Critical (wrong active record):** `activeScenes.first` (`TileGridView:65`,
    `TileScriptView:37`, `TileScriptValidator:33`), `sandboxes.first`
    (`ChildProfileResolver:77`), default-scene reactivation (`Scene.swift:121`,
    `AdminView+ScenesTab:176/189`), active-patient pick (`TransitionSheets:132`),
    onboarding "first real profile" (`OnboardingCommit:82`), `active.count == 1`
    tiebreak (`ChildProfile:180`). With duplicates these pick an arbitrary copy and
    **leave the others active/undeduped** → the board or child can flip on sync.
  - **Medium:** `TileArtVariant` upsert updates only the first (`:46`); `ProfileMigration`
    "ensure one Sandbox" only creates-if-zero, never dedups (`:83`); scene-name collision
    `Set` hides dupes (`Scene:146`); `Scene.activate` deactivate-all races late sync
    (`Scene:108`); doubled counts in logs/most-used.
  - Confirmed safe: **DeviceProfile** (`cloudKitDatabase: .none`, local-only) never dupes.
    Inline `PageSpec` on a scene dupes *with* its scene, not independently.

## Fix design — three layers

### Layer A — Self-healing dedup reconciliation (the core fix)
A `CloudKitDedupReconciler` that collapses duplicates to one **deterministic** winner so
all devices converge. Runs **on launch** (after the container loads) and **on CloudKit
remote-change events** (observe `NSPersistentCloudKitContainer.eventChangedNotification` /
remote-change notifications), plus on `scenePhase` → active as a cheap safety net.

Per-model logical key + winner:
- `TileModel` → key = `key` (scope: `isSystem == true`; never touch caregiver-added tiles).
- `BlasterScene` → key = `systemSceneKey` (non-empty). **Give All-Tiles a stable
  `systemSceneKey` too** so it dedups. Never dedup user scenes by name (same name is legal).
- `ChildProfile` → the **Sandbox** (`isSystem == true`) collapses to one. Real profiles are
  NOT auto-deleted (user-created); instead enforce the single-active invariant (Layer B).
- `TileArtVariant` → key = `(tileKey, imageSet)`, keep newest `created`.
- `SentenceCache` → key = `(cacheKey, childID)`, keep highest `hitCount` / newest.

**Deterministic winner:** lowest stable id (the record's own UUID field where present,
else `persistentModelID` description). Same input set on every device → same winner.

**Reference safety:** tiles/pages/scenes reference each other by **key string**, so
deleting a duplicate `TileModel` or system `BlasterScene` leaves references intact (they
resolve to the survivor). Deletes are per-object here (they SHOULD propagate — we want the
duplicate gone on all devices), which is the opposite of factory-reset's local-only wipe.
For records referenced by id (e.g. `childID`), only collapse the Sandbox (whose refs are
regenerable) — never orphan a real child's data.

### Layer B — Single-active invariants
After collapsing, enforce exactly one: active `BlasterScene`, active `ChildProfile`, and one
Sandbox. Deactivate/merge extras deterministically. Fold this into the reconciler so the
`*.first { $0.isActive }` readers are always correct. (Also makes the audit's critical
readers safe without touching each call site, though a deterministic sort there is cheap
defense-in-depth.)

### Layer C — Seed guard (reduce churn)
`needsBootstrap()` should also return false when the **synced store is already populated**
(e.g. any `isSystem` `TileModel` exists) even if the local flag is unset — so a second
device that has already received sync doesn't re-seed. This does NOT fully prevent dupes
(a device can seed before its initial import arrives); **Layer A is the guarantee**, Layer C
just minimizes the transient duplicate set. Optionally gate seeding until the initial
CloudKit import completes when iCloud is on.

## Testing plan
Two real devices, same Apple ID, **reset the CloudKit Development environment between runs**:
1. Fresh + fresh, both enable iCloud → expect one copy of everything, one active scene, one Sandbox.
2. Fresh device joining an existing iCloud dataset → no second seed, no dupes.
3. Edit on A → appears on B (the original sniff test), now without duplication.
4. Kill/relaunch mid-sync → reconciler converges.

## Rollout constraints
- Must be solid **before** iCloud is enabled by default and **before** promoting the schema
  to CloudKit **Production** (additive-only, permanent — see architecture-backlog §1).
- Reconciler deletes are per-object (propagate); keep them strictly scoped to system/dupe
  records so they never touch a real child's caregiver-authored data.

## Implemented (this worktree — builds clean, pending on-device test)
- **Crash-proofing:** 25 `Dictionary(uniqueKeysWithValues:)` → `uniquingKeysWith`.
- **Container pin:** explicit `iCloud.app.blasterai` (`AppSettings.swift`).
- **`Services/CloudKitDedupReconciler.swift`** (Layers A+B): collapses duplicate `TileModel`
  (by key; prefers a caregiver-customized copy), system `BlasterScene` (by `systemSceneKey`;
  prefers active/most-recently-modified), Sandbox `ChildProfile` **and the migration-seeded
  Legacy profile** — both re-seeded per device; Legacy is matched by its name + seed-notes
  signature so a user-renamed profile is never touched — repointing orphaned `childID` refs to
  the survivor, `TileArtVariant` (by tileKey+set; newest), `SentenceCache` (by
  cacheKey+childID; most-used). Enforces single-active scene + profile (reuses
  `ChildProfile.resolveActive`). Deterministic winner (semantic preference, then lowest synced
  `id`) → every device converges on the same winner/losers; deletes propagate to CloudKit.
- **`Services/CloudKitSyncCoordinator.swift`**: re-runs the reconciler (debounced 1s) on
  `.NSPersistentStoreRemoteChange` and on `scenePhase` → active (belt-and-suspenders, since
  SwiftData remote-change notifications can be flaky); refreshes `ChildProfileResolver` when a
  pass changed active state.
- **Seed guard (Layer C):** `BootstrapLoader.storeAlreadySeeded` + `claudeBlastApp` adopts an
  already-synced dataset instead of re-seeding a duplicate full copy.
- **All-Tiles `systemSceneKey = "all_tiles"`** so it dedups.
- Reconcile runs at launch (`claudeBlastApp.init`) and on every sync/foreground.
- **Observability — `Views/Admin/AboutStatsView.swift`** (Admin → Device → *About & Stats*):
  `@Query`-backed live vocabulary/board/activity counts plus a **Sync health** panel showing
  the current **duplicate-record count** (spikes on a bad multi-device sync, driven to 0 by the
  reconciler — watchable live) and reconciler telemetry (lifetime duplicates cleaned, last-checked
  time; local UserDefaults, no synced model). Includes a manual **Check & clean now** button.
  This is the instrument for the two-device test.

## Remaining
- **Two-device on-device test** (plan above): reset the CloudKit Development environment first,
  run fresh+fresh and fresh+existing, confirm one copy of everything + one active scene/profile.
- **Real (non-system) profile duplicates** are NOT auto-deleted — only single-active is enforced
  (two devices onboarding the same child leave two profiles). Decide later whether to merge.
- Unit tests for the reconciler comparators + `collapse` (winner determinism, childID repointing).
- Enable iCloud-default ON and promote the schema to **Production** only *after* the device test.
