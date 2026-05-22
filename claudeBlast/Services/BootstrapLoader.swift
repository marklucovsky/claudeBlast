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

            // Closure factory so each scene gets an INDEPENDENT set of PageModel +
            // PageTileModel instances built from the same codablePages source. We
            // hit this fragility when Core-First reused Legacy Default's topic
            // pages — SwiftData's @Relationship enforces effective single-parent
            // ownership on the implicit inverse, so the navigation graph in one
            // scene silently breaks when the same PageModel is assigned to another.
            let buildPagesFromCodable: () -> [PageModel] = {
                codablePages.map { codablePage in
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
            }
            let allPages: [PageModel] = buildPagesFromCodable()

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

            // Core-First — the new default scene. Layout: 8×6 home (48 tiles).
            // Restored from earlier 6×4/6×6 MVPs: category links for places +
            // body_health, common ailments (sick, hurt), social pleasantries
            // (please, thank_you, sorry), `like` and `stop`, `not`, and `play`
            // promoted from audible action to a link into play_activities.
            // Reuses Legacy Default's topic pages as link targets; the legacy
            // "home" page is filtered out so core_home is Core-First's landing.
            // Audible-link tiles (eat, drink, play): speak the word AND navigate
            // to a deeper page. The tap handler in TileGridView already supports
            // this combination — see recordAudibleNavigate.
            let coreFirstHomeSpecs: [(String, String, Bool)] = [
                // Row 1 — category links (8): all major topic pages reachable in one tap.
                ("people",     "people",          false),
                ("social",     "social",          false),
                ("actions",    "actions",         false),
                ("describe",   "describe",        false),
                ("food",       "food",            false),
                ("drinks",     "drinks",          false),
                ("places",     "places",          false),
                ("body_health","body_health",     false),
                // Row 2 — family (8): the people kids name most.
                ("mom",     "", true), ("dad",     "", true), ("sister",  "", true), ("brother", "", true),
                ("grandma", "", true), ("grandpa", "", true), ("baby",    "", true), ("friend",  "", true),
                // Row 3 — immediate needs + responses (8): hoisted next to pronouns
                // because these are what a child reaches for most under pressure.
                ("hungry",  "", true), ("thirsty", "", true), ("tired",   "", true), ("hurt",    "", true),
                ("sick",    "", true), ("toilet",  "", true), ("yes",     "", true), ("no",      "", true),
                // Row 4 — pronouns + demonstratives (8): the core grammar payload.
                ("i",       "", true), ("you",     "", true), ("me",      "", true), ("my",      "", true),
                ("your",    "", true), ("it",      "", true), ("that",    "", true), ("here",    "", true),
                // Row 5 — verbs (8). eat/drink/play are audible-link tiles: tap speaks
                // the word AND navigates to a curated landing page.
                ("want",    "",                true),
                ("eat",     "food_drinks",     true),
                ("play",    "play_activities", true),
                ("go",      "",                true),
                ("help",    "",                true),
                ("stop",    "",                true),
                ("like",    "",                true),
                // Row 6 — modifiers / state / pleasantries (8).
                ("more",    "", true), ("all",     "", true), ("all_done","", true), ("again",   "", true),
                ("not",     "", true), ("please",  "", true), ("thank_you","",true), ("sorry",   "", true),
                // ----- below-the-fold rows (visible after a scroll/swipe) -----
                
                // Row 7 — spatial prepositions (8): the v2 Core-First payload these
                // tiles unlock the spatial meaning the SentenceEngine cannot infer
                // ("ball IN" vs "ball OUT" vs "ball ON" are different intents).
                ("in",      "", true), ("on",      "", true), ("off",     "", true), ("out",     "", true),
                ("up",      "", true), ("down",    "", true), ("with",    "", true), ("for",     "", true),
                // Row 8 — weather + colors (8): secondary category nav with a couple
                // of in-class anchors for one-tap weather/color speech.
                ("weather", "weather",         false),
                ("hot",     "", true), ("cold",    "", true), ("sun",     "", true), ("rain",    "", true),
                ("colors",  "colors_shapes",   false),
                
                // Row 9 — art / activities (8): expressive verbs + a few high-value
                // playground items the child can name directly.
                ("art",     "", true), ("draw",    "", true), ("paint",   "", true), ("color",   "", true),
                ("sing",    "", true), ("dance",   "", true), ("read",    "", true),
            ]
            let coreFirstHomeTiles: [PageTileModel] = coreFirstHomeSpecs
                .compactMap { makePT($0.0, link: $0.1, audible: $0.2) }
            // Named "home" (not "core_home") so the back-button tile on every
            // topic page (link: "home" in pages.json) resolves to this page
            // when Core-First is active. SwiftData scope: scene.pages.first
            // { $0.displayName == "home" } resolves per-scene, so this doesn't
            // collide with Legacy Default's separate "home" page.
            let coreFirstHomePage = PageModel.make(
                displayName: "home",
                tiles: coreFirstHomeTiles,
                tileOrder: coreFirstHomeTiles.map(\.id)
            )

            // food_drinks combo page — destination of the audible-link `eat` tile.
            // Curated set of common kid foods + drinks so "I want to eat/drink
            // something" resolves to a specific choice in one tap.
            let foodDrinksSpecs: [(String, String, Bool)] = [
                // Top strip: home + sibling category links + immediate-need state.
                ("home",     "home",      false), ("food",    "food",   false),
                ("drinks",   "drinks",    false), ("hungry",  "", true),
                ("thirsty",  "",          true),  ("more",    "", true),
                // Drinks row
                ("water",    "", true), ("milk",    "", true),
                ("juice",    "", true), ("chocolate_milk", "", true),
                ("eat",      "", true), ("drink",   "", true),
                ("soda",     "", true), ("iced_tea",    "", true),
                ("milkshake",     "", true), ("lemonade",    "", true),
                ("ice_cubes",     "", true),

                
                // Foods (fruit + snacks)
                ("apple",    "", true), ("banana",  "", true),
                ("cookie",   "", true), ("cheese",  "", true),
                ("yogurt",   "", true), ("sandwich","", true),
                
                
                ("fries",   "", true), ("peanut_butter","", true),
                ("blueberries",   "", true), ("strawberry","", true),
                ("popcorn",   "", true), ("goldfish_cracker","", true),
                ("graham_cracker",   "", true), ("pretzels","", true),
                ("popsicle",   "", true), ("chips","", true),

                
                // Meals + close
                ("cereal",   "", true), ("pizza",   "", true),
                ("eggs",     "", true), ("please",  "", true),
                ("all_done", "", true), ("no",      "", true),
            ]
            let foodDrinksTiles: [PageTileModel] = foodDrinksSpecs
                .compactMap { makePT($0.0, link: $0.1, audible: $0.2) }
            let foodDrinksPage = PageModel.make(
                displayName: "food_drinks",
                tiles: foodDrinksTiles,
                tileOrder: foodDrinksTiles.map(\.id)
            )

            let coreFirstScene = BlasterScene(
                name: "Core-First",
                descriptionText: "High-reach home with pronouns, verbs, and category links",
                homePageKey: "home",
                isDefault: true,
                isActive: true
            )
            // Build INDEPENDENT topic-page instances for Core-First (separate
            // PageModel + PageTileModel objects than Legacy Default has). Required
            // because SwiftData's @Relationship can't safely share children across
            // two parent relationships — links silently break in one scene.
            let coreFirstTopicPages = buildPagesFromCodable().filter { $0.displayName != "home" }
            coreFirstScene.pages = [coreFirstHomePage, foodDrinksPage] + coreFirstTopicPages

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
                for pt in foodDrinksTiles { context.insert(pt) }
                context.insert(foodDrinksPage)
                // Core-First's independent topic-page set (its own PageModel +
                // PageTileModel instances, distinct from Legacy Default's).
                for page in coreFirstTopicPages {
                    for pt in page.tiles { context.insert(pt) }
                    context.insert(page)
                }
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
