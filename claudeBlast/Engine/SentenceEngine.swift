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

    var isPlaying: Bool { audioPlayer.isPlaying }

    func appendNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !sessionNotes.isEmpty { sessionNotes += "\n" }
        sessionNotes += trimmed
    }

    // MARK: - Configuration

    private(set) var provider: any SentenceProvider
    var audioEnabled: Bool = true
    let maxTiles: Int = 4

    // MARK: - Dependencies

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "SentenceEngine")
    private var cacheManager: SentenceCacheManager?
    private let audioPlayer = AudioPlayer()

    // MARK: - Internal state

    private var debounceTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var conversationHistory: [String] = []
    private var repetitionCount: Int = 0
    private var lastTileKey: String?
    private let maxConversationHistory = 5
    private let debounceDuration: Duration = .milliseconds(350)
    private let idleTimeout: Duration = .seconds(10)
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
        // Prevent duplicate tiles — repetition is handled by the repetition counter
        guard !selectedTiles.contains(where: { $0.key == selection.key }) else { return }
        idleTask?.cancel()
        selectedTiles.append(selection)
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
        audioPlayer.stop()
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
        audioPlayer.stop()

        // Single tile: show display name immediately, no API call
        if selectedTiles.count == 1 {
            generatedSentence = selectedTiles[0].value
            isWaiting = false
            recordHistory(tiles: selectedTiles, sentence: selectedTiles[0].value)
            // No idle timer — timer only runs after a full generateSentence completes
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

        let requestAudio = audioEnabled && provider.supportsIntegratedAudio

        // Cache lookup (skip for replay/escalation requests)
        if repetition == 0, let cached = cacheManager?.lookup(tiles: tiles) {
            // Staleness guard
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            Self.logger.info("generate: source=cache elapsed=0.000s tiles=[\(tileKeys)] sentence=\"\(cached.sentence)\" hasAudio=\(!cached.audioData.isEmpty)")
            generatedSentence = cached.sentence
            appendToHistory(cached.sentence)
            recordHistory(tiles: tiles, sentence: cached.sentence)
            // Play cached audio if available
            if !cached.audioData.isEmpty,
               let data = Data(base64Encoded: cached.audioData) {
                audioPlayer.play(data: data)
            }
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
                conversationContext: conversationHistory + [userPrompt],
                requestAudio: requestAudio
            )
            let elapsed = apiStart.duration(to: .now)

            // Encode audio for cache storage
            let audioBase64 = result.audioData?.base64EncodedString() ?? ""

            // Cache the result only for first-time (non-replay) requests
            if repetition == 0 {
                cacheManager?.store(tiles: tiles, sentence: result.text, audioData: audioBase64)
            }

            // Staleness guard: only display if tiles haven't changed
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }

            generatedSentence = result.text
            appendToHistory(result.text)
            recordHistory(tiles: tiles, sentence: result.text)

            // Log API response
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            if let u = result.usage {
                Self.logger.info("""
                generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] model=\(u.model) \
                sentence=\"\(result.text)\" hasAudio=\(result.audioData != nil) \
                tokens(total=\(u.totalTokens) prompt=\(u.promptTokens) completion=\(u.completionTokens)) \
                prompt_detail(text=\(u.promptTextTokens) audio=\(u.promptAudioTokens) cached=\(u.promptCachedTokens)) \
                completion_detail(text=\(u.completionTextTokens) audio=\(u.completionAudioTokens))
                """)
            } else {
                Self.logger.info("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] sentence=\"\(result.text)\" hasAudio=\(result.audioData != nil) usage=none")
            }

            // Play audio if available
            if let audioData = result.audioData {
                audioPlayer.play(data: audioData)
            }

            startIdleTimer()
        } catch {
            let elapsed = apiStart.duration(to: .now)
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            Self.logger.error("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] error=\"\(error.localizedDescription)\"")
            // On error, only update if tiles are still current
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            generatedSentence = nil
        }

        isThinking = false
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
