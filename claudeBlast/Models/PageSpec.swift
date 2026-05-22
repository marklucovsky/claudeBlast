// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageSpec.swift
//  claudeBlast
//
//  Codable inline page + tile types that will replace the PageModel /
//  PageTileModel SwiftData entities. Stored as an array attribute on
//  BlasterScene; no relationships, no cross-scene sharing fragility.
//
//  This is the *materialized* form (post-DSL-expansion). The on-disk
//  JSON shape — which carries DSL commands like {"selectAll": "actions"} —
//  lives in SceneJSON.swift. The SceneImporter (TBD) converts SceneJSON
//  → [PageSpec] at bootstrap time.
//

import Foundation

/// A page within a scene. `key` is scene-scoped — two scenes can both have
/// a page keyed "home" with no global collision.
struct PageSpec: Codable, Hashable, Identifiable {
    var id: String { key }
    var key: String
    var tiles: [TileEntry]
}

/// A single tile placement on a page. The vocabulary key identifies the
/// underlying TileModel (which still holds display name + wordClass).
///
/// `link`:
///   - empty string → terminal tile (audible only)
///   - a page key → navigate to that page within the same scene
///   - "<home>" → magic link; resolves to the active scene's homePageKey
///                at navigation time
struct TileEntry: Codable, Hashable, Identifiable {
    var id: String { key }
    var key: String
    var link: String
    var isAudible: Bool

    init(key: String, link: String = "", isAudible: Bool = true) {
        self.key = key
        self.link = link
        self.isAudible = isAudible
    }
}
