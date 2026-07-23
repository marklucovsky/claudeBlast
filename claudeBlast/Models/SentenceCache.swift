// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceCache.swift
//  claudeBlast
//

import SwiftData
import Foundation

@Model
final class SentenceCache {
    var id: String = UUID().uuidString
    var cacheKey: String = ""
    var tileKeys: [String] = []
    var sentence: String = ""
    /// Dead field: only ever written "" and never read anywhere. The one true
    /// removal candidate on this model — slated for the pre-promotion
    /// schema-hardening pass (remove while the CloudKit schema is still in
    /// Development, reset the dev environment, then promote a clean schema;
    /// the removal itself is a lightweight SwiftData migration — no custom code).
    var audioData: String = ""
    var hitCount: Int = 0
    var isPinned: Bool = false
    /// Set at creation; read by `CloudKitDedupReconciler.dedupeSentenceCache` as
    /// the tie-breaker when two synced duplicates share a `hitCount` (keep the
    /// newer). NOT vestigial — do not remove without updating that dedup order.
    var created: Date = Date.now
    var lastUsed: Date = Date.now
    /// `ChildProfile.id` whose interaction produced this cache entry. Nil
    /// for legacy entries written before commit 3. Reserved for per-child
    /// cache filtering / analytics; v1 lookups ignore the field.
    var childID: String?
    /// `CacheKeyPolicy.versionToken` (model id + prompt version) at write time.
    /// Drives stale-entry eviction: a model/prompt-version change leaves old
    /// entries with a mismatched token, swept at launch and on demand. Empty
    /// for legacy entries written before this field existed → treated as stale.
    var keyVersion: String = ""

    init(tiles: [TileSelection], grade: Int, sentence: String, audioData: String = "",
         childID: String? = nil) {
        self.tileKeys = tiles.map(\.key)
        self.cacheKey = CacheKeyPolicy.key(for: tiles, grade: grade)
        self.sentence = sentence
        self.audioData = audioData
        self.childID = childID
        self.keyVersion = CacheKeyPolicy.versionToken
    }
}
