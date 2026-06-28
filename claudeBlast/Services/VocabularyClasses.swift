// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  VocabularyClasses.swift
//  claudeBlast
//
//  Canonical catalog of word classes — the single source of truth for what
//  classes exist, their tile color, and whether a caregiver may pick one when
//  creating a word. Deriving "what classes exist" from the data is fragile (a
//  typo like `bassketball` would become a real, selectable class); this catalog
//  governs the creator picker and color instead.
//
//  NOTE: a tile's `wordClass` string is injected verbatim into the
//  sentence-generation prompt (SentencePromptBuilder) as a hint — e.g.
//  "pony (animal)" vs "pony (food)". So class names are plain semantic words,
//  and keeping a concept in ONE class (e.g. all emotions in `feeling`) matters
//  for generation quality, not just tidiness.
//

import SwiftUI

struct VocabularyClass: Identifiable, Hashable {
    /// The `wordClass` string stored on tiles and sent to the AI as a hint.
    let name: String
    /// Tile color for this class (see TileColorResolver).
    let color: Color
    /// Whether the caregiver "New Word" creator offers this class. Structural /
    /// function classes (core, navigation, question) are not caregiver content.
    let isCaregiverSelectable: Bool

    var id: String { name }
    /// Human label for pickers (e.g. "feeling" → "Feeling").
    var label: String { name.capitalized }
}

enum VocabularyClasses {
    /// Canonical word classes in caregiver-facing display order. Colors mirror
    /// the legacy switch, with `feeling` given its own rose (all emotions live
    /// here now) and `animal` added (brown).
    static let all: [VocabularyClass] = [
        VocabularyClass(name: "people",   color: .purple,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "animal",   color: .brown,                                    isCaregiverSelectable: true),
        VocabularyClass(name: "actions",  color: .orange,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "describe", color: .green,                                    isCaregiverSelectable: true),
        VocabularyClass(name: "feeling",  color: Color(red: 0.96, green: 0.42, blue: 0.55), isCaregiverSelectable: true),
        VocabularyClass(name: "social",   color: .pink,                                     isCaregiverSelectable: true),
        VocabularyClass(name: "food",     color: .red,                                      isCaregiverSelectable: true),
        VocabularyClass(name: "meals",    color: .red,                                      isCaregiverSelectable: true),
        VocabularyClass(name: "fruit",    color: .red,                                      isCaregiverSelectable: true),
        VocabularyClass(name: "veggie",   color: .red,                                      isCaregiverSelectable: true),
        VocabularyClass(name: "snacks",   color: .red,                                      isCaregiverSelectable: true),
        VocabularyClass(name: "drinks",   color: .cyan,                                     isCaregiverSelectable: true),
        VocabularyClass(name: "places",   color: .blue,                                     isCaregiverSelectable: true),
        VocabularyClass(name: "weather",  color: Color(red: 0.3, green: 0.6, blue: 0.9),    isCaregiverSelectable: true),
        VocabularyClass(name: "colors",   color: .mint,                                     isCaregiverSelectable: true),
        VocabularyClass(name: "shape",    color: .teal,                                     isCaregiverSelectable: true),
        VocabularyClass(name: "body",     color: Color(red: 0.9, green: 0.5, blue: 0.5),    isCaregiverSelectable: true),
        VocabularyClass(name: "health",   color: Color(red: 0.9, green: 0.5, blue: 0.5),    isCaregiverSelectable: true),
        VocabularyClass(name: "toy",      color: .yellow,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "games",    color: .yellow,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "sports",   color: .yellow,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "play",     color: .yellow,                                   isCaregiverSelectable: true),
        VocabularyClass(name: "art",      color: Color(red: 0.7, green: 0.4, blue: 0.8),    isCaregiverSelectable: true),
        // Generic concrete objects / tools / equipment / vehicles that don't fit a
        // more specific class (handcuffs, badge, hose, ladder, tractor). Neutral
        // steel so it reads as a real category, distinct from the gray fallback.
        VocabularyClass(name: "object",   color: Color(red: 0.45, green: 0.5, blue: 0.55),  isCaregiverSelectable: true),
        // Structural / function classes — not caregiver-creatable content.
        VocabularyClass(name: "core",       color: Color(red: 0.95, green: 0.88, blue: 0.55), isCaregiverSelectable: false),
        VocabularyClass(name: "navigation", color: .indigo,                                   isCaregiverSelectable: false),
        VocabularyClass(name: "question",   color: .pink,                                     isCaregiverSelectable: false),
        // Auto-minted per page: a silent link tile (key `page_<pageKey>`) that
        // navigates to a named page collection. Reusable on any board. Not
        // caregiver-creatable — pages mint these themselves.
        VocabularyClass(name: "page_link",  color: Color(red: 0.4, green: 0.45, blue: 0.85),  isCaregiverSelectable: false),
    ]

    private static let byName: [String: VocabularyClass] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static func known(_ name: String) -> VocabularyClass? { byName[name] }

    /// Classes offered in the caregiver "New Word" creator, in display order.
    static var caregiverSelectable: [VocabularyClass] { all.filter(\.isCaregiverSelectable) }
}

/// Single source of truth for tile color. Replaces the duplicated
/// `colorForWordClass` (TileImageView) and `wordClassColor` (SentenceTrayView)
/// switches, which they now delegate to. Unknown classes fall back to gray.
/// Future: an explicit per-tile color and per-word/page overrides resolve here
/// ahead of the class default.
enum TileColorResolver {
    static func color(for wordClass: String) -> Color {
        VocabularyClasses.known(wordClass)?.color ?? .gray
    }
}
