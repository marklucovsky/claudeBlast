// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceProvider.swift
//  claudeBlast
//

import Foundation

protocol SentenceProvider: Sendable {
    var displayName: String { get }
    var supportsIntegratedAudio: Bool { get }

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        conversationContext: [String],
        requestAudio: Bool
    ) async throws -> SentenceResult
}
