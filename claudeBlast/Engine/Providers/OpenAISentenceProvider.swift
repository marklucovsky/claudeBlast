//
//  OpenAISentenceProvider.swift
//  claudeBlast
//

import Foundation

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        case .decodingError(let detail):
            return "Failed to decode response: \(detail)"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        }
    }
}

struct OpenAISentenceProvider: SentenceProvider {
    let displayName = "OpenAI"
    let supportsIntegratedAudio = true

    let apiKey: String
    let voice: String

    init(apiKey: String, voice: String = "nova") {
        self.apiKey = apiKey
        self.voice = voice
    }

    func generateSentence(
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        conversationContext: [String],
        requestAudio: Bool
    ) async throws -> SentenceResult {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = buildRequestBody(
            systemPrompt: systemPrompt,
            conversationContext: conversationContext,
            requestAudio: requestAudio
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try parseResponse(data: data, requestedAudio: requestAudio)
    }

    // MARK: - Request building

    private func buildRequestBody(
        systemPrompt: [PromptMessage],
        conversationContext: [String],
        requestAudio: Bool
    ) -> [String: Any] {
        var messages: [[String: Any]] = systemPrompt.map {
            ["role": $0.role, "content": $0.content]
        }

        // Add conversation context as prior assistant turns
        for sentence in conversationContext {
            messages.append(["role": "assistant", "content": sentence])
        }

        // The last context entry is the user prompt (tile descriptions)
        if let userPrompt = conversationContext.last {
            messages[messages.count - 1] = ["role": "user", "content": userPrompt]
        }

        var body: [String: Any] = [
            "messages": messages,
            "temperature": 0.7,
        ]

        if requestAudio {
            body["model"] = "gpt-audio-mini"
            body["modalities"] = ["text", "audio"]
            body["audio"] = ["voice": voice, "format": "mp3"]
            body["max_tokens"] = 10000
        } else {
            body["model"] = "gpt-4o-mini"
            body["max_tokens"] = 500
        }

        return body
    }

    // MARK: - Response parsing

    private func parseResponse(data: Data, requestedAudio: Bool) throws -> SentenceResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw OpenAIError.decodingError("Could not parse choices from response")
        }

        // Check for API-level error
        if let error = json["error"] as? [String: Any],
           let errorMessage = error["message"] as? String {
            throw OpenAIError.apiError(errorMessage)
        }

        var text: String?
        var audioData: Data?

        // Try audio response first
        if let audio = message["audio"] as? [String: Any] {
            text = audio["transcript"] as? String
            if let base64String = audio["data"] as? String {
                audioData = Data(base64Encoded: base64String)
            }
        }

        // Fall back to text content
        if text == nil {
            text = message["content"] as? String
        }

        guard let sentenceText = text, !sentenceText.isEmpty else {
            throw OpenAIError.decodingError("No text content in response")
        }

        // Parse usage
        let usage = parseUsage(json: json)

        return SentenceResult(
            text: sentenceText,
            audioData: audioData,
            audioFormat: audioData != nil ? "mp3" : nil,
            usage: usage
        )
    }

    private func parseUsage(json: [String: Any]) -> TokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let model = json["model"] as? String ?? "unknown"
        let promptTokens = usage["prompt_tokens"] as? Int ?? 0
        let completionTokens = usage["completion_tokens"] as? Int ?? 0
        let totalTokens = usage["total_tokens"] as? Int ?? 0

        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        let completionDetails = usage["completion_tokens_details"] as? [String: Any]

        return TokenUsage(
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            promptTextTokens: promptDetails?["text_tokens"] as? Int ?? 0,
            promptAudioTokens: promptDetails?["audio_tokens"] as? Int ?? 0,
            promptCachedTokens: promptDetails?["cached_tokens"] as? Int ?? 0,
            completionTextTokens: completionDetails?["text_tokens"] as? Int ?? 0,
            completionAudioTokens: completionDetails?["audio_tokens"] as? Int ?? 0
        )
    }
}
