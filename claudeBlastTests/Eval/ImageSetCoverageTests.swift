// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ImageSetCoverageTests.swift
//  claudeBlastTests
//
//  Enforces the norm from the Playful-3D work: anything we ship must be complete.
//  Every ImageSetID marked `isShippable` must provide real art for every key in
//  the bundled vocabulary — no relying on the master-set backfill or the
//  letter-on-color placeholder to paper over gaps. Incomplete sets (High
//  Contrast today) are `isShippable == false` and are exempt until reviewed +
//  regenerated. Runs offline (tests are app-hosted, so Bundle.main is the app
//  bundle and the tile PNGs + vocabulary.json are present).

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct ImageSetCoverageTests {

    /// All vocabulary keys from the bundled vocabulary.json.
    private func vocabularyKeys() throws -> [String] {
        let url = try #require(Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
                               "vocabulary.json missing from the app bundle")
        struct Entry: Decodable { let key: String }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        return entries.map(\.key)
    }

    /// Known, tracked gaps in otherwise-shippable sets, pending a dedicated
    /// POLISH worktree. ARASAAC is missing art for 9 recently-added tiles; the
    /// decision (2026-06-20) is to fill them with our own replacements there,
    /// not to demote ARASAAC. Until then they render via the Playful-3D master
    /// backfill. The test allows exactly these and fails on any NEW gap, so the
    /// allowlist shrinks to empty when the polish work lands.
    private static let knownIncompleteShippable: [String: Set<String>] = [
        ImageSetID.arasaac.rawValue: [
            "basketball", "goldfish_cracker", "graham_cracker", "popsicle",
            "pretzel", "slide", "snack", "snack_bar", "tricycle",
        ],
    ]

    @Test func shippableSetsCoverEntireVocabulary() throws {
        let keys = try vocabularyKeys()
        #expect(!keys.isEmpty)

        let resolver = TileImageResolver()
        for set in ImageSetID.allCases where set.isShippable {
            // Real art only — bypasses photo overrides, master-set backfill, and
            // placeholders by querying the specific set.
            let missing = Set(keys.filter { resolver.image(for: $0, in: set) == nil })
            let allowed = Self.knownIncompleteShippable[set.rawValue] ?? []
            let unexpected = missing.subtracting(allowed).sorted()
            #expect(unexpected.isEmpty,
                    "Shippable set \(set.rawValue) has NEW missing art for \(unexpected.count) tile(s): \(unexpected.prefix(20).joined(separator: ", "))")

            // Surface when a tracked gap has been filled so the allowlist can shrink.
            let filled = allowed.subtracting(missing).sorted()
            if !filled.isEmpty {
                print("[eval] \(set.rawValue): tracked gaps now filled — remove from knownIncompleteShippable: \(filled.joined(separator: ", "))")
            }
        }
    }

    /// Guards the inverse: if a set has no gaps, it ought to be marked shippable.
    /// Surfaces "High Contrast is now complete — flip isShippable" without a code
    /// dive. A soft signal (record, not a failure) so finishing art doesn't
    /// require a test edit in the same change.
    @Test func reportsNonShippableSetsThatAreActuallyComplete() throws {
        let keys = try vocabularyKeys()
        let resolver = TileImageResolver()
        for set in ImageSetID.allCases where !set.isShippable {
            let missing = keys.filter { resolver.image(for: $0, in: set) == nil }
            if missing.isEmpty {
                print("[eval] \(set.rawValue) now has full coverage — consider marking it isShippable.")
            }
        }
    }
}
