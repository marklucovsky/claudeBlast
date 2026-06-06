// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LoggedUtterance.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Persisted record of a finalized tile group — what the child "said," when, and how many
/// times the same combo escalated before commit. Therapist/partner-facing review log.
/// No `@Attribute(.unique)` so the schema stays CloudKit-compatible.
@Model
final class LoggedUtterance {
    var id: String = UUID().uuidString
    var tileKeys: [String] = []
    var sentence: String = ""
    var createdAt: Date = Date.now
    var repetitionCount: Int = 0
    var sceneName: String?
    /// `ChildProfile.id` whose interaction produced this utterance. Nil for
    /// legacy entries written before commit 3 — therapist analytics that
    /// filter by child should treat nil as "unknown" rather than "any."
    var childID: String?

    init(
        tileKeys: [String],
        sentence: String,
        repetitionCount: Int = 0,
        sceneName: String? = nil,
        childID: String? = nil,
        createdAt: Date = .now
    ) {
        self.tileKeys = tileKeys
        self.sentence = sentence
        self.repetitionCount = repetitionCount
        self.sceneName = sceneName
        self.childID = childID
        self.createdAt = createdAt
    }
}
