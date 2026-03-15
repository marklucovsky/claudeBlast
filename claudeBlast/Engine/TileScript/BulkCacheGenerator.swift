// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BulkCacheGenerator.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Generates bulk cache traffic by creating random tile combinations and
/// exercising the SentenceCacheManager lookup/store path. Repeated combos
/// naturally produce cache hits, giving realistic hit/miss metrics.
@MainActor
final class BulkCacheGenerator {
    private let modelContext: ModelContext

    /// Progress callback: (completed, duplicates, total)
    var onProgress: ((Int, Int, Int) -> Void)?

    /// Final stats after generation completes.
    private(set) var insertedCount: Int = 0
    private(set) var duplicateCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Generate `spec.count` lookups using random tile combinations.
    /// Each combo goes through SentenceCacheManager: miss → store, hit → count.
    /// MetricEvents are logged so cache stats reflect real usage.
    func generate(spec: BulkTileSpec) async {
        let descriptor = FetchDescriptor<TileModel>()
        guard let allTiles = try? modelContext.fetch(descriptor), !allTiles.isEmpty else { return }

        let pool: [TileModel]
        switch spec.source {
        case .mostCommon:
            pool = mostCommonTiles(allTiles)
        case .random, .allCombos:
            pool = allTiles
        }

        let cacheManager = SentenceCacheManager(modelContext: modelContext)

        insertedCount = 0
        duplicateCount = 0
        let batchSize = 1000
        var batchCount = 0

        for i in 0..<spec.count {
            guard !Task.isCancelled else { break }

            let length = Int.random(in: spec.minLength...spec.maxLength)
            let combo = randomCombo(from: pool, length: length)
            let selections = combo.map { TileSelection(from: $0) }

            // Exercise the cache: lookup first, store on miss
            if let _ = cacheManager.lookup(tiles: selections) {
                // Cache hit — lookup already incremented hitCount
                cacheManager.logEvent(subjectType: "cache", subjectKey: SentenceCacheManager.cacheKey(for: selections), eventType: .hit)
                duplicateCount += 1
            } else {
                // Cache miss — generate mock sentence and store
                let sentence = buildMockSentence(from: combo)
                cacheManager.store(tiles: selections, sentence: sentence)
                cacheManager.logEvent(subjectType: "sentence", subjectKey: SentenceCacheManager.cacheKey(for: selections), eventType: .used)
                insertedCount += 1
            }

            batchCount += 1
            if batchCount >= batchSize {
                try? modelContext.save()
                onProgress?(i + 1, duplicateCount, spec.count)
                batchCount = 0
                await Task.yield()
            }
        }

        // Final save
        if batchCount > 0 {
            try? modelContext.save()
        }
        onProgress?(spec.count, duplicateCount, spec.count)
    }

    // MARK: - Helpers

    /// Return only high-frequency tiles for "most-common" source.
    /// A small pool (~30-50 tiles) ensures combos repeat naturally,
    /// producing realistic cache hit rates.
    private func mostCommonTiles(_ tiles: [TileModel]) -> [TileModel] {
        let highFrequency: Set<String> = ["actions", "people", "food", "social", "describe"]
        let pool = tiles.filter { highFrequency.contains($0.wordClass) }
        // Cap at ~40 tiles so the combinatorial space stays small
        return Array(pool.shuffled().prefix(40))
    }

    private func randomCombo(from tiles: [TileModel], length: Int) -> [TileModel] {
        var selected: [TileModel] = []
        var usedKeys: Set<String> = []
        var retries = length * 3
        while selected.count < length && retries > 0 {
            retries -= 1
            guard let tile = tiles.randomElement(), usedKeys.insert(tile.key).inserted else {
                continue
            }
            selected.append(tile)
        }
        return selected
    }

    private func buildMockSentence(from tiles: [TileModel]) -> String {
        let values = tiles.map(\.value)
        switch values.count {
        case 1: return "I want \(values[0])."
        case 2: return "I want \(values[0]) and \(values[1])."
        default:
            let allButLast = values.dropLast().joined(separator: ", ")
            return "I want \(allButLast), and \(values.last!)."
        }
    }
}
