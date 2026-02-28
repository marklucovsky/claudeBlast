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
private let kColumnWidth: CGFloat = 36

struct SentenceTrayView: View {
    let selectedTiles: [TileSelection]
    let generatedSentence: String?
    let isThinking: Bool
    let isWaiting: Bool
    let canReplay: Bool
    let recentHistory: [HistoryEntry]
    let onTileTap: (Int) -> Void
    let onClear: () -> Void
    let onReplay: () -> Void
    let onReplayHistory: (HistoryEntry) -> Void

    @State private var showHistory: Bool = false

    private var showReplay: Bool {
        canReplay && !isThinking && !isWaiting && generatedSentence != nil
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
                                        ZStack {
                                            wordClassColor(tile.wordClass).opacity(0.12)
                                            if UIImage(named: tile.key) != nil {
                                                Image(tile.key)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(2)
                                            } else {
                                                Text(String(tile.value.prefix(1)).uppercased())
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(wordClassColor(tile.wordClass))
                                            }
                                        }
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
            }
            .frame(maxWidth: .infinity)

            // Replay column — vertically centered between the right-column buttons
            Button(action: onReplay) {
                Image(systemName: "arrow.trianglehead.2.counterclockwise")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .opacity(showReplay ? 1 : 0)
            .allowsHitTesting(showReplay)
            .frame(width: kColumnWidth)
            .animation(.easeInOut(duration: 0.2), value: showReplay)

            // Right column — clear (top) + history (bottom)
            VStack {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(selectedTiles.isEmpty ? 0 : 1)
                .allowsHitTesting(!selectedTiles.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: selectedTiles.isEmpty)

                Spacer()

                Button { showHistory = true } label: {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(recentHistory.isEmpty ? 0 : 1)
                .allowsHitTesting(!recentHistory.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: recentHistory.isEmpty)
            }
            .frame(width: kColumnWidth, height: kContentHeight)
        }
        .frame(height: kContentHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                List(recentHistory) { entry in
                    Button {
                        onReplayHistory(entry)
                        showHistory = false
                    } label: {
                        HStack(spacing: 12) {
                            TileGridIcon(tiles: entry.tiles)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.sentence)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(entry.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showHistory = false }
                    }
                }
            }
        }
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
private struct TileGridIcon: View {
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
            ZStack {
                wordClassColor(tile.wordClass).opacity(0.12)
                if UIImage(named: tile.key) != nil {
                    Image(tile.key)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                } else {
                    wordClassColor(tile.wordClass)
                    Text(String(tile.value.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: cellSize, height: cellSize)
        } else {
            Color(.secondarySystemBackground)
                .frame(width: cellSize, height: cellSize)
        }
    }

}
