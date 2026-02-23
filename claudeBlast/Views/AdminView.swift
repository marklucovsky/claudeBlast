//
//  AdminView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Query(sort: \SentenceCache.lastUsed, order: .reverse) var cacheEntries: [SentenceCache]
    @Environment(\.modelContext) private var modelContext
    @Environment(SentenceEngine.self) private var sentenceEngine

    @AppStorage("openai_api_key") private var apiKey: String = ""
    @AppStorage("provider_choice") private var providerChoice: String = "openai"
    @AppStorage("audio_enabled") private var audioEnabled: Bool = true
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = false

    private var envKeyOverride: Bool {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sentence Provider") {
                    if envKeyOverride {
                        LabeledContent("Provider", value: "OpenAI (env override)")
                        LabeledContent("API Key") {
                            Text("Set via environment")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Picker("Provider", selection: $providerChoice) {
                            Text("OpenAI").tag("openai")
                            Text("Mock").tag("mock")
                        }

                        if providerChoice == "openai" {
                            SecureField("OpenAI API Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if apiKey.isEmpty {
                                Text("Enter your OpenAI API key to enable AI sentence generation.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    LabeledContent("Active Provider", value: sentenceEngine.provider.displayName)
                    if sentenceEngine.provider.supportsIntegratedAudio {
                        Toggle("Audio", isOn: $audioEnabled)
                    } else {
                        LabeledContent("Audio", value: "Not supported")
                    }
                    Toggle("Tile Speech Preview", isOn: $tileSpeechEnabled)
                }
                .onChange(of: providerChoice) { applyProvider() }
                .onChange(of: apiKey) { applyProvider() }
                .onChange(of: audioEnabled) { sentenceEngine.audioEnabled = audioEnabled }
                .onAppear { sentenceEngine.audioEnabled = audioEnabled }

                Section("Scenes") {
                    ForEach(scenes) { scene in
                        SceneRow(scene: scene) {
                            activateScene(scene)
                        }
                    }
                    .onDelete(perform: deleteScenes)
                }

                Section {
                    Button {
                        createSampleScene()
                    } label: {
                        Label("Create Sample Scene", systemImage: "plus.circle")
                    }
                }

                Section("Sentence Cache (\(cacheEntries.count))") {
                    if cacheEntries.isEmpty {
                        Text("No cached sentences")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cacheEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.cacheKey)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.sentence)
                                    .font(.subheadline)
                                Text("Hits: \(entry.hitCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .onDelete(perform: deleteCacheEntries)

                        Button(role: .destructive) {
                            flushAllCache()
                        } label: {
                            Label("Flush All Cache", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Admin")
        }
    }

    private func activateScene(_ scene: BlasterScene) {
        try? scene.activate(context: modelContext)
    }

    private func deleteScenes(at offsets: IndexSet) {
        for index in offsets {
            let scene = scenes[index]
            if scene.isDefault { continue }
            let wasActive = scene.isActive
            modelContext.delete(scene)
            if wasActive {
                // Restore default
                if let defaultScene = scenes.first(where: { $0.isDefault }) {
                    defaultScene.isActive = true
                }
            }
        }
    }

    private func deleteCacheEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cacheEntries[index])
        }
    }

    private func flushAllCache() {
        for entry in cacheEntries {
            modelContext.delete(entry)
        }
    }

    private func applyProvider() {
        guard !envKeyOverride else { return }
        let newProvider: any SentenceProvider
        if providerChoice == "openai", !apiKey.isEmpty {
            newProvider = OpenAISentenceProvider(apiKey: apiKey)
        } else {
            newProvider = MockSentenceProvider()
        }
        sentenceEngine.switchProvider(newProvider)
    }

    private func createSampleScene() {
        let tiles = [
            TileModel(key: "happy", wordClass: "describe"),
            TileModel(key: "sad", wordClass: "describe"),
            TileModel(key: "angry", wordClass: "describe"),
            TileModel(key: "afraid", wordClass: "describe"),
            TileModel(key: "tired", wordClass: "describe"),
            TileModel(key: "hungry", wordClass: "describe"),
            TileModel(key: "yes", wordClass: "social"),
            TileModel(key: "no", wordClass: "social"),
            TileModel(key: "help", wordClass: "actions"),
            TileModel(key: "stop", wordClass: "actions"),
            TileModel(key: "more", wordClass: "actions"),
            TileModel(key: "please", wordClass: "social"),
        ]

        for tile in tiles {
            modelContext.insert(tile)
        }

        let pageTiles = tiles.map { PageTileModel(tile: $0) }
        let tileOrder = pageTiles.map(\.id)
        let page = PageModel.make(
            displayName: "feelings_session",
            tiles: pageTiles,
            tileOrder: tileOrder
        )
        modelContext.insert(page)

        let scene = BlasterScene(
            name: "Feelings Session",
            descriptionText: "Focused emotions vocabulary for therapy",
            homePageKey: "feelings_session"
        )
        scene.pages = [page]
        modelContext.insert(scene)
    }
}

struct SceneRow: View {
    let scene: BlasterScene
    let onActivate: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scene.name)
                        .font(.headline)
                    if scene.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(scene.pages.count) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scene.descriptionText.isEmpty {
                    Text(scene.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if scene.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Activate") {
                    onActivate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
