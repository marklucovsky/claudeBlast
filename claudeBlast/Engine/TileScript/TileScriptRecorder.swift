// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRecorder.swift
//  claudeBlast
//

import Foundation
import Observation

/// Records user tile interactions into a replayable TileScript.
///
/// Row boundaries are detected two ways:
/// 1. `onWillClear` hook — fires when clearSelection() is called (X button, idle timer)
/// 2. Auto-split — when a new action arrives after a real sentence was generated
///    (2+ tiles, from cache or API), the previous row is finalized and carry-over
///    tiles (still in the engine's tray) are prepended to the new row.
///
/// Single-tile display names do NOT trigger row boundaries.
@Observable
@MainActor
final class TileScriptRecorder {

    enum State {
        case idle
        case recording
    }

    // MARK: - Public state

    private(set) var state: State = .idle
    private(set) var rowCount: Int = 0

    /// Set after stopRecording() — TileScriptView presents save modal when non-nil.
    var lastRecordedScript: TileScript?

    // MARK: - Navigation callbacks (set by ContentView)

    var onSwitchToHome: (() -> Void)?
    var onSwitchToScript: (() -> Void)?

    // MARK: - Internal state

    private var sceneName: String = ""
    private var currentActions: [TileAction] = []
    private var completedRows: [TileRow] = []
    private weak var engine: SentenceEngine?
    private weak var runner: TileScriptRunner?
    private weak var coordinator: NavigationCoordinator?

    /// Sentence received for the current row's tiles (from onSentenceReady).
    /// Set only for real multi-tile sentences, not single-tile display names.
    private var pendingSentence: String?

    // MARK: - Configuration

    func configure(engine: SentenceEngine, runner: TileScriptRunner, coordinator: NavigationCoordinator) {
        self.engine = engine
        self.runner = runner
        self.coordinator = coordinator
        // Row finalization on explicit clear (X button, idle timer, last-tile removal)
        engine.onWillClear = { [weak self] sentence in
            self?.finalizeRow(sentence: sentence)
            // No carry-over: clear is an explicit reset.
        }
        // Track when a real sentence is generated (2+ tiles)
        engine.onSentenceReady = { [weak self] sentence in
            guard let self, self.state == .recording else { return }
            self.pendingSentence = sentence
        }
    }

    // MARK: - Recording control

    func startRecording(sceneName: String) {
        // Dismiss any lingering playback overlay
        if runner?.state != .idle {
            runner?.stop()
        }
        // Clear the tile tray so recording starts fresh
        engine?.clearSelection()

        self.sceneName = sceneName
        completedRows = []
        rowCount = 0
        pendingSentence = nil
        lastRecordedScript = nil
        state = .recording
        onSwitchToHome?()

        // Seed first row with a navigate to the current page so playback
        // starts on the right page. After onSwitchToHome, coordinator
        // reflects the home page; if the user navigates elsewhere during
        // recording, those navigations are captured naturally.
        if let pageKey = coordinator?.currentPageKey {
            currentActions = [.navigate(pageKey: pageKey)]
        } else if let homePage = coordinator?.navigationPath.first {
            currentActions = [.navigate(pageKey: homePage)]
        } else {
            currentActions = []
        }
    }

    /// Stop recording, assemble script, switch to TileScript tab for save modal.
    func stopRecording() {
        if !currentActions.isEmpty {
            finalizeRow(sentence: pendingSentence)
        }
        state = .idle

        lastRecordedScript = TileScript(
            name: "Recording",
            description: "Recorded demo",
            audio: true,
            tileWait: .human,
            sentenceWait: .human,
            provider: nil,
            scene: sceneName.isEmpty ? nil : sceneName,
            commands: completedRows.isEmpty ? [] : [.tiles(rows: completedRows)]
        )
        onSwitchToScript?()
    }

    /// Cancel recording and discard everything.
    func discard() {
        state = .idle
        currentActions = []
        completedRows = []
        rowCount = 0
        sceneName = ""
        pendingSentence = nil
        lastRecordedScript = nil
    }

    // MARK: - Action capture

    func recordNavigate(pageKey: String) {
        guard state == .recording else { return }
        autoSplitIfNeeded(excludingTileKey: nil)
        currentActions.append(.navigate(pageKey: pageKey))
    }

    func recordTap(tileKey: String) {
        guard state == .recording else { return }
        // Exclude this tile from carry-over — it's about to be appended
        // and engine.addTile() has already added it to the tray.
        autoSplitIfNeeded(excludingTileKey: tileKey)
        currentActions.append(.tap(tileKey: tileKey))
    }

    /// Record a replay as a new row with the current tile set (taps only, no navigation).
    func recordReplay() {
        guard state == .recording, let engine else { return }
        // Finalize current row if it has a pending sentence
        if !currentActions.isEmpty, let sentence = pendingSentence {
            finalizeRow(sentence: sentence)
        }
        // Seed the new row with just the tile taps currently in the tray
        currentActions = engine.selectedTiles.map { .tap(tileKey: $0.key) }
        pendingSentence = nil
        // onSentenceReady will set pendingSentence when the replay sentence arrives
    }

    // MARK: - Row finalization

    /// If a real sentence was generated for the current actions, the row is complete.
    /// Carry-over tiles (still in the engine's tray) are prepended to the new row.
    /// `excludingTileKey`: the tile about to be appended by the caller — exclude from
    /// carry-over since engine.addTile() has already added it to the tray.
    private func autoSplitIfNeeded(excludingTileKey: String?) {
        guard !currentActions.isEmpty, let sentence = pendingSentence else { return }

        // Snapshot carry-over tiles, excluding the incoming tile to avoid duplication
        let carryOver = (engine?.selectedTiles ?? [])
            .filter { $0.key != excludingTileKey }
            .map { TileAction.tap(tileKey: $0.key) }

        finalizeRow(sentence: sentence)

        // Seed the new row with carry-over tiles so playback re-taps them
        currentActions = carryOver
    }

    /// Build a TileRow from accumulated actions and append to completedRows.
    func finalizeRow(sentence: String?) {
        guard state == .recording, !currentActions.isEmpty else { return }

        let rawText = currentActions.map { action in
            switch action {
            case .navigate(let key): return "<\(key)>"
            case .tap(let key): return key
            }
        }.joined(separator: ", ")

        let row = TileRow(
            actions: currentActions,
            rawText: rawText,
            comment: nil
        )
        completedRows.append(row)
        rowCount = completedRows.count
        currentActions = []
        pendingSentence = nil
    }
}
