//
//  TileGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileGridView: View {
    @Query var pages: [PageModel]
    @State var currentPageKey: String = "home"
    @State var selectedTiles: [TileModel] = []

    private let maxTiles = 4
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    private var currentPage: PageModel? {
        pages.first { $0.displayName == currentPageKey }
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
                    "Page Not Found",
                    systemImage: "questionmark.square",
                    description: Text("Could not find page: \(currentPageKey)")
                )
            }
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
            for: [TileModel.self, PageModel.self, PageTileModel.self],
            inMemory: true
        )
}
