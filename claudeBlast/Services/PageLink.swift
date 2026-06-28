// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftData
import Foundation

/// A `page_link` tile is a silent navigation tile that points to a named page
/// collection. Its key encodes the target page, so the tile can be dropped on
/// any board and resolve to a link. Every page mints one when it's created,
/// encouraging reuse of named tile collections (pages).
enum PageLink {
    static let wordClass = "page_link"
    private static let prefix = "page_"

    /// Stable tile key for the page-link tile of `pageKey` ("space" → "page_space").
    static func key(forPage pageKey: String) -> String { prefix + pageKey }

    /// The page a page-link tile navigates to (inverse of `key(forPage:)`), or nil
    /// if `key` isn't a page-link key.
    static func targetPage(forKey key: String) -> String? {
        key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
    }

    /// Find or mint the page-link tile for `pageKey`. Idempotent: returns the
    /// existing tile if present (filling in art if it had none). `image`, when
    /// given, becomes the icon; otherwise the tile renders the placeholder until
    /// art is generated.
    @discardableResult
    static func mint(pageKey: String,
                     displayName: String,
                     image: Data? = nil,
                     context: ModelContext,
                     existing: [String: TileModel]) -> TileModel {
        let k = key(forPage: pageKey)
        if let tile = existing[k] {
            if let image, tile.userImageData == nil { tile.userImageData = image }
            return tile
        }
        let tile = TileModel(key: k, value: displayName, wordClass: wordClass)
        tile.isSystem = false
        if let image { tile.userImageData = image }
        context.insert(tile)
        return tile
    }
}
