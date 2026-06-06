// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingCommitTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

@MainActor
struct OnboardingCommitTests {

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

    private func isolatedDefaults() -> UserDefaults {
        let suite = "OnboardingCommitTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func patientInputs(name: String = "Aubrey", age: Int = 5) -> OnboardingInputs {
        OnboardingInputs(
            role: .patient,
            deviceName: "  Sammy's iPad  ",
            createChild: true,
            childName: name,
            childBirthday: ChildProfile.synthesizeBirthday(age: age, asOf: date(2026, 6, 4)),
            childVoiceID: "com.apple.voice.Samantha",
            childMaxTiles: 6,
            apiKey: "sk-onboarding",
            icloudEnabled: false
        )
    }

    @Test func patient_createsDeviceAndChild_andForcesFaceID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        OnboardingCommit.apply(patientInputs(), context: ctx, defaults: defaults, secretStore: secret)

        let devices = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.role == .patient)
        #expect(device.displayName == "Sammy's iPad") // whitespace trimmed
        #expect(device.requireFaceIDForAdmin == true)
        #expect(device.onboardingCompleted == true)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].displayName == "Aubrey")
        #expect(kids[0].isActive == true)
        #expect(kids[0].voiceIdentifier == "com.apple.voice.Samantha")
        #expect(kids[0].maxSelectedTiles == 6)
        #expect(kids[0].age == 5)

        #expect(secret.read() == "sk-onboarding")
        #expect(defaults.bool(forKey: AppSettingsKey.icloudEnabled) == false)
    }

    @Test func personal_skipsChildProfileCreation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.role = .personal
        inputs.createChild = false

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        let devices = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(devices.first?.role == .personal)
        #expect(devices.first?.requireFaceIDForAdmin == false)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.isEmpty)
    }

    @Test func therapist_skippingChildProfile_leavesNoChild() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.role = .therapist
        inputs.createChild = false
        inputs.childName = "" // skip set this

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        let devices = try ctx.fetch(FetchDescriptor<DeviceProfile>())
        #expect(devices.first?.role == .therapist)
        #expect(devices.first?.requireFaceIDForAdmin == false) // therapist opt-in only

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.isEmpty)
    }

    @Test func returningUser_updatesLegacyChildInPlace() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        // Simulate the post-migration state: Legacy ChildProfile + placeholder
        // DeviceProfile already exist before onboarding runs.
        let legacy = ChildProfile(
            displayName: "Legacy",
            birthday: ChildProfile.synthesizeBirthday(age: 7),
            voiceIdentifier: "",
            maxSelectedTiles: 4,
            isActive: true
        )
        ctx.insert(legacy)
        _ = DeviceProfileStore.ensure(context: ctx)

        OnboardingCommit.apply(patientInputs(name: "Aubrey", age: 5),
                               context: ctx, defaults: defaults, secretStore: secret)

        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1) // updated in place, not duplicated
        #expect(kids[0].displayName == "Aubrey")
        #expect(kids[0].maxSelectedTiles == 6)
        #expect(kids[0].isActive == true)
    }

    @Test func emptyChildName_doesNotCreateChild_evenWhenCreateChildTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.childName = "   " // whitespace only

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        // Device still gets set up, but no child profile created.
        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ChildProfile>()).isEmpty)
    }

    @Test func nilApiKey_doesNotClobberStoredKey() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore(initial: "sk-from-env")
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.apiKey = nil // env-var path — leave Keychain alone

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(secret.read() == "sk-from-env")
    }

    @Test func emptyApiKey_explicitlyClears() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore(initial: "sk-old")
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.apiKey = "" // user pressed Skip

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(secret.read() == nil)
    }

    @Test func icloudFlag_isPersistedToDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        var inputs = patientInputs()
        inputs.icloudEnabled = true

        OnboardingCommit.apply(inputs, context: ctx, defaults: defaults, secretStore: secret)

        #expect(defaults.bool(forKey: AppSettingsKey.icloudEnabled) == true)
    }

    @Test func rerunningCommit_doesNotDuplicateRows() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let secret = InMemorySecretStore()
        let defaults = isolatedDefaults()

        OnboardingCommit.apply(patientInputs(), context: ctx, defaults: defaults, secretStore: secret)
        OnboardingCommit.apply(patientInputs(name: "Aubrey 2"), context: ctx, defaults: defaults, secretStore: secret)

        #expect(try ctx.fetch(FetchDescriptor<DeviceProfile>()).count == 1)
        let kids = try ctx.fetch(FetchDescriptor<ChildProfile>())
        #expect(kids.count == 1)
        #expect(kids[0].displayName == "Aubrey 2")
    }
}
