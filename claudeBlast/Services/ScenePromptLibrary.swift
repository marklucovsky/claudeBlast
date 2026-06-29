// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import Foundation
import SwiftData

/// A bundled, pre-verified "starter scene" offered in the scene builder. Loading
/// an UNCHANGED starter imports its cached bundle instantly ($0, no API key);
/// editing the prompt runs a live AI generation pass instead. Each starter seeds
/// a few new vocabulary words with bundled art and intentionally leaves one word
/// imageless so the caregiver can try the new-word image-generation flow once.
struct StarterScene: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let blurb: String
    /// The canonical example prompt. An exact (trimmed) match means "unchanged"
    /// → serve the cached bundle instead of calling the API.
    let prompt: String
    /// Bundle resource base name (e.g. "starter_farm"); the file is "<bundle>.json".
    let bundle: String
    /// New words shipped without art (the image-gen demo words).
    let imagelessWords: [String]

    /// The raw bundled .blasterscene JSON for this starter, if present.
    func bundleData() -> Data? {
        guard let url = Bundle.main.url(forResource: bundle, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}

enum StarterSceneCatalog {
    /// Decoded once at first access. Empty if the manifest is missing or malformed
    /// — the builder hides the "Start from an example" section in that case.
    static let all: [StarterScene] = {
        guard let url = Bundle.main.url(forResource: "starter_scenes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StarterScene].self, from: data)
        else { return [] }
        return decoded
    }()

    /// The starter whose canonical prompt exactly matches `text` (trimmed), if any.
    /// Used to decide cache-vs-live at Generate time.
    static func matching(_ text: String) -> StarterScene? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return all.first { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == needle }
    }
}

extension StarterScene {
    /// Bundled per-key art sidecar: Resources/starterart_<key>.png. The bundle
    /// JSON stays human-readable by keeping art out of it.
    static func artData(for key: String) -> Data? {
        guard let url = Bundle.main.url(forResource: "starterart_\(key)", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Decode the readable bundle into a GeneratedScene for the shared Scene
    /// Preview, plus a key→art map loaded from the sidecars so the new (not-yet-
    /// imported) tiles show their pictures. Accept then imports via `importBundle`.
    func loadPreview() -> (scene: GeneratedScene, images: [String: Data])? {
        guard let data = bundleData(),
              let exportable = try? JSONDecoder().decode(ExportableScene.self, from: data)
        else { return nil }

        var meta: [String: (displayName: String, wordClass: String)] = [:]
        var images: [String: Data] = [:]
        for tile in exportable.tiles ?? [] {
            meta[tile.key] = (tile.displayName, tile.wordClass)
            if let art = Self.artData(for: tile.key) { images[tile.key] = art }
        }

        let pages = exportable.pages.map { page in
            GeneratedPage(key: page.key, tiles: page.tiles.map { pt in
                if let m = meta[pt.key] {
                    return GeneratedTile(key: pt.key, isAudible: pt.isAudible, link: pt.link,
                                         displayName: m.displayName, wordClass: m.wordClass)
                }
                return GeneratedTile(key: pt.key, isAudible: pt.isAudible, link: pt.link)
            })
        }
        let scene = GeneratedScene(name: exportable.name, description: exportable.description,
                                   homePageKey: exportable.homePageKey, pages: pages)
        return (scene, images)
    }

    /// Import the bundled starter into `context`, attaching each new word's art
    /// from its sidecar (re-encoded inline so the standard SceneImporter path is
    /// reused unchanged). Returns the created scene.
    func importBundle(context: ModelContext) -> BlasterScene? {
        guard let data = bundleData(),
              var exportable = try? JSONDecoder().decode(ExportableScene.self, from: data)
        else { return nil }

        var tiles = exportable.tiles ?? []
        for i in tiles.indices {
            if let art = Self.artData(for: tiles[i].key) {
                tiles[i].imageData = art.base64EncodedString()
            }
        }
        exportable.tiles = tiles

        guard let encoded = try? JSONEncoder().encode(exportable),
              let result = try? SceneImporter.importJSON(encoded, context: context,
                                                         sourceURL: "starter:\(id)")
        else { return nil }
        return result.scene
    }
}
