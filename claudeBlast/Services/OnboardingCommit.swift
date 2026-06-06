// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingCommit.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Inputs collected by `OnboardingView`, factored out so the final mutation
/// step is a pure function we can unit-test without instantiating SwiftUI.
struct OnboardingInputs {
    var role: DeviceRole
    var deviceName: String
    /// `true` when a `ChildProfile` should be created/updated.
    /// Always `false` for `.personal`; conditionally true for `.therapist`.
    var createChild: Bool
    var childName: String
    var childBirthday: Date
    var childVoiceID: String
    var childMaxTiles: Int
    /// `nil` = don't touch the vault (env-var path is in play — the launch
    /// code already persisted the env key to the Keychain). `""` = explicit
    /// clear (user pressed Skip after a prior key was stored). Non-empty
    /// string = set to that value.
    var apiKey: String?
    var icloudEnabled: Bool
}

/// Materializes onboarding answers into SwiftData + UserDefaults + Keychain.
/// Called exactly once when the user taps "Open Blaster" on the final step.
///
/// Idempotent against re-runs: upserts the `DeviceProfile` singleton and the
/// `ChildProfile` if a Legacy one was seeded by `ProfileMigration`.
enum OnboardingCommit {
    static func apply(
        _ inputs: OnboardingInputs,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        secretStore: SecretStore = OpenAIKeyVault.defaultStore()
    ) {
        // 1. DeviceProfile — upsert.
        let device = DeviceProfileStore.ensure(context: context)
        device.role = inputs.role
        device.displayName = inputs.deviceName.trimmingCharacters(in: .whitespaces)
        // Patient devices are *always* gated; therapists opt in later from
        // Admin → Device. Personal devices stay ungated.
        if inputs.role == .patient {
            device.requireFaceIDForAdmin = true
        }
        device.onboardingCompleted = true
        device.modifiedAt = .now

        // 2. ChildProfile — upsert if applicable.
        if inputs.createChild
            && !inputs.childName.trimmingCharacters(in: .whitespaces).isEmpty {
            let existing = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
            if let kid = existing.first {
                kid.displayName = inputs.childName.trimmingCharacters(in: .whitespaces)
                kid.birthday = inputs.childBirthday
                kid.voiceIdentifier = inputs.childVoiceID
                kid.maxSelectedTiles = inputs.childMaxTiles
                kid.isActive = true
                kid.modifiedAt = .now
            } else {
                let kid = ChildProfile(
                    displayName: inputs.childName.trimmingCharacters(in: .whitespaces),
                    birthday: inputs.childBirthday,
                    voiceIdentifier: inputs.childVoiceID,
                    maxSelectedTiles: inputs.childMaxTiles,
                    isActive: true
                )
                context.insert(kid)
            }
        }

        // 3. API key — Vault handles trim + empty-as-delete. Skip entirely
        // when inputs.apiKey is nil (env-var path) to avoid clobbering the
        // launch-persisted key.
        if let apiKey = inputs.apiKey {
            OpenAIKeyVault.setKey(apiKey, store: secretStore)
        }

        // 4. iCloud preference — UserDefaults. Container rebuilds at next launch.
        defaults.set(inputs.icloudEnabled, forKey: AppSettingsKey.icloudEnabled)

        // No explicit context.save() — SwiftUI's .modelContainer enables
        // autosave (flushes on background + every few seconds). An explicit
        // save() at this point also throws an unrecoverable SIGABRT on the
        // in-memory test container when inserting DeviceProfile +
        // ChildProfile in the same transaction; needs investigation if a
        // similar crash ever surfaces in production.
    }
}
