// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRecorderTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

/// Tests for TileScriptRecorder row splitting and carry-over logic.
///
/// Input format: comma-separated tokens where:
/// - `<page>`  → navigation (recordNavigate)
/// - `*wait*`  → simulate sentence generation (fires onSentenceReady)
/// - `*clear*` → simulate explicit clear (fires onWillClear)
/// - `~tile~`  → removal tap (engine.removeTile, not recorded)
/// - `tile`    → audible tile tap (engine.addTile + recordTap)
@MainActor
struct TileScriptRecorderTests {

    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self, PageModel.self, PageTileModel.self,
            SentenceCache.self, BlasterScene.self, MetricEvent.self,
            RecordedScript.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Parse a test input string and drive the recorder + engine.
    /// Returns the row strings from the resulting TileScript.
    private func runRecording(_ input: String) throws -> [String] {
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)

        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")

        let tokens = input.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        for token in tokens {
            if token == "*wait*" {
                // Simulate sentence generation for 2+ tiles.
                // Build a fake sentence from selected tile keys.
                let sentence = engine.selectedTiles.map(\.key).joined(separator: " + ")
                engine.onSentenceReady?(sentence)
            } else if token == "*clear*" {
                // Simulate explicit clear (X button / idle timer)
                engine.clearSelection()
            } else if token.hasPrefix("~") && token.hasSuffix("~") {
                // Removal tap: remove from engine, don't record
                let key = String(token.dropFirst().dropLast())
                if let index = engine.selectedTiles.firstIndex(where: { $0.key == key }) {
                    // Remove without triggering clearSelection (unless it's the last tile).
                    // For testing, directly manipulate to avoid side effects.
                    engine.removeTile(at: index)
                }
            } else if token.hasPrefix("<") && token.hasSuffix(">") {
                // Navigation
                let pageKey = String(token.dropFirst().dropLast())
                recorder.recordNavigate(pageKey: pageKey)
            } else {
                // Audible tile tap: add to engine then record
                let tile = TileModel(key: token, wordClass: "actions")
                engine.addTile(tile)
                recorder.recordTap(tileKey: token)
            }
        }

        recorder.stopRecording()
        guard let script = recorder.lastRecordedScript else { return [] }

        // Extract row strings from the script's tile commands
        var rows: [String] = []
        for command in script.commands {
            if case .tiles(let tileRows) = command {
                for row in tileRows {
                    rows.append(row.rawText)
                }
            }
        }
        return rows
    }

    // MARK: - Tests

    @Test func basicTwoRows() throws {
        // grandpa, <food>, pizza, *wait*, pizza (remove), fries
        let rows = try runRecording("grandpa, <food>, pizza, *wait*, ~pizza~, fries")
        #expect(rows.count == 2)
        #expect(rows[0] == "grandpa, <food>, pizza")
        #expect(rows[1] == "grandpa, fries")
    }

    @Test func twoRowsWithNavigation() throws {
        // grandpa, <places>, playground, *wait*, ~playground~, <home>, <food>, fries
        let rows = try runRecording(
            "grandpa, <places>, playground, *wait*, ~playground~, <home>, <food>, fries"
        )
        #expect(rows.count == 2)
        #expect(rows[0] == "grandpa, <places>, playground")
        #expect(rows[1] == "grandpa, <home>, <food>, fries")
    }

    @Test func explicitClearNoCarryOver() throws {
        // grandpa, pizza, *wait*, *clear*, mom, fries
        let rows = try runRecording("grandpa, pizza, *wait*, *clear*, mom, fries")
        #expect(rows.count == 2)
        #expect(rows[0] == "grandpa, pizza")
        #expect(rows[1] == "mom, fries")
    }

    @Test func singleRowNoWait() throws {
        // Just tiles, no sentence generation
        let rows = try runRecording("grandpa, <food>, pizza")
        #expect(rows.count == 1)
        #expect(rows[0] == "grandpa, <food>, pizza")
    }

    @Test func threeRows() throws {
        let rows = try runRecording(
            "mom, pizza, *wait*, <home>, dad, fries, *wait*, <home>, grandpa"
        )
        #expect(rows.count == 3)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "mom, pizza, <home>, dad, fries")
        // Row 3: carry-over after second wait includes all tray tiles
    }

    @Test func carryOverExcludesRemovedTile() throws {
        // mom, pizza, *wait*, ~mom~, fries
        // After removing mom, only pizza remains. fries is new tap.
        let rows = try runRecording("mom, pizza, *wait*, ~mom~, fries")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "pizza, fries")
    }

    @Test func navigationOnlyRow() throws {
        // Pure navigation row (unusual but valid)
        let rows = try runRecording("<food>, <home>")
        #expect(rows.count == 1)
        #expect(rows[0] == "<food>, <home>")
    }

    @Test func emptyRecording() throws {
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)

        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")
        recorder.stopRecording()

        #expect(recorder.lastRecordedScript?.commands.isEmpty == true)
    }

    @Test func noCommentsInOutput() throws {
        let rows = try runRecording("grandpa, pizza, *wait*, mom, fries")
        // Verify the generated YAML has no comments
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)
        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")

        // Feed actions
        for token in ["grandpa", "pizza"] {
            let tile = TileModel(key: token, wordClass: "actions")
            engine.addTile(tile)
            recorder.recordTap(tileKey: token)
        }
        engine.onSentenceReady?("test sentence")
        let tile = TileModel(key: "mom", wordClass: "people")
        engine.addTile(tile)
        recorder.recordTap(tileKey: "mom")

        recorder.stopRecording()
        let yaml = TileScriptSerializer.serialize(recorder.lastRecordedScript!)
        #expect(!yaml.contains("#"))
    }
}
