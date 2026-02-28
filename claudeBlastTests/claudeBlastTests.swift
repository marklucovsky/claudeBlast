// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  claudeBlastTests.swift
//  claudeBlastTests
//
//  Created by MARK LUCOVSKY on 2/16/26.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
struct claudeBlastTests {

    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self, PageModel.self, PageTileModel.self,
            SentenceCache.self, BlasterScene.self, MetricEvent.self
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

    @Test func metricEventCreation() throws {
        let event = MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected)
        #expect(event.subjectType == "tile")
        #expect(event.subjectKey == "eat")
        #expect(event.eventType == .selected)
    }

    @Test func metricEventInsertAndQuery() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        context.insert(MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected))
        context.insert(MetricEvent(subjectType: "tile", subjectKey: "eat", eventType: .selected))
        context.insert(MetricEvent(subjectType: "tile", subjectKey: "pizza", eventType: .selected))
        context.insert(MetricEvent(subjectType: "cache", subjectKey: "eat,mom", eventType: .hit))

        let eatSelected = try context.fetch(
            FetchDescriptor<MetricEvent>(predicate: #Predicate {
                $0.subjectKey == "eat" && $0.subjectType == "tile"
            })
        )
        #expect(eatSelected.count == 2)

        let allTileEvents = try context.fetch(
            FetchDescriptor<MetricEvent>(predicate: #Predicate {
                $0.subjectType == "tile"
            })
        )
        #expect(allTileEvents.count == 3)
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

    @Test func tileSelectionLogic() throws {
        let eat = TileModel(key: "eat", wordClass: "actions")
        let pizza = TileModel(key: "pizza", wordClass: "food")
        let mom = TileModel(key: "mom", wordClass: "people")
        let drink = TileModel(key: "drink", wordClass: "actions")
        let water = TileModel(key: "water", wordClass: "food")

        let maxTiles = 4
        var selectedTiles: [TileModel] = []

        // Add tiles up to max
        for tile in [eat, pizza, mom, drink] {
            if selectedTiles.count < maxTiles {
                selectedTiles.append(tile)
            }
        }
        #expect(selectedTiles.count == 4)

        // Cannot exceed max
        if selectedTiles.count < maxTiles {
            selectedTiles.append(water)
        }
        #expect(selectedTiles.count == 4)

        // Remove by index (tap-to-remove)
        selectedTiles.remove(at: 1) // removes pizza
        #expect(selectedTiles.count == 3)
        #expect(selectedTiles[0].key == "eat")
        #expect(selectedTiles[1].key == "mom")

        // Clear all
        selectedTiles.removeAll()
        #expect(selectedTiles.isEmpty)
    }

    @Test func navigationTileHasLink() throws {
        let tile = TileModel(key: "food", wordClass: "navigation")
        let navTile = PageTileModel(tile: tile, link: "food_page", isAudible: false)
        #expect(!navTile.link.isEmpty)
        #expect(!navTile.isAudible)

        let audibleNavTile = PageTileModel(tile: tile, link: "food_page", isAudible: true)
        #expect(!audibleNavTile.link.isEmpty)
        #expect(audibleNavTile.isAudible)
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

    @Test func bootstrapCreatesDefaultScene() throws {
        let container = try makeTestContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)

        #expect(result.scene.isDefault)
        #expect(result.scene.isActive)
        #expect(result.scene.name == "Default")
        #expect(result.scene.homePageKey == "home")
        #expect(result.scene.pages.count == result.pages.count)
    }

    @Test func sceneActivationDeactivatesOthers() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let scene1 = BlasterScene(name: "Default", isDefault: true, isActive: true)
        let scene2 = BlasterScene(name: "Therapy", isActive: false)
        context.insert(scene1)
        context.insert(scene2)

        try scene2.activate(context: context)

        #expect(!scene1.isActive)
        #expect(scene2.isActive)
    }

    @Test func deactivateRestoresDefault() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let defaultScene = BlasterScene(name: "Default", isDefault: true, isActive: false)
        let therapyScene = BlasterScene(name: "Therapy", isActive: true)
        context.insert(defaultScene)
        context.insert(therapyScene)

        try therapyScene.deactivateAndRestoreDefault(context: context)

        #expect(!therapyScene.isActive)
        #expect(defaultScene.isActive)
    }

    @Test func sceneOwnsPages() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tile = TileModel(key: "eat", wordClass: "actions")
        let pageTile = PageTileModel(tile: tile, link: "", isAudible: true)
        let page = PageModel.make(displayName: "therapy_page", tiles: [pageTile], tileOrder: [pageTile.id])

        let scene = BlasterScene(name: "Therapy Session", homePageKey: "therapy_page")
        scene.pages = [page]

        context.insert(tile)
        context.insert(page)
        context.insert(scene)

        #expect(scene.pages.count == 1)
        #expect(scene.pages.first?.displayName == "therapy_page")
        #expect(scene.homePageKey == "therapy_page")
    }
}
