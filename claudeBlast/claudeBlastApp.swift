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
    @State private var navigationCoordinator = NavigationCoordinator()
    @State private var scriptRunner = TileScriptRunner()
    @State private var scriptRecorder = TileScriptRecorder()
    @State private var imageResolver = TileImageResolver()

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

        // Restore image set preference
        let resolver = TileImageResolver()
        if let storedSet = UserDefaults.standard.string(forKey: AppSettingsKey.imageSet),
           let setID = ImageSetID(rawValue: storedSet) {
            resolver.activeSet = setID
        }
        self._imageResolver = State(initialValue: resolver)

        // Configure audio session at launch so speech plays regardless of the
        // ringer/silent switch. .playback bypasses the mute switch; .spokenAudio
        // mode ducks other audio and resumes it after each utterance.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    @State private var importCoordinator = ImportCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sentenceEngine)
                .environment(navigationCoordinator)
                .environment(scriptRunner)
                .environment(scriptRecorder)
                .environment(imageResolver)
                .onAppear {
                    sentenceEngine.configure(modelContext: modelContainer.mainContext)
                    scriptRunner.configure(
                        engine: sentenceEngine,
                        coordinator: navigationCoordinator,
                        modelContext: modelContainer.mainContext
                    )
                    scriptRecorder.configure(engine: sentenceEngine, runner: scriptRunner, coordinator: navigationCoordinator)
                }
                .environment(importCoordinator)
                .onOpenURL { url in
                    guard url.pathExtension == BlasterSceneFormat.fileExtension else { return }
                    importCoordinator.pendingURL = url
                }
        }
        .modelContainer(modelContainer)
    }
}
