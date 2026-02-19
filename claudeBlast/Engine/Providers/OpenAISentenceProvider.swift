//
//  OpenAISentenceProvider.swift
//  claudeBlast
//
//  Stub — Phase 2 implementation.
//

import Foundation

struct OpenAISentenceProvider: SentenceProvider {
    let displayName = "OpenAI"
    let supportsIntegratedAudio = true

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: String,
        conversationContext: [String],
        requestAudio: Bool
    ) async throws -> SentenceResult {
        fatalError("OpenAISentenceProvider is not yet implemented. Use MockSentenceProvider for Phase 1.")
    }
}
