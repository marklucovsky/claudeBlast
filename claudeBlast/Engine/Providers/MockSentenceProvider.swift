// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MockSentenceProvider.swift
//  claudeBlast
//

import Foundation

struct MockSentenceProvider: SentenceProvider {
    let displayName = "Mock"
    let supportsIntegratedAudio = false

    private static let cannedResponses: [String: String] = [
        "eat,mom": "Mom, I want to eat something!",
        "eat,mom,pizza": "Mom, can I have some pizza please?",
        "eat,pizza": "I want pizza!",
        "help,mom": "Mom, I need help please.",
        "help": "I need help!",
        "happy": "I'm happy!",
        "sad": "I feel sad.",
        "hungry": "I'm hungry!",
        "more": "I want more please!",
        "stop": "Please stop!",
        "yes": "Yes!",
        "no": "No!",
        "drink,water": "Can I have some water?",
        "go,outside": "I want to go outside!",
        "play": "I want to play!",
        "tired": "I'm tired.",
    ]

    /// Simulated latency range in seconds
    var minLatency: Double = 0.3
    var maxLatency: Double = 1.5

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        conversationContext: [String],
        requestAudio: Bool
    ) async throws -> SentenceResult {
        // Simulate network latency
        let delay = Double.random(in: minLatency...maxLatency)
        try await Task.sleep(for: .seconds(delay))

        let key = Set(tiles.map(\.key)).sorted().joined(separator: ",")
        let text: String

        if let canned = Self.cannedResponses[key] {
            text = canned
        } else {
            text = buildFallbackSentence(from: tiles)
        }

        return SentenceResult(text: text)
    }

    private func buildFallbackSentence(from tiles: [TileSelection]) -> String {
        // Deduplicate while preserving order
        var seen = Set<String>()
        let unique = tiles.filter { seen.insert($0.key).inserted }
        let values = unique.map(\.value)

        switch values.count {
        case 1:
            return "I want \(values[0])."
        case 2:
            return "I want \(values[0]) and \(values[1])."
        default:
            let allButLast = values.dropLast().joined(separator: ", ")
            return "I want \(allButLast), and \(values.last!)."
        }
    }
}
