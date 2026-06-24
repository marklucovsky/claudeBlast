// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileFormSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Voice Picker

/// Lists installed English voices grouped by quality tier.
///
/// iOS ships three tiers:
///   Default   — built-in, always available, sounds robotic
///   Enhanced  — ~50–150 MB download per voice, noticeably better
///   Premium   — ~200 MB download, on-device neural model (iOS 17+),
///               sounds natural and is indistinguishable from cloud TTS
///
/// Downloads live in Settings → Accessibility → Spoken Content → Voices.
/// Audio never leaves the device regardless of tier.
// VoicePickerSection and AVSpeechSynthesisVoiceQuality.sortOrder live in
// VoicePickerSection.swift now — shared by Admin, the profile form, and
// onboarding so the picker stays consistent.

// MARK: - Voice section header with help popover

private struct VoiceSectionHeader: View {
    @State private var showHelp = false

    var body: some View {
        HStack {
            Text("Voice")
            Spacer()
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                VoiceHelpPopover()
            }
        }
    }
}

private struct VoiceHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice Quality Tiers")
                .font(.headline)
            Text("**Default** — Built-in voices, always available.")
            Text("**Enhanced** — Noticeably better quality. ~50–150 MB download per voice.")
            Text("**Premium** — On-device neural voice, sounds natural. ~200 MB download.")
            Divider()
            Text("To download Enhanced or Premium voices, go to:")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("Settings → Accessibility → Spoken Content → Voices")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(minWidth: 300, maxWidth: 400)
    }
}

// MARK: - Child profile form sheet

/// Compact create/edit form for a `ChildProfile`. Used by the Admin
/// Profiles section. Captures age in years and synthesizes
/// `ChildProfile.birthday` via the same helper as onboarding.
struct ChildProfileFormSheet: View {
    enum Mode {
        case create
        case edit(ChildProfile)
    }

    let mode: Mode
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var name: String = ""
    @State private var ageYears: Int = 5
    @State private var birthday: Date = ChildProfile.synthesizeBirthday(age: 5)
    @State private var editingExactBirthday: Bool = false
    @State private var voiceID: String = ""
    @State private var maxTiles: Int = 4
    @State private var ttsRate: Float = 0.5
    @State private var ttsVolume: Float = 1.0
    @State private var interactionMode: InteractionMode = .sentence
    @State private var makeActive: Bool = false

    private var titleText: String {
        switch mode {
        case .create: return "New Child Profile"
        case .edit:   return "Edit Child Profile"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Personalize the voice preview when the child's name is filled in:
    /// "Hi Aubrey, I'll be your voice." Otherwise a generic line so the
    /// preview still works while the form is being filled out.
    private var previewPhrase: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? "Hi, I'll be your voice."
            : "Hi \(trimmed), I'll be your voice."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Stepper(value: $ageYears, in: 1...21) {
                        HStack {
                            Text("Age")
                            Spacer()
                            Text("\(ageYears)").foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: ageYears) { _, newValue in
                        if !editingExactBirthday {
                            birthday = ChildProfile.synthesizeBirthday(age: newValue)
                        }
                    }
                    DisclosureGroup("Exact birthday", isExpanded: $editingExactBirthday) {
                        DatePicker("Birthday", selection: $birthday,
                                   in: ...Date.now, displayedComponents: .date)
                    }
                }

                Section("Voice") {
                    VoicePickerSection(
                        voiceIdentifier: $voiceID,
                        previewPhrase: previewPhrase
                    )
                }

                Section("Mode") {
                    Picker("Interaction", selection: $interactionMode) {
                        ForEach(InteractionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text(interactionMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Tiles + Audio") {
                    Stepper(value: $maxTiles, in: 2...8) {
                        HStack {
                            Text("Tiles per group")
                            Spacer()
                            Text("\(maxTiles)").foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Speech rate \(String(format: "%.2f", ttsRate))")
                            .font(.caption)
                        Slider(value: $ttsRate, in: 0.3...0.7)
                    }
                    VStack(alignment: .leading) {
                        Text("Volume \(String(format: "%.2f", ttsVolume))")
                            .font(.caption)
                        Slider(value: $ttsVolume, in: 0.0...1.0)
                    }
                }

                if case .create = mode {
                    Section {
                        Toggle("Make this profile active", isOn: $makeActive)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if case let .edit(profile) = mode {
            name = profile.displayName
            birthday = profile.birthday
            ageYears = ChildProfile.age(from: profile.birthday, asOf: .now)
            editingExactBirthday = true
            voiceID = profile.voiceIdentifier
            maxTiles = profile.maxSelectedTiles
            ttsRate = profile.ttsRate
            ttsVolume = profile.ttsVolume
            interactionMode = profile.interactionMode
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .create:
            let profile = ChildProfile(
                displayName: trimmed,
                birthday: birthday,
                voiceIdentifier: voiceID,
                maxSelectedTiles: maxTiles,
                isActive: false
            )
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            profile.interactionMode = interactionMode
            modelContext.insert(profile)
            if makeActive {
                profileResolver.setActive(id: profile.id)
            }
        case .edit(let profile):
            profile.displayName = trimmed
            profile.birthday = birthday
            profile.voiceIdentifier = voiceID
            profile.maxSelectedTiles = maxTiles
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            profile.interactionMode = interactionMode
            profile.modifiedAt = .now
            profileResolver.refresh()
        }
        onDismiss()
    }
}
