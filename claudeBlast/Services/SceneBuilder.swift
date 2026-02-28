// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneBuilder.swift
//  claudeBlast
//
//  Materializes a GeneratedScene (AI output) into the SwiftData model graph.
//  All objects are inserted in a single transaction.
//

import SwiftData

enum SceneBuilder {
    /// Build a BlasterScene from AI output, insert it into `context`, and return it.
    /// - Parameters:
    ///   - generated: The AI-generated scene structure.
    ///   - tileLookup: Dictionary mapping tile key → TileModel (already inserted).
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

        var allPageTiles: [PageTileModel] = []
        var pages: [PageModel] = []

        for genPage in generated.pages {
            var pageTiles: [PageTileModel] = []
            for genTile in genPage.tiles {
                guard let tile = tileLookup[genTile.key] else { continue }
                let pt = PageTileModel(tile: tile, link: genTile.link, isAudible: genTile.isAudible)
                pageTiles.append(pt)
            }
            let page = PageModel.make(
                displayName: genPage.key,
                tiles: pageTiles,
                tileOrder: pageTiles.map(\.id)
            )
            pages.append(page)
            allPageTiles.append(contentsOf: pageTiles)
        }

        scene.pages = pages

        try context.transaction {
            for pt in allPageTiles { context.insert(pt) }
            for page in pages { context.insert(page) }
            context.insert(scene)
        }

        return scene
    }
}
