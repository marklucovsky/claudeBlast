// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceEngine.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import os

struct HistoryEntry: Identifiable {
    let id = UUID()
    let tiles: [TileSelection]
    let sentence: String
    let timestamp: Date
}

@Observable
@MainActor
final class SentenceEngine {
    // MARK: - Published state

    /// The rightmost (in-progress or just-spoken) group. Always present, may be empty.
    private(set) var activeGroup: TileGroup = TileGroup()

    /// Newest-first rolling buffer of closed groups (newest at index 0). Capped by trayBufferSize.
    private(set) var groupHistory: [TileGroup] = []

    private(set) var isThinking: Bool = false
    private(set) var isWaiting: Bool = false
    private(set) var comparisonSentence: String?
    var sessionNotes: String = ""

    // MARK: - Backwards-compatible accessors

    /// The active group's tiles. Used by views built before the timeline refactor.
    var selectedTiles: [TileSelection] { activeGroup.tiles }

    /// The active group's generated sentence (or single-tile preview).
    var generatedSentence: String? { activeGroup.sentence }

    /// Closed groups exposed as legacy HistoryEntry items for the (soon-to-be-retired) history sheet.
    var recentHistory: [HistoryEntry] {
        groupHistory.prefix(maxHistorySheetEntries).compactMap { group in
            guard let sentence = group.sentence else { return nil }
            return HistoryEntry(tiles: group.tiles, sentence: sentence, timestamp: group.createdAt)
        }
    }

    /// Called with the active group's generatedSentence just before the group is flushed to history
    /// or the engine is reset. Used by TileScriptRecorder to finalize the current row.
    var onWillClear: ((String?) -> Void)?

    /// Called when a real multi-tile sentence is generated (from cache or API, 2+ tiles).
    /// Single-tile display names do NOT trigger this.
    var onSentenceReady: ((String) -> Void)?

    var isSpeaking: Bool { speechSynthesizer.isSpeaking }

    func appendNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !sessionNotes.isEmpty { sessionNotes += "\n" }
        sessionNotes += trimmed
    }

    // MARK: - Configuration

    private(set) var provider: any SentenceProvider
    var audioEnabled: Bool = true
    var voiceIdentifier: String = ""
    var compareProviders: Bool = false

    /// Max tiles per group; backed by AppStorage. Read on every check so live setting changes apply.
    var maxTilesPerGroup: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettingsKey.tileCapPerGroup)
        return (2...8).contains(stored) ? stored : 4
    }

    /// Idle debounce before auto-generation; backed by AppStorage.
    var idleDebounceDuration: Duration {
        let ms = UserDefaults.standard.integer(forKey: AppSettingsKey.idleDebounceMs)
        let clamped = (500...5000).contains(ms) ? ms : 2500
        return .milliseconds(clamped)
    }

    /// Max number of closed groups retained in groupHistory; backed by AppStorage.
    var trayBufferSize: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettingsKey.trayBufferSize)
        return (50...500).contains(stored) ? stored : 100
    }

    // MARK: - Dependencies

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "SentenceEngine")
    private var cacheManager: SentenceCacheManager?
    private let speechSynthesizer = SpeechSynthesizer()

    // MARK: - Internal state

    private var debounceTask: Task<Void, Never>?
    private var repetitionCount: Int = 0
    private var lastTileKey: String?
    private let maxConversationHistory = 5
    private let maxHistorySheetEntries = 10

    /// Last N generated sentences fed back as conversational context to the model.
    private var conversationHistory: [String] {
        Array(
            groupHistory
                .compactMap { $0.sentence }
                .prefix(maxConversationHistory)
                .reversed()
        )
    }

    // MARK: - Init

    init(provider: any SentenceProvider) {
        self.provider = provider
    }

    /// Must be called after init to wire up SwiftData cache.
    func configure(modelContext: ModelContext) {
        self.cacheManager = SentenceCacheManager(modelContext: modelContext)
    }

    // MARK: - Provider switching

    func switchProvider(_ newProvider: any SentenceProvider) {
        resetAll()
        provider = newProvider
    }

    // MARK: - Tile management

    /// Add a tile in response to a grid tap.
    /// - If the tile is already in the active group, this toggles it off (same as removeTile).
    /// - If the active group is locked, it is flushed to history and a new active group is seeded.
    /// - Otherwise the tile is appended to the active group; cap or debounce triggers generation.
    func addTile(_ tile: TileModel) {
        let selection = TileSelection(from: tile)

        // Toggle-off if tile is already in the active group.
        if let index = activeGroup.tiles.firstIndex(where: { $0.key == selection.key }) {
            removeTile(at: index)
            return
        }

        // Locked group: flush to history, then start a fresh active group with this tile.
        if activeGroup.state == .locked {
            flushActiveToHistory()
        }

        guard activeGroup.tiles.count < maxTilesPerGroup else { return }

        activeGroup.tiles.append(selection)
        cacheManager?.logEvent(subjectType: "tile", subjectKey: tile.key, eventType: .selected)
        scheduleGeneration()
    }

    /// Remove a tile from the active group.
    /// - From a locked group: transitions to .unlockedEditable; the stale sentence stays visible
    ///   until the next generation completes.
    /// - From an editable group: simply removes and reschedules generation.
    func removeTile(at index: Int) {
        guard activeGroup.tiles.indices.contains(index) else { return }

        let wasLocked = activeGroup.state == .locked
        activeGroup.tiles.remove(at: index)

        if wasLocked {
            activeGroup.state = .unlockedEditable
        }

        if activeGroup.tiles.isEmpty {
            debounceTask?.cancel()
            debounceTask = nil
            activeGroup.sentence = nil
            activeGroup.state = .building
            comparisonSentence = nil
            isThinking = false
            isWaiting = false
            speechSynthesizer.stop()
        } else {
            scheduleGeneration()
        }
    }

    /// Explicit "Go" tap — generate immediately, skipping the debounce wait.
    /// No-op if there aren't enough tiles or the group is already locked.
    func triggerGo() {
        guard activeGroup.tiles.count >= 2 else { return }
        guard activeGroup.state != .locked else { return }

        debounceTask?.cancel()
        isWaiting = false

        let tilesSnapshot = activeGroup.tiles
        let repetition = updateRepetitionState(for: tilesSnapshot)
        debounceTask = Task { [weak self] in
            guard let self else { return }
            await self.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    /// Clear the active group (no history change). Used by scene switching and by speakPromoted
    /// to overwrite the active slot. Fires onWillClear so script recording can finalize the row.
    func clearSelection() {
        onWillClear?(activeGroup.sentence)
        debounceTask?.cancel()
        debounceTask = nil
        activeGroup = TileGroup()
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        // Preserve repetitionCount and lastTileKey so escalation works across clear cycles
        // (e.g., TileScript rows). They reset naturally when a different combo is selected.
        speechSynthesizer.stop()
    }

    /// Full reset: clear active group AND history AND escalation state.
    /// Used by AdminView "Reset session" and by switchProvider.
    func resetAll() {
        clearSelection()
        groupHistory.removeAll()
        repetitionCount = 0
        lastTileKey = nil
    }

    /// Admin-only: reset the visible session (active + history).
    func resetSession() {
        resetAll()
    }

    // MARK: - Replay

    var canReplay: Bool {
        activeGroup.state == .locked && activeGroup.sentence != nil && !isThinking
    }

    /// Replay the active group's sentence using escalation (repetition increments, cache bypassed).
    /// Only valid when the active group is locked.
    func replay() {
        guard canReplay else { return }
        repetitionCount += 1
        let tilesSnapshot = activeGroup.tiles
        let repetition = repetitionCount
        Task { [weak self] in
            guard let self else { return }
            await self.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    // MARK: - History group interactions

    /// Speak + reopen an older history group. The current active group flushes to history first,
    /// then the target group is promoted to the active slot as .unlockedEditable so it can be
    /// further edited. Not yet wired into PR1 UI; here so PR2 can call it.
    func reopenHistoryGroup(id: UUID) {
        guard let index = groupHistory.firstIndex(where: { $0.id == id }) else { return }
        flushActiveToHistory()

        var target = groupHistory.remove(at: index)
        target.state = .unlockedEditable
        activeGroup = target

        if let sentence = target.sentence {
            speak(sentence)
        }
    }

    /// Delete a history group. Power-user gesture, surfaced in PR2 UI.
    func deleteHistoryGroup(id: UUID) {
        groupHistory.removeAll { $0.id == id }
    }

    /// Legacy history-sheet replay path. Reconstructs an old utterance into the active group.
    /// Kept for any callers that still bind to HistoryEntry; will be removed when the sheet is
    /// fully retired in PR3.
    func replayFromHistory(_ entry: HistoryEntry) {
        if let match = groupHistory.first(where: {
            $0.tiles.map(\.key) == entry.tiles.map(\.key) && $0.sentence == entry.sentence
        }) {
            reopenHistoryGroup(id: match.id)
            return
        }
        // Fallback: synthesize an active group from the legacy entry.
        clearSelection()
        activeGroup.tiles = entry.tiles
        activeGroup.sentence = entry.sentence
        activeGroup.state = .unlockedEditable
        speak(entry.sentence)
    }

    // MARK: - Idle timer (no-op shim)

    /// Retained for callers that used to cancel the 30s idle clear. The idle clear is gone in
    /// the timeline model, so this is now a no-op. Kept to avoid touching every call site.
    func cancelIdleTimer() {
        // Intentionally no-op.
    }

    // MARK: - Flush

    /// Move the active group into history (newest-first) and reset the active slot.
    /// Only flushes groups that produced a sentence; empty or in-flight groups are discarded.
    private func flushActiveToHistory() {
        onWillClear?(activeGroup.sentence)
        debounceTask?.cancel()
        debounceTask = nil

        if let _ = activeGroup.sentence, !activeGroup.tiles.isEmpty {
            var finalized = activeGroup
            finalized.state = .locked
            groupHistory.insert(finalized, at: 0)
            // Trim to configured buffer size.
            let limit = trayBufferSize
            if groupHistory.count > limit {
                groupHistory.removeLast(groupHistory.count - limit)
            }
        }

        activeGroup = TileGroup()
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        speechSynthesizer.stop()
    }

    // MARK: - Generation pipeline

    private func updateRepetitionState(for tiles: [TileSelection]) -> Int {
        let currentKey = SentenceCacheManager.cacheKey(for: tiles)
        if currentKey == lastTileKey {
            repetitionCount += 1
        } else {
            repetitionCount = 0
            lastTileKey = currentKey
        }
        return repetitionCount
    }

    private func scheduleGeneration() {
        debounceTask?.cancel()
        activeGroup.sentence = nil
        comparisonSentence = nil
        isThinking = false

        // Single tile: show display name immediately, no API call, no lock.
        if activeGroup.tiles.count == 1 {
            activeGroup.sentence = activeGroup.tiles[0].value
            isWaiting = false
            return
        }

        guard activeGroup.tiles.count >= 2 else {
            isWaiting = false
            return
        }

        isWaiting = true

        let tilesSnapshot = activeGroup.tiles
        let repetition = updateRepetitionState(for: tilesSnapshot)
        let hitCap = tilesSnapshot.count >= maxTilesPerGroup

        if hitCap {
            // Hit cap: auto-generate immediately (no debounce wait).
            debounceTask = Task { [weak self] in
                guard let self else { return }
                await self.generate(tiles: tilesSnapshot, repetition: repetition)
            }
        } else {
            let wait = idleDebounceDuration
            debounceTask = Task { [weak self] in
                do { try await Task.sleep(for: wait) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.generate(tiles: tilesSnapshot, repetition: repetition)
            }
        }
    }

    private func generate(tiles: [TileSelection], repetition: Int) async {
        isWaiting = false
        isThinking = true

        // Escalation: still count the hit even though we bypass the cached sentence
        if repetition > 0 {
            cacheManager?.recordHit(tiles: tiles)
        }

        // Cache lookup (skip for replay/escalation requests)
        if repetition == 0, let cached = cacheManager?.lookup(tiles: tiles) {
            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            Self.logger.info("generate: source=cache tiles=[\(tileKeys)] sentence=\"\(cached.sentence)\"")
            cacheManager?.logEvent(subjectType: "cache", subjectKey: cached.cacheKey, eventType: .hit)
            activeGroup.sentence = cached.sentence
            activeGroup.state = .locked
            onSentenceReady?(cached.sentence)
            speak(cached.sentence)
            isThinking = false
            return
        }

        // Build prompt
        var promptBuilder = SentencePromptBuilder()
        promptBuilder.repetitionCount = repetition
        promptBuilder.conversationContext = conversationHistory
        let systemPrompt = promptBuilder.buildSystemPrompt()
        let userPrompt = promptBuilder.formatUserPrompt(tiles: tiles)

        // Fire comparison provider in parallel when enabled
        let shouldCompare = compareProviders && repetition == 0
        let comparisonProvider: (any SentenceProvider)? = shouldCompare ? makeAppleProviderIfAvailable() : nil

        let context = conversationHistory + [userPrompt]
        let apiStart = ContinuousClock.now
        do {
            let result: SentenceResult
            let comparisonText: String?

            if let compProvider = comparisonProvider {
                // Run both providers concurrently
                async let primaryTask = provider.generateSentence(
                    tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
                async let compTask = Self.safeGenerate(
                    provider: compProvider, tiles: tiles, systemPrompt: systemPrompt, context: context)

                result = try await primaryTask
                comparisonText = await compTask
            } else {
                result = try await provider.generateSentence(
                    tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
                comparisonText = nil
            }

            let elapsed = apiStart.duration(to: .now)

            if repetition == 0 {
                cacheManager?.store(tiles: tiles, sentence: result.text)
                let usedKey = SentenceCacheManager.cacheKey(for: tiles)
                cacheManager?.logEvent(subjectType: "sentence", subjectKey: usedKey, eventType: .used)
            }

            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }

            activeGroup.sentence = result.text
            activeGroup.state = .locked
            comparisonSentence = comparisonText
            onSentenceReady?(result.text)

            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            if let u = result.usage {
                Self.logger.info("""
                generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] model=\(u.model) \
                sentence=\"\(result.text)\" \
                tokens(total=\(u.totalTokens) prompt=\(u.promptTokens) completion=\(u.completionTokens) cached=\(u.promptCachedTokens))
                """)
            } else {
                Self.logger.info("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] sentence=\"\(result.text)\"")
            }
            if let comp = comparisonText {
                Self.logger.info("generate: comparison(apple)=\"\(comp)\"")
            }

            speak(result.text)
        } catch {
            let elapsed = apiStart.duration(to: .now)
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            Self.logger.error("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] error=\"\(error.localizedDescription)\"")
            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }
            activeGroup.sentence = nil
            comparisonSentence = nil
        }

        isThinking = false
    }

    /// Play a promoted (cached) phrase directly — no API call, instant feedback.
    /// Populates the active group with the entry's tiles so the child sees what was selected.
    func speakPromoted(_ entry: SentenceCache) {
        clearSelection()
        // Reconstruct tile selections from cached keys
        if let ctx = cacheManager?.context {
            let keys = entry.tileKeys
            let descriptor = FetchDescriptor<TileModel>()
            if let allTiles = try? ctx.fetch(descriptor) {
                let lookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
                for key in keys {
                    if let tile = lookup[key] {
                        activeGroup.tiles.append(TileSelection(from: tile))
                    }
                }
            }
        }
        activeGroup.sentence = entry.sentence
        activeGroup.state = .locked
        cacheManager?.logEvent(subjectType: "promoted", subjectKey: entry.cacheKey, eventType: .hit)
        speak(entry.sentence)
    }

    func speakTile(_ text: String) {
        speak(text)
    }

    private func speak(_ text: String) {
        guard audioEnabled else { return }
        let vid = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        speechSynthesizer.speak(text, voiceIdentifier: vid)
    }

    // MARK: - Comparison helpers

    private func makeAppleProviderIfAvailable() -> (any SentenceProvider)? {
        if #available(iOS 26, *) {
            return AppleSentenceProvider()
        }
        return nil
    }

    /// Runs a provider's generateSentence without throwing — returns nil on failure.
    private static func safeGenerate(
        provider: any SentenceProvider,
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        context: [String]
    ) async -> String? {
        do {
            let result = try await provider.generateSentence(
                tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
            return result.text
        } catch {
            logger.warning("comparison provider failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private extension Duration {
    var timeInterval: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
