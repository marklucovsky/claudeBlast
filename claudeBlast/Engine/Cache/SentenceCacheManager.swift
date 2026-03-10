// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceCacheManager.swift
//  claudeBlast
//

import SwiftData
import Foundation

@MainActor
final class SentenceCacheManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Build a canonical cache key from tile keys (deduplicated, sorted, comma-joined).
    static func cacheKey(for tiles: [TileSelection]) -> String {
        Set(tiles.map(\.key)).sorted().joined(separator: ",")
    }

    /// Increment hitCount for an existing cache entry without returning the sentence.
    /// Called on escalation paths that bypass the cache for generation but should still count usage.
    func recordHit(tiles: [TileSelection]) {
        let key = Self.cacheKey(for: tiles)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = try? modelContext.fetch(descriptor).first else { return }
        entry.hitCount += 1
        entry.lastUsed = .now
    }

    /// Look up a cached sentence. Returns nil on miss; increments hitCount on hit.
    func lookup(tiles: [TileSelection]) -> SentenceCache? {
        let key = Self.cacheKey(for: tiles)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1

        guard let entry = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        entry.hitCount += 1
        entry.lastUsed = .now
        return entry
    }

    /// Store or update a cached sentence for the given tiles.
    func store(tiles: [TileSelection], sentence: String, audioData: String = "") {
        let key = Self.cacheKey(for: tiles)
        var descriptor = FetchDescriptor<SentenceCache>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.sentence = sentence
            existing.audioData = audioData
            existing.lastUsed = .now
        } else {
            let tileKeys = tiles.map(\.key)
            let entry = SentenceCache(tileKeys: tileKeys, sentence: sentence, audioData: audioData)
            modelContext.insert(entry)
        }
    }

    /// Fetch all cache entries, sorted by most recently used.
    func allEntries() -> [SentenceCache] {
        let descriptor = FetchDescriptor<SentenceCache>(
            sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Delete a single cache entry.
    func delete(_ entry: SentenceCache) {
        modelContext.delete(entry)
    }

    /// Flush all cache entries.
    func flushAll() {
        let entries = allEntries()
        for entry in entries {
            modelContext.delete(entry)
        }
    }

    /// Fetch promoted entries: hitCount >= threshold or pinned, sorted by hitCount desc.
    func fetchPromoted(threshold: Int = 3, limit: Int = 8) -> [SentenceCache] {
        let entries = allEntries()
        let promoted = entries.filter { $0.hitCount >= threshold || $0.isPinned }
        return Array(promoted.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.hitCount > $1.hitCount
        }.prefix(limit))
    }

    /// Log a MetricEvent.
    func logEvent(subjectType: String, subjectKey: String, eventType: MetricType) {
        let event = MetricEvent(subjectType: subjectType, subjectKey: subjectKey, eventType: eventType)
        modelContext.insert(event)
    }
}
