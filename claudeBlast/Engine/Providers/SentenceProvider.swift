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
        systemPrompt: String,
        conversationContext: [String],
        requestAudio: Bool
    ) async throws -> SentenceResult
}
