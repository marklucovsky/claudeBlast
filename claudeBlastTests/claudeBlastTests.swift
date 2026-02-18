//
//  claudeBlastTests.swift
//  claudeBlastTests
//
//  Created by MARK LUCOVSKY on 2/16/26.
//

import Testing
import SwiftData
@testable import claudeBlast

@MainActor
struct claudeBlastTests {

    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self, PageModel.self, PageTileModel.self,
            SentenceCache.self, BlasterScene.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func tileModelKeyNormalization() throws {
        let tile = TileModel(key: "Graham_Cracker", wordClass: "food")
        #expect(tile.key == "graham_cracker")
        #expect(tile.displayName == "graham cracker")
        #expect(tile.value == "graham cracker")
        #expect(tile.bundleImage == "graham_cracker")
        #expect(tile.wordClass == "food")
        #expect(tile.type == .word)
    }

    @Test func tileMetricsTracking() throws {
        let tile = TileModel(key: "eat", wordClass: "actions")
        tile.recordMetric(metric: .selected)
        tile.recordMetric(metric: .selected)
        #expect(tile.getMetricCount(metric: .selected) == 2)
        #expect(tile.getMetricCount(metric: .used) == 0)
    }

    @Test func pageModelWithOrderedTiles() throws {
        let tile = TileModel(key: "eat", wordClass: "actions")
        let pageTile = PageTileModel(tile: tile, link: "eat", isAudible: true)
        let page = PageModel.make(
            displayName: "home",
            tiles: [pageTile],
            tileOrder: [pageTile.id]
        )
        #expect(page.displayName == "home")
        #expect(page.tiles.count == 1)
        #expect(page.orderedTiles.count == 1)
        #expect(page.orderedTiles.first?.tile.key == "eat")
    }

    @Test func pageTileModelDefaults() throws {
        let tile = TileModel(key: "home", wordClass: "navigation")
        let pageTile = PageTileModel(tile: tile)
        #expect(pageTile.link == "")
        #expect(pageTile.isAudible == true)
    }

    @Test func sentenceCacheOrderIndependentKey() throws {
        let cache1 = SentenceCache(tileKeys: ["mom", "eat", "pizza"], sentence: "test")
        let cache2 = SentenceCache(tileKeys: ["pizza", "mom", "eat"], sentence: "test")
        #expect(cache1.cacheKey == cache2.cacheKey)
        #expect(cache1.cacheKey == "eat,mom,pizza")
    }

    @Test func bootstrapLoaderIntegration() throws {
        let container = try makeTestContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)

        #expect(result.tiles.count > 400)
        #expect(result.pages.count > 5)

        let homePage = result.pages.first { $0.displayName == "home" }
        #expect(homePage != nil)
        #expect(homePage!.tiles.count > 0)

        let snackTile = result.tiles.first { $0.key == "snack" }
        #expect(snackTile != nil)
        #expect(snackTile!.displayName == "snack")
    }
}
