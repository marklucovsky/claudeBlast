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
    /// True after the idle wait has elapsed AND the active group is not yet locked. Drives the
    /// play-button rainbow pulse — only nags the user when tiles have changed and a sentence
    /// hasn't been generated. Cleared when the user adds/removes a tile, taps Go, or generates.
    private(set) var isIdleNudge: Bool = false
    /// Fires `doneAttentionLead` seconds after the active group locks (post-Play). Resets on any
    /// tile add/remove or fresh Play, since those re-arm the idle timer task and reset the
    /// flag. The Done button drives its own escalating animation (blue → green → red, ramping
    /// in border / weight / shadow) internally once this flips true.
    private(set) var isDoneNudge: Bool = false
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

    /// Long idle timeout that auto-commits the active group to history (auto-Done). 0 disables.
    /// Default 30s if no value stored, clamped to 5s..2min when set.
    var autoDoneDuration: Duration {
        let ms = UserDefaults.standard.integer(forKey: AppSettingsKey.autoDoneMs)
        if ms == 0 { return .seconds(0) }
        let clamped = (5000...120000).contains(ms) ? ms : 30000
        return .milliseconds(clamped)
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
    /// - If there's room under the cap the tile is appended. A locked active group transitions to
    ///   `.unlockedEditable` (its sentence is now stale); the idle timers restart and the next
    ///   generation reflects the updated tile set.
    /// - At cap the tap is ignored. Use Done (commitActiveAndStartNew) to commit and start fresh.
    func addTile(_ tile: TileModel) {
        let selection = TileSelection(from: tile)

        // Toggle-off if tile is already in the active group.
        if let index = activeGroup.tiles.firstIndex(where: { $0.key == selection.key }) {
            removeTile(at: index)
            return
        }

        guard activeGroup.tiles.count < maxTilesPerGroup else { return }

        // Locked → unlocked: the stale sentence will be cleared by scheduleGeneration().
        if activeGroup.state == .locked {
            activeGroup.state = .unlockedEditable
        }

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
            isIdleNudge = false
            isDoneNudge = false
            speechSynthesizer.stop()
        } else {
            scheduleGeneration()
        }
    }

    /// Explicit "Go" tap — generate immediately. The default path now (auto-generation on idle is
    /// disabled except at cap). No-op if there aren't enough tiles or the group is already locked.
    func triggerGo() {
        guard activeGroup.tiles.count >= 2 else { return }
        guard activeGroup.state != .locked else { return }

        debounceTask?.cancel()
        isWaiting = true
        isIdleNudge = false
        isDoneNudge = false

        let tilesSnapshot = activeGroup.tiles
        let repetition = updateRepetitionState(for: tilesSnapshot)
        debounceTask = Task { [weak self] in
            guard let self else { return }
            await self.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    /// Clear the active group (no history change). Used by scene switching, the bubble's "×"
    /// dismiss, and speakPromoted's overwrite path. Fires onWillClear so script recording can
    /// finalize the row.
    func clearSelection() {
        onWillClear?(activeGroup.sentence)
        debounceTask?.cancel()
        debounceTask = nil
        activeGroup = TileGroup()
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        isIdleNudge = false
        isDoneNudge = false
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
        // Set isThinking synchronously so external observers (notably TileScriptRunner.waitFor-
        // Sentence) can race-freely detect that generation is in flight. generate() will also set
        // it at its top; the redundant assignment is harmless.
        isThinking = true
        isIdleNudge = false
        Task { [weak self] in
            guard let self else { return }
            await self.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    // MARK: - History group interactions

    /// Speak + reopen an older history group. The current active group flushes to history first,
    /// then the target group is promoted to the active slot as .unlockedEditable so it can be
    /// further edited.
    func reopenHistoryGroup(id: UUID) {
        // Verify target exists before doing any work — but DON'T cache its index here.
        // flushActiveToHistory() may prepend the current active to history and shift indices.
        guard groupHistory.contains(where: { $0.id == id }) else { return }
        flushActiveToHistory()

        guard let index = groupHistory.firstIndex(where: { $0.id == id }) else { return }
        var target = groupHistory.remove(at: index)

        if let sentence = target.sentence {
            // Reopening a group with a sentence is equivalent to a fresh Play: lock the group
            // and speak it. The startIdleTimers task below will see state == .locked, skip the
            // play-button pulse (no nag — the user just heard it), and fire the Done attention
            // ramp + auto-Done as if the user had just tapped Play. Adding a new tile later
            // unlocks and clears the sentence as usual via addTile().
            target.state = .locked
            activeGroup = target
            speak(sentence)
        } else {
            // No sentence on the history entry (defensive — current code always assigns one).
            // Treat as editable so the user can keep building.
            target.state = .unlockedEditable
            activeGroup = target
        }

        startIdleTimers()
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
    /// By default only flushes groups that produced a sentence — empty or in-flight groups are
    /// discarded. Pass `allowWithoutSentence: true` (used by the tray's explicit clear/Done
    /// button) to commit a partially-built group; the spelled-out tile values are stored as the
    /// sentence so the history chip and conversation context both have text to show.
    private func flushActiveToHistory(allowWithoutSentence: Bool = false) {
        onWillClear?(activeGroup.sentence)
        debounceTask?.cancel()
        debounceTask = nil
        isIdleNudge = false
        isDoneNudge = false

        let shouldFlush = !activeGroup.tiles.isEmpty
            && (activeGroup.sentence != nil || allowWithoutSentence)

        if shouldFlush {
            var finalized = activeGroup
            finalized.state = .locked
            if finalized.sentence == nil {
                finalized.sentence = activeGroup.tiles.map(\.value).joined(separator: " ")
            }
            groupHistory.insert(finalized, at: 0)
            // Trim to configured buffer size.
            let limit = trayBufferSize
            if groupHistory.count > limit {
                groupHistory.removeLast(groupHistory.count - limit)
            }
            // Persist the finalized utterance for therapist review (AdminView → Activity Log).
            // Final-state only: replay escalation is captured by repetitionCount, not as
            // separate rows.
            cacheManager?.logUtterance(
                tiles: finalized.tiles,
                sentence: finalized.sentence ?? "",
                repetitionCount: finalized.repetitionCount
            )
        }

        activeGroup = TileGroup()
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        speechSynthesizer.stop()
    }

    /// Explicit commit: flush the active group to history (even without a generated sentence)
    /// and reset. Wired to the tray's Done/clear button under the play control.
    func commitActiveAndStartNew() {
        flushActiveToHistory(allowWithoutSentence: true)
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
        isIdleNudge = false
        isDoneNudge = false

        // Single tile: no preview on the group; the view derives a spelled-out preview from
        // activeGroup.tiles. No API call, no idle timers.
        guard activeGroup.tiles.count >= 2 else {
            isWaiting = false
            return
        }

        let hitCap = activeGroup.tiles.count >= maxTilesPerGroup

        if hitCap {
            // Hit cap: auto-generate immediately, no idle nudge needed.
            isWaiting = true
            let tilesSnapshot = activeGroup.tiles
            let repetition = updateRepetitionState(for: tilesSnapshot)
            debounceTask = Task { [weak self] in
                guard let self else { return }
                await self.generate(tiles: tilesSnapshot, repetition: repetition)
            }
        } else {
            // Pre-cap: do NOT auto-generate. Run the two-stage idle timer (pulse → auto-Done).
            isWaiting = false
            startIdleTimers()
        }
    }

    /// Idle-timeline staging anchored to T=0 = "user just did something tile-related" — either
    /// added/removed a tile (state is building or unlocked-editable) or tapped Play and locked
    /// the group. Stages fire in time order:
    ///
    ///   1. Play-button pulse at `idleDebounceDuration` (~2.5s) — only for non-locked groups
    ///      (locked groups have already been spoken; no nag).
    ///   2. Done-button attention at `doneAttentionLead` (~5s post-lock) — only for locked
    ///      groups. Once true, the Done button owns its own internal escalation animation; the
    ///      engine just provides the binary trigger.
    ///   3. Auto-Done at `autoDoneWait` — `commitActiveAndStartNew()`.
    ///
    /// Auto-Done is skipped when `autoDoneDuration == .seconds(0)`. The Done attention stage is
    /// skipped when its trigger time falls behind a prior stage (e.g. user picked a very short
    /// pulse or auto-Done that overlaps).
    private static let doneAttentionLead: Duration = .seconds(5)

    private func startIdleTimers() {
        debounceTask?.cancel()
        guard activeGroup.tiles.count >= 2 else { return }

        let pulseWait = idleDebounceDuration
        let autoDoneWait = autoDoneDuration
        debounceTask = Task { [weak self] in
            // Stage 1: play-button pulse (only when not yet locked).
            do { try await Task.sleep(for: pulseWait) } catch { return }
            guard !Task.isCancelled, let self else { return }
            if self.activeGroup.state != .locked {
                self.isIdleNudge = true
            }

            // Auto-Done disabled → stop here.
            guard autoDoneWait > pulseWait else { return }

            var elapsed = pulseWait

            // Stage 2: Done attention at T=doneAttentionLead. Only for locked groups; the Done
            // button handles its own ramp from here.
            let attentionAt = Self.doneAttentionLead
            if attentionAt > elapsed && attentionAt < autoDoneWait {
                let until = attentionAt - elapsed
                do { try await Task.sleep(for: until) } catch { return }
                guard !Task.isCancelled else { return }
                if self.activeGroup.state == .locked {
                    self.isDoneNudge = true
                }
                elapsed = attentionAt
            }

            // Stage 3: auto-Done.
            let remaining = autoDoneWait - elapsed
            guard remaining > .seconds(0) else { return }
            do { try await Task.sleep(for: remaining) } catch { return }
            guard !Task.isCancelled else { return }
            self.commitActiveAndStartNew()
        }
    }

    private func generate(tiles: [TileSelection], repetition: Int) async {
        isWaiting = false
        isThinking = true
        isIdleNudge = false
        isDoneNudge = false

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
            startIdleTimers()
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

        // Provider treats the conversation context as a sequence of prior assistant turns, with
        // the last entry replaced as the user prompt. For escalation/replay we want the model to
        // see the exact sentence it is escalating from — but `conversationHistory` (derived from
        // `groupHistory`) doesn't include it (the group was popped by `reopenHistoryGroup`, or
        // the active group's sentence simply hasn't been flushed). Splice it in here so escalation
        // requests carry the prior turn explicitly.
        var contextWithPrior = conversationHistory
        if repetition > 0, let prior = activeGroup.sentence {
            contextWithPrior.append(prior)
        }
        let context = contextWithPrior + [userPrompt]
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
            isThinking = false
            startIdleTimers()
            return
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
