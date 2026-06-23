// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfile.swift
//  claudeBlast
//

import SwiftData
import Foundation
import AVFoundation

/// How the child's tile taps turn into communication.
enum InteractionMode: String, CaseIterable, Identifiable {
    /// Tiles accumulate into a group; AI builds a sentence (the default).
    case sentence
    /// Classic AAC: each tile speaks its own word on tap and appends to a
    /// running FIFO strip. No AI, no sentence — good for ABC/123/new-word
    /// boards and for demoing AI vs. classic side by side on one device.
    case singleWord

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sentence:   return "AI Sentences"
        case .singleWord: return "Single Words"
        }
    }

    var detail: String {
        switch self {
        case .sentence:   return "Tiles combine into an AI-generated sentence."
        case .singleWord: return "Each tile speaks its word; words build a strip. No AI."
        }
    }
}

/// Per-child identity. Syncs via CloudKit when iCloud is enabled, so a
/// therapist's roster appears across their own devices.
///
/// Age is never stored as an integer — it's computed from `birthday` on read,
/// so a child's age ticks over without any admin action. Onboarding captures
/// "age in years" and synthesizes a birthday via
/// `ChildProfile.synthesizeBirthday(age:asOf:)`, placed roughly 8 months
/// ahead in the calendar so the displayed age stays stable for ~8 months
/// then auto-increments at the synthetic birthday.
@Model
final class ChildProfile {
    /// String, not UUID — matches the project convention (TileModel, BlasterScene)
    /// and keeps SwiftData+CloudKit happy without `@Attribute(.unique)`.
    var id: String = UUID().uuidString
    var displayName: String = ""
    /// Source of truth for age. Editable directly by admin if the real
    /// birthday is known; otherwise synthesized from "age in years."
    var birthday: Date = Date.now
    /// AVSpeechSynthesisVoice identifier. Empty = system default.
    var voiceIdentifier: String = ""
    /// Replaces the device-wide `tile_cap_per_group` UserDefaults setting
    /// for the active child. Resolver falls back to 4 if no active child.
    var maxSelectedTiles: Int = 4
    /// AVSpeechUtterance rate. 0.5 ≈ AVSpeechUtteranceDefaultSpeechRate on iOS.
    var ttsRate: Float = 0.5
    /// AVSpeechUtterance volume. 0.0–1.0.
    var ttsVolume: Float = 1.0
    /// Interaction mode raw value (see `interactionMode`). Stored as a String
    /// for CloudKit; defaults to AI sentences. Unknown values fall back to
    /// `.sentence` so a future mode on another device degrades gracefully.
    var interactionModeRaw: String = InteractionMode.sentence.rawValue
    /// BlasterScene.name to land on at app launch / session-revert.
    /// Empty = honor the device's currently-active scene.
    var defaultSceneKey: String = ""
    /// Therapist-only notes. Never fed to the prompt.
    var notes: String = ""
    /// Hint only — `ChildProfileResolver` resolves the true active profile
    /// using a deterministic tiebreaker (most-recently-modified wins) to
    /// survive CloudKit races where two devices both set isActive.
    var isActive: Bool = false
    /// True for the per-device Sandbox profile — the always-present
    /// fallback the resolver returns when no real child is active. Created
    /// by `ProfileMigration.ensureProfilesAfterBootstrap` and visible (but
    /// undeletable) in the Admin Profiles list.
    var isSystem: Bool = false
    var createdAt: Date = Date.now
    /// Bumped on every mutation. Drives the resolver's tiebreaker.
    var modifiedAt: Date = Date.now

    init(displayName: String, birthday: Date, voiceIdentifier: String = "",
         maxSelectedTiles: Int = 4, defaultSceneKey: String = "",
         notes: String = "", isActive: Bool = false, isSystem: Bool = false) {
        self.displayName = displayName
        self.birthday = birthday
        self.voiceIdentifier = voiceIdentifier
        self.maxSelectedTiles = maxSelectedTiles
        self.defaultSceneKey = defaultSceneKey
        self.notes = notes
        self.isActive = isActive
        self.isSystem = isSystem
    }

    // MARK: - Derived getters

    /// Whole-year age computed live from `birthday`. Auto-increments as
    /// time passes — no admin action needed.
    var age: Int {
        ChildProfile.age(from: birthday, asOf: .now)
    }

    /// US grade-level approximation used by SentencePromptBuilder.
    /// Convention: 1st grade ≈ age 6, capped at K-12 range.
    var ageGrade: Int {
        min(12, max(1, age - 5))
    }

    /// Typed accessor over `interactionModeRaw`. Reads fall back to `.sentence`
    /// for an unknown raw value; writes store the raw string + bump `modifiedAt`.
    var interactionMode: InteractionMode {
        get { InteractionMode(rawValue: interactionModeRaw) ?? .sentence }
        set {
            interactionModeRaw = newValue.rawValue
            modifiedAt = .now
        }
    }

    // MARK: - Age helpers

    /// Whole-year age between `birthday` and `now`. Calendar-aware so
    /// month/day comparisons handle leap years correctly.
    static func age(from birthday: Date, asOf now: Date) -> Int {
        Calendar.current.dateComponents([.year], from: birthday, to: now).year ?? 0
    }

    /// Synthesize a birthday from "age in years" using the
    /// "8 months ahead, year back enough" formula:
    ///
    /// 1. Compute `nextBirthday = now + 8 months`.
    /// 2. Birthday year = nextBirthday.year - (age + 1) — so the *next*
    ///    birthday increments the child to `age + 1`.
    /// 3. Birthday month/day = nextBirthday.month/day.
    /// 4. Day clamped to the last valid day of the target month
    ///    (handles Feb 29, Jan 31 → Feb 28, etc.).
    ///
    /// Property: the kid's displayed age stays at `age` for ~8 months after
    /// the profile is created, then auto-ticks to `age + 1`.
    static func synthesizeBirthday(age: Int, asOf now: Date = .now) -> Date {
        let cal = Calendar.current
        guard let nextBday = cal.date(byAdding: .month, value: 8, to: now) else {
            return now
        }
        let nextComps = cal.dateComponents([.year, .month, .day], from: nextBday)
        let birthYear = (nextComps.year ?? 2000) - (age + 1)
        let birthMonth = nextComps.month ?? 1
        let requestedDay = nextComps.day ?? 1

        // Day-clamp: if the source day doesn't exist in the target month
        // (e.g., Feb 29 in a non-leap year), back off to the last valid day.
        let firstOfTarget = cal.date(from: DateComponents(
            year: birthYear, month: birthMonth, day: 1)) ?? now
        let dayRange = cal.range(of: .day, in: .month, for: firstOfTarget)
            ?? Range(uncheckedBounds: (lower: 1, upper: 29))
        let clampedDay = min(requestedDay, dayRange.upperBound - 1)

        return cal.date(from: DateComponents(
            year: birthYear, month: birthMonth, day: clampedDay)) ?? now
    }

    // MARK: - Active resolution

    /// Pure function used by `ChildProfileResolver` (commit 3) and tests.
    /// Picks the canonical active profile from a candidate list, surviving
    /// CloudKit races where two devices both set `isActive = true`.
    ///
    /// Resolution:
    /// 1. If exactly one is active, return it.
    /// 2. If multiple are active, prefer the most-recently-modified;
    ///    deterministic tiebreaker by lowest `id` lexicographically.
    /// 3. If none are active, return nil.
    static func resolveActive(from candidates: [ChildProfile]) -> ChildProfile? {
        let active = candidates.filter { $0.isActive }
        guard !active.isEmpty else { return nil }
        if active.count == 1 { return active[0] }
        return active.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.id < rhs.id
        }.first
    }
}
