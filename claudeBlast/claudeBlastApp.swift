// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  claudeBlastApp.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct claudeBlastApp: App {
    private let modelContainer: ModelContainer
    @State private var sentenceEngine: SentenceEngine

    init() {
        let icloudEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.icloudEnabled)
        let container = setModelContainer(icloudEnabled: icloudEnabled)
        self.modelContainer = container

        // Bootstrap only on first launch (or after a forced version bump).
        if BootstrapLoader.needsBootstrap() {
            _ = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
            BootstrapLoader.markBootstrapComplete()
        }

        // Select provider: env var wins, then UserDefaults, then Mock.
        // If the env var is present, persist it so standalone (non-Xcode) launches
        // on-device can still use the key after the app is force-killed and reopened.
        let provider: any SentenceProvider
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            if UserDefaults.standard.string(forKey: AppSettingsKey.openaiApiKey) != envKey {
                UserDefaults.standard.set(envKey, forKey: AppSettingsKey.openaiApiKey)
            }
            provider = OpenAISentenceProvider(apiKey: envKey)
        } else {
            let choice = UserDefaults.standard.string(forKey: AppSettingsKey.providerChoice) ?? "openai"
            let storedKey = UserDefaults.standard.string(forKey: AppSettingsKey.openaiApiKey) ?? ""
            if choice == "openai", !storedKey.isEmpty {
                provider = OpenAISentenceProvider(apiKey: storedKey)
            } else {
                provider = MockSentenceProvider()
            }
        }
        let engine = SentenceEngine(provider: provider)
        let storedAudio = UserDefaults.standard.object(forKey: AppSettingsKey.audioEnabled)
        engine.audioEnabled = (storedAudio as? Bool) ?? true
        engine.voiceIdentifier = UserDefaults.standard.string(forKey: AppSettingsKey.speechVoiceIdentifier) ?? ""
        self._sentenceEngine = State(initialValue: engine)

        // Configure audio session at launch so speech plays regardless of the
        // ringer/silent switch. .playback bypasses the mute switch; .spokenAudio
        // mode ducks other audio and resumes it after each utterance.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sentenceEngine)
                .onAppear {
                    sentenceEngine.configure(modelContext: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}
