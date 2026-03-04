// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
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
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false
    @State private var navigationPath: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

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

            breadcrumbBar
                .animation(.easeInOut(duration: 0.2), value: navigationPath.count > 1)
        }
        .task {
            haptic.prepare()
            navigationPath = [activeScene?.homePageKey ?? "home"]
        }
        .onChange(of: activeScene?.id) {
            currentPageKey = nil
            currentDisplayPage = 0
            navigationPath = [activeScene?.homePageKey ?? "home"]
            engine.clearSelection()
        }
        .onChange(of: activeScene?.pages.map(\.displayName)) { _, pageNames in
            // If the current page was deleted or renamed, navigate home
            guard let pageNames, let key = currentPageKey else { return }
            if !pageNames.contains(key) {
                currentPageKey = nil
                currentDisplayPage = 0
                navigationPath = [activeScene?.homePageKey ?? ""]
            }
        }
        .onChange(of: currentPage?.tileOrder) { _, _ in
            // Reset display page position when tile count changes significantly
            currentDisplayPage = 0
        }
        .onChange(of: currentPageKey) { _, newKey in
            currentDisplayPage = 0
            let pageKey = newKey ?? activeScene?.homePageKey ?? "home"
            if let idx = navigationPath.firstIndex(of: pageKey) {
                navigationPath = Array(navigationPath.prefix(idx + 1))
            } else {
                navigationPath.append(pageKey)
            }
        }
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Note", text: $pendingNote)
            Button("Add") { engine.appendNote(pendingNote) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // Precomputed breadcrumb steps — avoids @ViewBuilder let-binding type-inference pitfalls.
    private struct BreadcrumbStep: Identifiable {
        let id: String        // unique per render (index + segment)
        let segment: String
        let isFirst: Bool
        let isLast: Bool
        let label: String
    }

    private var breadcrumbSteps: [BreadcrumbStep] {
        navigationPath.enumerated().map { i, seg in
            BreadcrumbStep(
                id: "\(i)-\(seg)",
                segment: seg,
                isFirst: i == 0,
                isLast: i == navigationPath.count - 1,
                label: i == 0 ? "Home" : seg.replacingOccurrences(of: "_", with: " ").capitalized
            )
        }
    }

    // Navigation breadcrumb bar — shown only when one level below home.
    // Tapping any non-current segment navigates back to it.
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(breadcrumbSteps, id: \.id) { step in
                    breadcrumbStepView(step)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .opacity(navigationPath.count > 1 ? 1 : 0)
    }

    @ViewBuilder
    private func breadcrumbStepView(_ step: BreadcrumbStep) -> some View {
        if !step.isFirst {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
        }
        if step.isLast {
            Text(step.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            Button {
                currentPageKey = step.isFirst ? nil : step.segment
            } label: {
                HStack(spacing: 3) {
                    if step.isFirst {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                    }
                    Text(step.label)
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pagedGrid(for page: PageModel) -> some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let count = tilesPerPage(geo: geo, isLandscape: isLandscape)
            let chunkedTiles = page.orderedTiles.chunked(into: count)
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

    /// Compute how many tiles fit on one page given the available geometry.
    private func tilesPerPage(geo: GeometryProxy, isLandscape: Bool) -> Int {
        let hPad: CGFloat = 32   // 16pt padding each side
        let vPad: CGFloat = 32   // 16pt top + 16pt bottom within each page
        let spacing: CGFloat = 8
        let minTile: CGFloat = 72
        let labelH: CGFloat = 17 // 3pt gap + 11pt font + ~3pt margin

        let availW = geo.size.width - hPad
        let availH = geo.size.height - vPad

        let cols = max(1, Int((availW + spacing) / (minTile + spacing)))
        let tileW = (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let tileH = tileW + spacing + labelH  // image is 1:1 square

        let rows = max(1, Int((availH + spacing) / (tileH + spacing)))
        return cols * rows
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
            // VStack (not Lazy) ensures all page frames are committed upfront,
            // giving scrollTargetBehavior(.paging) correct snap offsets and
            // preventing layout artifacts on pages beyond the first.
            VStack(spacing: 0) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(tiles) { pageTile in
                            tileCellView(for: pageTile)
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
                    engine.speakTile(pageTile.tile.displayName)
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
