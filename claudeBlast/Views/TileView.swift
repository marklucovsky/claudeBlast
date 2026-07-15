// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TileView: View {
    let tile: TileModel
    var link: String = ""
    var isAudible: Bool = true
    var isSelected: Bool = false
    var labelFontSize: CGFloat = 11
    /// TileScript playback pulse: when `scriptPulseCount` changes and
    /// `scriptPulseKey` matches this tile, the tile bounces — so viewers can see
    /// each scripted tap, including repeated taps in repetition demos.
    var scriptPulseKey: String? = nil
    var scriptPulseCount: Int = 0
    let onTap: () -> Void

    private var isNavigation: Bool { !link.isEmpty }
    @State private var pulseScale: CGFloat = 1.0
    @State private var glow: CGFloat = 0.0

    var body: some View {
        Button {
            triggerPulse()   // every live tap bounces
            onTap()
        } label: {
            VStack(spacing: 0) {
                // Full-bleed square image card
                tileCard

                // Small label below — the images already carry the word,
                // so this is a subtle hint rather than the primary label
                Text(tile.displayName)
                    .font(.system(size: labelFontSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .onChange(of: scriptPulseCount) { _, _ in
            // Scripted taps don't press the Button, so drive the same bounce from
            // the runner's pulse. The count changes every tap, so mashing the same
            // tile re-fires the animation.
            guard scriptPulseKey == tile.key else { return }
            triggerPulse()
        }
    }

    // Quick press-bounce so every tap — live or scripted — has visible feedback.
    private func triggerPulse() {
      // Pop big and briefly HOLD the peak so it registers in motion / on camera,
      // then ease back slowly so the glow lingers long enough to read.
      withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pulseScale = 1.24; glow = 1.0 }
      withAnimation(.easeOut(duration: 0.45).delay(0.16)) { pulseScale = 1.0; glow = 0.0 }
    }

    @ViewBuilder
    private var tileCard: some View {
        ZStack(alignment: .bottomTrailing) {
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
        // Resting border: thick + saturated when selected so the tile clearly
        // stands out from the grid; thin wordClass tint otherwise.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.orange
                        : (isNavigation ? Color.blue.opacity(0.6)
                        : colorForWordClass(tile.wordClass).opacity(0.6)),
                    lineWidth: isSelected ? 6 : 3
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        // Persistent glow lifts the selected tile off the grid so it reads as
        // clearly different, not just "an orange border like any other tile."
        .shadow(color: Color.orange.opacity(isSelected ? 0.75 : 0.0), radius: 10)
        // Press "pop + glow": a thick bright ring + strong colored halo flashes
        // on every tap (glow springs 0→1→0 with the bounce), so a press is
        // unmistakable in motion and on camera.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(glow), lineWidth: 6)
        )
        .shadow(color: Color.cyan.opacity(0.9 * glow), radius: 20)
        .shadow(color: Color.cyan.opacity(0.6 * glow), radius: 9)
    }

    // colorForWordClass is now a shared function in TileImageView.swift
}

#Preview("Audible tile") {
    let tile = TileModel(key: "eat", wordClass: "actions")
    TileView(tile: tile, link: "", isAudible: true, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Nav tile") {
    let tile = TileModel(key: "food", wordClass: "navigation")
    TileView(tile: tile, link: "food", isAudible: false, isSelected: false) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}

#Preview("Selected tile") {
    let tile = TileModel(key: "happy", wordClass: "feeling")
    TileView(tile: tile, link: "", isAudible: true, isSelected: true) {}
        .frame(width: 80)
        .modelContainer(for: TileModel.self, inMemory: true)
}
