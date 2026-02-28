// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GridArrangeView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct GridArrangeView: View {
    @Bindable var page: PageModel
    @Environment(\.dismiss) private var dismiss

    // Local ordering modified during drag; committed only on Done
    @State private var previewOrder: [String] = []
    @State private var draggingID: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 110), spacing: 10)]

    private var currentOrder: [String] { previewOrder }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(currentOrder, id: \.self) { id in
                        if let pt = page.tiles.first(where: { $0.id == id }) {
                            arrangeTileCell(pt, id: id)
                                .opacity(draggingID == id ? 0 : 1)
                        }
                    }
                }
                .padding(16)
            }
            .coordinateSpace(name: "arrangeGrid")
            .scrollDisabled(draggingID != nil)
            .onPreferenceChange(ArrangeCellFrameKey.self) { cellFrames = $0 }
            .overlay(floatingTile)
            .navigationTitle("Arrange \(page.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        page.tileOrder = previewOrder
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            previewOrder = page.tileOrder
        }
    }

    // MARK: - Floating overlay tile (follows finger)

    @ViewBuilder
    private var floatingTile: some View {
        if let dragID = draggingID,
           let pt = page.tiles.first(where: { $0.id == dragID }),
           let frame = cellFrames[dragID] {
            ArrangeTileCell(pageTile: pt)
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
    private func arrangeTileCell(_ pageTile: PageTileModel, id: String) -> some View {
        ArrangeTileCell(pageTile: pageTile)
            .scaleEffect(0.85)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ArrangeCellFrameKey.self,
                        value: [id: geo.frame(in: .named("arrangeGrid"))]
                    )
                }
            )
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("arrangeGrid"))
                    .onChanged { value in
                        if draggingID == nil {
                            draggingID = id
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        dragLocation = value.location

                        // Find the cell under the current drag location and shift
                        if let hoveredID = cellFrames.first(where: {
                            $0.key != id && $0.value.contains(value.location)
                        })?.key,
                           let fromIdx = previewOrder.firstIndex(of: id),
                           let toIdx = previewOrder.firstIndex(of: hoveredID),
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
                            draggingID = nil
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
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
    let pageTile: PageTileModel

    var body: some View {
        let tile = pageTile.tile
        VStack(spacing: 3) {
            Group {
                if UIImage(named: tile.bundleImage) != nil {
                    Image(tile.bundleImage)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .background(wordClassColor(tile.wordClass).opacity(0.12))
                } else {
                    Text(String(tile.displayName.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(wordClassColor(tile.wordClass))
                }
            }
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
