// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftData
import Foundation

/// A bundled, pre-verified "page sample" — a tight single page of topical tiles
/// (Space, Dinosaurs, Vehicles) offered in the Add-Page flow. Loading an unedited
/// sample imports its bundle instantly ($0, no key); editing the goal runs live AI.
struct PageSample: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let goal: String
    let bundle: String
    let iconKey: String
}

enum PageSampleCatalog {
    static let all: [PageSample] = {
        guard let url = Bundle.main.url(forResource: "page_samples", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PageSample].self, from: data)
        else { return [] }
        return decoded
    }()

    /// The sample whose canonical goal exactly matches `goal` (trimmed), if any.
    static func matching(_ goal: String) -> PageSample? {
        let needle = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return all.first { $0.goal.trimmingCharacters(in: .whitespacesAndNewlines) == needle }
    }
}

private struct PageBundle: Decodable {
    struct Tile: Decodable { let key: String; let wordClass: String; let displayName: String }
    let pageKey: String
    let title: String
    let iconKey: String
    let tiles: [Tile]
    let page: [String]
}

extension PageSample {
    private func loadBundle() -> PageBundle? {
        guard let url = Bundle.main.url(forResource: bundle, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PageBundle.self, from: data)
        else { return nil }
        return decoded
    }

    /// Build a GeneratedPageResult for the shared Page Preview, plus a key→art map
    /// (from sidecars) so the new, not-yet-imported tiles show their pictures.
    /// Accept then imports via `importPage`.
    func loadPreview() -> (result: GeneratedPageResult, images: [String: Data])? {
        guard let b = loadBundle() else { return nil }
        var meta: [String: (name: String, wordClass: String)] = [:]
        for t in b.tiles where t.key != b.iconKey {
            meta[t.key] = (t.displayName, t.wordClass)
        }
        var images: [String: Data] = [:]
        for key in b.page where meta[key] != nil {
            if let art = StarterScene.artData(for: key) { images[key] = art }
        }
        let tiles = b.page.map { key -> GeneratedTile in
            if let m = meta[key] {
                return GeneratedTile(key: key, isAudible: true, link: "",
                                     displayName: m.name, wordClass: m.wordClass)
            }
            return GeneratedTile(key: key, isAudible: true, link: "")
        }
        let result = GeneratedPageResult(primaryPage: GeneratedPage(key: b.pageKey, tiles: tiles),
                                         subPages: [])
        return (result, images)
    }

    /// Import this cached page into `scene`: create its topical new tiles (with
    /// bundled sidecar art), append the tight page, and mint the page_link tile
    /// (with the bundled thematic icon). Existing-vocab keys are referenced.
    /// Returns the created page key (deduped if the scene already has it).
    @discardableResult
    func importPage(into scene: BlasterScene, context: ModelContext, allTiles: [TileModel]) -> String? {
        guard let b = loadBundle() else { return nil }
        var lookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

        // Topical new words (skip the page_link icon tile — minted below).
        for t in b.tiles where t.key != b.iconKey && lookup[t.key] == nil {
            let tile = TileModel(key: t.key, value: t.displayName, wordClass: t.wordClass)
            tile.isSystem = false
            if let art = StarterScene.artData(for: t.key) { tile.userImageData = art }
            context.insert(tile)
            lookup[t.key] = tile
        }

        // Dedupe the page key within the scene.
        var pageKey = b.pageKey
        var n = 2
        while scene.pages.contains(where: { $0.key == pageKey }) {
            pageKey = "\(b.pageKey)_\(n)"; n += 1
        }

        var pages = scene.pages
        let tiles: [TileEntry] = b.page.compactMap { key in
            lookup[key] != nil ? TileEntry(key: key, link: "", isAudible: true) : nil
        }
        pages.append(PageSpec(key: pageKey, tiles: tiles))
        scene.pages = pages
        if scene.homePageKey.isEmpty { scene.homePageKey = pageKey }

        // Mint the reusable page_link tile with the bundled thematic icon.
        PageLink.mint(pageKey: pageKey, displayName: b.title,
                      image: StarterScene.artData(for: b.iconKey),
                      context: context, existing: lookup)
        return pageKey
    }
}
