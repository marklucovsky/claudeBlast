// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageView.swift
//  claudeBlast
//
//  Unified tile image rendering. Replaces all inline UIImage(named:)/Image()
//  patterns with a single component that respects the active image set and
//  provides a composed placeholder for missing tiles in sparse sets.

import SwiftUI

struct TileImageView: View {
    let key: String
    let wordClass: String

    @Environment(TileImageResolver.self) private var resolver

    var body: some View {
        if let uiImage = resolver.image(for: key) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            // Composed placeholder for missing tiles in sparse sets.
            // Shows the word-class color with the first letter of the key,
            // plus a subtle indicator that this tile needs artwork.
            missingTilePlaceholder
        }
    }

    @ViewBuilder
    private var missingTilePlaceholder: some View {
        Rectangle()
            .fill(colorForWordClass(wordClass))
            .overlay {
                VStack(spacing: 4) {
                    Text(String(key.replacingOccurrences(of: "_", with: " ").prefix(1)).uppercased())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    // Small dot indicator that artwork is missing
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
    }
}

// MARK: - Word Class Colors (shared)

/// Word-class color mapping used by TileView and TileImageView.
/// Factored out so both the image placeholder and the tile card background use the same colors.
func colorForWordClass(_ wordClass: String) -> Color {
    switch wordClass {
    case "actions": return .orange
    case "describe": return .green
    case "people": return .purple
    case "food", "meals", "fruit", "veggie", "snacks": return .red
    case "places": return .blue
    case "social", "feeling", "question": return .pink
    case "navigation": return .indigo
    case "drinks": return .cyan
    case "weather": return Color(red: 0.3, green: 0.6, blue: 0.9)
    case "colors": return .mint
    case "shape": return .teal
    case "body", "health": return Color(red: 0.9, green: 0.5, blue: 0.5)
    case "toy", "games", "sports": return .yellow
    case "art": return Color(red: 0.7, green: 0.4, blue: 0.8)
    case "play": return .yellow
    default: return .gray
    }
}
