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
        let duration: TimeInterval
    }

    static func loadDefaultVocabulary(context: ModelContext) -> LoadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let vocabularyUrl = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            print("Failed to locate vocabulary.json in bundle.")
            return LoadResult(tiles: [], pages: [], duration: 0)
        }

        guard let pagesUrl = Bundle.main.url(forResource: "pages", withExtension: "json") else {
            print("Failed to locate pages.json in bundle.")
            return LoadResult(tiles: [], pages: [], duration: 0)
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

            try context.transaction {
                for tile in allTiles {
                    context.insert(tile)
                }
                for page in allPages {
                    context.insert(page)
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return LoadResult(tiles: allTiles, pages: allPages, duration: elapsed)

        } catch {
            print("Failed to load or decode vocabulary data: \(error)")
            return LoadResult(tiles: [], pages: [], duration: 0)
        }
    }
}
