// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import Speech

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Query(sort: \SentenceCache.lastUsed, order: .reverse) var cacheEntries: [SentenceCache]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(SentenceEngine.self) private var sentenceEngine

    @AppStorage("openai_api_key") private var apiKey: String = ""
    @AppStorage("provider_choice") private var providerChoice: String = "openai"
    @AppStorage("audio_enabled") private var audioEnabled: Bool = true
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = false

    @State private var navigateToNewScene: BlasterScene?
    @State private var isCreatingScene = false

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
                    SceneEditorView(scene: scene)
                }
                .sheet(isPresented: $isCreatingScene) {
                    SceneGeneratorSheet(allTiles: allTiles, apiKey: resolvedAPIKey) { scene in
                        navigateToNewScene = scene
                    } onManual: { name in
                        createBlankScene(name: name)
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
        .onAppear {
            // Request speech recognition permission now, while no sheet is open,
            // so the system dialog is never occluded by a presented sheet.
            SFSpeechRecognizer.requestAuthorization { _ in }
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

    private var resolvedAPIKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? apiKey
    }

    private func createBlankScene(name: String) {
        let scene = BlasterScene(name: name.isEmpty ? "New Scene" : name)
        modelContext.insert(scene)
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

// MARK: - Scene Generator Sheet

private struct SceneGeneratorSheet: View {
    let allTiles: [TileModel]
    let apiKey: String
    let onAccept: (BlasterScene) -> Void
    let onManual: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var sessionDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var preview: GeneratedScene? = nil
    @State private var manualName = ""
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            if let preview {
                ScenePreviewView(
                    preview: preview,
                    allTiles: allTiles,
                    onAccept: { buildAndAccept(preview) },
                    onRetry: { self.preview = nil; runGeneration() },
                    onCancel: { dismiss() }
                )
                .navigationTitle("Scene Preview")
                .navigationBarTitleDisplayMode(.inline)
            } else if showManual {
                manualForm
            } else {
                generatorForm
            }
        }
    }

    private var generatorForm: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $sessionDescription)
                        .frame(minHeight: 100)
                        .disabled(isGenerating)
                } header: {
                    Text("Describe the session")
                } footer: {
                    Text("e.g. \"Emotions and asking for help, food needs, and wanting to be alone\"")
                        .font(.caption)
                }

                if let error = generationError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if apiKey.isEmpty {
                    Section {
                        Text("Add an OpenAI API key in Admin to enable AI scene generation.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                runGeneration()
            } label: {
                Group {
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Generating…")
                        }
                    } else {
                        Label("Generate Scene", systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(sessionDescription.trimmingCharacters(in: .whitespaces).isEmpty
                      || apiKey.isEmpty
                      || isGenerating)
            .padding()
        }
        .navigationTitle("New Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Manual") { showManual = true }
                    .font(.subheadline)
            }
        }
    }

    private var manualForm: some View {
        Form {
            Section("Scene Name") {
                TextField("e.g. Morning routine", text: $manualName)
            }
        }
        .navigationTitle("New Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { showManual = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onManual(manualName)
                    dismiss()
                }
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func runGeneration() {
        let desc = sessionDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty, !apiKey.isEmpty else { return }
        isGenerating = true
        generationError = nil
        let service = SceneGeneratorService(apiKey: apiKey)
        let tiles = allTiles
        Task {
            do {
                let result = try await service.generate(description: desc, allTiles: tiles)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { generationError = error.localizedDescription }
            }
            await MainActor.run { isGenerating = false }
        }
    }

    private func buildAndAccept(_ generated: GeneratedScene) {
        let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
        if let scene = try? SceneBuilder.build(from: generated, tileLookup: tileLookup, context: modelContext) {
            onAccept(scene)
        }
        dismiss()
    }
}

// MARK: - Scene Preview View

private struct ScenePreviewView: View {
    let preview: GeneratedScene
    let allTiles: [TileModel]
    let onAccept: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var selectedPageIndex = 0

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 76))]

    private var currentPage: GeneratedPage {
        preview.pages[min(selectedPageIndex, preview.pages.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(preview.name)
                    .font(.headline)
                if !preview.description.isEmpty {
                    Text(preview.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal)

            // Page picker
            if preview.pages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(preview.pages.indices, id: \.self) { i in
                            let page = preview.pages[i]
                            let isHome = page.key == preview.homePageKey
                            Button { selectedPageIndex = i } label: {
                                HStack(spacing: 4) {
                                    Text(page.key)
                                    if isHome {
                                        Image(systemName: "house.fill")
                                            .font(.caption2)
                                    }
                                }
                                .font(.caption)
                                .fontWeight(selectedPageIndex == i ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selectedPageIndex == i
                                                   ? Color.accentColor
                                                   : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedPageIndex == i ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            } else {
                Spacer().frame(height: 12)
            }

            // Tile count
            Text("\(currentPage.tiles.count) tile\(currentPage.tiles.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            // Tile grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(currentPage.tiles, id: \.key) { genTile in
                        if let tile = tileLookup[genTile.key] {
                            GeneratedTileCell(tile: tile, link: genTile.link)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Divider()

            // Action bar
            HStack(spacing: 10) {
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Spacer()
                Button("Retry") { onRetry() }
                    .buttonStyle(.bordered)
                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// Lightweight tile cell for AI-generated preview grids (no SwiftData dependency).
private struct GeneratedTileCell: View {
    let tile: TileModel
    let link: String

    private var isNav: Bool { !link.isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if UIImage(named: tile.bundleImage) != nil {
                        Image(tile.bundleImage)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                            .background(wordClassColor(tile.wordClass).opacity(0.12))
                    } else {
                        wordClassColor(tile.wordClass)
                            .overlay {
                                Text(String(tile.displayName.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isNav ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

                if isNav {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, .blue)
                        .padding(3)
                }
            }

            Text(tile.displayName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}
