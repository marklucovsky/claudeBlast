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

    private(set) var selectedTiles: [TileSelection] = []
    private(set) var generatedSentence: String?
    private(set) var isThinking: Bool = false
    private(set) var isWaiting: Bool = false
    private(set) var recentHistory: [HistoryEntry] = []
    private(set) var comparisonSentence: String?
    var sessionNotes: String = ""

    /// Called with the current generatedSentence just before clearSelection() wipes state.
    /// Used by TileScriptRecorder to capture sentence text and finalize the current row.
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
    let maxTiles: Int = 4

    // MARK: - Dependencies

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "SentenceEngine")
    private var cacheManager: SentenceCacheManager?
    private let speechSynthesizer = SpeechSynthesizer()

    // MARK: - Internal state

    private var debounceTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var conversationHistory: [String] = []
    private var repetitionCount: Int = 0
    private var lastTileKey: String?
    private let maxConversationHistory = 5
    private let debounceDuration: Duration = .milliseconds(350)
    private let idleTimeout: Duration = .seconds(30)
    private let maxHistory = 10

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
        conversationHistory.removeAll()
        provider = newProvider
    }

    // MARK: - Tile management

    func addTile(_ tile: TileModel) {
        guard selectedTiles.count < maxTiles else { return }
        let selection = TileSelection(from: tile)
        guard !selectedTiles.contains(where: { $0.key == selection.key }) else { return }
        idleTask?.cancel()
        selectedTiles.append(selection)
        cacheManager?.logEvent(subjectType: "tile", subjectKey: tile.key, eventType: .selected)
        scheduleGeneration()
    }

    func removeTile(at index: Int) {
        guard selectedTiles.indices.contains(index) else { return }
        idleTask?.cancel()
        selectedTiles.remove(at: index)
        if selectedTiles.isEmpty {
            clearSelection()
        } else {
            scheduleGeneration()
        }
    }

    func clearSelection() {
        onWillClear?(generatedSentence)
        debounceTask?.cancel()
        debounceTask = nil
        idleTask?.cancel()
        idleTask = nil
        selectedTiles.removeAll()
        generatedSentence = nil
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        // Preserve repetitionCount and lastTileKey so escalation
        // works across clear cycles (e.g., TileScript rows).
        // They reset naturally in scheduleGeneration() when a
        // different combo is selected.
        speechSynthesizer.stop()
    }

    /// Full reset including escalation state. Used when switching
    /// providers or contexts where repetition history should not carry over.
    func resetAll() {
        clearSelection()
        repetitionCount = 0
        lastTileKey = nil
    }

    // MARK: - Replay

    var canReplay: Bool {
        selectedTiles.count >= 2 && !isThinking && generatedSentence != nil
    }

    func replay() {
        guard canReplay else { return }
        idleTask?.cancel()
        repetitionCount += 1
        let tilesSnapshot = selectedTiles
        let repetition = repetitionCount
        Task {
            await generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    // MARK: - History

    func replayFromHistory(_ entry: HistoryEntry) {
        clearSelection()
        selectedTiles = entry.tiles
        Task {
            await generate(tiles: entry.tiles, repetition: 0)
        }
    }

    private func recordHistory(tiles: [TileSelection], sentence: String) {
        recentHistory.removeAll { Set($0.tiles.map(\.key)) == Set(tiles.map(\.key)) }
        recentHistory.insert(HistoryEntry(tiles: tiles, sentence: sentence, timestamp: .now), at: 0)
        if recentHistory.count > maxHistory { recentHistory.removeLast() }
    }

    // MARK: - Idle timer

    func cancelIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
    }

    private func startIdleTimer() {
        idleTask?.cancel()
        idleTask = Task {
            do { try await Task.sleep(for: idleTimeout) } catch { return }
            clearSelection()
        }
    }

    // MARK: - Generation pipeline

    private func scheduleGeneration() {
        debounceTask?.cancel()
        generatedSentence = nil
        isThinking = false

        // Single tile: show display name immediately, no API call
        if selectedTiles.count == 1 {
            generatedSentence = selectedTiles[0].value
            isWaiting = false
            recordHistory(tiles: selectedTiles, sentence: selectedTiles[0].value)
            return
        }

        isWaiting = true

        // Track repetition
        let currentKey = SentenceCacheManager.cacheKey(for: selectedTiles)
        if currentKey == lastTileKey {
            repetitionCount += 1
        } else {
            repetitionCount = 0
            lastTileKey = currentKey
        }

        let tilesSnapshot = selectedTiles
        let repetition = repetitionCount

        debounceTask = Task {
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return // cancelled
            }

            guard !Task.isCancelled else { return }
            await generate(tiles: tilesSnapshot, repetition: repetition)
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
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            Self.logger.info("generate: source=cache tiles=[\(tileKeys)] sentence=\"\(cached.sentence)\"")
            cacheManager?.logEvent(subjectType: "cache", subjectKey: cached.cacheKey, eventType: .hit)
            generatedSentence = cached.sentence
            appendToHistory(cached.sentence)
            recordHistory(tiles: tiles, sentence: cached.sentence)
            onSentenceReady?(cached.sentence)
            speak(cached.sentence)
            isThinking = false
            startIdleTimer()
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

            guard tiles == selectedTiles else {
                isThinking = false
                return
            }

            generatedSentence = result.text
            comparisonSentence = comparisonText
            appendToHistory(result.text)
            recordHistory(tiles: tiles, sentence: result.text)
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
            startIdleTimer()
        } catch {
            let elapsed = apiStart.duration(to: .now)
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            Self.logger.error("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] error=\"\(error.localizedDescription)\"")
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            generatedSentence = nil
            comparisonSentence = nil
        }

        isThinking = false
    }

    /// Play a promoted (cached) phrase directly — no API call, instant feedback.
    /// Populates the tray with the entry's tiles so the child sees what was selected.
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
                        selectedTiles.append(TileSelection(from: tile))
                    }
                }
            }
        }
        generatedSentence = entry.sentence
        cacheManager?.logEvent(subjectType: "promoted", subjectKey: entry.cacheKey, eventType: .hit)
        speak(entry.sentence)
        startIdleTimer()
    }

    func speakTile(_ text: String) {
        speak(text)
    }

    private func speak(_ text: String) {
        guard audioEnabled else { return }
        let vid = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        speechSynthesizer.speak(text, voiceIdentifier: vid)
    }

    private func appendToHistory(_ sentence: String) {
        conversationHistory.append(sentence)
        if conversationHistory.count > maxConversationHistory {
            conversationHistory.removeFirst()
        }
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
