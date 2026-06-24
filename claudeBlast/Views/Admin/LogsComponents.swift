// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LogsComponents.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

// MARK: - Promoted Tiles Detail

struct PromotedTilesDetailView: View {
    let entries: [SentenceCache]
    let tileLookup: [String: TileModel]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        LogTileStrip(tiles: tileSelections(for: entry))
                        Spacer(minLength: 8)
                        Text("\(entry.hitCount) hits")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            entry.isPinned.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(entry.isPinned ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(entry.sentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle("Promoted Tiles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tileSelections(for entry: SentenceCache) -> [TileSelection] {
        entry.tileKeys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }
}

// MARK: - Cache Detail

struct CacheDetailView: View {
    let entries: [SentenceCache]
    let onDelete: (IndexSet) -> Void
    let onFlush: () -> Void

    var body: some View {
        List {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.cacheKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.sentence)
                        .font(.subheadline)
                    Text("Hits: \(entry.hitCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .onDelete(perform: onDelete)
        }
        .navigationTitle("Sentence Cache (\(entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Flush All", role: .destructive) {
                    onFlush()
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Cache Stats Box

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
