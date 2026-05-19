// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceTrayView.swift
//  claudeBlast
//
//  Two-row tray (iPad horizontal layout per Kurt's mockup):
//
//    Top row: the active group rendered as full-size tile cards, a prominent play/replay button,
//             and a yellow sentence bubble showing the AI sentence (or a spelled-out preview
//             while the child is still building).
//    Bottom row: a compact horizontal strip of closed history groups (tap to reopen, long-press
//                for Delete). A trailing "+" affordance unlocks a locked active group for further
//                additions when there's room under the cap.
//
//  Phone/portrait responsive layout (bubble → liquid-glass overlay) is a follow-up.
//

import SwiftUI
import UIKit

/// Shared height for the three top-row elements (active tile card, play+Done column, sentence
/// bubble). Each gets the same explicit frame height and a matching inner vertical padding so
/// they read as a single horizontal row.
private let kCardHeight: CGFloat = 88
private let kCardVerticalPadding: CGFloat = 6
private let kActiveRowHeight: CGFloat = kCardHeight
private let kHistoryRowHeight: CGFloat = 34
private let kActiveImageSize: CGFloat = 56
private let kPlayButtonWidth: CGFloat = 82
private let kPlayButtonHeight: CGFloat = 54
private let kDoneButtonHeight: CGFloat = 28
private let kPlayDoneSpacing: CGFloat = 6
private let kHistoryTileSize: CGFloat = 22

struct SentenceTrayView: View {
    @Environment(SentenceEngine.self) private var engine

    let onTileTap: (Int) -> Void
    let onGo: () -> Void
    let onReplay: () -> Void
    let onReopenHistory: (UUID) -> Void
    let onDeleteHistory: (UUID) -> Void
    /// Currently unused in iPad layout; reserved for the phone/responsive variant where the
    /// bubble becomes a dismissible overlay (the "×" → clearSelection).
    let onDismissActive: () -> Void
    /// Commit the active group to history and start fresh. Wired to the Done button below
    /// the play control, and triggered automatically by the engine's auto-Done idle timer.
    let onCommitActive: () -> Void

    // MARK: - Derived state

    private var canReplay: Bool {
        engine.canReplay && !engine.isThinking
    }

    private var canGo: Bool {
        !canReplay && engine.activeGroup.tiles.count >= 2 && !engine.isThinking
    }

    private var canFire: Bool { canReplay || canGo }

    private var isPulsing: Bool {
        engine.isIdleNudge && canFire && !engine.isThinking
    }

    private var bubbleContent: String {
        if let sentence = engine.activeGroup.sentence {
            return sentence
        }
        return engine.activeGroup.tiles.map(\.value).joined(separator: " ")
    }

    private var hasActiveContent: Bool {
        !engine.activeGroup.tiles.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            activeRow
            divider
            historyRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    // MARK: - Top row

    private var activeRow: some View {
        HStack(alignment: .center, spacing: 14) {
            activeTilesArea
                .frame(maxWidth: .infinity, alignment: .leading)

            playColumn
                .opacity(hasActiveContent ? 1 : 0.25)
                .allowsHitTesting(hasActiveContent)

            sentenceBubble
                .frame(maxWidth: .infinity)
        }
        .frame(height: kActiveRowHeight)
    }

    /// Play button + Done (commit) button stacked vertically. Total height = kCardHeight.
    private var playColumn: some View {
        VStack(spacing: kPlayDoneSpacing) {
            PrimaryPlayButton(
                canFire: canFire,
                isPulsing: isPulsing,
                isReplay: canReplay,
                action: canReplay ? onReplay : onGo
            )
            .allowsHitTesting(canFire)
            .opacity(canFire ? 1 : 0.45)

            DoneButton(
                isEnabled: hasActiveContent,
                isNudge: engine.isDoneNudge && hasActiveContent,
                action: onCommitActive
            )
        }
        .frame(height: kCardHeight)
    }

    @ViewBuilder
    private var activeTilesArea: some View {
        if hasActiveContent {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(engine.activeGroup.tiles.enumerated()), id: \.offset) { index, tile in
                        ActiveTileCard(tile: tile) { onTileTap(index) }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
            .animation(.easeInOut(duration: 0.18), value: engine.activeGroup.tiles.count)
        } else if engine.groupHistory.isEmpty {
            Text("Tap tiles to build a sentence")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var sentenceBubble: some View {
        if hasActiveContent {
            SentenceBubble(
                content: bubbleContent,
                isFinal: engine.activeGroup.sentence != nil,
                isThinking: engine.isThinking
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    // MARK: - Bottom row

    private var historyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                // Closed groups: oldest first (left), newest last (right).
                ForEach(Array(engine.groupHistory.reversed()), id: \.id) { group in
                    HistoryGroupChip(
                        group: group,
                        onTap: { onReopenHistory(group.id) },
                        onDelete: { onDeleteHistory(group.id) }
                    )
                    .id(group.id)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: kHistoryRowHeight)
    }
}

// MARK: - Active tile card

private struct ActiveTileCard: View {
    let tile: TileSelection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: kActiveImageSize, height: kActiveImageSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(tile.value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, kCardVerticalPadding)
            .frame(height: kCardHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(tile.value)")
    }
}

// MARK: - Primary play button

private struct PrimaryPlayButton: View {
    let canFire: Bool
    let isPulsing: Bool
    /// True when the active group is locked and tapping triggers an escalation-replay rather
    /// than first-time generation. The icon stays the play triangle either way; we add a small
    /// recycle badge in the top-right corner to mark replay mode.
    let isReplay: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulsePhase: Int = 0
    @State private var hueRotation: Double = 0

    /// Full ROYGBIV halo cycle. The shadow color steps through these in sequence so the halo
    /// reads as a slow rainbow sweep around the button. The icon itself uses a continuous
    /// hue-rotation on top of a blue base so its color drifts smoothly through every hue —
    /// the discrete halo + smooth icon combine for the rainbow effect.
    private static let pulseColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .indigo, .purple,
    ]
    /// How long each halo color holds before stepping to the next. With 7 colors and a 0.4s
    /// step the halo completes a full rainbow loop in ~2.8s.
    private static let phaseStepInterval: Duration = .milliseconds(400)
    /// Hue-rotation tick rate for the icon. ~30 Hz produces a visually smooth sweep.
    private static let hueTickInterval: Duration = .milliseconds(33)
    /// Degrees per tick. 4.5° × ~30 Hz ≈ 135°/s → full revolution in ~2.7s, roughly matching
    /// the halo cycle so the two stay in phase.
    private static let hueDegreesPerTick: Double = 4.5

    private var haloColor: Color {
        guard isPulsing else { return .black.opacity(0.06) }
        return Self.pulseColors[pulsePhase % Self.pulseColors.count].opacity(0.55)
    }

    private var haloRadius: CGFloat {
        isPulsing ? 18 : 2
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: haloColor, radius: haloRadius, y: 1)

                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .hueRotation(.degrees(hueRotation))
            }
            .overlay(alignment: .topTrailing) {
                if isReplay {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                        )
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: kPlayButtonWidth, height: kPlayButtonHeight)
            .scaleEffect(pulseScale)
        }
        .buttonStyle(.plain)
        .disabled(!canFire)
        .onAppear { applyScalePulse(isPulsing) }
        .onChange(of: isPulsing) { _, newValue in
            applyScalePulse(newValue)
            if !newValue {
                pulsePhase = 0
                withAnimation(.easeOut(duration: 0.3)) {
                    hueRotation = 0
                }
            }
        }
        .task(id: isPulsing) {
            guard isPulsing else { return }
            var phaseAccumulator: Duration = .seconds(0)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hueTickInterval)
                if Task.isCancelled { return }
                hueRotation = (hueRotation + Self.hueDegreesPerTick)
                    .truncatingRemainder(dividingBy: 360)
                phaseAccumulator += Self.hueTickInterval
                if phaseAccumulator >= Self.phaseStepInterval {
                    phaseAccumulator = .seconds(0)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        pulsePhase = (pulsePhase + 1) % Self.pulseColors.count
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isReplay)
        .animation(.easeInOut(duration: 0.3), value: isPulsing)
        .animation(.linear(duration: 0.04), value: hueRotation)
        .accessibilityLabel(isReplay ? "Replay sentence" : "Play sentence")
    }

    private func applyScalePulse(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Done / commit button

private struct DoneButton: View {
    let isEnabled: Bool
    /// Single binary trigger from the engine. Once true, the button drives its own escalating
    /// animation independent of any other clock: stage 0 (blue) → stage 1 (green) → stage 2
    /// (red), each ~2s apart, with progressively heavier border, font weight, and shadow.
    let isNudge: Bool
    let action: () -> Void

    @State private var nudgeScale: CGFloat = 1.0
    @State private var nudgeStage: Int = 0
    @State private var stageTask: Task<Void, Never>?

    /// Per-stage hold time inside the button's internal ramp.
    private static let stageInterval: Duration = .seconds(2)

    private var borderColor: Color {
        guard isNudge else { return Color.primary.opacity(0.12) }
        switch nudgeStage {
        case 0:  return Color.blue.opacity(0.75)
        case 1:  return Color.green.opacity(0.85)
        default: return Color.red.opacity(0.95)
        }
    }

    private var borderWidth: CGFloat {
        guard isNudge else { return 1 }
        switch nudgeStage {
        case 0:  return 1.5
        case 1:  return 2.0
        default: return 2.5
        }
    }

    private var foreground: Color {
        guard isNudge else { return .secondary }
        switch nudgeStage {
        case 0:  return .blue
        case 1:  return .green
        default: return .red
        }
    }

    private var textWeight: Font.Weight {
        guard isNudge else { return .medium }
        switch nudgeStage {
        case 0:  return .semibold
        case 1:  return .bold
        default: return .heavy
        }
    }

    private var iconWeight: Font.Weight {
        guard isNudge else { return .bold }
        switch nudgeStage {
        case 0:  return .bold
        case 1:  return .heavy
        default: return .black
        }
    }

    private var shadowColor: Color {
        guard isNudge else { return Color.accentColor }
        switch nudgeStage {
        case 0:  return .blue
        case 1:  return .green
        default: return .red
        }
    }

    private var shadowOpacity: Double {
        guard isNudge else { return 0 }
        switch nudgeStage {
        case 0:  return 0.20
        case 1:  return 0.32
        default: return 0.50
        }
    }

    private var shadowRadius: CGFloat {
        guard isNudge else { return 4 }
        switch nudgeStage {
        case 0:  return 4
        case 1:  return 6
        default: return 8
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: iconWeight))
                Text("Done")
                    .font(.caption.weight(textWeight))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: shadowColor.opacity(shadowOpacity), radius: shadowRadius, y: 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .frame(width: kPlayButtonWidth, height: kDoneButtonHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(nudgeScale)
        .onAppear { applyNudge(isNudge) }
        .onChange(of: isNudge) { _, newValue in
            applyNudge(newValue)
        }
        .animation(.easeInOut(duration: 0.35), value: isNudge)
        .animation(.easeInOut(duration: 0.4), value: nudgeStage)
        .accessibilityLabel("Save this sentence and start a new one")
    }

    private func applyNudge(_ active: Bool) {
        stageTask?.cancel()
        if active {
            nudgeStage = 0
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                nudgeScale = 1.07
            }
            stageTask = Task {
                for stage in 1...2 {
                    try? await Task.sleep(for: Self.stageInterval)
                    if Task.isCancelled { return }
                    nudgeStage = stage
                }
            }
        } else {
            nudgeStage = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                nudgeScale = 1.0
            }
        }
    }
}

// MARK: - Sentence bubble

private struct SentenceBubble: View {
    let content: String
    /// True when the active group's sentence has been generated (post-Go or post-cap). When
    /// false the bubble is showing a spelled-out preview of the selected tiles.
    let isFinal: Bool
    let isThinking: Bool

    var body: some View {
        Group {
            if isThinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if !content.isEmpty {
                Text(content)
                    .font(.title3)
                    .fontWeight(isFinal ? .semibold : .regular)
                    .foregroundStyle(isFinal ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, kCardVerticalPadding)
        .frame(height: kCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: content)
        .animation(.easeInOut(duration: 0.2), value: isFinal)
    }
}

// MARK: - History group chip

private struct HistoryGroupChip: View {
    let group: TileGroup
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            TileGroupBubble(tiles: group.tiles)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - TileGroupBubble (shared)

/// The "bubble of tiles" used by both the in-app sentence tray history row and the AdminView
/// Activity Log. Each tile is a tinted capsule chip (image + label colored by wordClass),
/// wrapped in a rounded card with a soft shadow.
struct TileGroupBubble: View {
    let tiles: [TileSelection]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                HStack(spacing: 3) {
                    TileImageView(key: tile.key, wordClass: tile.wordClass)
                        .frame(width: kHistoryTileSize, height: kHistoryTileSize)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(tile.value)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(wordClassColor(tile.wordClass).opacity(0.20))
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Shared helpers

func wordClassColor(_ wordClass: String) -> Color {
    switch wordClass {
    case "actions":                             return .orange
    case "describe":                            return .green
    case "people":                              return .purple
    case "food", "meals", "fruit",
         "veggie", "snacks":                    return .red
    case "places":                              return .blue
    case "social", "feeling", "question":       return .pink
    case "navigation":                          return .indigo
    case "drinks":                              return .cyan
    case "weather":                             return Color(red: 0.3, green: 0.6, blue: 0.9)
    case "colors":                              return .mint
    case "shape":                               return .teal
    case "body", "health":                      return Color(red: 0.9, green: 0.5, blue: 0.5)
    case "toy", "games", "sports":              return .yellow
    case "art":                                 return Color(red: 0.7, green: 0.4, blue: 0.8)
    case "play":                                return .yellow
    default:                                    return .gray
    }
}

// MARK: - TileGridIcon (used by AdminView; kept here for now)

/// Renders up to 4 tiles as a fixed 2×2 square icon.
struct TileGridIcon: View {
    let tiles: [TileSelection]

    private let cellSize: CGFloat = 22
    private let gap: CGFloat = 2

    private var slots: [TileSelection?] {
        let filled = tiles.prefix(4).map { Optional($0) }
        return Array(filled + [nil, nil, nil, nil]).prefix(4).map { $0 }
    }

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                cell(slots[0])
                cell(slots[1])
            }
            HStack(spacing: gap) {
                cell(slots[2])
                cell(slots[3])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func cell(_ tile: TileSelection?) -> some View {
        if let tile {
            TileImageView(key: tile.key, wordClass: tile.wordClass)
                .frame(width: cellSize, height: cellSize)
        } else {
            Color(.secondarySystemBackground)
                .frame(width: cellSize, height: cellSize)
        }
    }
}
