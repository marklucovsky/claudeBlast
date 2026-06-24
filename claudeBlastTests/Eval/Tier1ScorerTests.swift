// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  Tier1ScorerTests.swift
//  claudeBlastTests
//
//  Offline tests for the Tier-1 detectors themselves — they run with no network
//  and always execute in CI, proving the sanity floor actually fires on known
//  bad output (and stays quiet on good output). These guard the guardrails.

import Testing
import Foundation
@testable import claudeBlast

struct Tier1ScorerTests {

    private func tiles(_ raw: [(String, String, String)]) -> [TileSelection] {
        raw.map { TileSelection(key: $0.0, value: $0.1, wordClass: $0.2) }
    }

    // MARK: - wordClass echo (the headline failure mode)

    @Test func detectsWordClassEcho() {
        #expect(Tier1.containsWordClassEcho("I feel sick (feeling) today"))
        #expect(Tier1.containsWordClassEcho("Mom, I want pizza ( food )"))
        #expect(Tier1.containsWordClassEcho("Let's go to the snack bar (places)"))
    }

    @Test func cleanSentenceHasNoEcho() {
        #expect(!Tier1.containsWordClassEcho("Mom, I'm hungry. Can we eat?"))
        // A parenthetical that isn't a known class shouldn't trip it.
        #expect(!Tier1.containsWordClassEcho("I want it (a lot)."))
    }

    // MARK: - degenerate / echo

    @Test func detectsDegenerateOutput() {
        #expect(Tier1.isEmptyOrDegenerate(""))
        #expect(Tier1.isEmptyOrDegenerate("   "))
        #expect(Tier1.isEmptyOrDegenerate("!!! ..."))
        #expect(!Tier1.isEmptyOrDegenerate("Hi."))
    }

    @Test func detectsRawTileEcho() {
        let t = tiles([("mom", "mom", "people"), ("hungry", "hungry", "feeling")])
        #expect(Tier1.looksLikeRawTileEcho("mom hungry", tiles: t))
        #expect(Tier1.looksLikeRawTileEcho("Mom, hungry!", tiles: t)) // punctuation-insensitive
        #expect(!Tier1.looksLikeRawTileEcho("Mom, I am hungry.", tiles: t))
    }

    @Test func sentenceScoreAggregatesIssues() {
        let t = tiles([("mom", "mom", "people"), ("hungry", "hungry", "feeling")])
        let good = Tier1.scoreSentence("Mom, I'm hungry. Can we eat soon?", tiles: t)
        #expect(good.passed)

        let bad = Tier1.scoreSentence("hungry (feeling)", tiles: t)
        #expect(!bad.passed)
        #expect(bad.issues.contains { $0.contains("wordClass") })
    }

    // MARK: - escalation intensity + monotonicity

    @Test func intensityRisesWithInsistence() {
        let calm = Tier1.intensity("Mom, can we get a snack?")
        let urgent = Tier1.intensity("Mom, I am STARVING. We need to eat right now!")
        #expect(urgent > calm)
    }

    @Test func escalationLadderRising_passes() {
        let t = tiles([("mom", "mom", "people"), ("hungry", "hungry", "feeling")])
        let ladder = [
            "Mom, can we get something to eat soon?",
            "Mom, I'm really hungry — can we eat please?",
            "Mom, I am so hungry, we need to eat now!",
            "MOM, I'm STARVING. We need to eat right NOW!",
        ]
        let r = Tier1.scoreEscalation(ladder, tiles: t)
        #expect(r.passed)
        #expect(r.intensities == r.intensities.sorted())
    }

    @Test func escalationRegression_isFlagged() {
        let t = tiles([("mom", "mom", "people"), ("hungry", "hungry", "feeling")])
        let ladder = [
            "MOM, I'm STARVING, we need food right now!",
            "Mom, maybe a snack sometime.", // goes backwards
        ]
        let r = Tier1.scoreEscalation(ladder, tiles: t)
        #expect(!r.passed)
        #expect(r.issues.contains { $0.contains("less insistent") })
    }

    @Test func escalationFlat_isFlagged() {
        let t = tiles([("more", "more", "core")])
        let ladder = ["I want more.", "I want more.", "I want more."]
        let r = Tier1.scoreEscalation(ladder, tiles: t)
        #expect(!r.passed)
        #expect(r.issues.contains { $0.contains("no escalation") })
    }
}
