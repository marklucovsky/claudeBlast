// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfileMigrationTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
struct ProfileMigrationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            TileModel.self,
            SentenceCache.self, BlasterScene.self, MetricEvent.self,
            RecordedScript.self, LoggedUtterance.self,
            ChildProfile.self,
            DeviceProfile.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [cfg])
    }

    /// Isolated UserDefaults so writes from one test don't leak into another.
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ProfileMigrationTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    @Test func freshInstall_doesNotSeedLegacy() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.test", forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: false,
            defaults: defaults
        )

        // DeviceProfile always materialized.
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        // Legacy NOT seeded on a fresh install — onboarding will collect
        // child info from scratch.
        #expect(try ctx.fetch(FetchDescriptor<ChildProfile>()).isEmpty)
    }

    @Test func returningUser_seedsLegacyFromUserDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.compact.en-US.Samantha",
                     forKey: AppSettingsKey.speechVoiceIdentifier)
        defaults.set(5, forKey: AppSettingsKey.tileCapPerGroup)

        let stableNow = Calendar.current.date(from: DateComponents(
            year: 2026, month: 6, day: 4))!
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults,
            now: stableNow
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        let legacy = kids[0]
        #expect(legacy.displayName == "Legacy")
        #expect(legacy.isActive == true)
        #expect(legacy.voiceIdentifier == "com.apple.voice.compact.en-US.Samantha")
        #expect(legacy.maxSelectedTiles == 5)
        #expect(legacy.age == 7) // seeded from age=7 by spec
    }

    @Test func returningUser_withUnsetDefaults_seedsLegacyWithSafeDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        // No keys set.

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].voiceIdentifier == "")
        #expect(kids[0].maxSelectedTiles == 4) // safe fallback
    }

    @Test func returningUser_clampsOutOfRangeTileCap() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set(99, forKey: AppSettingsKey.tileCapPerGroup) // out of range

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx,
            seedLegacy: true,
            defaults: defaults
        )

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids[0].maxSelectedTiles == 8) // clamped to engine max
    }

    @Test func idempotent_doesNotSeedLegacyTwice() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)

        #expect(try ctx.fetch(FetchDescriptor<ChildProfile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
    }

    @Test func skipsLegacy_whenChildProfileAlreadyExists() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults()
        defaults.set("com.apple.voice.test", forKey: AppSettingsKey.speechVoiceIdentifier)

        // User already has a child (e.g., went through onboarding on another
        // synced device).
        let existing = ChildProfile(
            displayName: "Aubrey",
            birthday: ChildProfile.synthesizeBirthday(age: 5),
            voiceIdentifier: "real-voice",
            maxSelectedTiles: 6,
            isActive: true
        )
        ctx.insert(existing)

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: ctx, seedLegacy: true, defaults: defaults)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].displayName == "Aubrey") // unchanged
        #expect(kids[0].voiceIdentifier == "real-voice")
    }
}
