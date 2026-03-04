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
