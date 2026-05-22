// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneJSON.swift
//  claudeBlast
//
//  On-disk JSON shape for bundled scenes. The SceneImporter reads these,
//  applies the embedded DSL commands against vocabulary.json, and emits
//  materialized BlasterScene + [PageSpec] for SwiftData storage.
//
//  Each entry in a page's `tiles` array is a *command*, not a literal tile
//  struct. Commands run in document order against a working tile list, so
//  later commands can observe and modify earlier ones (e.g. makeLink on a
//  key already added by selectAll converts that tile to a link in place).
//

import Foundation

/// Root of one bundled scene file (e.g. Resources/scenes/core_first.json).
struct SceneJSON: Codable {
    let key: String                 // scene identifier, e.g. "core_first"
    let name: String                // display name, e.g. "Core-First"
    let description: String?
    let homePageKey: String         // must match one of the pages' keys
    let isDefault: Bool
    let pages: [PageJSON]
}

struct PageJSON: Codable {
    let key: String
    let tiles: [PageBuildCommand]
}

/// Sum type of DSL commands applied to a page's working tile list.
/// Encoded with implicit tagging — the present key (selectAll / selectKeys /
/// makeLink / deleteTile) determines the case.
enum PageBuildCommand: Codable, Hashable {
    /// Pull all vocabulary tiles whose wordClass matches one of `classes`.
    /// Tiles are appended as audible (no link). Use exclude/limit/orderBy
    /// to refine.
    case selectAll(classes: [String], exclude: [String], limit: Int?, orderBy: OrderBy)

    /// Explicit list of vocabulary keys. Each appended as audible (no link).
    case selectKeys([String])

    /// Add or update a single tile with a link. If `key` already exists in
    /// the working list (e.g. placed earlier by selectAll), update it in
    /// place to carry the link + audible setting. Otherwise append a new
    /// tile.
    case makeLink(key: String, link: String, audible: Bool)

    /// Remove the tile with this key from the working list, if present.
    case deleteTile(String)

    enum OrderBy: String, Codable {
        case vocab   // declaration order in vocabulary.json (default)
        case name    // alphabetical by key
        case score   // future: a `score` field on vocab entries
    }

    // MARK: - Codable
    //
    // The JSON shape uses the command name as the key on the surrounding
    // object. Examples:
    //   {"selectAll": "actions"}
    //   {"selectAll": ["food","drinks"], "exclude": ["pizza"], "limit": 8, "orderBy": "name"}
    //   {"selectKeys": ["i","me","you"]}
    //   {"makeLink": "people", "link": "people", "audible": false}
    //   {"deleteTile": "stop"}

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static func k(_ s: String) -> DynamicKey { DynamicKey(stringValue: s)! }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)

        if c.contains(.k("selectAll")) {
            // Value is either a string (single class) or [String] (multi-class).
            let classes: [String]
            if let single = try? c.decode(String.self, forKey: .k("selectAll")) {
                classes = [single]
            } else {
                classes = try c.decode([String].self, forKey: .k("selectAll"))
            }
            let exclude = (try? c.decode([String].self, forKey: .k("exclude"))) ?? []
            let limit = try? c.decode(Int.self, forKey: .k("limit"))
            let orderBy: OrderBy
            if let raw = try? c.decode(String.self, forKey: .k("orderBy")),
               let parsed = OrderBy(rawValue: raw) {
                orderBy = parsed
            } else {
                orderBy = .vocab
            }
            self = .selectAll(classes: classes, exclude: exclude, limit: limit, orderBy: orderBy)
            return
        }

        if c.contains(.k("selectKeys")) {
            let keys = try c.decode([String].self, forKey: .k("selectKeys"))
            self = .selectKeys(keys)
            return
        }

        if c.contains(.k("makeLink")) {
            let key = try c.decode(String.self, forKey: .k("makeLink"))
            let link = try c.decode(String.self, forKey: .k("link"))
            let audible = try c.decode(Bool.self, forKey: .k("audible"))
            self = .makeLink(key: key, link: link, audible: audible)
            return
        }

        if c.contains(.k("deleteTile")) {
            let key = try c.decode(String.self, forKey: .k("deleteTile"))
            self = .deleteTile(key)
            return
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unknown PageBuildCommand (no recognized key)"
        ))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case .selectAll(let classes, let exclude, let limit, let orderBy):
            if classes.count == 1 {
                try c.encode(classes[0], forKey: .k("selectAll"))
            } else {
                try c.encode(classes, forKey: .k("selectAll"))
            }
            if !exclude.isEmpty { try c.encode(exclude, forKey: .k("exclude")) }
            if let limit { try c.encode(limit, forKey: .k("limit")) }
            if orderBy != .vocab { try c.encode(orderBy.rawValue, forKey: .k("orderBy")) }
        case .selectKeys(let keys):
            try c.encode(keys, forKey: .k("selectKeys"))
        case .makeLink(let key, let link, let audible):
            try c.encode(key, forKey: .k("makeLink"))
            try c.encode(link, forKey: .k("link"))
            try c.encode(audible, forKey: .k("audible"))
        case .deleteTile(let key):
            try c.encode(key, forKey: .k("deleteTile"))
        }
    }
}
