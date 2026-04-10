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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arasaac: return "Classic (ARASAAC)"
        case .playful3D: return "Playful 3D"
        }
    }

    var description: String {
        switch self {
        case .arasaac: return "Original pictogram style"
        case .playful3D: return "Modern clay/plasticine 3D style"
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
    private func prefixedBundleImage(for key: String, prefix: String) -> UIImage? {
        let resourceName = "\(prefix)_\(key)"
        let cacheKey = NSString(string: resourceName)

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            return nil
        }

        cache.setObject(img, forKey: cacheKey)
        return img
    }
}
