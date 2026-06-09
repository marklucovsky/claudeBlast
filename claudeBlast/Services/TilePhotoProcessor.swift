// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePhotoProcessor.swift
//  claudeBlast
//
//  Downscale + compress a caregiver-supplied photo into a CloudKit-safe blob
//  for TileModel.userImageData. CloudKit silently stops syncing records that
//  exceed ~1MB, so a tile's photo is hard-capped well under that ceiling.
//
//  The caregiver first picks a 1:1 region in SquareImageCropper (which
//  normalizes orientation up front); this step is the final, orientation-free
//  downscale + compress on that already-square, already-upright crop.
//

import Foundation
import UIKit

enum TilePhotoProcessor {
    /// Longest-edge cap. Tiles render small; 512px is plenty and matches the
    /// scene-export resize so a photo round-trips through export unchanged.
    static let maxDimension: CGFloat = 512

    /// Encoded-byte budget. TileModel's other fields are a few short strings, so
    /// 400KB keeps the whole record comfortably under CloudKit's ~1MB limit even
    /// accounting for storage overhead.
    static let maxBytes = 400 * 1024

    enum ProcessError: LocalizedError {
        case tooLargeAfterCompression

        var errorDescription: String? {
            switch self {
            case .tooLargeAfterCompression:
                return "This photo is too detailed to store safely. Try a simpler or more cropped image."
            }
        }
    }

    /// Downscale `image` to within `maxDimension`, then JPEG-compress in a
    /// quality loop until the result is ≤ `maxBytes`. Redrawing through a
    /// renderer also bakes in `imageOrientation`, so the stored bytes are
    /// upright regardless of the source EXIF orientation.
    ///
    /// - Throws: `ProcessError.tooLargeAfterCompression` if even the lowest
    ///   quality exceeds the budget (rare at 512px / JPEG).
    static func process(_ image: UIImage) throws -> Data {
        let resized = downscaled(image, maxDimension: maxDimension)
        for quality in [0.8, 0.6, 0.4, 0.2] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        throw ProcessError.tooLargeAfterCompression
    }

    /// Resize so the longest edge is ≤ `maxDimension`, preserving aspect ratio.
    /// Returns the original if it already fits. Mirrors SceneExporter's resize.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
