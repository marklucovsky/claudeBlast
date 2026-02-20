//
//  claudeBlastApp.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

@main
struct claudeBlastApp: App {
    private let modelContainer: ModelContainer
    @State private var sentenceEngine: SentenceEngine

    init() {
        let schema = Schema([
            TileModel.self,
            PageModel.self,
            PageTileModel.self,
            SentenceCache.self,
            BlasterScene.self,
            MetricEvent.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container
        _ = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)

        // Select provider: env var wins, then UserDefaults, then Mock
        let provider: any SentenceProvider
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            provider = OpenAISentenceProvider(apiKey: envKey)
        } else {
            let choice = UserDefaults.standard.string(forKey: "provider_choice") ?? "openai"
            let storedKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
            if choice == "openai", !storedKey.isEmpty {
                provider = OpenAISentenceProvider(apiKey: storedKey)
            } else {
                provider = MockSentenceProvider()
            }
        }
        let engine = SentenceEngine(provider: provider)
        let storedAudio = UserDefaults.standard.object(forKey: "audio_enabled")
        engine.audioEnabled = (storedAudio as? Bool) ?? true
        self._sentenceEngine = State(initialValue: engine)
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
