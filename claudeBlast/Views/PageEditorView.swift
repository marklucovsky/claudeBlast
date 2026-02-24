//
//  PageEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct PageEditorView: View {
    @Bindable var page: PageModel
    let scene: BlasterScene
    @Environment(\.modelContext) private var modelContext
    @State private var isPickingTiles = false

    var body: some View {
        Group {
            if page.orderedTiles.isEmpty {
                ContentUnavailableView {
                    Label("No Tiles", systemImage: "square.grid.2x2")
                } description: {
                    Text("Tap + to add tiles to this page.")
                } actions: {
                    Button("Add Tiles") { isPickingTiles = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(page.orderedTiles) { pageTile in
                        tileRow(pageTile)
                    }
                    .onDelete(perform: deleteTiles)
                    .onMove(perform: moveTiles)
                }
            }
        }
        .navigationTitle(page.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { isPickingTiles = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $isPickingTiles) {
            TilePickerView(page: page)
        }
    }

    @ViewBuilder
    private func tileRow(_ pageTile: PageTileModel) -> some View {
        HStack(spacing: 12) {
            Group {
                if UIImage(named: pageTile.tile.bundleImage) != nil {
                    Image(pageTile.tile.bundleImage)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .background(wordClassColor(pageTile.tile.wordClass).opacity(0.12))
                } else {
                    Text(String(pageTile.tile.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(wordClassColor(pageTile.tile.wordClass))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(pageTile.tile.displayName)
                HStack(spacing: 8) {
                    if pageTile.isAudible {
                        Label("Audible", systemImage: "speaker.wave.2")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if !pageTile.link.isEmpty {
                        Label(pageTile.link, systemImage: "arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private func deleteTiles(at offsets: IndexSet) {
        let ordered = page.orderedTiles
        for index in offsets.sorted().reversed() {
            let pt = ordered[index]
            page.removeTile(pt)
            modelContext.delete(pt)
        }
    }

    private func moveTiles(from source: IndexSet, to destination: Int) {
        page.tileOrder.move(fromOffsets: source, toOffset: destination)
    }
}
