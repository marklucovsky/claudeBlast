// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageGeneratorService.swift
//  claudeBlast
//
//  Generates a page (with optional sub-pages) from a therapist's goal description.
//

import Foundation

struct PageGeneratorService {
    let apiKey: String

    // MARK: - Prompt configuration

    private let model = "gpt-4o-mini"
    private let temperature = 0.4
    private let maxTokens = 800

    // MARK: - Public API

    func generate(pageGoal: String, pageName: String, allTiles: [TileModel]) async throws -> GeneratedPageResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let system = buildSystemPrompt()
        let user = buildUserPrompt(pageGoal: pageGoal, pageName: pageName, vocabBlock: vocabBlock)

        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
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

        return try parsePage(data: data, pageName: pageName, validKeys: Set(allTiles.map(\.key)))
    }

    // MARK: - Prompt builders

    private func buildSystemPrompt() -> String {
        """
        You are a specialist in AAC (Augmentative and Alternative Communication) for non-verbal children. \
        Given a goal and vocabulary, select tiles for a single focused page.

        You may optionally include navigation tiles that link to new sub-pages when the vocabulary genuinely \
        spans two distinct contexts (e.g. general emotions + detailed feelings). Keep navigation to a minimum — \
        prefer a flat page for focused, single-topic goals.

        Tile rules:
        - Use ONLY tile keys from the provided vocabulary. Never invent keys.
        - Audible tiles (isAudible=true) contribute to the sentence tray.
        - Navigation tiles must have isAudible=false and a non-empty link matching a key in newPages.
        - Aim for 8–24 tiles on the primary page.

        Return ONLY valid JSON — no markdown, no prose:
        {
          "key": "string",
          "tiles": [
            { "key": "string", "isAudible": true, "link": "" }
          ],
          "newPages": [
            {
              "key": "string",
              "tiles": [{ "key": "string", "isAudible": true, "link": "" }]
            }
          ]
        }
        """
    }

    private func buildUserPrompt(pageGoal: String, pageName: String, vocabBlock: String) -> String {
        """
        Page name: \(pageName)
        Goal: \(pageGoal)

        Available vocabulary by category:
        \(vocabBlock)
        """
    }

    // MARK: - Vocab formatting

    private func buildVocabBlock(allTiles: [TileModel]) -> String {
        var byClass: [String: [String]] = [:]
        for tile in allTiles {
            byClass[tile.wordClass, default: []].append(tile.key)
        }
        return byClass.keys.sorted().map { wc in
            "\(wc): \(byClass[wc]!.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    // MARK: - Response parsing

    private func parsePage(data: Data, pageName: String, validKeys: Set<String>) throws -> GeneratedPageResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }

        let jsonText: String
        if let start = content.firstIndex(of: "{"),
           let end = content.lastIndex(of: "}") {
            jsonText = String(content[start...end])
        } else {
            jsonText = content
        }

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw OpenAIError.decodingError("Response JSON was not valid UTF-8")
        }

        let raw = try JSONDecoder().decode(GeneratedPageResponse.self, from: jsonData)

        let validPrimary = raw.tiles.filter { validKeys.contains($0.key) }
        guard !validPrimary.isEmpty else {
            throw OpenAIError.decodingError("No valid tiles found in generated page")
        }

        let primaryPage = GeneratedPage(key: pageName, tiles: validPrimary)

        let subPages = raw.newPages.map { sub in
            let validTiles = sub.tiles.filter { validKeys.contains($0.key) }
            return GeneratedPage(key: sub.key, tiles: validTiles)
        }.filter { !$0.tiles.isEmpty }

        return GeneratedPageResult(primaryPage: primaryPage, subPages: subPages)
    }
}
