// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneExporter.swift
//  claudeBlast
//
//  Exports a BlasterScene to the portable JSON exchange format.
//

import Foundation
import UIKit

enum SceneExporter {

    /// Convert a BlasterScene into an ExportableScene struct.
    static func export(_ scene: BlasterScene, defaultTileKeys: Set<String> = []) -> ExportableScene {
        var exportTiles: [ExportableTile] = []
        var seenTileKeys = Set<String>()

        let exportPages: [ExportablePage] = scene.pages.map { page in
            let pageTiles = page.orderedTiles.map { pt -> ExportablePageTile in
                let tile = pt.tile

                // Collect tiles that are not in the default vocabulary or have custom images
                if seenTileKeys.insert(tile.key).inserted {
                    let isCustom = !defaultTileKeys.contains(tile.key)
                    let hasCustomImage = tile.userImageData != nil

                    if isCustom || hasCustomImage {
                        let imageBase64 = encodeImage(tile.userImageData)
                        exportTiles.append(ExportableTile(
                            key: tile.key,
                            wordClass: tile.wordClass,
                            displayName: tile.displayName,
                            imageData: imageBase64
                        ))
                    }
                }

                return ExportablePageTile(
                    key: tile.key,
                    isAudible: pt.isAudible,
                    link: pt.link
                )
            }
            return ExportablePage(key: page.displayName, tiles: pageTiles)
        }

        return ExportableScene(
            type: BlasterSceneFormat.mediaType,
            version: BlasterSceneFormat.currentVersion,
            name: scene.name,
            description: scene.descriptionText,
            homePageKey: scene.homePageKey,
            tiles: exportTiles.isEmpty ? nil : exportTiles,
            pages: exportPages
        )
    }

    /// Export a BlasterScene to pretty-printed JSON Data.
    static func exportJSON(_ scene: BlasterScene, defaultTileKeys: Set<String> = []) throws -> Data {
        let exportable = export(scene, defaultTileKeys: defaultTileKeys)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportable)
    }

    // MARK: - Image encoding

    /// Resize and base64-encode image data. Returns nil if no data or encoding fails.
    private static func encodeImage(_ imageData: Data?) -> String? {
        guard let imageData, let image = UIImage(data: imageData) else { return nil }

        let maxDim = BlasterSceneFormat.maxImageDimension
        let resized: UIImage
        if image.size.width > maxDim || image.size.height > maxDim {
            let scale = min(maxDim / image.size.width, maxDim / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            resized = image
        }

        guard let pngData = resized.pngData(),
              pngData.count <= BlasterSceneFormat.maxImageDataSize else {
            // Fall back to JPEG if PNG is too large
            guard let jpegData = resized.jpegData(compressionQuality: 0.8),
                  jpegData.count <= BlasterSceneFormat.maxImageDataSize else {
                return nil
            }
            return jpegData.base64EncodedString()
        }
        return pngData.base64EncodedString()
    }
}
