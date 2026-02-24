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

    static func loadDefaultVocabulary(context: ModelContext) -> LoadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let emptyScene = BlasterScene(name: "Default", isDefault: true, isActive: true)

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
            let allTiles = codableTiles.map { TileModel(from: $0) }

            let tileLookup = Dictionary(
                allTiles.map { ($0.key, $0) },
                uniquingKeysWith: { first, _ in first }
            )

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

            let defaultScene = BlasterScene(
                name: "Default",
                descriptionText: "Built-in vocabulary",
                homePageKey: "home",
                isDefault: true,
                isActive: true
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

            try context.transaction {
                for tile in allTiles {
                    context.insert(tile)
                }
                for page in allPages {
                    context.insert(page)
                }
                context.insert(defaultScene)
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
            return LoadResult(tiles: allTiles, pages: allPages, scene: defaultScene, duration: elapsed)

        } catch {
            print("Failed to load or decode vocabulary data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }
}
