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
            VStack(spacing: 6) {
                tileImage
                .overlay(alignment: .bottomTrailing) {
                    if isNavigation {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, .blue)
                            .offset(x: 4, y: 4)
                    }
                }

                Text(tile.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.orange.opacity(0.1) : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.orange : (isNavigation ? Color.blue.opacity(0.4) : Color.clear),
                        lineWidth: isSelected ? 2.5 : 2
                    )
            )
            .opacity(isSelected ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tileImage: some View {
        if UIImage(named: tile.bundleImage) != nil {
            Image(tile.bundleImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                Circle()
                    .fill(colorForWordClass(tile.wordClass))
                    .frame(width: 64, height: 64)
                Text(String(tile.displayName.prefix(1)).uppercased())
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
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
