// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImporter.swift
//  claudeBlast
//
//  Imports a scene from the portable JSON exchange format into SwiftData.
//

import SwiftData
import Foundation

enum SceneImportError: LocalizedError {
    case invalidType(String)
    case unsupportedVersion(String)
    case decodingFailed(String)
    case noPages

    var errorDescription: String? {
        switch self {
        case .invalidType(let type):
            return "Not a Blaster scene file (type: \(type))"
        case .unsupportedVersion(let version):
            return "Unsupported scene format version: \(version)"
        case .decodingFailed(let detail):
            return "Could not read scene file: \(detail)"
        case .noPages:
            return "Scene has no pages"
        }
    }
}

@MainActor
enum SceneImporter {

    struct ImportResult {
        let scene: BlasterScene
        let skippedKeys: [String]
        let newTileCount: Int
        let oversizedImages: [String]  // tile keys where imageData exceeded cap
        /// Existing tiles whose image was filled or replaced — the caller should
        /// invalidate the image resolver's cache for these so they re-render.
        let imageUpdatedKeys: [String]
    }

    /// How the file's custom tiles relate to THIS device's vocabulary — used to
    /// preview the import and to drive per-word image-collision consent.
    struct ImportAnalysis {
        /// Keys not on the device — will be created.
        let newWords: [ExportableTile]
        /// On the device with NO custom image; the file carries one → auto-fill.
        let fillWords: [ExportableTile]
        /// On the device WITH a custom image, and the file carries a (different)
        /// one → needs the importer's consent; never replaced without it.
        let collisions: [ExportableTile]
    }

    /// Categorize the file's custom tiles against the device's tiles. Word
    /// identity (key/displayName/wordClass) is never changed by import; this only
    /// governs images.
    static func analyze(_ exportable: ExportableScene, deviceTiles: [TileModel]) -> ImportAnalysis {
        let lookup = Dictionary(uniqueKeysWithValues: deviceTiles.map { ($0.key, $0) })
        var newWords: [ExportableTile] = []
        var fillWords: [ExportableTile] = []
        var collisions: [ExportableTile] = []
        for tile in exportable.tiles ?? [] {
            if let existing = lookup[tile.key] {
                guard tile.imageData != nil else { continue }   // nothing to offer
                if existing.userImageData == nil { fillWords.append(tile) }
                else { collisions.append(tile) }
            } else {
                newWords.append(tile)
            }
        }
        return ImportAnalysis(newWords: newWords, fillWords: fillWords, collisions: collisions)
    }

    /// Import a scene from JSON data.
    /// - Parameters:
    ///   - data: Raw JSON data in the ExportableScene format.
    ///   - context: The ModelContext to insert new objects into.
    /// - Returns: An ImportResult with the new scene and any warnings.
    static func importJSON(_ data: Data,
                           context: ModelContext,
                           sourceURL: String = "",
                           acceptedImageCollisions: Set<String> = []) throws -> ImportResult {
        let decoder = JSONDecoder()
        let exportable: ExportableScene
        do {
            exportable = try decoder.decode(ExportableScene.self, from: data)
        } catch {
            throw SceneImportError.decodingFailed(error.localizedDescription)
        }

        // Validate type
        guard exportable.type == BlasterSceneFormat.mediaType else {
            throw SceneImportError.invalidType(exportable.type)
        }

        // Validate version (accept any 1.x.x)
        guard exportable.version.hasPrefix("1.") else {
            throw SceneImportError.unsupportedVersion(exportable.version)
        }

        guard !exportable.pages.isEmpty else {
            throw SceneImportError.noPages
        }

        // Fetch existing tiles + categorize the file's custom tiles.
        let deviceTiles = try context.fetch(FetchDescriptor<TileModel>())
        var tileLookup = Dictionary(uniqueKeysWithValues: deviceTiles.map { ($0.key, $0) })
        let analysis = analyze(exportable, deviceTiles: deviceTiles)

        var newTileCount = 0
        var oversizedImages: [String] = []
        var imageUpdatedKeys: [String] = []

        // Decode a tile's image if present and within the size cap.
        func decodedImage(_ tile: ExportableTile) -> Data? {
            guard let base64 = tile.imageData, let decoded = Data(base64Encoded: base64) else { return nil }
            guard decoded.count <= BlasterSceneFormat.maxImageDataSize else {
                oversizedImages.append(tile.key)
                return nil
            }
            return decoded
        }

        // 1. New words → create the tile (with image if carried).
        for incoming in analysis.newWords {
            let tile = TileModel(key: incoming.key, value: incoming.displayName, wordClass: incoming.wordClass)
            if let image = decodedImage(incoming) { tile.userImageData = image }
            context.insert(tile)
            tileLookup[tile.key] = tile
            newTileCount += 1
        }

        // 2. Fill-if-empty → existing tile has no image; apply the shared one.
        for incoming in analysis.fillWords {
            guard let tile = tileLookup[incoming.key], let image = decodedImage(incoming) else { continue }
            tile.userImageData = image
            imageUpdatedKeys.append(incoming.key)
        }

        // 3. Collisions → only replace where the importer consented. Word
        //    identity is never touched.
        for incoming in analysis.collisions where acceptedImageCollisions.contains(incoming.key) {
            guard let tile = tileLookup[incoming.key], let image = decodedImage(incoming) else { continue }
            tile.userImageData = image
            imageUpdatedKeys.append(incoming.key)
        }

        // Build pages as inline PageSpec values. Tiles missing from the import
        // are reported in `skippedKeys` and dropped from their page.
        var skippedKeys: [String] = []
        let pages: [PageSpec] = exportable.pages.map { exportPage in
            let tiles: [TileEntry] = exportPage.tiles.compactMap { exportTile in
                guard tileLookup[exportTile.key] != nil else {
                    if !skippedKeys.contains(exportTile.key) {
                        skippedKeys.append(exportTile.key)
                    }
                    return nil
                }
                return TileEntry(
                    key: exportTile.key,
                    link: exportTile.link,
                    isAudible: exportTile.isAudible
                )
            }
            return PageSpec(key: exportPage.key, tiles: tiles)
        }

        let scene = BlasterScene(
            name: exportable.name,
            descriptionText: exportable.description,
            homePageKey: exportable.homePageKey,
            isDefault: false,
            isActive: false
        )
        scene.isImported = true
        scene.sourceURL = sourceURL
        scene.pages = pages

        try context.transaction {
            context.insert(scene)
        }

        return ImportResult(
            scene: scene,
            skippedKeys: skippedKeys,
            newTileCount: newTileCount,
            oversizedImages: oversizedImages,
            imageUpdatedKeys: imageUpdatedKeys
        )
    }

    /// Parse ExportableScene from JSON data without importing — for preview purposes.
    static func preview(_ data: Data) throws -> ExportableScene {
        let decoder = JSONDecoder()
        let exportable: ExportableScene
        do {
            exportable = try decoder.decode(ExportableScene.self, from: data)
        } catch {
            throw SceneImportError.decodingFailed(error.localizedDescription)
        }
        guard exportable.type == BlasterSceneFormat.mediaType else {
            throw SceneImportError.invalidType(exportable.type)
        }
        guard exportable.version.hasPrefix("1.") else {
            throw SceneImportError.unsupportedVersion(exportable.version)
        }
        return exportable
    }
}
