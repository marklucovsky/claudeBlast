// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LiveTier1EvalTests.swift
//  claudeBlastTests
//
//  End-to-end Tier-1 eval against the real subject model. OPT-IN ONLY: skipped
//  unless RUN_LIVE_EVAL=1 and a key are present, so normal test/CI runs make no
//  network calls. This proves the harness plumbing (real prompts → subject model
//  → Tier-1 scoring) before the Tier-2 judge lands in A2, and gives an early
//  read on whether the system is grossly broken (e.g. wordClass leakage).

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct LiveTier1EvalTests {

    private var enabled: Bool { EvalEnv.liveEnabled && EvalEnv.apiKey != nil }

    private func makeSubjectRunner() -> SubjectRunner {
        let cfg = EvalModelConfig.subject(apiKey: EvalEnv.apiKey ?? "", model: EvalEnv.subjectModel)
        return SubjectRunner(client: EvalChatClient(config: cfg))
    }

    @Test(.enabled(if: EvalEnv.liveEnabled && EvalEnv.apiKey != nil))
    func liveSentenceSanity() async throws {
        let runner = makeSubjectRunner()
        var failures: [String] = []

        for c in EvalCases.sentences {
            let text = try await runner.generate(tiles: c.tiles)
            let score = Tier1.scoreSentence(text, tiles: c.tiles)
            print("[eval/sentence] \(c.id): \"\(text)\"  \(score.passed ? "OK" : "FAIL \(score.issues)")")
            if !score.passed { failures.append("\(c.id): \(score.issues.joined(separator: "; "))") }
        }

        #expect(failures.isEmpty, Comment(rawValue: "Tier-1 sentence failures:\n" + failures.joined(separator: "\n")))
    }

    @Test(.enabled(if: EvalEnv.liveEnabled && EvalEnv.apiKey != nil))
    func liveEscalationSanity() async throws {
        let runner = makeSubjectRunner()
        var failures: [String] = []

        for c in EvalCases.escalations {
            let ladder = try await runner.generateEscalationLadder(tiles: c.tiles, extraSteps: c.extraSteps)
            let score = Tier1.scoreEscalation(ladder, tiles: c.tiles)
            print("[eval/escalation] \(c.id) intensities=\(score.intensities)")
            for (i, rung) in ladder.enumerated() { print("    [\(i)] \"\(rung)\"") }
            if !score.passed {
                print("    -> FAIL \(score.issues)")
                failures.append("\(c.id): \(score.issues.joined(separator: "; "))")
            }
        }

        // Tier 1 is a floor: a regression or flat ramp here is a real signal that
        // escalation is broken — exactly the failure mode this milestone targets.
        #expect(failures.isEmpty, Comment(rawValue: "Tier-1 escalation failures:\n" + failures.joined(separator: "\n")))
    }
}
