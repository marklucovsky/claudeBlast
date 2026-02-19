//
//  SentenceTrayView.swift
//  claudeBlast
//

import SwiftUI
import UIKit

struct SentenceTrayView: View {
    let selectedTiles: [TileSelection]
    let generatedSentence: String?
    let isThinking: Bool
    let isWaiting: Bool
    let onTileTap: (Int) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if selectedTiles.isEmpty {
                    Text("Tap tiles to build a sentence")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(selectedTiles.enumerated()), id: \.offset) { index, tile in
                                Button {
                                    onTileTap(index)
                                } label: {
                                    HStack(spacing: 4) {
                                        Group {
                                            if UIImage(named: tile.key) != nil {
                                                Image(tile.key)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            } else {
                                                Circle()
                                                    .fill(Color.orange)
                                                    .overlay {
                                                        Text(String(tile.value.prefix(1)).uppercased())
                                                            .font(.caption2)
                                                            .fontWeight(.bold)
                                                            .foregroundStyle(.white)
                                                    }
                                            }
                                        }
                                        .frame(width: 28, height: 28)
                                        Text(tile.value)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !selectedTiles.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sentence display area
            if !selectedTiles.isEmpty {
                HStack(spacing: 6) {
                    if isThinking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                    }
                    Spacer()
                }
                .frame(minHeight: 24)
                .animation(.easeInOut(duration: 0.2), value: generatedSentence)
                .animation(.easeInOut(duration: 0.2), value: isThinking)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}
