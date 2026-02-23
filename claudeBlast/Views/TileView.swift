//
//  TileView.swift
//  claudeBlast
//

import SwiftUI

struct TileView: View {
    let pageTile: PageTileModel
    var isSelected: Bool = false
    let onTap: () -> Void

    private var tile: TileModel { pageTile.tile }
    private var isNavigation: Bool { !pageTile.link.isEmpty }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
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
            if UIImage(named: tile.bundleImage) != nil {
                Image(tile.bundleImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            } else {
                Rectangle()
                    .fill(colorForWordClass(tile.wordClass))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Text(String(tile.displayName.prefix(1)).uppercased())
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
            }

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

    private func colorForWordClass(_ wordClass: String) -> Color {
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
}
