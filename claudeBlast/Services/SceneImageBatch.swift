// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImageBatch.swift
//  claudeBlast
//
//  Helpers for batch-generating tile art for the caregiver-created words a
//  scene introduces. AI scene generation/refinement proposes new words that
//  start with no image (a letter-on-color placeholder); this finds those words
//  so the editor can offer to illustrate them in one pass. The generation loop
//  itself lives in SceneImageBatchSheet (it owns the progress + cancel state).
//

import Foundation

enum SceneImageBatch {
    /// Distinct tiles referenced by `scene` that have NO real art — nothing
    /// resolves for them (no user photo, no set art, no master-set backfill), so
    /// they'd render the letter placeholder. These are the words to illustrate.
    ///
    /// Asking the resolver (not just `userImageData == nil`) is what makes the
    /// count correct for pack words: a pack word carries no userImageData but has
    /// bundled p3d_/cls_ art, so it resolves and is correctly excluded.
    @MainActor
    static func tilesNeedingArt(in scene: BlasterScene, tileLookup: [String: TileModel],
                                resolver: TileImageResolver) -> [TileModel] {
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                guard let tile = tileLookup[entry.key] else { continue }
                if resolver.image(for: tile.bundleImage) == nil {
                    result.append(tile)
                }
            }
        }
        return result
    }
}
