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
    ///
    /// Resolution order:
    /// 1. Any *real* (`isSystem == false`) profile marked active wins, with
    ///    `ChildProfile.resolveActive` picking the canonical one under a
    ///    CloudKit race.
    /// 2. Otherwise the Sandbox (`isSystem == true`) profile becomes
    ///    active. ProfileMigration guarantees it exists.
    /// 3. If neither exists (bootstrap hasn't run yet), `active` is nil
    ///    and the synchronous getters use safe fallbacks.
    func refresh() {
        guard let ctx = context else {
            active = nil
            return
        }
        let activeFetch = FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isActive && !$0.isSystem }
        )
        let realActive = (try? ctx.fetch(activeFetch)) ?? []
        if let winner = ChildProfile.resolveActive(from: realActive) {
            active = winner
            return
        }
        let sandboxFetch = FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isSystem }
        )
        let sandboxes = (try? ctx.fetch(sandboxFetch)) ?? []
        active = sandboxes.first
    }

    // MARK: - Synchronous getters with safe fallbacks

    var ageGrade: Int { active?.ageGrade ?? Self.fallbackAgeGrade }
    var voiceIdentifier: String { active?.voiceIdentifier ?? "" }
    var ttsRate: Float { active?.ttsRate ?? Self.fallbackTTSRate }
    var ttsVolume: Float { active?.ttsVolume ?? Self.fallbackTTSVolume }
    var maxSelectedTiles: Int { active?.maxSelectedTiles ?? Self.fallbackMaxTiles }
    /// Interaction mode of the active child; defaults to AI sentences when no
    /// real profile is active (Sandbox/pre-onboarding).
    var interactionMode: InteractionMode { active?.interactionMode ?? .sentence }
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
