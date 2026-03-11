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

private let promotedHitThreshold = 3

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]

    @Query(
        filter: #Predicate<SentenceCache> { entry in
            entry.hitCount >= promotedHitThreshold || entry.isPinned
        },
        sort: \SentenceCache.hitCount, order: .reverse
    )
    private var promotedEntries: [SentenceCache]

    @Environment(SentenceEngine.self) private var engine
    @Environment(NavigationCoordinator.self) private var coordinator
    @Environment(TileScriptRunner.self) private var scriptRunner
    @State private var currentDisplayPage: Int? = 0
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false

    @AppStorage(AppSettingsKey.tileMinSize) private var tileMinSize: Double = 72

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(tileMinSize)), spacing: 8)]
    }

    private var activeScene: BlasterScene? { activeScenes.first }

    /// All tile keys reachable anywhere in the active scene.
    private var sceneKeySet: Set<String> {
        guard let scene = activeScene else { return [] }
        return Set(scene.pages.flatMap { $0.orderedTiles.map(\.tile.key) })
    }

    /// key → wordClass for all tiles in the active scene (used for icon color coding).
    private var tileWordClass: [String: String] {
        guard let scene = activeScene else { return [:] }
        var result: [String: String] = [:]
        for page in scene.pages {
            for pt in page.orderedTiles {
                result[pt.tile.key] = pt.tile.wordClass
            }
        }
        return result
    }

    private var currentPage: PageModel? {
        guard let scene = activeScene else { return nil }
        let key = coordinator.currentPageKey ?? scene.homePageKey
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

            if !promotedEntries.isEmpty {
                PromotedTileStrip(
                    entries: Array(promotedEntries.prefix(8)),
                    sceneKeySet: sceneKeySet,
                    tileWordClass: tileWordClass
                ) { entry in
                    engine.speakPromoted(entry)
                }
            }

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
                .animation(.easeInOut(duration: 0.2), value: coordinator.navigationPath.count > 1)
        }
        .overlay(alignment: .bottom) {
            if scriptRunner.state != .idle {
                TileScriptPlaybackOverlay()
            }
        }
        .task {
            haptic.prepare()
            coordinator.navigationPath = [activeScene?.homePageKey ?? "home"]
        }
        .onChange(of: activeScene?.id) {
            coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "home")
            currentDisplayPage = 0
            engine.clearSelection()
        }
        .onChange(of: activeScene?.pages.map(\.displayName)) { _, pageNames in
            // If the current page was deleted or renamed, navigate home
            guard let pageNames, let key = coordinator.currentPageKey else { return }
            if !pageNames.contains(key) {
                coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "")
                currentDisplayPage = 0
            }
        }
        .onChange(of: currentPage?.tileOrder) { _, _ in
            // Reset display page position when tile count changes significantly
            currentDisplayPage = 0
        }
        .onChange(of: coordinator.currentPageKey) { _, _ in
            currentDisplayPage = 0
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
        coordinator.navigationPath.enumerated().map { i, seg in
            BreadcrumbStep(
                id: "\(i)-\(seg)",
                segment: seg,
                isFirst: i == 0,
                isLast: i == coordinator.navigationPath.count - 1,
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
        .opacity(coordinator.navigationPath.count > 1 ? 1 : 0)
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
                if step.isFirst {
                    coordinator.navigateToRoot()
                } else {
                    coordinator.navigate(to: step.segment)
                }
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
        let minTile = CGFloat(tileMinSize)
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
            coordinator.navigate(to: pageTile.link)
        }
    }
}

// MARK: - Promoted Tile Strip

private struct PromotedTileStrip: View {
    let entries: [SentenceCache]
    let sceneKeySet: Set<String>
    let tileWordClass: [String: String]
    let onTap: (SentenceCache) -> Void

    private func isInScene(_ entry: SentenceCache) -> Bool {
        entry.tileKeys.allSatisfy { sceneKeySet.contains($0) }
    }

    private var inScene: [SentenceCache] { entries.filter { isInScene($0) } }
    private var outOfScene: [SentenceCache] { entries.filter { !isInScene($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Frequent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(inScene) { entry in
                        PromotedChip(entry: entry, isInScene: true,
                                     tileWordClass: tileWordClass, onTap: onTap)
                    }

                    if !outOfScene.isEmpty {
                        if !inScene.isEmpty {
                            Rectangle()
                                .fill(.separator)
                                .frame(width: 1, height: 36)
                                .padding(.horizontal, 4)
                        }
                        Text("other")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ForEach(outOfScene) { entry in
                            PromotedChip(entry: entry, isInScene: false,
                                         tileWordClass: tileWordClass, onTap: onTap)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct PromotedChip: View {
    let entry: SentenceCache
    let isInScene: Bool
    let tileWordClass: [String: String]
    let onTap: (SentenceCache) -> Void

    private let iconSize: CGFloat = 30
    private let cornerRadius: CGFloat = 10

    private var borderColor: Color {
        if entry.isPinned && isInScene { return .orange.opacity(0.7) }
        if isInScene { return .primary.opacity(0.15) }
        return .secondary.opacity(0.25)
    }

    var body: some View {
        Button { onTap(entry) } label: {
            HStack(spacing: 3) {
                ForEach(entry.tileKeys.prefix(4), id: \.self) { key in
                    let wordClass = tileWordClass[key] ?? "default"
                    ZStack {
                        wordClassColor(wordClass).opacity(0.15)
                        if UIImage(named: key) != nil {
                            Image(key)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        } else {
                            Text(String(key.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(wordClassColor(wordClass))
                        }
                    }
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
            .opacity(isInScene ? 1 : 0.6)
        }
        .buttonStyle(.plain)
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
        .environment(NavigationCoordinator())
        .environment(TileScriptRunner())
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self, BlasterScene.self],
            inMemory: true
        )
}
