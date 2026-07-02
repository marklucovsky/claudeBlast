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
/// The new tile-group/history model gives us explicit Play/Replay/Done events, so the recorder
/// no longer needs the old "auto-split when a sentence arrives" heuristic. Row boundaries are
/// driven by user UI actions:
///
///   - **Play tap on an unlocked group** (`recordPlay`): finalize a tiles row that captures
///     every navigate plus every tile currently in the active group. Do NOT reset accumulated
///     actions — the user may keep adding to the same active group, and the next Play snapshots
///     the now-extended state.
///   - **Replay tap on a locked group** (`recordReplay`): emit a standalone `<tilescript:replay>`
///     row. Does not reset accumulated actions.
///   - **History-group reopen tap** (`recordReplay` — same call site): also a `<tilescript:replay>`
///     row, since reopening the most recent history group plays it again with escalation.
///   - **Done** (and any other flush — auto-Done, scene switch, clearSelection): fires
///     `onWillClear` from the engine and resets `currentActions`. No row emission here; the
///     most recent Play already produced the row.
///
/// Single-tile "utterances" never produce a row because the play button is hidden under 2 tiles
/// and no Play event ever fires for them.
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
    /// Accumulated user actions (navigates + tile taps) since the last flush. Resets on
    /// `onWillClear` (i.e. when an active group is committed/cleared).
    private var currentActions: [TileAction] = []
    private var completedRows: [TileRow] = []
    private weak var engine: SentenceEngine?
    private weak var runner: TileScriptRunner?
    private weak var coordinator: NavigationCoordinator?

    /// Latest generated sentence (informational; surfaced for tests and debugging). Cleared on
    /// flush. Not used for row boundaries in the new model.
    private var pendingSentence: String?

    /// True when actions have been appended to `currentActions` since the last `recordPlay`,
    /// flush, or recording start. Lets `stopRecording` finalize a trailing row only when the
    /// user actually built something they didn't yet capture via a Play tap.
    private var currentActionsDirty: Bool = false

    // MARK: - Configuration

    func configure(engine: SentenceEngine, runner: TileScriptRunner, coordinator: NavigationCoordinator) {
        self.engine = engine
        self.runner = runner
        self.coordinator = coordinator

        // onWillClear fires from flushActiveToHistory — Done, auto-Done, reopenHistoryGroup,
        // scene switch, clearSelection. In every case, the next user gesture starts a fresh
        // active group, so we reset our accumulated actions.
        engine.onWillClear = { [weak self] _ in
            self?.handleFlush()
        }
        // Track the latest sentence text (informational only — rows are bounded by Play events).
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

        // Seed first row with a navigate to the current page so playback starts on the right
        // page. After onSwitchToHome, coordinator reflects the home page; if the user navigates
        // elsewhere during recording, those navigations are captured naturally.
        if let pageKey = coordinator?.currentPageKey {
            currentActions = [.navigate(pageKey: pageKey)]
        } else if let homePage = coordinator?.navigationPath.first {
            currentActions = [.navigate(pageKey: homePage)]
        } else {
            currentActions = []
        }
        // The seed navigate isn't user-content; the dirty flag only flips once the user actually
        // taps a tile or navigates somewhere new.
        currentActionsDirty = false
    }

    /// Stop recording, assemble script, switch to TileScript tab for save modal.
    ///
    /// If the user built something but didn't tap Play (or extended an already-played group
    /// with more tiles), we finalize the current state as a trailing tiles row so the recording
    /// matches their on-screen intent. We rely on `currentActionsDirty` to avoid duplicating a
    /// row that's already been captured by an earlier Play.
    func stopRecording() {
        if currentActionsDirty {
            recordPlay()
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
            mode: nil,   // recordings default to sentence on playback (capture mode: TODO)
            commands: completedRows.isEmpty ? [] : [.tiles(rows: completedRows)]
        )
        onSwitchToScript?()
    }

    /// Cancel recording and discard everything.
    func discard() {
        state = .idle
        currentActions = []
        currentActionsDirty = false
        completedRows = []
        rowCount = 0
        sceneName = ""
        pendingSentence = nil
        lastRecordedScript = nil
    }

    // MARK: - Action capture

    func recordNavigate(pageKey: String) {
        guard state == .recording else { return }
        currentActions.append(.navigate(pageKey: pageKey))
        currentActionsDirty = true
    }

    func recordTap(tileKey: String) {
        guard state == .recording else { return }
        currentActions.append(.tap(tileKey: tileKey))
        currentActionsDirty = true
    }

    /// Called when the user taps a PageTileModel where both `isAudible` is true and `link`
    /// matches the tile key — i.e. a single user gesture that both adds the tile and navigates.
    /// Captured as one `.audibleNavigate` action so the resulting script reads as
    /// `<key isAudible=t/>` rather than the noisier `key, <key>`.
    func recordAudibleNavigate(pageKey: String) {
        guard state == .recording else { return }
        currentActions.append(.audibleNavigate(pageKey: pageKey))
        currentActionsDirty = true
    }

    /// Called when the user taps Play on a non-locked active group (i.e. the first generation
    /// for the current tile combo). Emits a tiles row that captures every navigate plus every
    /// tile currently visible in the active group. Does NOT reset `currentActions` — the user
    /// can keep adding to the same active group, and the next Play will snapshot the extended
    /// state.
    func recordPlay() {
        guard state == .recording, let engine else { return }

        let activeKeys = Set(engine.activeGroup.tiles.map(\.key))
        let rowActions: [TileAction] = currentActions.filter { action in
            switch action {
            case .navigate: return true
            case .tap(let key): return activeKeys.contains(key)
            case .audibleNavigate(let key): return activeKeys.contains(key)
            case .replay, .noclose: return false
            }
        }

        // Only emit if the row contains a real utterance — at least one tap or audibleNavigate.
        // Pure navigation rows aren't meaningful as standalone script content (and would happen
        // e.g. when stopRecording finalizes a seed-only state).
        let hasTileContent = rowActions.contains { action in
            switch action {
            case .tap, .audibleNavigate: return true
            default: return false
            }
        }
        guard hasTileContent else { return }

        appendRow(actions: rowActions)
        currentActionsDirty = false
    }

    /// Called when the user taps Play on a locked group (replay/escalation) OR taps a closed
    /// history group to reopen. Emits a `<tilescript:replay>` row.
    func recordReplay() {
        guard state == .recording else { return }
        appendRow(actions: [.replay])
    }

    // MARK: - Row helpers

    private func appendRow(actions: [TileAction]) {
        let rawText = actions.map { action -> String in
            switch action {
            case .navigate(let key): return "<\(key)>"
            case .tap(let key): return key
            case .audibleNavigate(let key): return "<\(key) isAudible=t/>"
            case .replay: return "<tilescript:replay>"
            case .noclose: return "<tilescript:noclose>"
            }
        }.joined(separator: ", ")

        completedRows.append(TileRow(actions: actions, rawText: rawText, comment: nil))
        rowCount = completedRows.count
    }

    /// Reset accumulated actions after the active group flushes. We don't emit a row here —
    /// any row that should exist for the just-flushed group was already produced by an earlier
    /// Play or Replay tap.
    private func handleFlush() {
        guard state == .recording else { return }
        currentActions = []
        currentActionsDirty = false
        pendingSentence = nil
    }
}
