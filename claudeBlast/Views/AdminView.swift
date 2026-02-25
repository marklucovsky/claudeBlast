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

    @State private var navigateToNewScene: BlasterScene?
    @State private var isCreatingScene = false
    @State private var newSceneFirstPageGoal = ""

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
                        NavigationLink(destination: SceneEditorView(scene: scene)) {
                            SceneRow(scene: scene) {
                                activateScene(scene)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !scene.isActive {
                                Button("Activate") { activateScene(scene) }
                                    .tint(.green)
                            }
                        }
                    }
                    .onDelete(perform: deleteScenes)
                }

                Section {
                    Button {
                        isCreatingScene = true
                    } label: {
                        Label("New Scene", systemImage: "plus.circle")
                    }
                }
                .navigationDestination(item: $navigateToNewScene) { scene in
                    SceneEditorView(scene: scene, initialPageGoal: newSceneFirstPageGoal)
                }
                .sheet(isPresented: $isCreatingScene) {
                    NewSceneSheet { name, goal in
                        createNewScene(name: name, goal: goal)
                    }
                }

                Section("Session Notes") {
                    if sentenceEngine.sessionNotes.isEmpty {
                        Text("Long-press any tile to add a note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(sentenceEngine.sessionNotes)
                            .font(.caption.monospaced())
                        Button {
                            UIPasteboard.general.string = sentenceEngine.sessionNotes
                        } label: {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            sentenceEngine.sessionNotes = ""
                        } label: {
                            Label("Clear Notes", systemImage: "trash")
                        }
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

    private func createNewScene(name: String, goal: String) {
        let scene = BlasterScene(name: name.isEmpty ? "New Scene" : name)
        modelContext.insert(scene)
        if !goal.isEmpty {
            let home = PageModel(displayName: "home")
            modelContext.insert(home)
            scene.pages.append(home)
            scene.homePageKey = "home"
        }
        newSceneFirstPageGoal = goal
        navigateToNewScene = scene
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

// MARK: - New Scene Sheet

private struct NewSceneSheet: View {
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sceneName = ""
    @State private var goal = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Scene") {
                    TextField("Scene name", text: $sceneName)
                }
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        TextField("Suggest tiles for home page… (optional)", text: $goal)
                    }
                } header: {
                    Text("AI Tile Suggestion")
                } footer: {
                    Text("AI will pre-select tiles for this scene's home page.")
                }
            }
            .navigationTitle("New Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(sceneName, goal)
                        dismiss()
                    }
                }
            }
        }
    }
}
