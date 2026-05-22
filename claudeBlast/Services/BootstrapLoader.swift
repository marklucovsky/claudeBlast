// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BootstrapLoader.swift
//  claudeBlast
//

import SwiftData
import Foundation

enum BootstrapLoader {
    struct LoadResult {
        let tiles: [TileModel]
        let pages: [PageModel]
        let scene: BlasterScene
        let duration: TimeInterval
    }

    static func needsBootstrap() -> Bool {
        UserDefaults.standard.integer(forKey: AppSettingsKey.bootstrapVersion) < currentBootstrapVersion
    }

    static func markBootstrapComplete() {
        UserDefaults.standard.set(currentBootstrapVersion, forKey: AppSettingsKey.bootstrapVersion)
    }

    /// Wipe all app-owned SwiftData records. Relationship-safe order matches
    /// performFactoryReset in AdminView. Safe to call on a fresh store (no-op).
    static func wipeAllData(context: ModelContext) {
        do {
            try context.delete(model: MetricEvent.self)
            try context.delete(model: SentenceCache.self)
            try context.delete(model: BlasterScene.self)
            try context.delete(model: PageModel.self) // cascades PageTileModel
            try context.delete(model: TileModel.self)
            try context.save()
        } catch {
            print("BootstrapLoader.wipeAllData failed: \(error)")
        }
    }

    static func loadDefaultVocabulary(context: ModelContext) -> LoadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let emptyScene = BlasterScene(name: "Empty", isDefault: true, isActive: true)

        guard let vocabularyUrl = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            print("Failed to locate vocabulary.json in bundle.")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }

        do {
            // ----- vocabulary -----
            let tilesData = try Data(contentsOf: vocabularyUrl)
            let codableTiles = try JSONDecoder().decode([TileModelCodable].self, from: tilesData)
            // Deduplicate by key at load time (CloudKit does not support @Attribute(.unique))
            var seenTileKeys = Set<String>()
            let allTiles: [TileModel] = codableTiles.compactMap { codable in
                guard seenTileKeys.insert(codable.key).inserted else { return nil }
                return TileModel(from: codable)
            }
            let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

            // ----- Core-First scene from Resources/scenes/core_first.json -----
            // The hardcoded Swift scene specs (coreFirstHomeSpecs / foodDrinksSpecs)
            // are gone — the scene now lives in JSON, with DSL commands
            // (selectAll / selectKeys / makeLink / deleteTile) expanded by
            // SceneMaterializer against the vocabulary. The materialized
            // PageSpec list is then converted to PageModel/PageTileModel
            // instances for SwiftData storage; that conversion is a
            // transition step — Step K replaces the PageModel storage with
            // inline [PageSpec] on BlasterScene.
            // The Xcode synchronized group flattens Resources/scenes/*.json into
            // the bundle root, so no subdirectory: parameter. (We'll revisit
            // naming when more than one bundled scene file ships.)
            guard let coreSceneUrl = Bundle.main.url(
                forResource: "core_first", withExtension: "json"
            ) else {
                print("Failed to locate core_first.json in bundle.")
                return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
            }
            let coreSceneData = try Data(contentsOf: coreSceneUrl)
            let coreSceneJSON = try JSONDecoder().decode(SceneJSON.self, from: coreSceneData)
            let materialized = try SceneMaterializer.materialize(
                scene: coreSceneJSON, vocabulary: codableTiles
            )
            let (coreFirstScene, corePages, corePageTiles) = buildScene(
                from: materialized, tileLookup: tileLookup
            )

            // ----- All Tiles scene (programmatic) -----
            // Single page with every vocab tile, grouped by wordClass in vocab
            // declaration order. Useful for review/admin; not a child-facing
            // scene. Programmatic rather than JSON because the content is just
            // "all of vocabulary" — no curation needed.
            var wcOrder: [String] = []
            var wcGroups: [String: [TileModel]] = [:]
            for tile in allTiles {
                if wcGroups[tile.wordClass] == nil {
                    wcOrder.append(tile.wordClass)
                    wcGroups[tile.wordClass] = []
                }
                wcGroups[tile.wordClass]!.append(tile)
            }
            let allTilesPageTiles: [PageTileModel] = wcOrder.flatMap { wc in
                (wcGroups[wc] ?? []).map { PageTileModel(tile: $0, link: "", isAudible: true) }
            }
            let allTilesPage = PageModel.make(
                displayName: "all_tiles",
                tiles: allTilesPageTiles,
                tileOrder: allTilesPageTiles.map(\.id)
            )
            let allTilesScene = BlasterScene(
                name: "All Tiles",
                descriptionText: "Full vocabulary grouped by word class",
                homePageKey: "all_tiles",
                isDefault: false,
                isActive: false
            )
            allTilesScene.pages = [allTilesPage]

            // makePT is no longer used here — kept as a typealias-less shim
            // so any future programmatic scene-builders inside this function
            // have the same pattern available without re-deriving it.
            func makePT(_ key: String, link: String = "", audible: Bool = true) -> PageTileModel? {
                guard let tile = tileLookup[key] else { return nil }
                return PageTileModel(tile: tile, link: link, isAudible: audible)
            }
            _ = makePT  // silence unused-symbol warning until a programmatic scene needs it

            // ----- persist -----
            try context.transaction {
                for tile in allTiles { context.insert(tile) }
                for pt in corePageTiles { context.insert(pt) }
                for page in corePages { context.insert(page) }
                context.insert(coreFirstScene)
                for pt in allTilesPageTiles { context.insert(pt) }
                context.insert(allTilesPage)
                context.insert(allTilesScene)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(
                tiles: allTiles,
                pages: corePages,
                scene: coreFirstScene,
                duration: elapsed
            )

        } catch {
            print("Failed to load or decode bootstrap data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }

    // MARK: - Materialized scene → SwiftData

    /// Convert a SceneMaterializer.MaterializedScene into a BlasterScene + its
    /// underlying PageModel/PageTileModel children. Symbolic "<home>" links
    /// rewrite to the scene's actual homePageKey at this point — Step J will
    /// move that resolution to navigation time.
    private static func buildScene(
        from materialized: SceneMaterializer.MaterializedScene,
        tileLookup: [String: TileModel]
    ) -> (BlasterScene, [PageModel], [PageTileModel]) {
        var allPageTiles: [PageTileModel] = []
        let pageModels: [PageModel] = materialized.pages.map { spec in
            var pageTiles: [PageTileModel] = []
            for entry in spec.tiles {
                guard let tile = tileLookup[entry.key] else {
                    print("Warning: tile not found for key '\(entry.key)' on page '\(spec.key)'")
                    continue
                }
                let resolvedLink = entry.link == "<home>" ? materialized.homePageKey : entry.link
                let pt = PageTileModel(tile: tile, link: resolvedLink, isAudible: entry.isAudible)
                pageTiles.append(pt)
                allPageTiles.append(pt)
            }
            return PageModel.make(
                displayName: spec.key,
                tiles: pageTiles,
                tileOrder: pageTiles.map(\.id)
            )
        }
        let scene = BlasterScene(
            name: materialized.name,
            descriptionText: materialized.description,
            homePageKey: materialized.homePageKey,
            isDefault: materialized.isDefault,
            isActive: materialized.isDefault
        )
        scene.pages = pageModels
        return (scene, pageModels, allPageTiles)
    }
}
