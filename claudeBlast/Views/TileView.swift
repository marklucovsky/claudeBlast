//
//  TileView.swift
//  claudeBlast
//

import SwiftUI

struct TileView: View {
    let pageTile: PageTileModel
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
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isNavigation ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 2)
            )
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
        case "descriptions": return .green
        case "people": return .purple
        case "food": return .red
        case "places": return .blue
        case "things": return .teal
        case "navigation": return .indigo
        default: return .gray
        }
    }
}
