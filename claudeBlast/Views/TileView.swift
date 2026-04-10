// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileView: View {
    let pageTile: PageTileModel
    var isSelected: Bool = false
    let onTap: () -> Void

    private var tile: TileModel { pageTile.tile }
    private var isNavigation: Bool { !pageTile.link.isEmpty }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Full-bleed square image card
                tileCard

                // Small label below — the images already carry the word,
                // so this is a subtle hint rather than the primary label
                Text(tile.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tileCard: some View {
        ZStack(alignment: .bottomTrailing) {
            // Card background — word-class color at low opacity so the
            // ARASAAC images have a solid, tinted base instead of transparency.
            colorForWordClass(tile.wordClass).opacity(0.12)
                .aspectRatio(1, contentMode: .fit)

            TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                .aspectRatio(1, contentMode: .fit)
                .padding(6)

            if isNavigation {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .blue)
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.orange : (isNavigation ? Color.blue.opacity(0.5) : Color.clear),
                    lineWidth: isSelected ? 3 : 2
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .opacity(isSelected ? 0.8 : 1.0)
    }

    // colorForWordClass is now a shared function in TileImageView.swift
}

#Preview("Audible tile") {
    let tile = TileModel(key: "eat", wordClass: "actions")
    let pageTile = PageTileModel(tile: tile, link: "", isAudible: true)
    TileView(pageTile: pageTile, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Nav tile") {
    let tile = TileModel(key: "food", wordClass: "navigation")
    let pageTile = PageTileModel(tile: tile, link: "food", isAudible: false)
    TileView(pageTile: pageTile, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Selected tile") {
    let tile = TileModel(key: "happy", wordClass: "feeling")
    let pageTile = PageTileModel(tile: tile, link: "", isAudible: true)
    TileView(pageTile: pageTile, isSelected: true) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}
