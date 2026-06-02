// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BlasterScene.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class BlasterScene {
    var id: String = UUID().uuidString
    var name: String = ""
    var descriptionText: String = ""
    var homePageKey: String = "home"
    var isDefault: Bool = false
    var isActive: Bool = false
    var isImported: Bool = false
    var created: Date = Date.now
    var lastModified: Date = Date.now
    /// Source URL if the scene was imported from a web link.
    var sourceURL: String = ""

    /// Non-empty for system-defined scenes backed by a bundled JSON file
    /// (e.g. "core_first"). Empty for user-created or duplicated scenes.
    /// Drives the AdminView "system scene" label and the bundle-update
    /// affordance — only a scene with a systemSceneKey can be force-refreshed
    /// from the bundle.
    var systemSceneKey: String = ""

    /// JSON-encoded [PageSpec], stored inline. Exposed via `pages` accessor.
    /// Kept as Data (not [PageSpec] direct) for CloudKit compatibility — SwiftData's
    /// CloudKit mirror is conservative about Codable arrays-as-attributes.
    private var pagesData: Data = Data()

    /// Inline page list — replaces the prior PageModel relationship. Pages are
    /// scene-scoped (their `key` is unique only within this scene). No cross-scene
    /// sharing, no SwiftData @Relationship inverse, no deletion-rule fragility.
    var pages: [PageSpec] {
        get {
            guard !pagesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([PageSpec].self, from: pagesData)) ?? []
        }
        set {
            pagesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            lastModified = .now
        }
    }

    init(name: String, descriptionText: String = "", homePageKey: String = "home",
         isDefault: Bool = false, isActive: Bool = false) {
        self.name = name
        self.descriptionText = descriptionText
        self.homePageKey = homePageKey
        self.isDefault = isDefault
        self.isActive = isActive
    }

    // MARK: - Page mutations (helpers for editor views)

    /// Append a tile to the page with `pageKey`. No-op if the page doesn't exist.
    func appendTile(_ entry: TileEntry, toPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        pages[idx].tiles.append(entry)
        self.pages = pages
    }

    /// Remove every tile matching `key` from page `pageKey`.
    func removeTile(withKey key: String, fromPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        pages[idx].tiles.removeAll { $0.key == key }
        self.pages = pages
    }

    /// Reorder a tile within a page.
    func moveTile(from source: Int, to destination: Int, inPage pageKey: String) {
        var pages = self.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        guard source != destination,
              pages[idx].tiles.indices.contains(source),
              pages[idx].tiles.indices.contains(destination) else { return }
        let moved = pages[idx].tiles.remove(at: source)
        pages[idx].tiles.insert(moved, at: destination)
        self.pages = pages
    }

    /// Find a page by key in this scene.
    func page(withKey key: String) -> PageSpec? {
        pages.first { $0.key == key }
    }

    /// Activate this scene, deactivating any other active scene in the context.
    func activate(context: ModelContext) throws {
        let allScenes = try context.fetch(FetchDescriptor<BlasterScene>())
        for scene in allScenes where scene.isActive {
            scene.isActive = false
        }
        self.isActive = true
    }

    /// Deactivate this scene and restore the default scene.
    func deactivateAndRestoreDefault(context: ModelContext) throws {
        self.isActive = false
        let defaultScenes = try context.fetch(
            FetchDescriptor<BlasterScene>(predicate: #Predicate { $0.isDefault })
        )
        if let defaultScene = defaultScenes.first {
            defaultScene.isActive = true
        }
    }

    // MARK: - Duplicate

    /// Create a peer copy of `source`. The new scene is inserted into `context`
    /// and returned.
    ///
    /// Conventions:
    /// - name: "duplicate-of:{source.name}" with a "-2", "-3", … suffix if
    ///   that name is already taken (collision avoidance).
    /// - description: "duplicated from {source.name}::{ISO8601 source.created}"
    ///   so provenance survives even if the source is later renamed or deleted.
    /// - created: now.
    /// - isDefault / isActive / isImported: false (a fresh duplicate is never
    ///   the active scene and is never marked as the default).
    /// - systemSceneKey: empty. Duplicates of a system scene are user-owned
    ///   copies; they're not protected by the force-refresh path and won't
    ///   be touched by bundled updates.
    /// - pages: deep copy of the source's PageSpec list.
    @discardableResult
    static func duplicate(of source: BlasterScene, in context: ModelContext) -> BlasterScene {
        let baseName = "duplicate-of:\(source.name)"
        let existingNames: Set<String> = (try? context.fetch(FetchDescriptor<BlasterScene>()))
            .map { Set($0.map(\.name)) } ?? []
        var candidate = baseName
        var n = 2
        while existingNames.contains(candidate) {
            candidate = "\(baseName)-\(n)"
            n += 1
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let originStamp = iso.string(from: source.created)

        let copy = BlasterScene(
            name: candidate,
            descriptionText: "duplicated from \(source.name)::\(originStamp)",
            homePageKey: source.homePageKey,
            isDefault: false,
            isActive: false
        )
        copy.pages = source.pages  // deep copy via Codable round-trip in the setter
        context.insert(copy)
        return copy
    }
}
