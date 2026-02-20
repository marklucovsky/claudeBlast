//
//  SentenceEngine.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class SentenceEngine {
    // MARK: - Published state

    private(set) var selectedTiles: [TileSelection] = []
    private(set) var generatedSentence: String?
    private(set) var isThinking: Bool = false
    private(set) var isWaiting: Bool = false

    var isPlaying: Bool { audioPlayer.isPlaying }

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
    private var conversationHistory: [String] = []
    private var repetitionCount: Int = 0
    private var lastTileKey: String?
    private let maxConversationHistory = 5
    private let debounceDuration: Duration = .seconds(1)

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
        selectedTiles.append(selection)
        scheduleGeneration()
    }

    func removeTile(at index: Int) {
        guard selectedTiles.indices.contains(index) else { return }
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
        selectedTiles.removeAll()
        generatedSentence = nil
        isThinking = false
        isWaiting = false
        repetitionCount = 0
        lastTileKey = nil
        audioPlayer.stop()
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

        // Cache lookup
        if let cached = cacheManager?.lookup(tiles: tiles) {
            // Staleness guard
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            Self.logger.info("generate: source=cache elapsed=0.000s tiles=[\(tileKeys)] sentence=\"\(cached.sentence)\" hasAudio=\(!cached.audioData.isEmpty)")
            generatedSentence = cached.sentence
            appendToHistory(cached.sentence)
            // Play cached audio if available
            if !cached.audioData.isEmpty,
               let data = Data(base64Encoded: cached.audioData) {
                audioPlayer.play(data: data)
            }
            isThinking = false
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

            // Cache the result regardless of staleness
            cacheManager?.store(tiles: tiles, sentence: result.text, audioData: audioBase64)

            // Staleness guard: only display if tiles haven't changed
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }

            generatedSentence = result.text
            appendToHistory(result.text)

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
