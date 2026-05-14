// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceTrayView.swift
//  claudeBlast
//

import SwiftUI
import UIKit

// Fixed inner content height: chips (36) + spacing (4) + sentence (22) = 62pt
private let kChipsHeight: CGFloat = 36
private let kSentenceHeight: CGFloat = 22
private let kContentHeight: CGFloat = kChipsHeight + 4 + kSentenceHeight
private let kComparisonHeight: CGFloat = 16
private let kColumnWidth: CGFloat = 36

struct SentenceTrayView: View {
    let selectedTiles: [TileSelection]
    let generatedSentence: String?
    let comparisonSentence: String?
    let isThinking: Bool
    let isWaiting: Bool
    /// True when the active group is locked and replay-with-escalation is available.
    let canReplay: Bool
    let onTileTap: (Int) -> Void
    let onGo: () -> Void
    let onReplay: () -> Void

    /// "Play" affordance: replay the locked group's spoken sentence (with escalation).
    private var showReplay: Bool {
        canReplay && !isThinking && !isWaiting
    }

    /// "Go" affordance: commit the in-progress group immediately, skipping the debounce wait.
    /// Visible during the debounce window too — that's its whole point. Hidden once generation
    /// is actually in flight (isThinking) or after the group locks (showReplay takes over).
    private var showGo: Bool {
        !showReplay && selectedTiles.count >= 2 && !isThinking
    }

    private var showCommit: Bool {
        showReplay || showGo
    }

    private var hasComparison: Bool {
        comparisonSentence != nil && generatedSentence != nil
    }

    private var totalContentHeight: CGFloat {
        hasComparison ? kContentHeight + kComparisonHeight + 4 : kContentHeight
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            // Left: tile chips + sentence (fills remaining space)
            VStack(alignment: .leading, spacing: 4) {

                // Chips row — ZStack keeps layout stable; opacity gates visibility
                ZStack(alignment: .leading) {
                    Text("Tap tiles to build a sentence")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .opacity(selectedTiles.isEmpty ? 1 : 0)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(selectedTiles.enumerated()), id: \.offset) { index, tile in
                                Button {
                                    onTileTap(index)
                                } label: {
                                    HStack(spacing: 4) {
                                        TileImageView(key: tile.key, wordClass: tile.wordClass)
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        Text(tile.value)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(wordClassColor(tile.wordClass).opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .opacity(selectedTiles.isEmpty ? 0 : 1)
                }
                .frame(height: kChipsHeight)

                // Sentence row — always present, content varies by state
                Group {
                    if isThinking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Generating...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if isWaiting {
                        Image(systemName: "ellipsis")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .symbolEffect(.variableColor.iterative)
                    } else if let sentence = generatedSentence {
                        Text(sentence)
                            .font(.body)
                            .fontWeight(.medium)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Color.clear
                    }
                }
                .frame(height: kSentenceHeight, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: generatedSentence)
                .animation(.easeInOut(duration: 0.2), value: isThinking)

                // Comparison sentence (Apple Intelligence A/B mode)
                if let comparison = comparisonSentence, generatedSentence != nil {
                    HStack(spacing: 4) {
                        Text("AI")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text(comparison)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: kComparisonHeight, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)

            // Commit column — Play (locked group) or Go (editable group, ≥2 tiles).
            Button(action: showReplay ? onReplay : onGo) {
                Image(systemName: showReplay ? "arrow.trianglehead.2.counterclockwise" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(showReplay ? .orange : .blue)
            }
            .buttonStyle(.plain)
            .opacity(showCommit ? 1 : 0)
            .allowsHitTesting(showCommit)
            .frame(width: kColumnWidth)
            .animation(.easeInOut(duration: 0.2), value: showCommit)
        }
        .frame(height: totalContentHeight)
        .animation(.easeInOut(duration: 0.2), value: hasComparison)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
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

// MARK: - TileGridIcon

/// Renders up to 4 tiles as a fixed 2×2 square icon.
struct TileGridIcon: View {
    let tiles: [TileSelection]

    private let cellSize: CGFloat = 26
    private let gap: CGFloat = 2

    // Pad to exactly 4 optional slots
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
