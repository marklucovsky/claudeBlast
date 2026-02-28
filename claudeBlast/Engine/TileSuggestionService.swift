// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileSuggestionService.swift
//  claudeBlast
//

import Foundation
import SwiftData

struct TileSuggestionService {
    let apiKey: String

    /// Ask gpt-4o-mini to suggest tile keys from `allTiles` that fit `goal`.
    /// Returns only keys that actually exist in `allTiles`.
    func suggest(goal: String, allTiles: [TileModel]) async throws -> Set<String> {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let validKeys = Set(allTiles.map(\.key))
        let vocabBlock = buildVocabBlock(allTiles: allTiles)

        let systemMessage = """
        You are helping configure an AAC (Augmentative and Alternative Communication) app \
        for non-verbal children. Given a vocabulary of tiles grouped by category, select the \
        tiles most relevant to the stated goal.
        Respond with ONLY a JSON array of tile key strings, e.g. ["eat","drink","happy"].
        Use only keys from the vocabulary provided. Aim for 8–20 tiles.
        """

        let userMessage = """
        Goal: \(goal)

        Available vocabulary by category:
        \(vocabBlock)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "max_tokens": 300,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user",   "content": userMessage]
            ]
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.httpError(statusCode: http.statusCode, body: body)
        }

        return try parseKeys(data: data, validKeys: validKeys)
    }

    // MARK: - Helpers

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    private func parseKeys(data: Data, validKeys: Set<String>) throws -> Set<String> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse response")
        }

        // Extract the JSON array from the content (strip any surrounding prose)
        let arrayText: String
        if let start = content.firstIndex(of: "["),
           let end = content.lastIndex(of: "]") {
            arrayText = String(content[start...end])
        } else {
            arrayText = content
        }

        guard let arrayData = arrayText.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: arrayData) else {
            throw OpenAIError.decodingError("Response was not a JSON array of strings")
        }

        // Filter to only keys that exist in the vocabulary
        return Set(keys).intersection(validKeys)
    }
}
