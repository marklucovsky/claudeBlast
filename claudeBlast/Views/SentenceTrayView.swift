//
//  SentenceTrayView.swift
//  claudeBlast
//

import SwiftUI

struct SentenceTrayView: View {
    let selectedTiles: [TileModel]
    let onTileTap: (Int) -> Void
    let onClear: () -> Void

    var body: some View {
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
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            Text(String(tile.displayName.prefix(1)).uppercased())
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                        }
                                    Text(tile.displayName)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}
