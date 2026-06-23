// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  InteractionModeTests.swift
//  claudeBlastTests
//
//  Covers single-word (classic AAC) mode and the universal "grid tap adds,
//  never deletes" rule introduced alongside it.

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
struct InteractionModeTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self, SentenceCache.self, BlasterScene.self, MetricEvent.self,
            RecordedScript.self, LoggedUtterance.self, ChildProfile.self, DeviceProfile.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [cfg])
    }

    /// Run `body` with an engine wired to a resolver whose active profile uses
    /// `mode`. The container is held alive for the whole closure — returning the
    /// engine alone would deallocate the container and orphan the profile, and
    /// reading a SwiftData property on an orphaned model traps.
    private func withEngine(mode: InteractionMode,
                            _ body: (SentenceEngine) throws -> Void) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", birthday: .now, isActive: true)
        profile.interactionMode = mode
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        try body(engine)
        withExtendedLifetime(container) {}
    }

    // MARK: - Model

    @Test func interactionModeRawRoundTrips() {
        let p = ChildProfile(displayName: "A", birthday: .now)
        #expect(p.interactionMode == .sentence) // default
        p.interactionMode = .singleWord
        #expect(p.interactionModeRaw == "singleWord")
        #expect(p.interactionMode == .singleWord)
    }

    @Test func unknownRawFallsBackToSentence() {
        let p = ChildProfile(displayName: "A", birthday: .now)
        p.interactionModeRaw = "somethingFuture"
        #expect(p.interactionMode == .sentence)
    }

    // MARK: - Universal: grid tap adds, never deletes (sentence mode)

    @Test func sentenceMode_reTapIsNoOp_notToggleOff() throws {
        try withEngine(mode: .sentence) { engine in
            let dad = TileModel(key: "dad", wordClass: "people")
            engine.addTile(dad)
            engine.addTile(dad) // re-tap: no toggle-off, no duplicate
            #expect(engine.selectedTiles.count == 1)
            #expect(engine.selectedTiles[0].key == "dad")
        }
    }

    // MARK: - Single-word mode

    @Test func singleWordMode_appendsToStrip_notGroup() throws {
        try withEngine(mode: .singleWord) { engine in
            engine.addTile(TileModel(key: "dad", wordClass: "people"))
            #expect(engine.spokenStrip.count == 1)
            #expect(engine.selectedTiles.isEmpty) // no sentence group
            #expect(engine.generatedSentence == nil)
        }
    }

    @Test func singleWordMode_allowsDuplicates() throws {
        try withEngine(mode: .singleWord) { engine in
            let dad = TileModel(key: "dad", wordClass: "people")
            engine.addTile(dad)
            engine.addTile(dad)
            engine.addTile(dad)
            #expect(engine.spokenStrip.count == 3)
            #expect(engine.spokenStrip.allSatisfy { $0.key == "dad" })
        }
    }

    @Test func singleWordMode_stripRollsAtCap() throws {
        try withEngine(mode: .singleWord) { engine in
            for i in 0..<25 {
                engine.addTile(TileModel(key: "w\(i)", wordClass: "actions"))
            }
            // Capped at 20; oldest dropped off the left, newest retained.
            #expect(engine.spokenStrip.count == 20)
            #expect(engine.spokenStrip.first?.key == "w5")
            #expect(engine.spokenStrip.last?.key == "w24")
        }
    }

    @Test func singleWordMode_removeAndClear() throws {
        try withEngine(mode: .singleWord) { engine in
            engine.addTile(TileModel(key: "a", wordClass: "actions"))
            engine.addTile(TileModel(key: "b", wordClass: "actions"))
            engine.removeStripWord(at: 0)
            #expect(engine.spokenStrip.map(\.key) == ["b"])
            engine.clearStrip()
            #expect(engine.spokenStrip.isEmpty)
        }
    }

    // MARK: - Escalation accounting

    /// Regression: escalation depth must reach the flushed group (and the logged
    /// utterance). Previously the flush logged the TileGroup's own repetitionCount
    /// (never updated) instead of the engine's live counter, so every utterance
    /// recorded 0 escalations.
    @Test func escalationDepthIsLoggedOnCommit() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Default profile is .sentence mode.
        let profile = ChildProfile(displayName: "Test", birthday: .now, isActive: true)
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)

        engine.addTile(TileModel(key: "eat", wordClass: "actions"))
        engine.addTile(TileModel(key: "pizza", wordClass: "food"))
        engine.triggerGo()
        try await waitUntil { engine.canReplay }
        engine.replay()
        try await waitUntil { !engine.isThinking }
        engine.replay()
        try await waitUntil { !engine.isThinking }

        #expect(engine.repetitionCount == 2)
        engine.commitActiveAndStartNew()
        #expect(engine.groupHistory.first?.repetitionCount == 2)

        let logged = try ctx.fetch(FetchDescriptor<LoggedUtterance>())
        #expect(logged.contains { $0.repetitionCount == 2 })
        withExtendedLifetime(container) {}
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout {
                Issue.record("waitUntil timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
