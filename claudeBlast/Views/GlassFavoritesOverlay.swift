// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GlassFavoritesOverlay.swift
//  claudeBlast
//
//  Compact-width favorites surface. Opens from the FavoritesCard in the
//  nav strip. Slides down from the top of the tile grid like the history
//  overlay and hosts the same PromotedChipStrip used by the iPad nav bar
//  so behavior (in-scene/out-of-scene split, pinned ordering) stays
//  identical across form factors.
//

import SwiftUI

struct GlassFavoritesOverlay: View {
    let entries: [SentenceCache]
    let sceneKeySet: Set<String>
    let tileWordClass: [String: String]
    let onPlay: (SentenceCache) -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Favorites")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.trailing, 48)
                    .padding(.bottom, 6)

                    if entries.isEmpty {
                        Text("No favorites yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                    } else {
                        PromotedChipStrip(
                            entries: entries,
                            sceneKeySet: sceneKeySet,
                            tileWordClass: tileWordClass,
                            onTap: { entry in
                                onPlay(entry)
                                onDismiss()
                            }
                        )
                        .padding(.bottom, 8)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

                DismissButton(action: onDismiss)
                    .padding(6)
                    .accessibilityLabel("Dismiss favorites")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { /* swallow tap-through to tiles below */ }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

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
