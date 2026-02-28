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
    /// Must match an existing TileModel.key in the vocabulary.
    let key: String
    /// Whether tapping adds the tile to the sentence tray.
    let isAudible: Bool
    /// If non-empty, tapping navigates to the page with this key.
    let link: String
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
}

/// Raw AI response for a page (includes optional sub-pages via `newPages`).
struct GeneratedPageResponse: Codable {
    let key: String
    let tiles: [GeneratedTile]
    let newPages: [GeneratedPage]
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
