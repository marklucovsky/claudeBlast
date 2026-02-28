// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceEngineTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
struct SentenceEngineTests {

    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self, PageModel.self, PageTileModel.self,
            SentenceCache.self, BlasterScene.self, MetricEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - SentencePromptBuilder

    @Test func promptBuilderIncludesGradeLevel() {
        let builder = SentencePromptBuilder()
        let prompt = builder.buildSystemPrompt()
        #expect(prompt.contains(where: { $0.content.contains("2nd-grade") }))
    }

    @Test func promptBuilderIncludesRepetition() {
        var builder = SentencePromptBuilder()
        builder.repetitionCount = 2
        let prompt = builder.buildSystemPrompt()
        #expect(prompt.contains(where: { $0.content.contains("repeated") }))
        #expect(prompt.contains(where: { $0.content.contains("urgent") }))
    }

    @Test func promptBuilderFormatsUserPrompt() {
        let builder = SentencePromptBuilder()
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]
        let prompt = builder.formatUserPrompt(tiles: tiles)
        #expect(prompt == "eat (actions), pizza (food)")
    }

    // MARK: - SentenceCacheManager

    @Test func cacheLookupMiss() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]
        let result = cache.lookup(tiles: tiles)
        #expect(result == nil)
    }

    @Test func cacheStoreAndHit() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]

        cache.store(tiles: tiles, sentence: "I want pizza!")
        let hit = cache.lookup(tiles: tiles)
        #expect(hit != nil)
        #expect(hit?.sentence == "I want pizza!")
        #expect(hit?.hitCount == 1)
    }

    @Test func cacheHitCountIncrements() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]

        cache.store(tiles: tiles, sentence: "I want to eat!")
        _ = cache.lookup(tiles: tiles)
        let second = cache.lookup(tiles: tiles)
        #expect(second?.hitCount == 2)
    }

    @Test func cacheUpsertUpdates() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]

        cache.store(tiles: tiles, sentence: "Original")
        cache.store(tiles: tiles, sentence: "Updated")

        let hit = cache.lookup(tiles: tiles)
        #expect(hit?.sentence == "Updated")
    }

    @Test func cacheFlushAll() throws {
        let container = try makeTestContainer()
        let cache = SentenceCacheManager(modelContext: container.mainContext)
        let tiles1 = [TileSelection(key: "eat", value: "eat", wordClass: "actions")]
        let tiles2 = [TileSelection(key: "drink", value: "drink", wordClass: "actions")]

        cache.store(tiles: tiles1, sentence: "I want to eat!")
        cache.store(tiles: tiles2, sentence: "I want to drink!")
        #expect(cache.allEntries().count == 2)

        cache.flushAll()
        #expect(cache.allEntries().count == 0)
    }

    @Test func cacheKeyIsOrderIndependent() throws {
        let tilesA = [
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
        ]
        let tilesB = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "pizza", value: "pizza", wordClass: "food"),
        ]
        #expect(SentenceCacheManager.cacheKey(for: tilesA) == SentenceCacheManager.cacheKey(for: tilesB))
    }

    // MARK: - MockSentenceProvider

    @Test func mockProviderCannedResponse() async throws {
        let mock = MockSentenceProvider(minLatency: 0, maxLatency: 0)
        let tiles = [
            TileSelection(key: "eat", value: "eat", wordClass: "actions"),
            TileSelection(key: "mom", value: "mom", wordClass: "people"),
        ]
        let result = try await mock.generateSentence(
            tiles: tiles, systemPrompt: [], conversationContext: [], requestAudio: false
        )
        #expect(result.text == "Mom, I want to eat something!")
    }

    @Test func mockProviderFallbackResponse() async throws {
        let mock = MockSentenceProvider(minLatency: 0, maxLatency: 0)
        let tiles = [
            TileSelection(key: "run", value: "run", wordClass: "actions"),
            TileSelection(key: "fast", value: "fast", wordClass: "describe"),
        ]
        let result = try await mock.generateSentence(
            tiles: tiles, systemPrompt: [], conversationContext: [], requestAudio: false
        )
        #expect(result.text.contains("run"))
        #expect(result.text.contains("fast"))
    }

    // MARK: - SentenceEngine

    @Test func singleTileShowsValueImmediately() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        let tile = TileModel(key: "happy", wordClass: "describe")
        engine.addTile(tile)

        #expect(engine.selectedTiles.count == 1)
        #expect(engine.generatedSentence == "happy")
        #expect(!engine.isThinking)
        #expect(!engine.isWaiting)
    }

    @Test func clearResetsAllState() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "happy", wordClass: "describe"))
        engine.clearSelection()

        #expect(engine.selectedTiles.isEmpty)
        #expect(engine.generatedSentence == nil)
        #expect(!engine.isThinking)
        #expect(!engine.isWaiting)
    }

    @Test func maxTilesEnforced() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        for i in 0..<5 {
            engine.addTile(TileModel(key: "tile\(i)", wordClass: "actions"))
        }

        #expect(engine.selectedTiles.count == 4)
    }

    @Test func multipleTilesStartDebounce() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))

        // After adding 2 tiles, should be in waiting state (debounce active)
        #expect(engine.selectedTiles.count == 2)
        #expect(engine.isWaiting)
    }

    @Test func removeTileAtValidIndex() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))
        engine.removeTile(at: 0)

        #expect(engine.selectedTiles.count == 1)
        #expect(engine.selectedTiles[0].key == "pizza")
    }

    @Test func removingLastTileClears() throws {
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        let container = try makeTestContainer()
        engine.configure(modelContext: container.mainContext)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.removeTile(at: 0)

        #expect(engine.selectedTiles.isEmpty)
        #expect(engine.generatedSentence == nil)
    }

    @Test func tileSelectionEquality() {
        let a = TileSelection(key: "eat", value: "eat", wordClass: "actions")
        let b = TileSelection(key: "eat", value: "eat", wordClass: "actions")
        let c = TileSelection(key: "pizza", value: "pizza", wordClass: "food")
        #expect(a == b)
        #expect(a != c)
    }
}
