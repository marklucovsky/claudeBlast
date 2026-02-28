//
//  SceneGeneratorService.swift
//  claudeBlast
//
//  Generates a complete multi-page AAC scene from a therapist's free-form
//  session description.
//

import Foundation

struct SceneGeneratorService {
    let apiKey: String

    // MARK: - Prompt configuration
    // These constants are intentionally separate so prompt engineering is easy.

    /// Target tile count below which we prefer a single page (no nav overhead).
    private let singlePageTileThreshold = 50

    /// Model and sampling settings.
    private let model = "gpt-4o-mini"
    private let temperature = 0.4
    private let maxTokens = 2000

    // MARK: - Public API

    func generate(description: String, allTiles: [TileModel]) async throws -> GeneratedScene {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let vocabBlock = buildVocabBlock(allTiles: allTiles)
        let system = buildSystemPrompt(tileCount: allTiles.count)
        let user = buildUserPrompt(description: description, vocabBlock: vocabBlock)

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

        return try parseScene(data: data, validKeys: Set(allTiles.map(\.key)))
    }

    // MARK: - Prompt builders
    // Each builder is a separate function so individual prompt sections are easy to tune.

    private func buildSystemPrompt(tileCount: Int) -> String {
        """
        You are a specialist in AAC (Augmentative and Alternative Communication) for non-verbal children. \
        Given a therapist's session description and vocabulary, design a focused scene.

        Navigation guidance:
        - If the total number of relevant tiles is roughly \(singlePageTileThreshold) or fewer, use a SINGLE \
          page. Smart word-class clustering is better than forced navigation for small sessions.
        - Only add multiple pages when the vocabulary genuinely spans separate contexts \
          (e.g. "emotions" vs "food needs" vs "school activities").
        - Navigation tiles must have isAudible=false and a non-empty link matching another page key.

        Tile rules:
        - Use ONLY tile keys from the provided vocabulary. Never invent keys.
        - Prefer audible tiles (isAudible=true) for communicative vocabulary.
        - Limit each page to 12–30 tiles so the grid is not overwhelming.

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose:
        {
          "name": "string",
          "description": "string",
          "homePageKey": "string",
          "pages": [
            {
              "key": "string",
              "tiles": [
                { "key": "string", "isAudible": true, "link": "" }
              ]
            }
          ]
        }
        """
    }

    private func buildUserPrompt(description: String, vocabBlock: String) -> String {
        """
        Session description: \(description)

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

    private func parseScene(data: Data, validKeys: Set<String>) throws -> GeneratedScene {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodingError("Could not parse chat response")
        }

        // Strip any surrounding prose; extract the JSON object
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

        let raw = try JSONDecoder().decode(GeneratedScene.self, from: jsonData)

        // Filter tiles to only valid vocabulary keys and sanitize links
        let sanitizedPages = raw.pages.map { page in
            let validTiles = page.tiles.compactMap { tile -> GeneratedTile? in
                guard validKeys.contains(tile.key) else { return nil }
                return tile
            }
            return GeneratedPage(key: page.key, tiles: validTiles)
        }.filter { !$0.tiles.isEmpty }

        guard !sanitizedPages.isEmpty else {
            throw OpenAIError.decodingError("No valid tiles found in generated scene")
        }

        let homeKey = sanitizedPages.contains(where: { $0.key == raw.homePageKey })
            ? raw.homePageKey
            : sanitizedPages[0].key

        return GeneratedScene(
            name: raw.name,
            description: raw.description,
            homePageKey: homeKey,
            pages: sanitizedPages
        )
    }
}
