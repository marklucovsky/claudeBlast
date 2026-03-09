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
    var sessionNotes: String = ""

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
        clearSelection()
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
        debounceTask?.cancel()
        debounceTask = nil
        idleTask?.cancel()
        idleTask = nil
        selectedTiles.removeAll()
        generatedSentence = nil
        isThinking = false
        isWaiting = false
        repetitionCount = 0
        lastTileKey = nil
        speechSynthesizer.stop()
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

        let apiStart = ContinuousClock.now
        do {
            let result = try await provider.generateSentence(
                tiles: tiles,
                systemPrompt: systemPrompt,
                conversationContext: conversationHistory + [userPrompt]
            )
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
            appendToHistory(result.text)
            recordHistory(tiles: tiles, sentence: result.text)

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
        }

        isThinking = false
    }

    /// Play a promoted (cached) phrase directly — no API call, instant feedback.
    func speakPromoted(_ entry: SentenceCache) {
        clearSelection()
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
}

private extension Duration {
    var timeInterval: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
