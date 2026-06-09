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
    var audioData: String = ""
    var hitCount: Int = 0
    var isPinned: Bool = false
    var created: Date = Date.now
    var lastUsed: Date = Date.now
    /// `ChildProfile.id` whose interaction produced this cache entry. Nil
    /// for legacy entries written before commit 3. Reserved for per-child
    /// cache filtering / analytics; v1 lookups ignore the field.
    var childID: String?

    init(tileKeys: [String], sentence: String, audioData: String = "",
         childID: String? = nil) {
        self.tileKeys = tileKeys
        self.cacheKey = Set(tileKeys).sorted().joined(separator: ",")
        self.sentence = sentence
        self.audioData = audioData
        self.childID = childID
    }
}
