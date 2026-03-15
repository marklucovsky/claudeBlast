// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRunner.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import os

/// Execution engine for TileScript playback with debugger-style stepping.
@Observable
@MainActor
final class TileScriptRunner {
    // MARK: - State

    enum State: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    private(set) var state: State = .idle
    private(set) var commandIndex: Int = 0
    private(set) var rowIndex: Int = 0
    private(set) var actionIndex: Int = 0
    private(set) var totalCommands: Int = 0
    private(set) var currentComment: String?
    private(set) var currentScript: TileScript?

    /// The tile row currently being pointed at (for the overlay to render).
    private(set) var currentRow: TileRow?
    /// Total rows in the current tiles command (0 if not in a tiles command).
    private(set) var currentRowCount: Int = 0

    /// Bulk generation progress (completed, total). Nil when not generating.
    private(set) var bulkProgress: (completed: Int, total: Int)?
    /// Number of duplicate combos skipped during bulk generation.
    private(set) var bulkDuplicates: Int = 0

    /// Human-readable description of the current command (non-tiles commands).
    var nextCommandDescription: String? {
        guard let script = currentScript,
              commandIndex < script.commands.count else { return nil }
        let cmd = script.commands[commandIndex]
        if case .tiles = cmd { return nil }
        return describeCommand(cmd)
    }

    // MARK: - Dependencies

    private var engine: SentenceEngine?
    private var coordinator: NavigationCoordinator?
    private var modelContext: ModelContext?

    // MARK: - Internal

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "TileScriptRunner")
    private var executionTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    private var tileWait: TimingValue = .human
    private var sentenceWait: TimingValue = .human

    private enum StepMode {
        case stepOver
        case stepInto
        case continueTo
    }
    private var stepMode: StepMode?

    /// Tab switching callback — runner sets this to switch to Home tab on play.
    var onSwitchToHome: (() -> Void)?

    // MARK: - Configuration

    func configure(engine: SentenceEngine, coordinator: NavigationCoordinator, modelContext: ModelContext) {
        self.engine = engine
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    // MARK: - Controls

    func play(script: TileScript) {
        guard state == .idle || state == .finished else { return }
        startScript(script, paused: false)
    }

    func playPaused(script: TileScript) {
        guard state == .idle || state == .finished else { return }
        startScript(script, paused: true)
    }

    private func startScript(_ script: TileScript, paused: Bool) {
        currentScript = script
        commandIndex = 0
        rowIndex = 0
        actionIndex = 0
        totalCommands = script.commands.count
        currentComment = nil
        currentRow = nil
        currentRowCount = 0
        bulkProgress = nil
        tileWait = script.tileWait
        sentenceWait = script.sentenceWait

        engine?.audioEnabled = script.audio
        if let providerName = script.provider {
            applyProvider(providerName)
        }

        // Point currentRow at the first tiles row if applicable
        updateCurrentRow()

        if paused {
            state = .paused
        } else {
            state = .running
        }
        onSwitchToHome?()

        executionTask = Task {
            await executeScript(script)
        }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        engine?.cancelIdleTimer()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        stepMode = nil
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stop() {
        executionTask?.cancel()
        executionTask = nil
        pauseContinuation?.resume()
        pauseContinuation = nil
        state = .idle
        currentScript = nil
        currentComment = nil
        currentRow = nil
        currentRowCount = 0
        bulkProgress = nil
        engine?.resetAll()
    }

    func rewind() {
        let script = currentScript
        stop()
        if let script {
            playPaused(script: script)
        }
    }

    func stepOver() {
        guard state == .paused else { return }
        stepMode = .stepOver
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stepInto() {
        guard state == .paused else { return }
        stepMode = .stepInto
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func continueToEnd() {
        guard state == .paused else { return }
        stepMode = .continueTo
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    // MARK: - Execution

    private func executeScript(_ script: TileScript) async {
        while commandIndex < script.commands.count {
            guard !Task.isCancelled else { break }

            // Pause-before-execute: wait if paused
            if state == .paused {
                await waitForResume()
                if Task.isCancelled { break }
            }

            let command = script.commands[commandIndex]

            // For tiles commands, delegate entirely (it handles its own stepping)
            if case .tiles(let rows) = command {
                await executeTileRows(rows)
                if Task.isCancelled { break }
            } else {
                // Execute non-tiles command
                await executeCommand(command)
                if Task.isCancelled { break }
            }

            // Advance to next command
            commandIndex += 1
            rowIndex = 0
            actionIndex = 0
            updateCurrentRow()

            // In step mode, pause before the next command
            if stepMode == .stepOver || stepMode == .stepInto {
                if commandIndex < script.commands.count {
                    state = .paused
                    stepMode = nil
                    engine?.cancelIdleTimer()
                }
            }
        }

        if !Task.isCancelled {
            currentRow = nil
            currentRowCount = 0
            state = .finished
        }
    }

    /// Sync currentRow/currentRowCount from commandIndex + rowIndex.
    private func updateCurrentRow() {
        guard let script = currentScript,
              commandIndex < script.commands.count else {
            currentRow = nil
            currentRowCount = 0
            return
        }
        if case .tiles(let rows) = script.commands[commandIndex] {
            currentRow = rowIndex < rows.count ? rows[rowIndex] : nil
            currentRowCount = rows.count
        } else {
            currentRow = nil
            currentRowCount = 0
        }
    }

    private func executeCommand(_ command: TileScriptCommand) async {
        switch command {
        case .tiles:
            break // handled separately in executeScript

        case .bulkTiles(let spec):
            await executeBulkTiles(spec)

        case .clear:
            engine?.clearSelection()

        case .comment(let text):
            currentComment = text
            Self.logger.info("TileScript comment: \(text)")

        case .wait(let duration):
            do { try await Task.sleep(for: duration) } catch { return }

        case .setAudio(let enabled):
            engine?.audioEnabled = enabled

        case .setTileWait(let value):
            tileWait = value

        case .setSentenceWait(let value):
            sentenceWait = value

        case .setProvider(let name):
            applyProvider(name)

        case .setScene(let name):
            await activateScene(named: name)
        }
    }

    // MARK: - Tile Row Execution

    private func executeTileRows(_ rows: [TileRow]) async {
        currentRowCount = rows.count

        while rowIndex < rows.count {
            guard !Task.isCancelled else { return }

            currentRow = rows[rowIndex]
            actionIndex = 0

            // In step mode, pause BEFORE executing each row so the user sees what's next
            if state == .paused {
                await waitForResume()
                if Task.isCancelled { return }
            }

            let row = rows[rowIndex]

            if stepMode == .stepInto {
                await executeRowStepInto(row)
            } else {
                await executeRow(row)
            }

            if Task.isCancelled { return }

            rowIndex += 1
            actionIndex = 0

            // Point to next row for display
            if rowIndex < rows.count {
                currentRow = rows[rowIndex]
            }

            // stepOver: pause after executing this row, before the next
            if stepMode == .stepOver {
                if rowIndex < rows.count {
                    state = .paused
                    stepMode = nil
                    engine?.cancelIdleTimer()
                } else {
                    // Last row in block — let executeScript handle the pause
                    // so it can advance commandIndex first
                }
            }
        }

        // continueTo: pause after the entire tiles block
        if stepMode == .continueTo {
            state = .paused
            stepMode = nil
            engine?.cancelIdleTimer()
        }
    }

    /// Execute a row action-by-action, pausing after each for step-into.
    private func executeRowStepInto(_ row: TileRow) async {
        while actionIndex < row.actions.count {
            guard !Task.isCancelled else { return }

            await executeAction(row.actions[actionIndex])
            actionIndex += 1

            // If more actions in this row, pause to show next action highlighted
            if actionIndex < row.actions.count && stepMode == .stepInto {
                state = .paused
                stepMode = nil
                engine?.cancelIdleTimer()
                await waitForResume()
                if Task.isCancelled { return }
            }
        }

        // All actions done — sentence + speech + clear
        await waitForSentence()
        await waitForSpeech()
        if sentenceWait.duration > .zero {
            do { try await Task.sleep(for: sentenceWait.duration) } catch { return }
        }
        engine?.clearSelection()

        // After the row completes, pause
        if stepMode == .stepInto {
            state = .paused
            stepMode = nil
            engine?.cancelIdleTimer()
        }
    }

    private func executeRow(_ row: TileRow) async {
        for (i, action) in row.actions.enumerated() {
            guard !Task.isCancelled else { return }
            actionIndex = i
            await executeAction(action)

            if tileWait.duration > .zero {
                do { try await Task.sleep(for: tileWait.duration) } catch { return }
            }
        }
        actionIndex = row.actions.count

        await waitForSentence()
        await waitForSpeech()

        if sentenceWait.duration > .zero {
            do { try await Task.sleep(for: sentenceWait.duration) } catch { return }
        }

        engine?.clearSelection()
    }

    private func executeAction(_ action: TileAction) async {
        guard let engine, let coordinator else { return }

        switch action {
        case .navigate(let pageKey):
            if pageKey == "home" {
                coordinator.navigateToRoot()
            } else {
                coordinator.navigate(to: pageKey)
            }
            engine.cancelIdleTimer()

        case .tap(let tileKey):
            guard let modelContext else { return }
            var descriptor = FetchDescriptor<TileModel>(
                predicate: #Predicate { $0.key == tileKey }
            )
            descriptor.fetchLimit = 1
            guard let tile = try? modelContext.fetch(descriptor).first else {
                Self.logger.warning("TileScript: tile '\(tileKey)' not found, skipping")
                return
            }
            engine.addTile(tile)
        }
    }

    // MARK: - Sentence / Speech Wait

    private func waitForSpeech() async {
        guard let engine else { return }
        while engine.isSpeaking && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private func waitForSentence() async {
        guard let engine else { return }
        if engine.isWaiting {
            while engine.isWaiting && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        while engine.isThinking && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    // MARK: - Bulk

    private func executeBulkTiles(_ spec: BulkTileSpec) async {
        guard let modelContext else { return }
        let generator = BulkCacheGenerator(modelContext: modelContext)
        generator.onProgress = { [weak self] completed, duplicates, total in
            self?.bulkProgress = (completed, total)
            self?.bulkDuplicates = duplicates
        }
        bulkProgress = (0, spec.count)
        bulkDuplicates = 0
        await generator.generate(spec: spec)
        // Keep final stats visible until cleared
        bulkProgress = (spec.count, spec.count)
        bulkDuplicates = generator.duplicateCount
    }

    // MARK: - Pause/Resume

    private func waitForResume() async {
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
        }
    }

    // MARK: - Helpers

    private func applyProvider(_ name: String) {
        switch name.lowercased() {
        case "mock":
            engine?.switchProvider(MockSentenceProvider())
        case "openai":
            let key = UserDefaults.standard.string(forKey: AppSettingsKey.openaiApiKey) ?? ""
            if !key.isEmpty {
                engine?.switchProvider(OpenAISentenceProvider(apiKey: key))
            }
        default:
            Self.logger.warning("TileScript: unknown provider '\(name)'")
        }
    }

    private func activateScene(named name: String) async {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<BlasterScene>()
        guard let scenes = try? modelContext.fetch(descriptor) else { return }
        guard let target = scenes.first(where: { $0.name == name }) else {
            Self.logger.warning("TileScript: scene '\(name)' not found")
            return
        }
        try? target.activate(context: modelContext)
    }

    // MARK: - Command Description

    private func describeCommand(_ command: TileScriptCommand) -> String {
        switch command {
        case .tiles:
            return "tiles"
        case .bulkTiles(let spec):
            return "bulk: \(spec.count) entries"
        case .clear:
            return "clear"
        case .comment(let text):
            return text
        case .wait(let duration):
            let ms = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
            return "wait: \(ms)ms"
        case .setAudio(let enabled):
            return "audio: \(enabled ? "on" : "off")"
        case .setTileWait(let value):
            return "tileWait: \(describeTimingValue(value))"
        case .setSentenceWait(let value):
            return "sentenceWait: \(describeTimingValue(value))"
        case .setProvider(let name):
            return "provider: \(name)"
        case .setScene(let name):
            return "scene: \(name)"
        }
    }

    private func describeTimingValue(_ value: TimingValue) -> String {
        switch value {
        case .human: return ".human"
        case .fast: return ".fast"
        case .instant: return ".instant"
        case .explicit(let ms): return "\(ms)ms"
        }
    }
}
