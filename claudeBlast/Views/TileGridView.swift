//
//  TileGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]

    @State var currentPageKey: String?
    @State var selectedTiles: [TileModel] = []

    private let maxTiles = 4
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
                selectedTiles: selectedTiles,
                onTileTap: { index in
                    selectedTiles.remove(at: index)
                },
                onClear: {
                    selectedTiles.removeAll()
                }
            )
            .padding(.top, 8)

            if let page = currentPage {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(page.orderedTiles) { pageTile in
                            TileView(pageTile: pageTile) {
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
            selectedTiles.removeAll()
        }
    }

    private func handleTileTap(_ pageTile: PageTileModel) {
        if pageTile.isAudible && selectedTiles.count < maxTiles {
            selectedTiles.append(pageTile.tile)
        }
        if !pageTile.link.isEmpty {
            currentPageKey = pageTile.link
        }
    }
}

#Preview {
    TileGridView()
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self, BlasterScene.self],
            inMemory: true
        )
}
