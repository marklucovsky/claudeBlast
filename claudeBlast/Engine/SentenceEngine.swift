//
//  SentenceEngine.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class SentenceEngine {
    // MARK: - Published state

    private(set) var selectedTiles: [TileSelection] = []
    private(set) var generatedSentence: String?
    private(set) var isThinking: Bool = false
    private(set) var isWaiting: Bool = false

    // MARK: - Configuration

    let provider: any SentenceProvider
    let maxTiles: Int = 4

    // MARK: - Dependencies

    private var cacheManager: SentenceCacheManager?

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

        // Cache lookup
        if let cached = cacheManager?.lookup(tiles: tiles) {
            // Staleness guard
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }
            generatedSentence = cached.sentence
            appendToHistory(cached.sentence)
            isThinking = false
            return
        }

        // Build prompt
        var promptBuilder = SentencePromptBuilder()
        promptBuilder.repetitionCount = repetition
        promptBuilder.conversationContext = conversationHistory
        let systemPrompt = promptBuilder.buildSystemPrompt()
        let userPrompt = promptBuilder.formatUserPrompt(tiles: tiles)

        do {
            let result = try await provider.generateSentence(
                tiles: tiles,
                systemPrompt: systemPrompt,
                conversationContext: conversationHistory + [userPrompt],
                requestAudio: false
            )

            // Cache the result regardless of staleness
            cacheManager?.store(tiles: tiles, sentence: result.text)

            // Staleness guard: only display if tiles haven't changed
            guard tiles == selectedTiles else {
                isThinking = false
                return
            }

            generatedSentence = result.text
            appendToHistory(result.text)
        } catch {
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
