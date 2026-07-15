<!-- SPDX-License-Identifier: Apache-2.0 -->
# Scene & pack identity (design note)

**Status:** proposed — not yet implemented. Owner: Mark. Raised 2026-07-14.
**Do not block the demo on this.** Bare scene names work for local boards and the
current recordings; this is groundwork for the *shared/published* scene + pack
ecosystem.

## Problem

Scenes are identified by a bare `name` string (`"Vocab"`, `"Tide Pools"`), which
doubles as the lookup key. That is fine for a private board on one device, but it
breaks the moment scenes are **shared or versioned**:

- **Collisions.** Two "Vocab" scenes cannot be told apart. Import can only guess —
  overwrite? duplicate? — and TileScript's `scene: "Vocab"` is equally ambiguous.
- **No provenance / version.** No way to say "which Vocab", "who published it", or
  "is this newer than the copy I have".
- **Packs already solved this — inconsistently.** Packs carry qualified ids
  (`vocab.blaster.app/tidepools`) + `slug` + `version`. Scenes never adopted the
  pattern, and the pack domain is `vocab.blaster.app` — **not** `blasterai.app`,
  which we own. Fix the inconsistency now, while the catalog is tiny.

Not broken (leave alone): **word keys** (`rocket`, `trex`) are the global *asset*
namespace and map to art — keep flat. **Page keys** (`space`, `home`) are
scene-*local* children — no global qualification needed.

## Proposal

Give every **shareable** top-level object (scene, pack) a structured identity;
keep local/user objects lightweight until they are published.

```json
{
  "@type": "application/vnd.claudeblast.scene+json",
  "id": "scenes.blasterai.app/vocab",   // authority-qualified, stable
  "slug": "vocab",                        // short, UI + TileScript
  "version": "1.0.0",
  "displayName": "Vocab",
  "homePageKey": "home",
  "pages": [ ... ]
}
```

- **Authority = a domain the publisher controls.** First-party
  `scenes.blasterai.app/*`; third-party `scenes.someclinic.org/feelings-v2`. This
  is exactly what makes an open ecosystem work later.
- **Local/user scenes** get no authority (`id: "local/<uuid>"` or just a name) and
  are clearly *not shareable until published*. A domain id is minted only on
  export/publish.
- **TileScript resolver:** match by `id` → fall back to `slug` → fall back to
  `displayName` (back-compat). `scene: vocab` keeps working, unambiguously.
- **Import/upgrade** dedupes by `id` + `version` instead of clobbering by name.

## Share transport ≠ identity

`blasterai://scenes.blasterai.app/vocab` conflates two layers. Keep them separate:

- **Identity** = the stored URN-ish string above (no scheme).
- **Share link** = a **Universal Link** `https://blasterai.app/s/<id>`, preferred
  over a custom `blasterai://` scheme (custom schemes get hijacked, don't preview,
  fail in mail/messages; universal links degrade to a web page). We already host
  `blasterai.app` on Cloudflare Pages — serve `/.well-known/apple-app-site-association`
  there so the site and the app-sharing story reinforce each other.

## Domain standardization

Migrate `vocab.blaster.app/*` → `blasterai.app`:
- packs: `packs.blasterai.app/<slug>`
- scenes: `scenes.blasterai.app/<slug>`

Bundled-resource find/replace + version bump. Low risk today (6 packs, ~1 scene).

## Implementation surface (scope)

- **Model:** `BlasterScene` gains `id`/`slug`/`version` (nullable for local).
- **Bootstrap + import/export:** mint/read ids; dedupe by id+version.
- **TileScript resolver:** id → slug → displayName.
- **Packs:** id migration + domain fix.
- **Universal links:** AASA on blasterai.app + app association.

### Related implementation finding (starter-scene bundling)
`SceneImporter.importJSON` **drops any tile whose key is not already a TileModel**
(`SceneImporter.swift:157`) — it only creates tiles listed in the bundle's
top-level `tiles[]`. A raw in-app `.blasterscene` export omits `tiles[]`, so
bundling it as a starter would import **empty pages**. A shippable
`starter_<name>.json` must carry a full word manifest (every page's keys, with
`displayName`/`wordClass`) plus resolved page-link icons. For multi-pack scenes
(e.g. Vocab = space+vehicles+tidepools+dinosaurs+farm) the hub `page_*` link tiles
need cover art — today `packcover_<slug>` assets do **not** exist, so those either
need generating or the link tiles should alias a representative pack word's art.

## Sequencing

Do this in its own worktree (`cb-scene-identity`), separate from the demo work.
Fold the `blaster.app → blasterai.app` domain fix into the same change.
