// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceResult.swift
//  claudeBlast
//

import Foundation

struct TileSelection: Sendable, Equatable, Hashable {
    let key: String
    let value: String
    let wordClass: String

    init(key: String, value: String, wordClass: String) {
        self.key = key
        self.value = value
        self.wordClass = wordClass
    }

    init(from tile: TileModel) {
        self.key = tile.key
        self.value = tile.value
        self.wordClass = tile.wordClass
    }
}

struct TokenUsage: Sendable {
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let promptCachedTokens: Int
}

struct SentenceResult: Sendable {
    let text: String
    let usage: TokenUsage?

    init(text: String, usage: TokenUsage? = nil) {
        self.text = text
        self.usage = usage
    }
}

/// Lifecycle state for a TileGroup in the sentence tray timeline.
enum TileGroupState: Sendable, Equatable {
    /// Tiles being added; no sentence has been generated yet.
    case building
    /// Sentence has been generated. Tapping a new tile flushes this group to history.
    case locked
    /// Was locked; child has removed a tile and the previously-locked sentence is now stale.
    /// Generation will re-fire on debounce/Go.
    case unlockedEditable
}

/// An utterance in the sentence tray timeline: up to N tiles plus the generated sentence.
struct TileGroup: Identifiable, Sendable, Equatable {
    let id: UUID
    var tiles: [TileSelection]
    var sentence: String?
    var state: TileGroupState
    let createdAt: Date
    var repetitionCount: Int

    init(
        id: UUID = UUID(),
        tiles: [TileSelection] = [],
        sentence: String? = nil,
        state: TileGroupState = .building,
        createdAt: Date = .now,
        repetitionCount: Int = 0
    ) {
        self.id = id
        self.tiles = tiles
        self.sentence = sentence
        self.state = state
        self.createdAt = createdAt
        self.repetitionCount = repetitionCount
    }
}
