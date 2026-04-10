// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Query(sort: \SentenceCache.hitCount, order: .reverse) var cacheEntries: [SentenceCache]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Query(
        filter: #Predicate<SentenceCache> { entry in
            entry.hitCount >= 3 || entry.isPinned
        },
        sort: \SentenceCache.hitCount, order: .reverse
    ) private var promotedCandidates: [SentenceCache]

    // Cache hit/miss metrics from MetricEvent log
    @Query(sort: \MetricEvent.timestamp) private var allMetricEvents: [MetricEvent]

    private var cacheHitCount: Int {
        allMetricEvents.count { $0.subjectType == "cache" && $0.eventType == .hit }
    }
    private var cacheMissCount: Int {
        allMetricEvents.count { $0.subjectType == "sentence" && $0.eventType == .used }
    }
    @Environment(\.modelContext) private var modelContext
    @Environment(SentenceEngine.self) private var sentenceEngine

    @AppStorage(AppSettingsKey.openaiApiKey) private var apiKey: String = ""
    @AppStorage(AppSettingsKey.providerChoice) private var providerChoice: String = "openai"
    @AppStorage(AppSettingsKey.audioEnabled) private var audioEnabled: Bool = true
    @AppStorage(AppSettingsKey.tileSpeechEnabled) private var tileSpeechEnabled: Bool = false
    @AppStorage(AppSettingsKey.speechVoiceIdentifier) private var voiceIdentifier: String = ""
    @AppStorage(AppSettingsKey.tileMinSize) private var tileMinSize: Double = 72
    @AppStorage(AppSettingsKey.imageSet) private var imageSetRaw: String = ImageSetID.arasaac.rawValue
    @Environment(TileImageResolver.self) private var imageResolver

    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @AppStorage(AppSettingsKey.icloudEnabled) private var icloudEnabled: Bool = false
    @AppStorage(AppSettingsKey.devShowNav) private var devShowNav: Bool = false
    @State private var showResetConfirmation = false
    @State private var isResetting = false
    #endif

    @State private var navigateToNewScene: BlasterScene?
    @State private var isCreatingScene = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importWarning: String?
    @State private var sceneToExport: BlasterSceneFile?

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
                            // Apple Intelligence hidden — on-device safety guardrails
                            // block innocuous AAC content (see PRD discussion log).
                            // Comparison infrastructure retained for future provider A/B.
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
                    Toggle("Audio", isOn: $audioEnabled)
                    Toggle("Tile Speech Preview", isOn: $tileSpeechEnabled)
                    Stepper(
                        "Tile Size: \(Int(tileMinSize))pt",
                        value: $tileMinSize,
                        in: 56...140,
                        step: 4
                    )

                    Picker("Image Set", selection: $imageSetRaw) {
                        ForEach(ImageSetID.allCases) { setID in
                            VStack(alignment: .leading) {
                                Text(setID.displayName)
                            }
                            .tag(setID.rawValue)
                        }
                    }
                }
                .onChange(of: imageSetRaw) {
                    if let setID = ImageSetID(rawValue: imageSetRaw) {
                        imageResolver.activeSet = setID
                    }
                }
                .onChange(of: providerChoice) { applyProvider() }
                .onChange(of: apiKey) { applyProvider() }
                .onChange(of: audioEnabled) { sentenceEngine.audioEnabled = audioEnabled }
                .onAppear {
                    sentenceEngine.audioEnabled = audioEnabled
                    sentenceEngine.voiceIdentifier = voiceIdentifier
                }

                Section {
                    VoicePickerSection(voiceIdentifier: $voiceIdentifier)
                } header: {
                    VoiceSectionHeader()
                }
                .onChange(of: voiceIdentifier) { sentenceEngine.voiceIdentifier = voiceIdentifier }

                #if DEBUG
                Section("Storage") {
                    Toggle("iCloud Sync", isOn: $icloudEnabled)
                    if icloudEnabled {
                        Text("iCloud sync takes effect on next launch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !scene.isDefault {
                                Button(role: .destructive) {
                                    deleteScene(scene)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button {
                                exportScene(scene)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }

                Section {
                    Button {
                        isCreatingScene = true
                    } label: {
                        Label("New Scene", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Scene", systemImage: "square.and.arrow.down")
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

                Section {
                    cacheStatsView
                } header: {
                    Text("Cache Performance")
                }

                Section {
                    if promotedCandidates.isEmpty {
                        Text("No promoted tiles yet — use the same tile combo 3+ times")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(promotedCandidates.prefix(5)) { entry in
                            promotedTileRow(entry)
                        }
                        if promotedCandidates.count > 5 {
                            NavigationLink {
                                PromotedTilesDetailView(entries: promotedCandidates, tileLookup: tileLookup)
                            } label: {
                                Text("View All (\(promotedCandidates.count))")
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Promoted Tiles (\(promotedCandidates.count))")
                }

                Section {
                    NavigationLink {
                        CacheDetailView(entries: cacheEntries, onDelete: deleteCacheEntries, onFlush: flushAllCache)
                    } label: {
                        Text("View \(cacheEntries.count) entries")
                    }
                    .disabled(cacheEntries.isEmpty)
                } header: {
                    HStack {
                        Text("Sentence Cache (\(cacheEntries.count))")
                        Spacer()
                        if !cacheEntries.isEmpty {
                            Button("Flush All", role: .destructive) {
                                flushAllCache()
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
                #if DEBUG
                Section("Developer") {
                    Toggle("Show Nav Menu", isOn: $devShowNav)
                    if isResetting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Resetting…").foregroundStyle(.secondary)
                        }
                    } else {
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Factory Reset", systemImage: "exclamationmark.triangle")
                        }
                    }
                }
                .confirmationDialog("Factory Reset", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                    Button("Reset All Data", role: .destructive) { performFactoryReset() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Deletes all scenes, pages, tiles, and cache. Vocabulary reloads from the bundle.")
                }
                #endif
            }
            .navigationTitle("Admin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Request speech recognition permission now, while no sheet is open,
            // so the system dialog is never occluded by a presented sheet.
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.blasterScene, .json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importWarning != nil },
            set: { if !$0 { importWarning = nil } }
        )) {
            Button("OK") { importWarning = nil }
        } message: {
            Text(importWarning ?? "")
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
        }
    }

    // MARK: - Tile Lookup

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private func tileSelections(for entry: SentenceCache) -> [TileSelection] {
        entry.tileKeys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }

    private func promotedTileRow(_ entry: SentenceCache) -> some View {
        HStack(spacing: 10) {
            TileGridIcon(tiles: tileSelections(for: entry))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sentence)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(entry.hitCount) hits")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Cache Stats

    private var cacheStatsView: some View {
        let hits = cacheHitCount
        let misses = cacheMissCount
        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) * 100 : 0
        let missRate = total > 0 ? Double(misses) / Double(total) * 100 : 0

        return Group {
            HStack {
                StatBox(label: "Lookups", value: "\(total)", color: .primary)
                StatBox(label: "Hits", value: "\(hits)", color: .green)
                StatBox(label: "Misses", value: "\(misses)", color: .orange)
            }

            HStack {
                StatBox(label: "Hit Rate", value: String(format: "%.1f%%", hitRate), color: .green)
                StatBox(label: "Miss Rate", value: String(format: "%.1f%%", missRate), color: .orange)
                StatBox(label: "Entries", value: "\(cacheEntries.count)", color: .blue)
            }

            if total == 0 {
                Text("No lookups recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        try? modelContext.save()
    }

    private func deleteScene(_ scene: BlasterScene) {
        guard !scene.isDefault else { return }
        let wasActive = scene.isActive
        modelContext.delete(scene)
        if wasActive {
            if let defaultScene = scenes.first(where: { $0.isDefault }) {
                defaultScene.isActive = true
            }
        }
        try? modelContext.save()
    }

    private func deleteCacheEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cacheEntries[index])
        }
        try? modelContext.save()
    }

    private func flushAllCache() {
        for entry in cacheEntries {
            modelContext.delete(entry)
        }
        // Clear cache-related metric events so stats reset with the cache
        for event in allMetricEvents where
            (event.subjectType == "cache" && event.eventType == .hit) ||
            (event.subjectType == "sentence" && event.eventType == .used) {
            modelContext.delete(event)
        }
        try? modelContext.save()
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

    /// Set of tile keys from the default vocabulary (used to determine which tiles need exporting).
    private var defaultTileKeys: Set<String> {
        Set(allTiles.filter { imageResolver.hasImage(for: $0.bundleImage) }.map(\.key))
    }

    private func exportScene(_ scene: BlasterScene) {
        do {
            let data = try SceneExporter.exportJSON(scene, defaultTileKeys: defaultTileKeys)
            sceneToExport = BlasterSceneFile(
                data: data,
                filename: scene.name.sanitizedFilename + "." + BlasterSceneFormat.fileExtension
            )
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let importResult = try SceneImporter.importJSON(data, context: modelContext)
                navigateToNewScene = importResult.scene

                var warnings: [String] = []
                if !importResult.skippedKeys.isEmpty {
                    warnings.append("\(importResult.skippedKeys.count) tile(s) not found: \(importResult.skippedKeys.joined(separator: ", "))")
                }
                if importResult.newTileCount > 0 {
                    warnings.append("\(importResult.newTileCount) new tile(s) added to vocabulary")
                }
                if !importResult.oversizedImages.isEmpty {
                    warnings.append("\(importResult.oversizedImages.count) image(s) exceeded size limit")
                }
                if !warnings.isEmpty {
                    importWarning = warnings.joined(separator: "\n")
                }
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    #if DEBUG
    private func performFactoryReset() {
        isResetting = true
        sentenceEngine.clearSelection()
        do {
            // Relationship-safe deletion order:
            // BlasterScene.pages = nullify (doesn't cascade to PageModel)
            // PageModel.tiles = cascade (auto-deletes PageTileModel)
            try modelContext.delete(model: MetricEvent.self)
            try modelContext.delete(model: SentenceCache.self)
            try modelContext.delete(model: BlasterScene.self)
            try modelContext.delete(model: PageModel.self)   // cascades PageTileModel
            try modelContext.delete(model: TileModel.self)
            try modelContext.save()
        } catch {
            print("Factory reset failed: \(error)")
            isResetting = false
            return
        }
        UserDefaults.standard.set(0, forKey: AppSettingsKey.bootstrapVersion)
        _ = BootstrapLoader.loadDefaultVocabulary(context: modelContext)
        BootstrapLoader.markBootstrapComplete()
        isResetting = false
    }
    #endif
}

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
private struct VoicePickerSection: View {
    @Binding var voiceIdentifier: String
    @State private var previewSynthesizer = AVSpeechSynthesizer()

    private var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.sortOrder > $1.quality.sortOrder }
                return $0.name < $1.name
            }
    }

    private var hasHighQualityVoice: Bool {
        englishVoices.contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    var body: some View {
        Picker("Voice", selection: $voiceIdentifier) {
            Text("System Default").tag("")
            ForEach(englishVoices, id: \.identifier) { voice in
                Text(voice.name).tag(voice.identifier)
            }
        }
        .onChange(of: voiceIdentifier) { _, newValue in
            previewVoice(identifier: newValue)
        }

        if !hasHighQualityVoice {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enhanced and Premium voices sound much more natural.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Settings → Accessibility → Spoken Content → Voices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .font(.caption)
            }
            .padding(.vertical, 2)
        }
    }

    private func previewVoice(identifier: String) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: "Welcome to Blaster")
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        previewSynthesizer.speak(utterance)
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    var sortOrder: Int {
        switch self {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }
}

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
                    if scene.isImported {
                        Text("Imported")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(scene.pages.count) pages · \(scene.lastModified, style: .date)")
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
                TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
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

// MARK: - Promoted Tiles Detail

private struct PromotedTilesDetailView: View {
    let entries: [SentenceCache]
    let tileLookup: [String: TileModel]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    TileGridIcon(tiles: tileSelections(for: entry))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.sentence)
                            .font(.subheadline)
                        Text(entry.cacheKey)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Hits: \(entry.hitCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        entry.isPinned.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(entry.isPinned ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Promoted Tiles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tileSelections(for entry: SentenceCache) -> [TileSelection] {
        entry.tileKeys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }
}

// MARK: - Cache Detail

private struct CacheDetailView: View {
    let entries: [SentenceCache]
    let onDelete: (IndexSet) -> Void
    let onFlush: () -> Void

    var body: some View {
        List {
            ForEach(entries) { entry in
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
            .onDelete(perform: onDelete)
        }
        .navigationTitle("Sentence Cache (\(entries.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Flush All", role: .destructive) {
                    onFlush()
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Cache Stats Box

private struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AdminView()
        .previewEnvironment()
}
