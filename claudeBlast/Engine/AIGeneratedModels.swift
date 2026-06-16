// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AIGeneratedModels.swift
//  claudeBlast
//
//  Shared Codable structs used by SceneGeneratorService and PageGeneratorService.
//

import Foundation

/// A single tile suggested by AI.
struct GeneratedTile: Codable {
    /// For existing tiles, an existing TileModel.key. For a proposed NEW word,
    /// the normalized key derived from `displayName` (see the service parsers).
    let key: String
    /// Whether tapping adds the tile to the sentence tray.
    let isAudible: Bool
    /// If non-empty, tapping navigates to the page with this key.
    let link: String
    /// Present only for a proposed NEW word (not yet in vocabulary). Together
    /// with `wordClass`, this is what lets the word be materialized on Accept.
    var displayName: String? = nil
    /// Word class for a proposed NEW word (one of VocabularyClasses).
    var wordClass: String? = nil

    /// A proposed new word carries both `displayName` and `wordClass`.
    var isProposedNew: Bool { displayName != nil && wordClass != nil }
}

/// A new vocabulary word the AI declares ONCE in the response's `newWords`
/// array (rather than inlining metadata per tile — gpt-4o-mini does that
/// unreliably). Page tiles reference it by `key`.
struct GeneratedNewWord: Codable {
    let key: String
    let displayName: String
    let wordClass: String
}

extension GeneratedNewWord {
    /// Build a normalized-key → new word map. The map key is normalized so page
    /// tiles resolve regardless of the model's casing/spacing.
    ///
    /// We keep words whose wordClass isn't a known VocabularyClass rather than
    /// dropping them: the model occasionally reaches for a sensible-but-untaxon­
    /// omized class (e.g. "plant" for seaweed, "tools" for a bucket), and a tile
    /// with a neutral tint plus a good image-gen sense hint beats a silently
    /// missing word. Only entries with an empty key or class are skipped.
    static func lookup(from words: [GeneratedNewWord]?) -> [String: GeneratedNewWord] {
        var map: [String: GeneratedNewWord] = [:]
        for word in words ?? [] {
            guard !word.wordClass.isEmpty else { continue }
            let source = word.displayName.isEmpty ? word.key : word.displayName
            let key = TileModel.normalizeKey(source)
            guard !key.isEmpty else { continue }
            map[key] = word
        }
        return map
    }
}

extension GeneratedTile {
    /// Resolve a raw AI page tile against the existing vocabulary and the
    /// declared `newWords`. Shared by the scene and page generators.
    /// - key already in vocab → existing reference.
    /// - key declared in `newWords` → new word (carries displayName + wordClass).
    /// - else (hallucinated key, not declared) → nil (dropped).
    static func sanitize(_ tile: GeneratedTile,
                         validKeys: Set<String>,
                         newWords: [String: GeneratedNewWord]) -> GeneratedTile? {
        if validKeys.contains(tile.key) {
            return GeneratedTile(key: tile.key, isAudible: tile.isAudible, link: tile.link)
        }
        let key = TileModel.normalizeKey(tile.key)
        if validKeys.contains(key) {
            return GeneratedTile(key: key, isAudible: tile.isAudible, link: tile.link)
        }
        if let word = newWords[key] {
            let displayName = word.displayName.isEmpty
                ? key.replacingOccurrences(of: "_", with: " ")
                : word.displayName
            return GeneratedTile(key: key, isAudible: tile.isAudible, link: tile.link,
                                 displayName: displayName, wordClass: word.wordClass)
        }
        return nil
    }
}

/// A page (possibly a sub-page) suggested by AI.
struct GeneratedPage: Codable {
    /// Unique key for this page (snake_case, lowercase).
    let key: String
    let tiles: [GeneratedTile]
}

/// A full scene suggested by AI.
struct GeneratedScene: Codable {
    let name: String
    let description: String
    /// Must match the key of one of the pages below.
    let homePageKey: String
    let pages: [GeneratedPage]
    /// New words declared by the AI (decoded from the raw response). nil on the
    /// sanitized scene returned to callers — by then the metadata lives on the
    /// individual tiles.
    var newWords: [GeneratedNewWord]? = nil
}

/// Raw AI response for a page (includes optional sub-pages via `newPages`).
struct GeneratedPageResponse: Codable {
    let key: String
    let tiles: [GeneratedTile]
    let newPages: [GeneratedPage]
    var newWords: [GeneratedNewWord]? = nil
}

/// Result returned by PageGeneratorService — a primary page plus optional sub-pages.
struct GeneratedPageResult {
    let primaryPage: GeneratedPage
    /// Sub-pages referenced by nav tiles in the primary page.
    let subPages: [GeneratedPage]

    /// Tile keys for the primary page (for pre-selecting in TilePickerView Edit path).
    var primaryTileKeys: Set<String> {
        Set(primaryPage.tiles.map(\.key))
    }
}
