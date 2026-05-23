// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridArrangeView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UIKit

struct GridArrangeView: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.dismiss) private var dismiss

    // Local ordering modified during drag; committed only on Done.
    // Stored as tile keys (the page's PageSpec uses keys as identifiers).
    @State private var previewOrder: [String] = []
    @State private var draggingKey: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 110), spacing: 10)]

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private var page: PageSpec? {
        scene.pages.first { $0.key == pageKey }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(previewOrder, id: \.self) { key in
                        if let tile = tileLookup[key] {
                            arrangeTileCell(tile: tile)
                                .opacity(draggingKey == key ? 0 : 1)
                        }
                    }
                }
                .padding(16)
            }
            .coordinateSpace(name: "arrangeGrid")
            .scrollDisabled(draggingKey != nil)
            .onPreferenceChange(ArrangeCellFrameKey.self) { cellFrames = $0 }
            .overlay(floatingTile)
            .navigationTitle("Arrange \(pageKey)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitOrder()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            previewOrder = page?.tiles.map(\.key) ?? []
        }
    }

    // MARK: - Floating overlay tile (follows finger)

    @ViewBuilder
    private var floatingTile: some View {
        if let dragKey = draggingKey,
           let tile = tileLookup[dragKey],
           let frame = cellFrames[dragKey] {
            ArrangeTileCell(tile: tile)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(1.08)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                .position(dragLocation)
                .allowsHitTesting(false)
                .animation(.none, value: dragLocation)
        }
    }

    // MARK: - Individual tile cell

    @ViewBuilder
    private func arrangeTileCell(tile: TileModel) -> some View {
        let key = tile.key
        ArrangeTileCell(tile: tile)
            .scaleEffect(0.85)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ArrangeCellFrameKey.self,
                        value: [key: geo.frame(in: .named("arrangeGrid"))]
                    )
                }
            )
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("arrangeGrid"))
                    .onChanged { value in
                        if draggingKey == nil {
                            draggingKey = key
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        dragLocation = value.location

                        if let hoveredKey = cellFrames.first(where: {
                            $0.key != key && $0.value.contains(value.location)
                        })?.key,
                           let fromIdx = previewOrder.firstIndex(of: key),
                           let toIdx = previewOrder.firstIndex(of: hoveredKey),
                           fromIdx != toIdx {
                            withAnimation(.interactiveSpring(response: 0.25)) {
                                previewOrder.move(
                                    fromOffsets: IndexSet(integer: fromIdx),
                                    toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
                                )
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draggingKey = nil
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
    }

    private func commitOrder() {
        var pages = scene.pages
        guard let pageIdx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        let byKey = Dictionary(uniqueKeysWithValues: pages[pageIdx].tiles.map { ($0.key, $0) })
        let reordered = previewOrder.compactMap { byKey[$0] }
        pages[pageIdx].tiles = reordered
        scene.pages = pages
    }
}

// MARK: - Preference key for collecting cell frames

private struct ArrangeCellFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Tile display cell (shared between grid and floating overlay)

struct ArrangeTileCell: View {
    let tile: TileModel

    var body: some View {
        VStack(spacing: 3) {
            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .padding(5)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            Text(tile.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
