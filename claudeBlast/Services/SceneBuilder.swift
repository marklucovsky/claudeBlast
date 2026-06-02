// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneBuilder.swift
//  claudeBlast
//
//  Materializes a GeneratedScene (AI output) into BlasterScene + inline
//  [PageSpec]. Inserts the scene in a single transaction.
//

import SwiftData

enum SceneBuilder {
    /// Build a BlasterScene from AI output, insert it into `context`, and return it.
    /// - Parameters:
    ///   - generated: The AI-generated scene structure.
    ///   - tileLookup: Dictionary mapping tile key → TileModel. Used only to
    ///     validate that every generated key exists in vocabulary; the resulting
    ///     PageSpec.tiles store keys directly (no PageTileModel/TileModel refs).
    ///   - context: The ModelContext to insert into.
    @discardableResult
    static func build(
        from generated: GeneratedScene,
        tileLookup: [String: TileModel],
        context: ModelContext
    ) throws -> BlasterScene {
        let scene = BlasterScene(
            name: generated.name,
            descriptionText: generated.description,
            homePageKey: generated.homePageKey,
            isDefault: false,
            isActive: false
        )

        let pages: [PageSpec] = generated.pages.map { genPage in
            let tiles = genPage.tiles.compactMap { genTile -> TileEntry? in
                guard tileLookup[genTile.key] != nil else { return nil }
                return TileEntry(key: genTile.key, link: genTile.link, isAudible: genTile.isAudible)
            }
            return PageSpec(key: genPage.key, tiles: tiles)
        }
        scene.pages = pages

        try context.transaction {
            context.insert(scene)
        }

        return scene
    }
}
