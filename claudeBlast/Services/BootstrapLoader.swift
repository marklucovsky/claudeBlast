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

            try context.transaction {
                for tile in allTiles {
                    context.insert(tile)
                }
                for page in allPages {
                    context.insert(page)
                }
                context.insert(defaultScene)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(tiles: allTiles, pages: allPages, scene: defaultScene, duration: elapsed)

        } catch {
            print("Failed to load or decode vocabulary data: \(error)")
            return LoadResult(tiles: [], pages: [], scene: emptyScene, duration: 0)
        }
    }
}
