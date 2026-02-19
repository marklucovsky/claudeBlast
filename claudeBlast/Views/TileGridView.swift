//
//  TileGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]

    @Environment(SentenceEngine.self) private var engine
    @State var currentPageKey: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

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
                onTileTap: { index in
                    engine.removeTile(at: index)
                },
                onClear: {
                    engine.clearSelection()
                }
            )
            .padding(.top, 8)

            if let page = currentPage {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(page.orderedTiles) { pageTile in
                            TileView(
                                pageTile: pageTile,
                                isSelected: engine.selectedTiles.contains { $0.key == pageTile.tile.key }
                            ) {
                                handleTileTap(pageTile)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Active Scene",
                    systemImage: "questionmark.square",
                    description: Text("No scene is currently active.")
                )
            }
        }
        .onChange(of: activeScene?.id) {
            // Reset to new scene's home page when scene changes
            currentPageKey = nil
            engine.clearSelection()
        }
    }

    private func handleTileTap(_ pageTile: PageTileModel) {
        if pageTile.isAudible {
            // Toggle: tap selected tile in grid to deselect it
            if let index = engine.selectedTiles.firstIndex(where: { $0.key == pageTile.tile.key }) {
                engine.removeTile(at: index)
            } else {
                engine.addTile(pageTile.tile)
            }
        }
        if !pageTile.link.isEmpty {
            currentPageKey = pageTile.link
        }
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
