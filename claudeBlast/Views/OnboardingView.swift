// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OnboardingView.swift
//  claudeBlast
//
//  First-launch wizard. Gated in ContentView on
//  `DeviceProfile.onboardingCompleted == false`. Mode-branched: a Patient
//  device must create a child profile, a Therapist device may skip it, a
//  Personal device skips it outright.
//

import SwiftUI
import SwiftData
import AVFoundation

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Environment(SentenceEngine.self) private var sentenceEngine

    // Step machine -----------------------------------------------------------

    private enum Step: Int, CaseIterable {
        case welcome, role, deviceName, childProfile, apiKey, icloud, done
    }

    @State private var step: Step = .welcome

    // Collected answers ------------------------------------------------------

    @State private var role: DeviceRole = .patient
    @State private var deviceName: String = ""

    @State private var childName: String = ""
    @State private var childAgeYears: Int = 5
    @State private var childBirthday: Date = ChildProfile.synthesizeBirthday(age: 5)
    @State private var editingExactBirthday: Bool = false
    @State private var childVoiceID: String = ""
    @State private var childMaxTiles: Int = 4
    @State private var skipChildProfile: Bool = false

    @State private var apiKey: String = ""
    @State private var icloudEnabled: Bool = false

    // Derived ----------------------------------------------------------------

    /// True when the env var path is consumed silently — the API key step is
    /// auto-skipped (developer path, not surfaced in the consumer UI).
    private var hasEnvKey: Bool {
        if let v = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespaces), !v.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                Group {
                    switch step {
                    case .welcome:       welcomeStep
                    case .role:          roleStep
                    case .deviceName:    deviceNameStep
                    case .childProfile:  childProfileStep
                    case .apiKey:        apiKeyStep
                    case .icloud:        icloudStep
                    case .done:          doneStep
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }

            navBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.bar)
        }
        .onAppear(perform: prefillFromExistingProfileIfAny)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let visibleSteps = Step.allCases.filter { isStepVisible($0) }
        let idx = visibleSteps.firstIndex(of: step) ?? 0
        return ProgressView(value: Double(idx),
                            total: Double(max(1, visibleSteps.count - 1)))
            .progressViewStyle(.linear)
    }

    private func isStepVisible(_ s: Step) -> Bool {
        switch s {
        case .childProfile: return role != .personal
        case .apiKey:       return !hasEnvKey
        default:            return true
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Blaster")
                .font(.largeTitle.bold())
            Text("A voice for non-verbal children. Pick tiles, hear sentences.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 8)
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private by default").font(.headline)
                    Text("Your child's data lives on this device. AI calls send the selected words and nothing else.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.title)
            }
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open source").font(.headline)
                    Text("Apache-licensed. Built so the community can adapt it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.title)
            }
        }
    }

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How will this device be used?")
                .font(.title.bold())
            Text("Tap one. You can change this later from Admin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(DeviceRole.allCases, id: \.self) { option in
                    roleCard(option)
                }
            }
        }
    }

    private func roleCard(_ option: DeviceRole) -> some View {
        Button {
            role = option
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: role == option
                      ? "largecircle.fill.circle"
                      : "circle")
                    .font(.title2)
                    .foregroundStyle(role == option ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.displayName).font(.headline)
                    Text(option.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(role == option ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: role == option ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deviceNameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name this device")
                .font(.title.bold())
            Text("Used for AirDrop attribution when sharing scenes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(deviceNamePlaceholder, text: $deviceName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var deviceNamePlaceholder: String {
        switch role {
        case .patient:   return "Sammy's iPad"
        case .therapist: return "Dr. Yalcin's iPad"
        case .personal:  return "My iPad"
        }
    }

    private var childProfileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(role == .therapist ? "Add your first patient" : "About the child")
                .font(.title.bold())
            if role == .therapist {
                Text("Optional — you can add patients later from Admin → Profiles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.headline)
                TextField("Aubrey", text: $childName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Age").font(.headline)
                    Spacer()
                    Text("\(childAgeYears) years old")
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $childAgeYears, in: 1...21) {
                    EmptyView()
                }
                .labelsHidden()
                .onChange(of: childAgeYears) { _, newValue in
                    if !editingExactBirthday {
                        childBirthday = ChildProfile.synthesizeBirthday(age: newValue)
                    }
                }
                Text("Birthday: \(birthdayDisplay) — age auto-updates from this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Edit exact birthday", isExpanded: $editingExactBirthday) {
                    DatePicker("Birthday", selection: $childBirthday,
                               in: ...Date.now,
                               displayedComponents: .date)
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tiles per group").font(.headline)
                    Spacer()
                    Text("\(childMaxTiles)").foregroundStyle(.secondary)
                }
                Stepper(value: $childMaxTiles, in: 2...8) { EmptyView() }
                    .labelsHidden()
                Text("Maximum tiles selectable before the sentence is generated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice").font(.headline)
                voicePicker
            }
        }
    }

    private var birthdayDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: childBirthday)
    }

    private var voicePicker: some View {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
        return HStack {
            Picker("Voice", selection: $childVoiceID) {
                Text("System Default").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name) (\(v.language))").tag(v.identifier)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
            Button {
                previewVoice()
            } label: {
                Label("Preview", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @State private var previewSynth = AVSpeechSynthesizer()

    private func previewVoice() {
        previewSynth.stopSpeaking(at: .immediate)
        let phrase = childName.isEmpty
            ? "Hi, this is the voice I'll use."
            : "Hi \(childName), I'll be your voice."
        let utt = AVSpeechUtterance(string: phrase)
        if !childVoiceID.isEmpty,
           let v = AVSpeechSynthesisVoice(identifier: childVoiceID) {
            utt.voice = v
        }
        previewSynth.speak(utt)
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenAI API Key")
                .font(.title.bold())
            Text("Blaster uses OpenAI to turn tile selections into sentences. Get a key at platform.openai.com.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Label {
                Text("Stored in this device's Keychain only. Never synced via iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "key.fill").foregroundStyle(.orange)
            }
            Text("Skip to use Mock responses instead (no API calls). You can add a key later from Admin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var icloudStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync via iCloud?")
                .font(.title.bold())
            Toggle(isOn: $icloudEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable iCloud sync").font(.headline)
                    Text("Sync child profiles, scenes, and history across your own Apple devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if icloudEnabled {
                Label {
                    Text("Sync activates after the next app launch.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                }
            }
            Label {
                Text("The OpenAI API key never syncs — it stays in this device's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.green)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Ready").font(.largeTitle.bold())
            Text(doneSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var doneSummary: String {
        switch role {
        case .patient:
            return childName.isEmpty
                ? "Your patient device is set up. Tap Open Blaster to start."
                : "\(childName)'s device is ready. Tap Open Blaster to start."
        case .therapist:
            return "Therapist mode is on. Add more patients from Admin → Profiles."
        case .personal:
            return "Personal mode. No child profile, no auth gate."
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            if canGoBack {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if canSkip {
                Button("Skip") { skipAndAdvance() }
                    .buttonStyle(.borderless)
            }
            Button(primaryActionLabel) {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvance)
        }
    }

    private var canGoBack: Bool {
        step != .welcome && step != .done
    }

    private var canSkip: Bool {
        switch step {
        case .childProfile: return role == .therapist
        case .apiKey:       return true
        default:            return false
        }
    }

    private var primaryActionLabel: String {
        switch step {
        case .welcome: return "Get Started"
        case .done:    return "Open Blaster"
        default:       return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome:      return true
        case .role:         return true
        case .deviceName:   return !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
        case .childProfile: return !childName.trimmingCharacters(in: .whitespaces).isEmpty
        case .apiKey:       return true
        case .icloud:       return true
        case .done:         return true
        }
    }

    // MARK: - Step transitions

    private func primaryAction() {
        if step == .done {
            commitAndFinish()
        } else {
            advance()
        }
    }

    private func advance() {
        skipChildProfile = false
        moveStep(forward: true)
    }

    private func skipAndAdvance() {
        if step == .childProfile { skipChildProfile = true }
        if step == .apiKey { apiKey = "" }
        moveStep(forward: true)
    }

    private func goBack() {
        moveStep(forward: false)
    }

    private func moveStep(forward: Bool) {
        let all = Step.allCases
        let currentIdx = all.firstIndex(of: step) ?? 0
        if forward {
            for i in (currentIdx + 1)..<all.count where isStepVisible(all[i]) {
                withAnimation(.easeInOut(duration: 0.2)) { step = all[i] }
                return
            }
        } else {
            for i in stride(from: currentIdx - 1, through: 0, by: -1) where isStepVisible(all[i]) {
                withAnimation(.easeInOut(duration: 0.2)) { step = all[i] }
                return
            }
        }
    }

    // MARK: - Pre-fill from Legacy seed

    private func prefillFromExistingProfileIfAny() {
        let existing = (try? modelContext.fetch(FetchDescriptor<ChildProfile>())) ?? []
        guard let legacy = existing.first else { return }
        childName = legacy.displayName == "Legacy" ? "" : legacy.displayName
        childBirthday = legacy.birthday
        childAgeYears = ChildProfile.age(from: legacy.birthday, asOf: .now)
        childVoiceID = legacy.voiceIdentifier
        childMaxTiles = legacy.maxSelectedTiles
        editingExactBirthday = legacy.displayName != "Legacy"

        // Pre-fill the device display name too if we can recover it.
        if let device = DeviceProfileStore.current(context: modelContext) {
            if !device.displayName.isEmpty { deviceName = device.displayName }
        }
    }

    // MARK: - Final commit

    private func commitAndFinish() {
        let inputs = OnboardingInputs(
            role: role,
            deviceName: deviceName,
            createChild: role != .personal && !skipChildProfile,
            childName: childName,
            childBirthday: childBirthday,
            childVoiceID: childVoiceID,
            childMaxTiles: childMaxTiles,
            apiKey: hasEnvKey ? nil : apiKey, // env-var path keeps its launch-persisted key
            icloudEnabled: icloudEnabled
        )
        OnboardingCommit.apply(inputs, context: modelContext)
        profileResolver.refresh()
        // Switch the running engine to OpenAI when the user just supplied a key.
        if let key = OpenAIKeyVault.currentKey() {
            sentenceEngine.switchProvider(OpenAISentenceProvider(apiKey: key))
        }
    }
}
