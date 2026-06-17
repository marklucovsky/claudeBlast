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
import SwiftData
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

    /// Whether this set is **complete** — ships reviewed, real art for every
    /// vocabulary key — and is therefore offered to end users as a first-class
    /// choice.
    ///
    /// Norm: anything we ship must be complete and reviewed, and we hold any
    /// community-contributed set we bless as shippable to the same bar. The
    /// Playful-3D master backfill (`TileImageResolver.image(for:)`) removes the
    /// *absolute* need for completeness so you can prototype an alternate style
    /// without first generating the whole world — but an incomplete set stays a
    /// development-only affordance, hidden from the release picker until it has
    /// been reviewed and regenerated to full coverage.
    ///
    /// High Contrast is currently incomplete (~20 vocabulary gaps) and is
    /// pending a full review + regen pass before it can ship.
    var isShippable: Bool {
        switch self {
        case .playful3D:    return true   // master set — full coverage, reviewed
        case .arasaac:      return true   // complete fallback set
        case .highContrast: return false  // pending full review + regen
        }
    }

    /// Sets offered to end users. In release builds only complete sets appear;
    /// debug builds expose every set (incomplete ones flagged) so alternate
    /// tile sets can be developed against the live app.
    static var selectable: [ImageSetID] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter(\.isShippable)
        #endif
    }
}

// MARK: - Tile Image Resolver



@Observable
@MainActor
final class TileImageResolver {

    /// The currently active image set. Changing this causes all tiles to re-render.
    /// Defaults to Playful 3D — the master set: most complete vocabulary
    /// coverage, highest tile quality, and fully owned (clears the ARASAAC
    /// CC BY-NC-SA licensing concern for display). ARASAAC is one swappable
    /// option among others; see `image(for:)` for the master-set backfill.
    var activeSet: ImageSetID = .playful3D

    /// Bumped whenever a per-key photo override is added or removed so SwiftUI
    /// views that read it (TileImageView) re-render. NSCache reads/writes are
    /// not observable on their own, so this is the explicit invalidation signal.
    private(set) var revision = 0

    /// In-memory cache for non-asset-catalog images (keyed by "setID:tileKey").
    private var cache = NSCache<NSString, UIImage>()

    /// SwiftData context used to fetch per-tile photo overrides
    /// (`TileModel.userImageData`). Wired via `configure` at launch, mirroring
    /// `ChildProfileResolver`. Nil before configuration → overrides are skipped.
    private var context: ModelContext?

    /// Decoded photo overrides, keyed "override:<tileKey>".
    private var overrideCache = NSCache<NSString, UIImage>()

    /// Keys known to have NO photo override. Without this negative cache every
    /// render of every photo-less tile (the vast majority) would issue a fetch.
    private var overrideMisses = Set<String>()

    init() {
        cache.countLimit = 600 // ~500 tiles + headroom
        overrideCache.countLimit = 600
    }

    /// Wire the SwiftData context so photo overrides can be resolved. Safe to
    /// call multiple times; clears any cached override state so a fresh store
    /// is re-read.
    func configure(modelContext: ModelContext) {
        self.context = modelContext
        overrideCache.removeAllObjects()
        overrideMisses.removeAll()
    }

    /// Resolve a UIImage for the given tile key, applying the full fallback
    /// chain. A caregiver-supplied photo override (`TileModel.userImageData`)
    /// wins over every image set, so it is consulted first.
    ///
    /// Fallback order:
    ///   1. caregiver photo override
    ///   2. the active set's real art
    ///   3. **Playful-3D backfill** — the master set is the most complete and
    ///      backs up any sparser active set (ARASAAC, High Contrast, a future
    ///      set). Skipped when P3D is already active.
    ///   4. the active set's own missing-art placeholder (currently only High
    ///      Contrast ships one). With full P3D coverage this is rarely reached;
    ///      kept defensively for tiles even P3D lacks.
    ///   5. nil → TileImageView renders its letter-on-color placeholder.
    func image(for key: String) -> UIImage? {
        if let photo = userPhoto(for: key) { return photo }
        if let img = rawImage(for: key, in: activeSet) { return img }
        if activeSet != .playful3D, let img = rawImage(for: key, in: .playful3D) { return img }
        return placeholderImage(for: activeSet)
    }

    /// Resolve a tile's real art in a specific image set — no placeholder, no
    /// master-set backfill. Returns nil when that set genuinely lacks the tile.
    func image(for key: String, in imageSet: ImageSetID) -> UIImage? {
        rawImage(for: key, in: imageSet)
    }

    /// Check whether a tile has bundled art. True when the active set OR the
    /// Playful-3D master set ships real art for the key — i.e. it's a known
    /// bundled tile, not a custom user-only one. Deliberately bypasses photo
    /// overrides and placeholders: callers (e.g. export's `defaultTileKeys`)
    /// use this to decide whether a tile relies on bundled art, and a caregiver
    /// photo must not make a custom tile look bundled.
    func hasImage(for key: String) -> Bool {
        if rawImage(for: key, in: activeSet) != nil { return true }
        return rawImage(for: key, in: .playful3D) != nil
    }

    /// Raw art for a key in a set, with no placeholder or backfill. This is the
    /// single switch over set → asset lookup used by the public resolvers.
    private func rawImage(for key: String, in imageSet: ImageSetID) -> UIImage? {
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

    /// The active set's shared missing-art placeholder, if it ships one.
    /// Only High Contrast does today (`hc_missing.png`). This is now a defensive
    /// last resort: the Playful-3D backfill (step 3 of `image(for:)`) runs first
    /// and, with full master coverage, supplies art for every known tile — so a
    /// sparse High Contrast tile shows the master art, and this placeholder is
    /// only reached for a key even P3D lacks. Cached on first load.
    private func placeholderImage(for imageSet: ImageSetID) -> UIImage? {
        let prefix: String
        switch imageSet {
        case .highContrast: prefix = "hc"
        case .arasaac, .playful3D: return nil
        }
        guard let placeholderName = Self.missingPlaceholderName(for: prefix) else { return nil }
        let cacheKey = NSString(string: placeholderName)
        if let cached = cache.object(forKey: cacheKey) { return cached }
        if let url = Bundle.main.url(forResource: placeholderName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            cache.setObject(img, forKey: cacheKey)
            return img
        }
        return nil
    }

    // MARK: - Photo overrides

    /// Resolve a caregiver-supplied photo override for `key`, or nil. Uses a
    /// positive cache + a negative (`overrideMisses`) cache so photo-less tiles
    /// — almost all of them — cost at most one fetch ever.
    private func userPhoto(for key: String) -> UIImage? {
        guard context != nil else { return nil }
        if overrideMisses.contains(key) { return nil }
        let cacheKey = NSString(string: "override:\(key)")
        if let cached = overrideCache.object(forKey: cacheKey) { return cached }

        var descriptor = FetchDescriptor<TileModel>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let tile = try? context?.fetch(descriptor).first,
           let data = tile.userImageData,
           let img = UIImage(data: data) {
            overrideCache.setObject(img, forKey: cacheKey)
            return img
        }
        overrideMisses.insert(key)
        return nil
    }

    /// Invalidate the cached override for `key` after its photo is added or
    /// removed, and bump `revision` so views showing that tile re-render.
    func invalidatePhoto(for key: String) {
        overrideCache.removeObject(forKey: NSString(string: "override:\(key)"))
        overrideMisses.remove(key)
        revision &+= 1
    }

    // MARK: - Private

    /// Load a prefixed image's real art from the bundle root ({prefix}_{key}.png).
    /// Non-asset-catalog images land at the bundle root with the synchronized
    /// group build system. Uses NSCache to avoid repeated disk reads. Returns
    /// nil on a miss — the master-set backfill and placeholder fallback are
    /// handled by `image(for:)` / `placeholderImage(for:)`, not here.
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
