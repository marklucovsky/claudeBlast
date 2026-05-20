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
    @Environment(TileScriptRecorder.self) private var recorder
    @State private var currentDisplayPage: Int? = 0
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false
    @State private var promotedExpanded: Bool = false

    @AppStorage(AppSettingsKey.tileSizeStep) private var tileSizeStep: Int = 0

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var compactOverlay: CompactOverlay = .none
    @State private var overlayEpoch: Int = 0

    private var isCompact: Bool { hSizeClass == .compact }

    enum CompactOverlay: Equatable {
        case none
        case sentence
        case history
        case favorites
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
            if isCompact {
                CompactTrayStrip(
                    onTileTap: { index in engine.removeTile(at: index) },
                    onGo: {
                        if recorder.state == .recording { recorder.recordPlay() }
                        engine.triggerGo()
                    },
                    onReplay: {
                        if recorder.state == .recording { recorder.recordReplay() }
                        engine.replay()
                    },
                    onCommitActive: { engine.commitActiveAndStartNew() },
                    onShowSentence: { showCompactOverlay(.sentence) },
                    onShowHistory: { showCompactOverlay(.history) },
                    onShowFavorites: { showCompactOverlay(.favorites) },
                    onHome: {
                        coordinator.navigateToRoot()
                        currentDisplayPage = 0
                    },
                    isAtHome: coordinator.navigationPath.count <= 1,
                    favoritesCount: min(promotedEntries.count, 99),
                    isSentenceShown: compactOverlay == .sentence,
                    isHistoryShown: compactOverlay == .history,
                    isFavoritesShown: compactOverlay == .favorites
                )
            } else {
                SentenceTrayView(
                    onTileTap: { index in
                        engine.removeTile(at: index)
                    },
                    onGo: {
                        if recorder.state == .recording {
                            recorder.recordPlay()
                        }
                        engine.triggerGo()
                    },
                    onReplay: {
                        if recorder.state == .recording {
                            recorder.recordReplay()
                        }
                        engine.replay()
                    },
                    onReopenHistory: { id in
                        if recorder.state == .recording {
                            recorder.recordReplay()
                        }
                        engine.reopenHistoryGroup(id: id)
                    },
                    onDeleteHistory: { id in
                        engine.deleteHistoryGroup(id: id)
                    },
                    onExpandSentence: { showCompactOverlay(.sentence) },
                    onHome: {
                        coordinator.navigateToRoot()
                        currentDisplayPage = 0
                    },
                    onShowFavorites: { showCompactOverlay(.favorites) },
                    isAtHome: coordinator.navigationPath.count <= 1,
                    favoritesCount: min(promotedEntries.count, 99),
                    isSentenceShown: compactOverlay == .sentence,
                    isFavoritesShown: compactOverlay == .favorites,
                    onDismissActive: {
                        engine.clearSelection()
                    },
                    onCommitActive: {
                        engine.commitActiveAndStartNew()
                    }
                )
                .padding(.top, 8)
            }

            if let page = currentPage {
                pagedGrid(for: page)
                    .overlay(alignment: .top) {
                        compactOverlayContent
                    }
            } else {
                ContentUnavailableView(
                    "No Active Scene",
                    systemImage: "questionmark.square",
                    description: Text("No scene is currently active.")
                )
            }
        }
        .overlay(alignment: .bottom) {
            if scriptRunner.state != .idle {
                TileScriptPlaybackOverlay()
            } else {
                TileScriptRecordingOverlay()
            }
        }
        .onChange(of: engine.canReplay) { _, isReady in
            guard isCompact else { return }
            if isReady {
                // Auto-pop the sentence overlay when a sentence becomes ready,
                // unless the caregiver is currently browsing history (don't interrupt).
                if compactOverlay != .history { showCompactOverlay(.sentence) }
            } else if compactOverlay == .sentence {
                dismissCompactOverlay()
            }
        }
        .task(id: overlayEpoch) {
            // Only the sentence overlay auto-dismisses. History stays until tapped.
            guard isCompact, compactOverlay == .sentence else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if compactOverlay == .sentence { compactOverlay = .none }
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

    // Combined nav bar: breadcrumbs (leading) + frequent toggle (trailing).
    // Shares a single row of vertical space when both are active.
    private var navBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Breadcrumbs — leading
                if coordinator.navigationPath.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(breadcrumbSteps, id: \.id) { step in
                                breadcrumbStepView(step)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                // Frequent toggle — trailing
                if !promotedEntries.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            promotedExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(promotedEntries.prefix(8).count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(promotedExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 26)

            // Expanded chip strip
            if promotedExpanded && !promotedEntries.isEmpty {
                PromotedChipStrip(
                    entries: Array(promotedEntries.prefix(8)),
                    sceneKeySet: sceneKeySet,
                    tileWordClass: tileWordClass
                ) { entry in
                    engine.speakPromoted(entry)
                }
            }

            Divider()
        }
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
            let spec = GridLayoutCalculator.compute(
                screenSize: UIScreen.main.bounds.size,
                geo: geo.size,
                userStep: tileSizeStep
            )
            let chunkedTiles = page.orderedTiles.chunked(into: spec.perPage)
            Group {
                if isLandscape {
                    landscapeTabView(chunks: chunkedTiles, spec: spec)
                } else {
                    portraitScrollView(chunks: chunkedTiles, pageHeight: geo.size.height, spec: spec)
                }
            }
            #if DEBUG
            .overlay(alignment: .centerLastTextBaseline) {
                gridDebugBadge(spec: spec, tileCount: page.orderedTiles.count)
            }
            #endif
            .onChange(of: isLandscape) { _, _ in
                currentDisplayPage = 0
            }
        }
    }

    // MARK: - Compact (iPhone) overlays

    @ViewBuilder
    private var compactOverlayContent: some View {
        switch compactOverlay {
        case .none:
            EmptyView()
        case .sentence:
            if let sentence = engine.activeGroup.sentence {
                GlassSentencePopover(
                    sentence: sentence,
                    onDismiss: { dismissCompactOverlay() }
                )
                .allowsHitTesting(true)
            }
        case .history:
            let groups = engine.groupHistory.filter { $0.sentence != nil }
            if !groups.isEmpty {
                GlassHistoryOverlay(
                    groups: groups,
                    onReopen: { id in
                        if recorder.state == .recording { recorder.recordReplay() }
                        engine.reopenHistoryGroup(id: id)
                        dismissCompactOverlay()
                    },
                    onDelete: { id in engine.deleteHistoryGroup(id: id) },
                    onDismiss: { dismissCompactOverlay() }
                )
                .allowsHitTesting(true)
            }
        case .favorites:
            GlassFavoritesOverlay(
                entries: Array(promotedEntries.prefix(12)),
                sceneKeySet: sceneKeySet,
                tileWordClass: tileWordClass,
                onPlay: { entry in engine.speakPromoted(entry) },
                onDismiss: { dismissCompactOverlay() }
            )
            .allowsHitTesting(true)
        }
    }

    private func showCompactOverlay(_ kind: CompactOverlay) {
        withAnimation(.spring(duration: 0.35)) { compactOverlay = kind }
        overlayEpoch &+= 1
    }

    private func dismissCompactOverlay() {
        withAnimation(.easeOut(duration: 0.25)) { compactOverlay = .none }
    }

    #if DEBUG
    @ViewBuilder
    private func gridDebugBadge(spec: GridLayoutSpec, tileCount: Int) -> some View {
        let pages = max(1, Int(ceil(Double(tileCount) / Double(max(1, spec.perPage)))))
        Text("\(spec.cols)×\(spec.rows) · \(spec.perPage)/pg · \(tileCount)t/\(pages)p · \(Int(spec.tileSize))pt")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
            .allowsHitTesting(false)
    }
    #endif

    @ViewBuilder
    private func landscapeTabView(chunks: [[PageTileModel]], spec: GridLayoutSpec) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: spec.cols)
        TabView(selection: $currentDisplayPage) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                    ForEach(tiles) { pageTile in
                        tileCellView(for: pageTile, labelFontSize: spec.labelFontSize)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
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
    private func portraitScrollView(chunks: [[PageTileModel]], pageHeight: CGFloat, spec: GridLayoutSpec) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: spec.cols)
        ScrollView {
            // VStack (not Lazy) ensures all page frames are committed upfront,
            // giving scrollTargetBehavior(.paging) correct snap offsets and
            // preventing layout artifacts on pages beyond the first.
            VStack(spacing: 0) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                    LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                        ForEach(tiles) { pageTile in
                            tileCellView(for: pageTile, labelFontSize: spec.labelFontSize)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(height: pageHeight, alignment: .top)
                    .id(index)
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollClipDisabled(false)
        .clipped()
        .scrollPosition(id: $currentDisplayPage)
        .onScrollPhaseChange { old, new in
            if old != .idle && new == .idle {
                haptic.impactOccurred()
            }
        }
    }

    @ViewBuilder
    private func tileCellView(for pageTile: PageTileModel, labelFontSize: CGFloat) -> some View {
        TileView(
            pageTile: pageTile,
            isSelected: engine.selectedTiles.contains { $0.key == pageTile.tile.key },
            labelFontSize: labelFontSize
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
        let key = pageTile.tile.key
        // An "audible nav tile" is a single gesture that both adds a tile to the active group
        // AND navigates. We treat it as such in recordings only when the tile key matches the
        // link key (the conventional case for nav tiles like <drinks isAudible=t/>).
        let isAudibleNavTile = pageTile.isAudible
            && !pageTile.link.isEmpty
            && pageTile.link == key

        var alreadySelected = false
        if pageTile.isAudible {
            alreadySelected = engine.selectedTiles.contains { $0.key == key }
            if alreadySelected {
                if let index = engine.selectedTiles.firstIndex(where: { $0.key == key }) {
                    engine.removeTile(at: index)
                }
            } else {
                if tileSpeechEnabled {
                    engine.speakTile(pageTile.tile.displayName)
                }
                engine.addTile(pageTile.tile)
                if recorder.state == .recording {
                    if isAudibleNavTile {
                        recorder.recordAudibleNavigate(pageKey: pageTile.link)
                    } else {
                        recorder.recordTap(tileKey: key)
                    }
                }
            }
        }
        if !pageTile.link.isEmpty {
            coordinator.navigate(to: pageTile.link)
            if recorder.state == .recording {
                // Skip a separate navigate record if we already recorded an audible-nav for
                // this gesture (it covers both the tile and the navigation).
                let recordedAsAudibleNav = isAudibleNavTile && !alreadySelected
                if !recordedAsAudibleNav {
                    recorder.recordNavigate(pageKey: pageTile.link)
                }
            }
        }
    }
}

// MARK: - Promoted Tile Strip

/// Horizontal scroll of promoted chips — shown when expanded from the nav bar.
struct PromotedChipStrip: View {
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
                    TileImageView(key: key, wordClass: wordClass)
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
        .previewEnvironment()
}
