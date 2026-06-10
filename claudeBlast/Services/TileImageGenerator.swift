// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageGenerator.swift
//  claudeBlast
//
//  Generate a first-pass tile image for a word via the OpenAI images API, styled
//  to match the ACTIVE image set so a generated tile sits alongside the bundled
//  ones (Playful 3D clay, High Contrast, or the flat ARASAAC-style pictogram).
//  The style strings are ported from tools/generate_sets.py so in-app generation
//  matches the offline tile-set workflow. The result is just another source of
//  TileModel.userImageData — callers run it through TilePhotoProcessor and store
//  it like a photo, so it renders everywhere via TileImageResolver and syncs.
//

import Foundation
import UIKit

enum TileImageGenerator {
    /// OpenAI images model. `gpt-image-1` is the current model (dall-e-3 is
    /// retired on the images endpoint). It always returns base64 and does NOT
    /// accept `response_format`; `quality` is low/medium/high/auto (not dall-e-3's
    /// standard/hd). Swap here to change the model later.
    private static let model = "gpt-image-1"
    private static let quality = "medium" // low | medium | high | auto

    /// Generate a square (1024²) image for a word, styled to `imageSet`. Caller
    /// downscales/compresses via TilePhotoProcessor before storing. Throws
    /// OpenAIError on failure.
    /// Soft cap on the optional refinement detail (e.g. "purple tail and mane").
    static let maxDetailLength = 120
    /// Show the character counter only within the last 20% of the cap.
    static var detailCounterThreshold: Int { maxDetailLength * 4 / 5 }

    static func generate(displayName: String,
                         wordClass: String,
                         imageSet: ImageSetID,
                         detail: String = "",
                         apiKey: String) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        // Note: no `response_format` — OpenAI removed it from the images endpoint.
        // The response is handled for either base64 (default now) or a URL.
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt(displayName: displayName, wordClass: wordClass, imageSet: imageSet, detail: detail),
            "size": "1024x1024",
            "quality": quality,
            "n": 1,
        ]

        let url = URL(string: "https://api.openai.com/v1/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60 // image generation is slow (~10-20s)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            // Surface OpenAI's structured error message (e.g. content policy,
            // model access, invalid parameter) rather than the raw body.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try await decodeImage(data: data)
    }

    /// Build the prompt as `<style> Subject: <word> (<class>).` — mirroring
    /// tools/generate_sets.py `build_prompt`. The word class is a sense hint so
    /// ambiguous words resolve correctly (e.g. "snack bar (food)" → a granola bar,
    /// "snack bar (place)" → a building).
    private static func prompt(displayName: String, wordClass: String, imageSet: ImageSetID, detail: String) -> String {
        let base = "\(style(for: imageSet)) Subject: \(displayName) (\(wordClass))."
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : "\(base) \(trimmed)."
    }

    /// Style prefix per image set. Loaded from the shared `image_styles.json`
    /// (the single source of truth, also read by tools/generate_sets.py) so
    /// in-app generation matches the offline tile-set art. Falls back to a short
    /// built-in style only if the bundled file is missing/corrupt.
    private static func style(for imageSet: ImageSetID) -> String {
        // ImageSetID raw values (arasaac / playful_3d / high_contrast) are the
        // JSON keys.
        loadedStyles[imageSet.rawValue] ?? fallbackStyle(for: imageSet)
    }

    /// Decoded `image_styles.json` (key → style prefix), loaded once.
    private static let loadedStyles: [String: String] = {
        guard let url = Bundle.main.url(forResource: "image_styles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }()

    /// Minimal graceful-degradation styles if the JSON is unavailable. The
    /// authoritative long versions live in image_styles.json — keep these short.
    private static func fallbackStyle(for imageSet: ImageSetID) -> String {
        switch imageSet {
        case .playful3D:
            return "3D clay/plasticine sculpture, soft rounded shapes, pastel-bright colors, clean solid-color background, no text. Square format, single clear subject centered."
        case .highContrast:
            return "High-contrast pictogram: one bold white subject on a pure solid black background, thick clean lines, no frame, no border, no text. Square format, subject centered."
        case .arasaac:
            return "Flat 2D AAC pictogram, bold clean outlines, bright saturated solid colors, white background, no text. Square format, single clear subject centered."
        }
    }

    private static func decodeImage(data: Data) async throws -> UIImage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.decodingError("Response was not JSON")
        }
        // Surface a structured API error if present (content policy, access, etc.)
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw OpenAIError.apiError(message)
        }
        guard let first = (json["data"] as? [[String: Any]])?.first else {
            throw OpenAIError.decodingError("No image in response")
        }
        // Inline base64 (current default)…
        if let b64 = first["b64_json"] as? String,
           let imgData = Data(base64Encoded: b64),
           let image = UIImage(data: imgData) {
            return image
        }
        // …or a URL to fetch.
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (imgData, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: imgData) { return image }
        }
        throw OpenAIError.decodingError("No image in response")
    }
}
