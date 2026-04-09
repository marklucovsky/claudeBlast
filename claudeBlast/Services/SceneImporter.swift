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
    }

    /// Import a scene from JSON data.
    /// - Parameters:
    ///   - data: Raw JSON data in the ExportableScene format.
    ///   - context: The ModelContext to insert new objects into.
    /// - Returns: An ImportResult with the new scene and any warnings.
    static func importJSON(_ data: Data, context: ModelContext, sourceURL: String = "") throws -> ImportResult {
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

        // Fetch existing tiles
        let allTiles = try context.fetch(FetchDescriptor<TileModel>())
        var tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

        // Merge new tiles from the tiles array
        var newTileCount = 0
        var oversizedImages: [String] = []

        if let incomingTiles = exportable.tiles {
            for incoming in incomingTiles {
                // Device wins — skip if key already exists
                guard tileLookup[incoming.key] == nil else { continue }

                let tile = TileModel(
                    key: incoming.key,
                    value: incoming.displayName,
                    wordClass: incoming.wordClass
                )

                // Decode optional image data
                if let base64 = incoming.imageData,
                   let decoded = Data(base64Encoded: base64) {
                    if decoded.count <= BlasterSceneFormat.maxImageDataSize {
                        tile.userImageData = decoded
                    } else {
                        oversizedImages.append(incoming.key)
                    }
                }

                context.insert(tile)
                tileLookup[tile.key] = tile
                newTileCount += 1
            }
        }

        // Build pages
        var skippedKeys: [String] = []
        var allPageTiles: [PageTileModel] = []
        var pages: [PageModel] = []

        for exportPage in exportable.pages {
            var pageTiles: [PageTileModel] = []
            for exportTile in exportPage.tiles {
                guard let tile = tileLookup[exportTile.key] else {
                    if !skippedKeys.contains(exportTile.key) {
                        skippedKeys.append(exportTile.key)
                    }
                    continue
                }
                let pt = PageTileModel(
                    tile: tile,
                    link: exportTile.link,
                    isAudible: exportTile.isAudible
                )
                pageTiles.append(pt)
            }
            let page = PageModel.make(
                displayName: exportPage.key,
                tiles: pageTiles,
                tileOrder: pageTiles.map(\.id)
            )
            pages.append(page)
            allPageTiles.append(contentsOf: pageTiles)
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
            for pt in allPageTiles { context.insert(pt) }
            for page in pages { context.insert(page) }
            context.insert(scene)
        }

        return ImportResult(
            scene: scene,
            skippedKeys: skippedKeys,
            newTileCount: newTileCount,
            oversizedImages: oversizedImages
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
