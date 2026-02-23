//
//  TileGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation
import UIKit

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]

    @Environment(SentenceEngine.self) private var engine
    @State var currentPageKey: String?
    @State private var currentDisplayPage: Int? = 0
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    private var activeScene: BlasterScene? { activeScenes.first }

    private var currentPage: PageModel? {
        guard let scene = activeScene else { return nil }
        let key = currentPageKey ?? scene.homePageKey
        return scene.pages.first { $0.displayName == key }
    }

    var body: some View {
        VStack(spacing: 0) {
            SentenceTrayView(
                selectedTiles: engine.selectedTiles,
                generatedSentence: engine.generatedSentence,
                isThinking: engine.isThinking,
                isWaiting: engine.isWaiting,
                canReplay: engine.canReplay,
                recentHistory: engine.recentHistory,
                onTileTap: { index in
                    engine.removeTile(at: index)
                },
                onClear: {
                    engine.clearSelection()
                },
                onReplay: {
                    engine.replay()
                },
                onReplayHistory: { entry in
                    engine.replayFromHistory(entry)
                }
            )
            .padding(.top, 8)

            if let page = currentPage {
                pagedGrid(for: page)
            } else {
                ContentUnavailableView(
                    "No Active Scene",
                    systemImage: "questionmark.square",
                    description: Text("No scene is currently active.")
                )
            }
        }
        .task {
            haptic.prepare()
            // Pre-warm AVSpeechSynthesizer on first appear to eliminate first-tap delay
            let warmup = AVSpeechUtterance(string: " ")
            warmup.volume = 0
            speechSynthesizer.speak(warmup)
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        .onChange(of: activeScene?.id) {
            currentPageKey = nil
            currentDisplayPage = 0
            engine.clearSelection()
        }
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Note", text: $pendingNote)
            Button("Add") { engine.appendNote(pendingNote) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func pagedGrid(for page: PageModel) -> some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let chunkedTiles = page.orderedTiles.chunked(into: 24)
            Group {
                if isLandscape {
                    landscapeTabView(chunks: chunkedTiles)
                } else {
                    portraitScrollView(chunks: chunkedTiles, pageHeight: geo.size.height)
                }
            }
            .onChange(of: isLandscape) { _, _ in
                currentDisplayPage = 0
            }
        }
    }

    @ViewBuilder
    private func landscapeTabView(chunks: [[PageTileModel]]) -> some View {
        TabView(selection: $currentDisplayPage) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(tiles) { pageTile in
                        tileCellView(for: pageTile)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tag(index as Int?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: currentDisplayPage) { _, _ in
            haptic.impactOccurred()
        }
    }

    @ViewBuilder
    private func portraitScrollView(chunks: [[PageTileModel]], pageHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(tiles) { pageTile in
                            TileView(
                                pageTile: pageTile,
                                isSelected: engine.selectedTiles.contains { $0.key == pageTile.tile.key }
                            ) { handleTileTap(pageTile) }
                        }
                    }
                    .padding()
                    .frame(height: pageHeight, alignment: .top)
                    .id(index)
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentDisplayPage)
        .onScrollPhaseChange { old, new in
            if old != .idle && new == .idle {
                haptic.impactOccurred()
            }
        }
    }

    @ViewBuilder
    private func tileCellView(for pageTile: PageTileModel) -> some View {
        TileView(
            pageTile: pageTile,
            isSelected: engine.selectedTiles.contains { $0.key == pageTile.tile.key }
        ) { handleTileTap(pageTile) }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    pendingNote = "\(pageTile.tile.key) [\(pageTile.tile.wordClass)]"
                    showNoteAlert = true
                }
        )
    }

    private func handleTileTap(_ pageTile: PageTileModel) {
        if pageTile.isAudible {
            let alreadySelected = engine.selectedTiles.contains { $0.key == pageTile.tile.key }
            if alreadySelected {
                if let index = engine.selectedTiles.firstIndex(where: { $0.key == pageTile.tile.key }) {
                    engine.removeTile(at: index)
                }
            } else {
                // Only speak when adding to the tray
                if tileSpeechEnabled {
                    let name = pageTile.tile.displayName
                    Task { @MainActor in
                        let utterance = AVSpeechUtterance(string: name)
                        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
                        speechSynthesizer.speak(utterance)
                    }
                }
                engine.addTile(pageTile.tile)
            }
        }
        if !pageTile.link.isEmpty {
            engine.cancelIdleTimer()
            currentPageKey = pageTile.link
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

#Preview {
    TileGridView()
        .environment(SentenceEngine(provider: MockSentenceProvider()))
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self, BlasterScene.self],
            inMemory: true
        )
}
