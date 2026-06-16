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
    /// Distinct caregiver-created tiles referenced by `scene` that still have no
    /// image. These are the words an AI accept/refine just introduced. Order
    /// follows first appearance across the scene's pages.
    static func tilesNeedingArt(in scene: BlasterScene, tileLookup: [String: TileModel]) -> [TileModel] {
        var seen = Set<String>()
        var result: [TileModel] = []
        for page in scene.pages {
            for entry in page.tiles where seen.insert(entry.key).inserted {
                if let tile = tileLookup[entry.key], !tile.isSystem, tile.userImageData == nil {
                    result.append(tile)
                }
            }
        }
        return result
    }
}
