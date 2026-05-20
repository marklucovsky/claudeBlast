// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GlassHistoryOverlay.swift
//  claudeBlast
//
//  Compact-width history surface. Slides down from the top of the tile
//  grid like GlassSentencePopover and overlaps the top row of tiles so
//  the Liquid Glass material refracts colorful content. Vertical scroll
//  list of historical TileGroups (chips + sentence). Tap a row to reopen
//  the group, long-press for delete.
//
//  iPad's existing horizontal history strip in SentenceTrayView is
//  untouched — this is the iPhone-class equivalent.
//

import SwiftUI

struct GlassHistoryOverlay: View {
    let groups: [TileGroup]
    let onReopen: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""

    private var filteredGroups: [TileGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            if let sentence = group.sentence, sentence.lowercased().contains(query) {
                return true
            }
            return group.tiles.contains { tile in
                tile.value.lowercased().contains(query) ||
                tile.key.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    SearchField(text: $searchText)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.trailing, 40)
                        .padding(.bottom, 8)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            if filteredGroups.isEmpty {
                                Text(searchText.isEmpty ? "No history yet" : "No matches")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(filteredGroups) { group in
                                    HistoryRow(
                                        group: group,
                                        onTap: { onReopen(group.id) },
                                        onDelete: { onDelete(group.id) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .frame(maxHeight: 460)

                DismissButton(action: onDismiss)
                    .padding(6)
                    .accessibilityLabel("Dismiss history")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { /* swallow tap-through to tiles below */ }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 44pt-hit-target dismiss button. Visible chip is a 32pt circle with a
/// solid material fill + dark stroke so it reads as an obvious close
/// affordance against the glass card; tappable area extends to 44pt.
private struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search history", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.subheadline)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.55))
        )
    }
}

private struct HistoryRow: View {
    let group: TileGroup
    let onTap: () -> Void
    let onDelete: () -> Void

    private let chipSize: CGFloat = 32

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(group.tiles.enumerated()), id: \.offset) { _, tile in
                        ZStack {
                            wordClassColor(tile.wordClass).opacity(0.12)
                            TileImageView(key: tile.key, wordClass: tile.wordClass)
                                .padding(2)
                        }
                        .frame(width: chipSize, height: chipSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                }

                if let sentence = group.sentence {
                    Text(sentence)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
