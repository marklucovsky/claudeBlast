// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageResolver.swift
//  claudeBlast
//
//  Centralized tile image resolution with support for multiple image sets.
//  Injected as an environment object; all tile image rendering flows through here.

import SwiftUI
import UIKit
import Observation

// MARK: - Image Set Identifier

enum ImageSetID: String, CaseIterable, Identifiable {
    case arasaac = "arasaac"
    case playful3D = "playful_3d"
    case highContrast = "high_contrast"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arasaac: return "Classic (ARASAAC)"
        case .playful3D: return "Playful 3D"
        case .highContrast: return "High Contrast"
        }
    }

    var description: String {
        switch self {
        case .arasaac: return "Original pictogram style"
        case .playful3D: return "Modern clay/plasticine 3D style"
        case .highContrast: return "Bold white-on-black accessibility style"
        }
    }
}

// MARK: - Tile Image Resolver

@Observable
@MainActor
final class TileImageResolver {

    /// The currently active image set. Changing this causes all tiles to re-render.
    var activeSet: ImageSetID = .arasaac

    /// In-memory cache for non-asset-catalog images (keyed by "setID:tileKey").
    private var cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 600 // ~500 tiles + headroom
    }

    /// Resolve a UIImage for the given tile key in the active image set.
    /// Returns nil if the tile has no image in the active set (sparse set support).
    func image(for key: String) -> UIImage? {
        image(for: key, in: activeSet)
    }

    /// Resolve a UIImage for the given tile key in a specific image set.
    func image(for key: String, in imageSet: ImageSetID) -> UIImage? {
        switch imageSet {
        case .arasaac:
            // ARASAAC images live in Assets.xcassets — UIKit caches these internally.
            return UIImage(named: key)

        case .playful3D:
            return prefixedBundleImage(for: key, prefix: "p3d")

        case .highContrast:
            return prefixedBundleImage(for: key, prefix: "hc")
        }
    }

    /// Check whether a tile has an image in the active set.
    func hasImage(for key: String) -> Bool {
        image(for: key) != nil
    }

    // MARK: - Private

    /// Load a prefixed image from the bundle root ({prefix}_{key}.png).
    /// Non-asset-catalog images land at the bundle root with the synchronized group build system.
    /// Uses NSCache to avoid repeated disk reads.
    ///
    /// Fallback chain: if {prefix}_{key}.png is missing AND the prefix has a
    /// registered missing-image placeholder (currently only `hc` →
    /// `hc_missing.png`), return the placeholder. This lets us ship sparse
    /// sets without forcing every new tile through bespoke art generation.
    private func prefixedBundleImage(for key: String, prefix: String) -> UIImage? {
        let resourceName = "\(prefix)_\(key)"
        let cacheKey = NSString(string: resourceName)

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            cache.setObject(img, forKey: cacheKey)
            return img
        }

        // Per-set placeholder fallback. Cache under the same cacheKey so each
        // missing tile pays the disk read once; subsequent lookups for the
        // same tile hit the cache without reloading the placeholder PNG.
        if let placeholderName = Self.missingPlaceholderName(for: prefix),
           let url = Bundle.main.url(forResource: placeholderName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            cache.setObject(img, forKey: cacheKey)
            return img
        }

        return nil
    }

    /// Per-prefix missing-image placeholder name (without `.png`).
    /// Currently only the high-contrast set has a shared placeholder; the
    /// other sets fall through to TileImageView's letter-on-color rendering.
    private static func missingPlaceholderName(for prefix: String) -> String? {
        switch prefix {
        case "hc": return "hc_missing"
        default:   return nil
        }
    }
}
