// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileResolver.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import Foundation

/// Single source of truth for "which child is active right now and what
/// are their settings." Injected into `SentenceEngine` so the prompt
/// builder, tile cap, and TTS voice all derive from the same place.
///
/// `ChildProfile.isActive` is treated as a *hint* — under CloudKit, two
/// devices can race and end up with multiple flags set. The resolver
/// runs every candidate through `ChildProfile.resolveActive(from:)` which
/// picks the canonical winner with a deterministic tiebreaker.
///
/// Mutations that change `isActive` should call `setActive(id:)` so the
/// resolver re-reads the store after a single atomic transaction.
@Observable
@MainActor
final class ChildProfileResolver {
    /// The currently active profile, resolved from SwiftData. Nil when no
    /// profile is marked active yet (fresh install pre-onboarding).
    private(set) var active: ChildProfile?

    private var context: ModelContext?

    /// Fallbacks for the no-active-profile case. Sized for a safe baseline
    /// rather than a "best guess" — better to be conservative than to send
    /// a 12-year-old prompt to a 4-year-old.
    static let fallbackAgeGrade: Int = 2
    static let fallbackMaxTiles: Int = 4
    static let fallbackTTSRate: Float = 0.5
    static let fallbackTTSVolume: Float = 1.0

    init() {}

    /// Wire the SwiftData context. Safe to call multiple times; each call
    /// re-resolves the active profile from the current store.
    func configure(modelContext: ModelContext) {
        self.context = modelContext
        refresh()
    }

    /// Re-read the active profile from SwiftData. Called from
    /// `configure` and after mutations.
    func refresh() {
        guard let ctx = context else {
            active = nil
            return
        }
        let descriptor = FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isActive }
        )
        let candidates = (try? ctx.fetch(descriptor)) ?? []
        active = ChildProfile.resolveActive(from: candidates)
    }

    // MARK: - Synchronous getters with safe fallbacks

    var ageGrade: Int { active?.ageGrade ?? Self.fallbackAgeGrade }
    var voiceIdentifier: String { active?.voiceIdentifier ?? "" }
    var ttsRate: Float { active?.ttsRate ?? Self.fallbackTTSRate }
    var ttsVolume: Float { active?.ttsVolume ?? Self.fallbackTTSVolume }
    var maxSelectedTiles: Int { active?.maxSelectedTiles ?? Self.fallbackMaxTiles }
    var activeChildID: String? { active?.id }

    // MARK: - Mutation

    /// Set the given profile as the sole active one. Deactivates every
    /// other profile and bumps `modifiedAt` so the resolver's CloudKit-race
    /// tiebreaker (most-recent-modifiedAt wins) reflects the user's intent.
    func setActive(id: String) {
        guard let ctx = context else { return }
        let all = (try? ctx.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for profile in all {
            if profile.id == id {
                if !profile.isActive { profile.isActive = true }
                profile.modifiedAt = now
            } else if profile.isActive {
                profile.isActive = false
                profile.modifiedAt = now
            }
        }
        try? ctx.save()
        refresh()
    }
}
