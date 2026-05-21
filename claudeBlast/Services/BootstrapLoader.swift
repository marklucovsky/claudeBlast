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

        let emptyScene = BlasterScene(name: "Legacy Default", isDefault: true, isActive: true)

        guard let vocabularyUrl = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            print("Failed to locate vocabulary.json in bundle.")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }

        guard let pagesUrl = Bundle.main.url(forResource: "pages", withExtension: "json") else {
            print("Failed to locate pages.json in bundle.")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }

        do {
            let tilesData = try Data(contentsOf: vocabularyUrl)
            let codableTiles = try JSONDecoder().decode([TileModelCodable].self, from: tilesData)
            // Deduplicate by key at load time (CloudKit does not support @Attribute(.unique))
            var seenTileKeys = Set<String>()
            let allTiles: [TileModel] = codableTiles.compactMap { codable in
                guard seenTileKeys.insert(codable.key).inserted else { return nil }
                return TileModel(from: codable)
            }

            let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

            let pagesData = try Data(contentsOf: pagesUrl)
            let codablePages = try JSONDecoder().decode([PageModelCodable].self, from: pagesData)

            let allPages: [PageModel] = codablePages.map { codablePage in
                var pageTiles: [PageTileModel] = []

                for ptc in codablePage.pageTiles {
                    let tileKey = ptc.key
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if let tile = tileLookup[tileKey] {
                        let pageTile = PageTileModel(
                            tile: tile,
                            link: ptc.link,
                            isAudible: ptc.isAudible
                        )
                        pageTiles.append(pageTile)
                    } else {
                        print("Warning: Tile not found for key '\(tileKey)' on page '\(codablePage.key)'")
                    }
                }

                let tileOrder = pageTiles.map(\.id)
                return PageModel.make(
                    displayName: codablePage.key,
                    tiles: pageTiles,
                    tileOrder: tileOrder
                )
            }

            // Legacy Default — the original bundled scene. Demoted: the Core-First
            // scene below now owns `isDefault: true, isActive: true`.
            let defaultScene = BlasterScene(
                name: "Legacy Default",
                descriptionText: "Original bundled vocabulary",
                homePageKey: "home",
                isDefault: false,
                isActive: false
            )
            defaultScene.pages = allPages

            // "All Tiles (Review)" scene — full vocabulary sorted by word class,
            // one flat page for image quality review.
            var wcOrder: [String] = []
            var wcGroups: [String: [TileModel]] = [:]
            for tile in allTiles {
                if wcGroups[tile.wordClass] == nil {
                    wcOrder.append(tile.wordClass)
                    wcGroups[tile.wordClass] = []
                }
                wcGroups[tile.wordClass]!.append(tile)
            }
            let reviewPageTiles: [PageTileModel] = wcOrder.flatMap { wc in
                (wcGroups[wc] ?? []).map { PageTileModel(tile: $0, link: "", isAudible: true) }
            }
            let reviewPage = PageModel.make(
                displayName: "all_tiles",
                tiles: reviewPageTiles,
                tileOrder: reviewPageTiles.map(\.id)
            )
            let reviewScene = BlasterScene(
                name: "All Tiles (Review)",
                descriptionText: "Full vocabulary by word class — image review",
                homePageKey: "all_tiles",
                isDefault: false,
                isActive: false
            )
            reviewScene.pages = [reviewPage]

            // "Starter" scene — small people + food vocabulary for quick demos
            func makePT(_ key: String, link: String = "", audible: Bool = true) -> PageTileModel? {
                guard let tile = tileLookup[key] else { return nil }
                return PageTileModel(tile: tile, link: link, isAudible: audible)
            }

            let starterHomeTiles: [PageTileModel] = [
                ("people", "starter_people", false),
                ("eat",    "starter_food",   true),
                ("drink",  "",               true),
                ("yes",    "",               true),
                ("no",     "",               true),
                ("more",   "",               true),
                ("want",   "",               true),
                ("help",   "",               true),
                ("go",     "",               true),
                ("good",   "",               true),
                ("play",   "",               true),
                ("stop",   "",               true),
            ].compactMap { makePT($0.0, link: $0.1, audible: $0.2) }
            let starterHomePage = PageModel.make(
                displayName: "starter_home",
                tiles: starterHomeTiles,
                tileOrder: starterHomeTiles.map(\.id)
            )

            let starterPeopleTiles: [PageTileModel] = ["mom", "dad", "brother", "sister",
                "grandma", "grandpa", "friend", "baby",
                "boy", "girl", "she", "teacher",
                "family", "people"]
                .compactMap { makePT($0) }
            let starterPeoplePage = PageModel.make(
                displayName: "starter_people",
                tiles: starterPeopleTiles,
                tileOrder: starterPeopleTiles.map(\.id)
            )

            let starterFoodTiles: [PageTileModel] = ["eat", "drink", "apple", "banana",
                "pizza", "cereal", "crackers", "cookie",
                "milk", "juice", "water", "snacks",
                "fruit", "cheese", "grapes", "yogurt"]
                .compactMap { makePT($0) }
            let starterFoodPage = PageModel.make(
                displayName: "starter_food",
                tiles: starterFoodTiles,
                tileOrder: starterFoodTiles.map(\.id)
            )

            let starterScene = BlasterScene(
                name: "Starter",
                descriptionText: "People & food — small vocabulary for quick demos",
                homePageKey: "starter_home",
                isDefault: false,
                isActive: false
            )
            starterScene.pages = [starterHomePage, starterPeoplePage, starterFoodPage]
            let starterAllTiles = starterHomeTiles + starterPeopleTiles + starterFoodTiles

            // Core-First — the new default scene. Layout: 6×6 home with
            // categories, family, pronouns, verbs, modifiers, and immediate-needs
            // rows. Reuses Legacy Default's topic pages (people/social/actions/...)
            // as link targets; the legacy "home" page is filtered out so
            // Core-First's own core_home is the only landing page in this scene.
            let coreFirstHomeSpecs: [(String, String, Bool)] = [
                // Row 1 — category links (audible=false; navigate to topic page)
                ("people",   "people",   false),
                ("social",   "social",   false),
                ("actions",  "actions",  false),
                ("describe", "describe", false),
                ("food",     "food",     false),
                ("drinks",   "drinks",   false),
                // Row 2 — family (high-frequency people)
                ("mom",      "", true), ("dad",     "", true), ("sister",  "", true),
                ("brother",  "", true), ("grandma", "", true), ("grandpa", "", true),
                // Row 3 — pronouns
                ("i",        "", true), ("you",     "", true), ("me",      "", true),
                ("my",       "", true), ("your",    "", true), ("it",      "", true),
                // Row 4 — high-frequency verbs
                ("want",     "", true), ("eat",     "", true), ("drink",   "", true),
                ("play",     "", true), ("go",      "", true), ("help",    "", true),
                // Row 5 — modifiers + state
                ("more",     "", true), ("here",    "", true), ("that",    "", true),
                ("all",      "", true), ("all_done","", true), ("again",   "", true),
                // Row 6 — immediate needs / yes-no
                ("yes",      "", true), ("no",      "", true), ("toilet",  "", true),
                ("hungry",   "", true), ("thirsty", "", true), ("tired",   "", true),
            ]
            let coreFirstHomeTiles: [PageTileModel] = coreFirstHomeSpecs
                .compactMap { makePT($0.0, link: $0.1, audible: $0.2) }
            let coreFirstHomePage = PageModel.make(
                displayName: "core_home",
                tiles: coreFirstHomeTiles,
                tileOrder: coreFirstHomeTiles.map(\.id)
            )

            let coreFirstScene = BlasterScene(
                name: "Core-First",
                descriptionText: "High-reach home with pronouns, verbs, and category links",
                homePageKey: "core_home",
                isDefault: true,
                isActive: true
            )
            // Share Legacy Default's topic pages; drop the legacy `home` page since
            // Core-First's `core_home` replaces it.
            let topicPagesForCoreFirst = allPages.filter { $0.displayName != "home" }
            coreFirstScene.pages = [coreFirstHomePage] + topicPagesForCoreFirst

            try context.transaction {
                for tile in allTiles {
                    context.insert(tile)
                }
                for page in allPages {
                    context.insert(page)
                }
                context.insert(defaultScene)
                for pt in coreFirstHomeTiles { context.insert(pt) }
                context.insert(coreFirstHomePage)
                context.insert(coreFirstScene)
                for pt in reviewPageTiles { context.insert(pt) }
                context.insert(reviewPage)
                context.insert(reviewScene)
                for pt in starterAllTiles { context.insert(pt) }
                context.insert(starterHomePage)
                context.insert(starterPeoplePage)
                context.insert(starterFoodPage)
                context.insert(starterScene)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(tiles: allTiles, pages: allPages, scene: coreFirstScene, duration: elapsed)

        } catch {
            print("Failed to load or decode vocabulary data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }
}
