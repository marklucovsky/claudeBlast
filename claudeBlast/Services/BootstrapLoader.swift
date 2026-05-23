// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BootstrapLoader.swift
//  claudeBlast
//

import SwiftData
import Foundation
import CryptoKit

enum BootstrapLoader {
    struct LoadResult {
        let tiles: [TileModel]
        let pages: [PageSpec]
        let scene: BlasterScene
        let duration: TimeInterval
    }

    /// Bundled-content fingerprint: SHA256 of vocabulary.json + every
    /// scenes/*.json in the bundle. Recomputed on each call; cheap (few hundred
    /// KB of input). Used to detect content drift in DEBUG builds.
    static var bundledContentHash: String {
        var hasher = SHA256()
        let names: [(String, String)] = [
            ("vocabulary", "json"),
            ("core_first", "json"),
        ]
        for (name, ext) in names {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Decide whether bootstrap should run. Two modes:
    ///
    /// - **RELEASE**: bootstrap fires only on first install. The
    ///   bootstrapInstalled flag is set once and never re-checked. App updates
    ///   that change bundled JSON files do NOT auto-replace the user's
    ///   scene/vocab. This protects children in the wild — they keep their
    ///   muscle-memory layout across app updates.
    ///
    /// - **DEBUG**: bootstrap fires whenever the bundled content hash changes,
    ///   so developers editing scenes/*.json see updates on next launch.
    ///
    /// Both modes still respect AdminView's "Factory Reset" — that path resets
    /// both flags so the next launch performs a fresh bootstrap regardless.
    static func needsBootstrap() -> Bool {
        let defaults = UserDefaults.standard
        let installed = defaults.bool(forKey: AppSettingsKey.bootstrapInstalled)

        #if DEBUG
        // Migrate from the old integer-version scheme: if installed-flag is
        // unset but the legacy bootstrap_version key is set, we already
        // bootstrapped at least once. Migrate forward without an extra wipe.
        if !installed && defaults.integer(forKey: AppSettingsKey.bootstrapVersion) > 0 {
            defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
            // Don't store the hash here; let the next bootstrap or the next
            // hash check write it. We deliberately return true on this branch
            // so the developer sees up-to-date content.
            return true
        }
        if !installed { return true }
        let stored = defaults.string(forKey: AppSettingsKey.bootstrapContentHash) ?? ""
        return stored != bundledContentHash
        #else
        return !installed
        #endif
    }

    static func markBootstrapComplete() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppSettingsKey.bootstrapInstalled)
        defaults.set(bundledContentHash, forKey: AppSettingsKey.bootstrapContentHash)
    }

    /// Wipe all app-owned SwiftData records. Relationship-safe order matches
    /// performFactoryReset in AdminView. Safe to call on a fresh store (no-op).
    static func wipeAllData(context: ModelContext) {
        do {
            try context.delete(model: MetricEvent.self)
            try context.delete(model: SentenceCache.self)
            try context.delete(model: BlasterScene.self)
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
            let coreFirstScene = buildScene(from: materialized)

            // ----- All Tiles scene (programmatic) -----
            // Single page with every vocab tile, grouped by wordClass in vocab
            // declaration order. Useful for review/admin; not a child-facing
            // scene. Programmatic rather than JSON because the content is just
            // "all of vocabulary" — no curation needed.
            var wcOrder: [String] = []
            var wcGroups: [String: [String]] = [:]
            for tile in allTiles {
                if wcGroups[tile.wordClass] == nil {
                    wcOrder.append(tile.wordClass)
                    wcGroups[tile.wordClass] = []
                }
                wcGroups[tile.wordClass]!.append(tile.key)
            }
            let allTilesEntries: [TileEntry] = wcOrder.flatMap { wc in
                (wcGroups[wc] ?? []).map { TileEntry(key: $0, link: "", isAudible: true) }
            }
            let allTilesPage = PageSpec(key: "all_tiles", tiles: allTilesEntries)
            let allTilesScene = BlasterScene(
                name: "All Tiles",
                descriptionText: "Full vocabulary grouped by word class",
                homePageKey: "all_tiles",
                isDefault: false,
                isActive: false
            )
            allTilesScene.pages = [allTilesPage]

            // ----- persist -----
            // BlasterScene.pages is now an inline JSON-encoded attribute, so
            // there are no PageModel / PageTileModel children to insert
            // alongside each scene. Just the tiles + scenes.
            try context.transaction {
                for tile in allTiles { context.insert(tile) }
                context.insert(coreFirstScene)
                context.insert(allTilesScene)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(
                tiles: allTiles,
                pages: coreFirstScene.pages,
                scene: coreFirstScene,
                duration: elapsed
            )

        } catch {
            print("Failed to load or decode bootstrap data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }

    // MARK: - Materialized scene → BlasterScene

    /// Convert a SceneMaterializer.MaterializedScene into a BlasterScene whose
    /// `pages` array carries the materialized [PageSpec] directly. Symbolic
    /// "<home>" links rewrite to the scene's actual homePageKey at this point;
    /// Step J will move that resolution to navigation time.
    private static func buildScene(
        from materialized: SceneMaterializer.MaterializedScene
    ) -> BlasterScene {
        let resolvedPages: [PageSpec] = materialized.pages.map { spec in
            let tiles = spec.tiles.map { entry -> TileEntry in
                let to = entry.link == "<home>" ? materialized.homePageKey : entry.link
                return TileEntry(key: entry.key, link: to, isAudible: entry.isAudible)
            }
            return PageSpec(key: spec.key, tiles: tiles)
        }
        let scene = BlasterScene(
            name: materialized.name,
            descriptionText: materialized.description,
            homePageKey: materialized.homePageKey,
            isDefault: materialized.isDefault,
            isActive: materialized.isDefault
        )
        scene.pages = resolvedPages
        return scene
    }
}
