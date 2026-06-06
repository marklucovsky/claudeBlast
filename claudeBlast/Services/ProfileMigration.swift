// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfileMigration.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// One-shot migration that runs after `BootstrapLoader` at app launch.
///
/// Two jobs:
/// 1. Materialize the singleton `DeviceProfile` so the onboarding gate
///    always has a row to read.
/// 2. For *returning users* (this version is the first one that knows about
///    `ChildProfile`, but they already have scenes and tuned UserDefaults),
///    seed a "Legacy" `ChildProfile` pre-populated with their prior voice
///    and tile-cap. Onboarding step 4 reads the Legacy profile and lets the
///    user accept-as-is or revise.
///
/// Fresh installs (no prior bootstrap) skip the Legacy seed — onboarding
/// collects the child's info from scratch.
enum ProfileMigration {

    /// Run after `BootstrapLoader.loadDefaultVocabulary` / `needsBootstrap`.
    ///
    /// - Parameters:
    ///   - context: model context to mutate
    ///   - seedLegacy: pass `true` for returning users (the
    ///     `bootstrapInstalled` flag was set before this launch), `false`
    ///     for fresh installs.
    ///   - defaults: injected for test isolation. Defaults to `.standard`.
    ///   - now: clock injection for the Legacy birthday synthesis.
    static func ensureProfilesAfterBootstrap(
        context: ModelContext,
        seedLegacy: Bool,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        DeviceProfileStore.ensure(context: context)

        guard seedLegacy else { return }

        let existing = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        guard existing.isEmpty else { return }

        let voiceID = defaults.string(forKey: AppSettingsKey.speechVoiceIdentifier) ?? ""
        // tile_cap_per_group is engine-clamped to [2, 8]; mirror that here.
        let rawCap = defaults.integer(forKey: AppSettingsKey.tileCapPerGroup)
        let tileCap = rawCap > 0 ? min(8, max(2, rawCap)) : 4

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let legacy = ChildProfile(
            displayName: "Legacy",
            birthday: ChildProfile.synthesizeBirthday(age: 7, asOf: now),
            voiceIdentifier: voiceID,
            maxSelectedTiles: tileCap,
            defaultSceneKey: "",
            notes: "Seeded from prior install at \(isoFormatter.string(from: now))",
            isActive: true
        )
        context.insert(legacy)
    }
}
