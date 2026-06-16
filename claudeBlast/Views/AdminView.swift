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
import AVFoundation

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Query(sort: \SentenceCache.hitCount, order: .reverse) var cacheEntries: [SentenceCache]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Query private var deviceProfiles: [DeviceProfile]
    @Query(sort: \ChildProfile.displayName) private var childProfiles: [ChildProfile]
    @Environment(ChildProfileResolver.self) private var profileResolver
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

    // API key lives in the Keychain (per-device, non-synced). @State seeds
    // from the vault when the view is constructed; writes flow through
    // OpenAIKeyVault.setKey in the .onChange handler below.
    @State private var apiKey: String = OpenAIKeyVault.currentKey() ?? ""
    @AppStorage(AppSettingsKey.providerChoice) private var providerChoice: String = "openai"
    @AppStorage(AppSettingsKey.audioEnabled) private var audioEnabled: Bool = true
    @AppStorage(AppSettingsKey.tileSpeechEnabled) private var tileSpeechEnabled: Bool = false
    @AppStorage(AppSettingsKey.speechVoiceIdentifier) private var voiceIdentifier: String = ""
    @AppStorage(AppSettingsKey.tileSizeStep) private var tileSizeStep: Int = 0
    @AppStorage(AppSettingsKey.imageSet) private var imageSetRaw: String = ImageSetID.arasaac.rawValue

    // Sentence tray timeline settings
    @AppStorage(AppSettingsKey.tileCapPerGroup) private var tileCapPerGroup: Int = 4
    @AppStorage(AppSettingsKey.idleDebounceMs) private var idleDebounceMs: Int = 2500
    @AppStorage(AppSettingsKey.trayBufferSize) private var trayBufferSize: Int = 100
    @AppStorage(AppSettingsKey.autoDoneMs) private var autoDoneMs: Int = 30000

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
    @State private var pendingImportURL: ImportSheetURL?
    @State private var sceneToExport: BlasterSceneFile?

    @State private var profileSheet: ProfileSheet?

    /// Drives both create and edit flows through a single `.sheet(item:)`.
    /// Two separate `.sheet` modifiers on the same view would race — the
    /// second one wins and dismisses the first on the next render — which
    /// is exactly the "sheet self-dismisses" bug we hit in therapist mode.
    private enum ProfileSheet: Identifiable {
        case create
        case edit(ChildProfile)

        var id: String {
            switch self {
            case .create:        return "create"
            case .edit(let p):   return "edit:\(p.id)"
            }
        }
    }

    /// Mirrors `device.role` for the picker. Lets us intercept a switch to
    /// `.patient` without committing it until the confirmation sheet wraps
    /// the loose ends (PIN setup + API key disposition).
    @State private var displayedRole: DeviceRole = .caregiver
    @State private var pendingPatientTransition = false
    @State private var pendingCaregiverTransition = false

    /// Whether the bundled Core-First content differs from what's installed.
    /// Recomputed onAppear and after an update is applied. Drives the
    /// per-scene "Update Available" affordance.
    @State private var bundleUpdateAvailable = false
    /// Set to the system scene the caregiver tapped "Update" on, to drive the
    /// confirmation dialog.
    @State private var sceneToUpdate: BlasterScene?

    private var envKeyOverride: Bool {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
    }

    private func tileDensityLabel(_ step: Int) -> String {
        switch step {
        case -3: return "Tightest"
        case -2: return "Tighter"
        case -1: return "Tight"
        case  0: return "Auto"
        case  1: return "Roomy"
        case  2: return "Roomier"
        case  3: return "Roomiest"
        default: return "Auto"
        }
    }

    var body: some View {
        // Tab segmentation:
        //   Now — parent-style quick tweaks (default landing)
        //   Profiles — child roster management
        //   Scenes — scene library + editor
        //   Device — device config (provider, API key, role, PIN, engine)
        //   Logs — diagnostics (cache, activity, promoted tiles)
        // Defaulting to Now means a parent landing in Admin to adjust
        // voice/volume/scene never has to scroll past therapist UI.
        TabView {
            nowTab
            profilesTab
            scenesTab
            deviceTab
            logsTab
        }
        .onAppear {
            // Global setup — request speech-recognition permission while
            // no sheet is open so the system dialog isn't occluded, and
            // check whether the bundled scenes have a pending update.
            SFSpeechRecognizer.requestAuthorization { _ in }
            bundleUpdateAvailable = BootstrapLoader.isBundleUpdateAvailable()
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

    private func applySystemSceneUpdate(duplicateFirst: Bool, remember: Bool) {
        // Persist the sticky preference state to match the toggle exactly:
        // - remember ON → store remembered=true + the duplicate value
        // - remember OFF → store remembered=false (toggling off explicitly
        //   forgets a previous choice, so the dialog reverts to safe defaults
        //   next time)
        let defaults = UserDefaults.standard
        defaults.set(remember, forKey: AppSettingsKey.forceRefreshDuplicateRemembered)
        if remember {
            defaults.set(duplicateFirst, forKey: AppSettingsKey.forceRefreshDuplicate)
        }

        // Snapshot the current Core-First into a duplicate before applying
        // the bundled overwrite, so the caregiver always has a recovery path.
        if duplicateFirst, let source = sceneToUpdate {
            _ = BlasterScene.duplicate(of: source, in: modelContext)
            try? modelContext.save()
        }

        sceneToUpdate = nil
        guard BootstrapLoader.updateSystemScene(context: modelContext) else { return }
        bundleUpdateAvailable = BootstrapLoader.isBundleUpdateAvailable()
        sentenceEngine.clearSelection()
    }

    private func duplicateScene(_ scene: BlasterScene) {
        _ = BlasterScene.duplicate(of: scene, in: modelContext)
        try? modelContext.save()
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

    // MARK: - Tabs

    private var nowTab: some View {
        NavigationStack {
            List {
                activeProfileSection
                activeSceneSection
                sessionNotesSection
            }
            .navigationTitle("Now")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Now", systemImage: "speaker.wave.2.fill") }
    }

    private var profilesTab: some View {
        NavigationStack {
            List {
                profilesSection
            }
            .navigationTitle("Profiles")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Profiles", systemImage: "person.2.fill") }
        .sheet(item: $profileSheet) { sheet in
            switch sheet {
            case .create:
                ChildProfileFormSheet(mode: .create) { profileSheet = nil }
            case .edit(let profile):
                ChildProfileFormSheet(mode: .edit(profile)) { profileSheet = nil }
            }
        }
    }

    private var scenesTab: some View {
        NavigationStack {
            List {
                scenesSection
                newSceneSection
                importSceneSection
            }
            .navigationTitle("Scenes")
            .navigationDestination(item: $navigateToNewScene) { scene in
                SceneEditorView(scene: scene)
            }
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Scenes", systemImage: "square.grid.2x2.fill") }
        .sheet(isPresented: $isCreatingScene) {
            SceneGeneratorSheet(allTiles: allTiles, apiKey: resolvedAPIKey) { scene in
                navigateToNewScene = scene
            } onManual: { name in
                createBlankScene(name: name)
            }
        }
        .sheet(item: $sceneToUpdate) { scene in
            UpdateConfirmationSheet(
                sceneName: scene.name,
                onConfirm: { duplicateFirst, remember in
                    applySystemSceneUpdate(duplicateFirst: duplicateFirst, remember: remember)
                }
            )
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.blasterScene, .json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $pendingImportURL) { item in
            SceneImportSheet(url: item.url) { pendingImportURL = nil }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var deviceTab: some View {
        NavigationStack {
            List {
                deviceSection
                sentenceProviderSection
                sentenceTraySection
                #if DEBUG
                storageSection
                #endif
            }
            .navigationTitle("Device")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Device", systemImage: "gear") }
        .sheet(isPresented: $pendingPatientTransition) {
            if let device = deviceProfiles.first {
                PatientTransitionSheet(
                    device: device,
                    suggestedName: suggestedPatientDeviceName(device: device),
                    onConfirm: {
                        pendingPatientTransition = false
                        displayedRole = device.role
                        // Tearing down the admin cover immediately would
                        // leave a stale dimming overlay. The short sleep
                        // lets the sheet animate out first.
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            dismiss()
                        }
                    },
                    onCancel: {
                        pendingPatientTransition = false
                        displayedRole = device.role
                    }
                )
            }
        }
        .sheet(isPresented: $pendingCaregiverTransition) {
            if let device = deviceProfiles.first {
                CaregiverTransitionSheet(
                    device: device,
                    onConfirm: {
                        pendingCaregiverTransition = false
                        displayedRole = device.role
                        // Resolver picks up the Sandbox profile that the
                        // sheet activated; refresh so subsequent reads see it.
                        profileResolver.refresh()
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            dismiss()
                        }
                    },
                    onCancel: {
                        pendingCaregiverTransition = false
                        displayedRole = device.role
                    }
                )
            }
        }
    }

    private var logsTab: some View {
        NavigationStack {
            List {
                cachePerformanceSection
                promotedTilesSection
                activityLogSection
                sentenceCacheSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Logs")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Logs", systemImage: "list.bullet.rectangle.fill") }
    }

    @ToolbarContentBuilder
    private var adminDoneToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
    }

    // MARK: - Section extractions

    @ViewBuilder
    private var sessionNotesSection: some View {
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
    }

    @ViewBuilder
    private var sentenceProviderSection: some View {
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
                "Tile Density: \(tileDensityLabel(tileSizeStep))",
                value: $tileSizeStep,
                in: -3...3,
                step: 1
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
        .onChange(of: apiKey) {
            OpenAIKeyVault.setKey(apiKey)
            applyProvider()
        }
        .onChange(of: audioEnabled) { sentenceEngine.audioEnabled = audioEnabled }
        .onAppear {
            sentenceEngine.audioEnabled = audioEnabled
            // Voice is per-child now — set in the Now tab's Active Profile
            // section. Leaving engine.voiceIdentifier empty lets the
            // resolver pick the active child's voice.
        }
    }

    @ViewBuilder
    private var sentenceTraySection: some View {
        Section {
            // Tiles per group is per-profile (active ChildProfile.maxSelectedTiles)
            // and lives on the Now tab. Don't expose a device-wide stepper
            // here — it'd shadow the per-profile value and confuse users
            // wondering which one wins.
            Stepper(
                "Pulse after: \(idleDebounceMs) ms",
                value: $idleDebounceMs,
                in: 500...5000,
                step: 250
            )
            Stepper(
                autoDoneMs == 0
                    ? "Auto-Done: off"
                    : "Auto-Done: \(autoDoneMs / 1000) s",
                value: $autoDoneMs,
                in: 0...120000,
                step: 5000
            )
            Stepper(
                "Tray buffer: \(trayBufferSize) groups",
                value: $trayBufferSize,
                in: 50...500,
                step: 50
            )
            Button(role: .destructive) {
                sentenceEngine.resetSession()
            } label: {
                Label("Reset Session", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Sentence Tray")
        } footer: {
            Text("Engine timings shared across profiles. Tiles-per-group is per-child — set it on the Now tab.")
                .font(.caption)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var storageSection: some View {
        Section("Storage") {
            Toggle("iCloud Sync", isOn: $icloudEnabled)
            if icloudEnabled {
                Text("iCloud sync takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

    @ViewBuilder
    private var scenesSection: some View {
        Section("Scenes") {
            ForEach(scenes) { scene in
                NavigationLink(destination: SceneEditorView(scene: scene)) {
                    SceneRow(
                        scene: scene,
                        updateAvailable: bundleUpdateAvailable,
                        onActivate: { activateScene(scene) },
                        onUpdate: { sceneToUpdate = scene }
                    )
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
                    Button {
                        duplicateScene(scene)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.indigo)
                }
            }
        }
    }

    @ViewBuilder
    private var newSceneSection: some View {
        Section {
            Button {
                isCreatingScene = true
            } label: {
                Label("New Scene", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var importSceneSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import Scene", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private var cachePerformanceSection: some View {
        Section {
            cacheStatsView
        } header: {
            Text("Cache Performance")
        }
    }

    @ViewBuilder
    private var promotedTilesSection: some View {
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
    }

    @ViewBuilder
    private var activityLogSection: some View {
        Section {
            NavigationLink {
                ActivityLogView()
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    Text("View Activity Log")
                }
            }
        } header: {
            Text("Activity Log")
        } footer: {
            Text("Finalized utterances from the sentence tray, grouped by day. Read-only review for therapists and partners.")
        }
    }

    @ViewBuilder
    private var sentenceCacheSection: some View {
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
    }

    #if DEBUG
    @ViewBuilder
    private var developerSection: some View {
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
    }
    #endif

    // MARK: - Active Profile section (parent-style quick tweaks)

    /// Top-of-Admin section that edits the *currently active* `ChildProfile`
    /// inline — voice, rate, volume, tile cap. These are the high-frequency
    /// parent-style tweaks; they live at the top of Admin so a parent
    /// landing here for "make her quieter" or "switch her voice" doesn't
    /// have to scroll past the therapist-style management UI.
    @ViewBuilder
    private var activeProfileSection: some View {
        if let active = profileResolver.active {
            Section {
                if childProfiles.count > 1 {
                    Picker("Profile", selection: Binding(
                        get: { active.id },
                        set: { newID in profileResolver.setActive(id: newID) }
                    )) {
                        ForEach(childProfiles) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                } else {
                    LabeledContent("Profile", value: active.displayName)
                }
                LabeledContent("Age",
                               value: "\(active.age) (grade \(active.ageGrade))")

                NavigationLink {
                    activeProfileVoicePicker(for: active)
                        .navigationTitle("Voice")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Voice") {
                        Text(voiceDisplayName(for: active.voiceIdentifier))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Speech rate")
                        Spacer()
                        Text(String(format: "%.2f", active.ttsRate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { active.ttsRate },
                        set: { active.ttsRate = $0; active.modifiedAt = .now }
                    ), in: 0.3...0.7)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text(String(format: "%.2f", active.ttsVolume))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { active.ttsVolume },
                        set: { active.ttsVolume = $0; active.modifiedAt = .now }
                    ), in: 0.0...1.0)
                }

                Stepper(value: Binding(
                    get: { active.maxSelectedTiles },
                    set: { active.maxSelectedTiles = $0; active.modifiedAt = .now }
                ), in: 2...8) {
                    HStack {
                        Text("Tiles per group")
                        Spacer()
                        Text("\(active.maxSelectedTiles)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Active Profile — \(active.displayName)")
            } footer: {
                Text("Voice, speed, and volume apply to this profile only. Switching the active profile applies that profile's preferences.")
            }
        } else {
            Section("Active Profile") {
                Text("No active profile.")
                    .foregroundStyle(.secondary)
                Text("Add one from the Child Profiles section below, or tap an existing profile to make it active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activeProfileVoicePicker(for profile: ChildProfile) -> some View {
        Form {
            VoicePickerSection(voiceIdentifier: Binding(
                get: { profile.voiceIdentifier },
                set: { profile.voiceIdentifier = $0; profile.modifiedAt = .now }
            ))
        }
    }

    private func voiceDisplayName(for identifier: String) -> String {
        if identifier.isEmpty { return "System Default" }
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice.name
        }
        return "Custom"
    }

    // MARK: - Active Scene section (picker only — no editor)

    /// Lets the user switch among installed scenes without exposing the
    /// editor surface. Therapist-style scene management stays in the
    /// "Scenes" section below; this is the parent-style "today is bedtime
    /// → switch to the Bedtime scene" path.
    @ViewBuilder
    private var activeSceneSection: some View {
        if !scenes.isEmpty {
            Section("Active Scene") {
                ForEach(scenes) { scene in
                    Button {
                        try? scene.activate(context: modelContext)
                    } label: {
                        HStack {
                            Text(scene.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if scene.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Device section (role, gating, PIN)

    @ViewBuilder
    private var deviceSection: some View {
        if let device = deviceProfiles.first {
            Section("Device") {
                LabeledContent("Name", value: device.displayName.isEmpty ? "—" : device.displayName)
                Picker("Role", selection: $displayedRole) {
                    ForEach(DeviceRole.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .onAppear { displayedRole = device.role }
                .onChange(of: displayedRole) { _, newRole in
                    switch (device.role, newRole) {
                    case (.patient, .patient), (.caregiver, .caregiver):
                        return // no-op
                    case (_, .patient):
                        // Caregiver → Patient: capture PIN + key disposition.
                        pendingPatientTransition = true
                    case (.patient, .caregiver):
                        // Patient → Caregiver: confirm gate retention + key.
                        pendingCaregiverTransition = true
                    default:
                        device.role = newRole
                    }
                }
                Toggle("Require Face ID for Admin",
                       isOn: Binding(
                        get: { device.requireFaceIDForAdmin },
                        set: { device.requireFaceIDForAdmin = $0 }
                       ))
                .disabled(device.role == .patient) // patient always on
                if device.adminPINHash != nil {
                    Button("Remove PIN", role: .destructive) {
                        device.adminPINHash = nil
                        device.adminPINSalt = nil
                        device.modifiedAt = .now
                    }
                    Text("Removing the PIN means Face ID is the only way in. You'll be prompted to set a new one on next Admin entry if Face ID fails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if device.requireFaceIDForAdmin {
                    Text("PIN not set — you'll be asked to create one next time Face ID fails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Profiles section (child roster)

    @ViewBuilder
    private var profilesSection: some View {
        Section {
            if childProfiles.isEmpty {
                Text("No child profiles yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(childProfiles) { profile in
                    profileRow(profile)
                }
            }
            Button {
                profileSheet = .create
            } label: {
                Label("Add Profile", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Child Profiles")
                Spacer()
                if let active = profileResolver.active {
                    Text("Active: \(active.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Pick the best string to seed `PatientTransitionSheet`'s device-name
    /// field with. Order of preference:
    /// 1. Active child profile's name → "{name}'s iPhone/iPad"
    /// 2. Any non-Legacy child profile (most-recently-created) — covers the
    ///    therapist-just-created-Aubrey-but-didn't-activate-her case.
    /// 3. The existing device.displayName (preserves the therapist's setup).
    /// 4. "Patient's iPhone/iPad" as a final fallback so the field is never
    ///    empty — an empty value collapses to the placeholder and looks like
    ///    the form is broken.
    private func suggestedPatientDeviceName(device: DeviceProfile) -> String {
        let model = UIDevice.current.model
        if let active = profileResolver.active,
           !active.displayName.isEmpty,
           active.displayName != "Legacy" {
            return "\(active.displayName)'s \(model)"
        }
        if let named = childProfiles
            .filter({ !$0.displayName.isEmpty && $0.displayName != "Legacy" })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first {
            return "\(named.displayName)'s \(model)"
        }
        if !device.displayName.isEmpty {
            return device.displayName
        }
        return "Patient's \(model)"
    }

    private func profileRow(_ profile: ChildProfile) -> some View {
        Button {
            profileResolver.setActive(id: profile.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: profile.isSystem
                      ? "gearshape.fill"
                      : "person.crop.circle.fill")
                    .foregroundStyle(profile.isSystem ? Color.gray : Color.accentColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.displayName).font(.body)
                        if profile.isSystem {
                            Text("Sandbox")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(profile.isSystem
                         ? "Default when no real patient is active"
                         : "Age \(profile.age) · grade \(profile.ageGrade) · max \(profile.maxSelectedTiles) tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if profile.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button {
                    profileSheet = .edit(profile)
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .buttonStyle(.borderless)
            }
            // Without contentShape(Rectangle()) the outer Button only
            // registers taps on the labeled content (icon + name + meta);
            // the Spacer between the text and the trailing pencil/check
            // fell through as un-hittable, making most of the row visually
            // dead. Forcing the hit area to the full HStack makes the
            // whole row tappable while the pencil's own .borderless Button
            // still takes priority for the edit affordance.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            // Sandbox can't be deleted — the resolver depends on its
            // existence. Real profiles can be deleted if not currently
            // active.
            if !profile.isActive && !profile.isSystem {
                Button(role: .destructive) {
                    modelContext.delete(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
        OpenAIKeyVault.currentKey() ?? ""
    }

    private func createBlankScene(name: String) {
        let scene = BlasterScene(name: name.isEmpty ? "New Scene" : name)
        modelContext.insert(scene)
        navigateToNewScene = scene
    }

    /// Bundled (system) vocabulary keys — the importer already has these, so they
    /// aren't packaged. Caregiver-added words (isSystem=false) ARE exported.
    /// Provenance-based and image-set-independent (unlike a bundled-art check,
    /// which would over-export on a sparse set).
    private var defaultTileKeys: Set<String> {
        Set(allTiles.filter(\.isSystem).map(\.key))
    }

    private func exportScene(_ scene: BlasterScene) {
        do {
            let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
            let data = try SceneExporter.exportJSON(scene,
                                                    defaultTileKeys: defaultTileKeys,
                                                    tileLookup: tileLookup)
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
            // Route through the same confirmation sheet as the file-open/iMessage
            // path so an in-app import is previewed (new words, images) before it
            // lands — rather than importing immediately.
            pendingImportURL = ImportSheetURL(url: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    #if DEBUG
    private func performFactoryReset() {
        isResetting = true
        sentenceEngine.clearSelection()
        do {
            // BlasterScene.pages is inline JSON-encoded data (no PageModel
            // relationship), so deleting BlasterScene is sufficient.
            try modelContext.delete(model: MetricEvent.self)
            try modelContext.delete(model: SentenceCache.self)
            try modelContext.delete(model: BlasterScene.self)
            try modelContext.delete(model: TileModel.self)
            try modelContext.delete(model: ChildProfile.self)
            try modelContext.delete(model: DeviceProfile.self)
            try modelContext.save()
        } catch {
            print("Factory reset failed: \(error)")
            isResetting = false
            return
        }
        // Clear all bootstrap-state flags so the next loadDefaultVocabulary
        // call writes fresh hash + installed flag via markBootstrapComplete.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettingsKey.bootstrapInstalled)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapContentHash)
        defaults.removeObject(forKey: AppSettingsKey.bootstrapVersion)
        _ = BootstrapLoader.loadDefaultVocabulary(context: modelContext)
        BootstrapLoader.markBootstrapComplete()
        // Match cold-launch behavior: re-seed the DeviceProfile placeholder
        // and the Sandbox ChildProfile so the user lands in the same state
        // as a fresh install. Without this, the Admin Profiles list comes
        // back empty after a reset and the resolver has nothing to fall
        // back to until OnboardingCommit creates a real profile.
        ProfileMigration.ensureProfilesAfterBootstrap(
            context: modelContext,
            seedLegacy: false
        )
        profileResolver.refresh()
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

struct SceneRow: View {
    let scene: BlasterScene
    var updateAvailable: Bool = false
    let onActivate: () -> Void
    var onUpdate: (() -> Void)? = nil

    private var isSystemScene: Bool { !scene.systemSceneKey.isEmpty }
    /// Show the update affordance only for the system scene, and only when a
    /// newer bundled version is available.
    private var showUpdateButton: Bool { isSystemScene && updateAvailable && onUpdate != nil }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scene.name)
                        .font(.headline)
                    if scene.isDefault {
                        badge("Default", .blue)
                    }
                    if isSystemScene {
                        badge("System", .purple)
                    }
                    if showUpdateButton {
                        // Inline next to the System badge — a tappable badge
                        // that drives the same confirmation dialog.
                        Button {
                            onUpdate?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .imageScale(.small)
                                Text("Update")
                            }
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    if scene.isImported {
                        badge("Imported", .orange)
                    }
                }
                Text("\(scene.pages.count) pages · \(scene.lastModified, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSystemScene {
                    Text("Built-in scene — defined by the app. Updates ship with new versions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !scene.descriptionText.isEmpty {
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
                Button("Activate") { onActivate() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Update Confirmation Sheet

/// Confirms the caregiver's intent to overwrite the system Core-First scene
/// with the latest bundled version. Two safety affordances:
///
/// - "Save a copy first" toggle (default ON) creates a duplicate of the
///   current scene before applying the overwrite, preserving any caregiver
///   customizations as a recoverable peer scene.
/// - "Remember this choice" persists the toggle's value via UserDefaults so
///   future updates pre-select accordingly. The dialog is still shown every
///   time — caregivers shouldn't be conditioned to dismiss without reading.
struct UpdateConfirmationSheet: View {
    let sceneName: String
    /// Callback: (duplicateFirst, remember)
    let onConfirm: (Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var duplicateFirst: Bool
    @State private var rememberChoice: Bool

    private var hasRememberedChoice: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKey.forceRefreshDuplicateRemembered)
    }

    init(sceneName: String, onConfirm: @escaping (Bool, Bool) -> Void) {
        self.sceneName = sceneName
        self.onConfirm = onConfirm
        let defaults = UserDefaults.standard
        let remembered = defaults.bool(forKey: AppSettingsKey.forceRefreshDuplicateRemembered)
        let initialDuplicate: Bool
        if remembered {
            // .bool returns false for missing keys, so use .object check.
            initialDuplicate = defaults.object(forKey: AppSettingsKey.forceRefreshDuplicate) as? Bool ?? true
        } else {
            initialDuplicate = true   // safe default for first-time and unremembered cases
        }
        _duplicateFirst = State(initialValue: initialDuplicate)
        // Pre-check the Remember toggle when a previous choice is stored, so
        // the caregiver sees the persisted state. Unchecking it on confirm
        // clears the sticky preference (handled in applySystemSceneUpdate).
        _rememberChoice = State(initialValue: remembered)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This replaces the **\(sceneName)** layout with the latest built-in version.")
                        .font(.callout)
                    Text("If someone depends on the current layout, save a copy first — the update overwrites in place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle(isOn: $duplicateFirst) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save a copy of the current \(sceneName) first")
                            Text("Recommended")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Remember this choice", isOn: $rememberChoice)
                } footer: {
                    if hasRememberedChoice {
                        Text("Last choice was remembered. Change here and check Remember to update.")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("Update \(sceneName)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        onConfirm(duplicateFirst, rememberChoice)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
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
                    apiKey: apiKey,
                    onAccept: { scene in buildAndAccept(scene) },
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

struct ScenePreviewView: View {
    let allTiles: [TileModel]
    let apiKey: String
    /// Emits the (possibly refined) scene the author accepted.
    let onAccept: (GeneratedScene) -> Void
    let onCancel: () -> Void

    /// The scene currently shown — seeded from the initial preview and replaced
    /// in place by AI refinement.
    @State private var working: GeneratedScene
    @State private var selectedPageIndex = 0
    @State private var isRefining = false
    @State private var refineError: String? = nil
    @State private var showRefineSheet = false

    init(preview: GeneratedScene,
         allTiles: [TileModel],
         apiKey: String,
         onAccept: @escaping (GeneratedScene) -> Void,
         onCancel: @escaping () -> Void) {
        self.allTiles = allTiles
        self.apiKey = apiKey
        self.onAccept = onAccept
        self.onCancel = onCancel
        _working = State(initialValue: preview)
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 76))]

    private var currentPage: GeneratedPage {
        working.pages[min(selectedPageIndex, working.pages.count - 1)]
    }

    /// Distinct proposed-new word display names across the whole scene.
    private var newWords: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for page in working.pages {
            for tile in page.tiles where tile.isProposedNew {
                if let name = tile.displayName, seen.insert(tile.key).inserted {
                    names.append(name)
                }
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(working.name)
                    .font(.headline)
                if !working.description.isEmpty {
                    Text(working.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal)

            // New-word summary: tells the author what will be added to vocabulary.
            if !newWords.isEmpty {
                Label("Adds \(newWords.count) new word\(newWords.count == 1 ? "" : "s"): \(newWords.joined(separator: ", "))",
                      systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Page picker
            if working.pages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(working.pages.indices, id: \.self) { i in
                            let page = working.pages[i]
                            let isHome = page.key == working.homePageKey
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
                            GeneratedTileCell(key: tile.bundleImage, displayName: tile.displayName,
                                              wordClass: tile.wordClass, link: genTile.link)
                        } else if let name = genTile.displayName, let wc = genTile.wordClass {
                            GeneratedTileCell(key: genTile.key, displayName: name,
                                              wordClass: wc, link: genTile.link, isNew: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            if let refineError {
                Text(refineError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            Divider()

            // Action bar
            HStack(spacing: 10) {
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Spacer()
                Button {
                    showRefineSheet = true
                } label: {
                    if isRefining {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Refining…") }
                    } else {
                        Label("Refine", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefining || apiKey.isEmpty)
                Button("Accept") { onAccept(working) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefining)
            }
            .padding()
        }
        .sheet(isPresented: $showRefineSheet) {
            SceneRefineInputSheet { instruction in
                showRefineSheet = false
                runRefine(instruction)
            } onCancel: {
                showRefineSheet = false
            }
        }
    }

    private func runRefine(_ instruction: String) {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !apiKey.isEmpty else { return }
        isRefining = true
        refineError = nil
        let service = SceneRefinerService(apiKey: apiKey)
        let currentTopical = SceneNavigation.topicalTiles(of: working)
        let tiles = allTiles
        Task {
            do {
                let result = try await service.refine(instruction: text, currentTopical: currentTopical, allTiles: tiles)
                await MainActor.run {
                    working = result
                    selectedPageIndex = 0
                }
            } catch {
                await MainActor.run { refineError = error.localizedDescription }
            }
            await MainActor.run { isRefining = false }
        }
    }
}

// Small modal that collects a natural-language refinement instruction for a
// scene preview ("add a fish pond and a creek"). Shared by every preview.
struct SceneRefineInputSheet: View {
    let onRefine: (String) -> Void
    let onCancel: () -> Void

    @State private var instruction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe the change…", text: $instruction, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("e.g. \u{201C}add a fish pond and a creek\u{201D}, or \u{201C}remove the tractor\u{201D}. The familiar core board stays the same.")
                }
            }
            .navigationTitle("Refine Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Refine") { onRefine(instruction) }
                        .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// Lightweight tile cell for AI-generated preview grids (no SwiftData dependency).
// Renders existing tiles and proposed-new words alike; `isNew` adds a badge and
// the word renders as its letter placeholder (no art until generated/added).
private struct GeneratedTileCell: View {
    let key: String
    let displayName: String
    let wordClass: String
    let link: String
    var isNew: Bool = false

    private var isNav: Bool { !link.isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                TileImageView(key: key, wordClass: wordClass)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isNav ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .topLeading) {
                    if isNew {
                        Text("NEW")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.purple))
                            .padding(3)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

                if isNav {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, .blue)
                        .padding(3)
                }
            }

            Text(displayName)
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

// MARK: - Child profile form sheet

/// Compact create/edit form for a `ChildProfile`. Used by the Admin
/// Profiles section. Captures age in years and synthesizes
/// `ChildProfile.birthday` via the same helper as onboarding.
private struct ChildProfileFormSheet: View {
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
            profile.modifiedAt = .now
            profileResolver.refresh()
        }
        onDismiss()
    }
}

// MARK: - Patient transition sheet

/// Presented when an Admin user flips the device role to Patient. Captures
/// the handoff loose ends in one place: PIN (required), API key disposition,
/// device name. Without this, the therapist would have to set up the PIN on
/// the next Admin re-entry — which means the *next* person opening Admin
/// (the patient or their parent) sets it. Wrong owner.
private struct PatientTransitionSheet: View {
    let device: DeviceProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Query(filter: #Predicate<ChildProfile> { !$0.isSystem },
           sort: \ChildProfile.displayName) private var realPatients: [ChildProfile]

    @State private var deviceName: String
    @State private var selectedPatientID: String = ""
    @State private var pinInput: String = ""
    @State private var pinConfirm: String = ""
    @State private var pinStage: PINStage = .enter
    @State private var keyChoice: KeyChoice = .keep
    @State private var newAPIKey: String = ""
    @State private var step: Step = .patient

    /// Three-page step machine — the keypad on `.pin` is too tall for an
    /// iPad form-sheet to render alongside everything else, so we give it
    /// its own page rather than stacking the whole flow into one Form.
    private enum Step: Int, CaseIterable {
        case patient   // pick patient + device name
        case pin       // PIN entry + confirm
        case apiKey    // API key disposition
    }

    private enum PINStage {
        case enter
        case confirm
    }

    /// Seeded synchronously from `suggestedName` so the field shows real
    /// editable text on the first render. Setting `@State` from `.onAppear`
    /// causes a one-frame empty flash that reads as "this is placeholder
    /// text" — and stays that way if the suggestion happens to be empty.
    init(device: DeviceProfile,
         suggestedName: String,
         onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.device = device
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._deviceName = State(initialValue: suggestedName)
    }

    enum KeyChoice: String, CaseIterable, Identifiable {
        case keep
        case clear
        case replace
        var id: String { rawValue }
    }

    private var hasExistingKey: Bool {
        OpenAIKeyVault.currentKey() != nil
    }

    private var availableChoices: [KeyChoice] {
        hasExistingKey ? [.keep, .clear, .replace] : [.clear, .replace]
    }

    private func keyChoiceLabel(_ c: KeyChoice) -> String {
        switch c {
        case .keep:    return "Keep the key currently on this device"
        case .clear:   return "No key — use Mock responses"
        case .replace: return "Use a different key for the patient"
        }
    }

    /// True when the device already has a PIN we can preserve. Skipping
    /// the PIN setup step in that case is the difference between a clean
    /// caregiver → patient flip and an annoying forced re-entry.
    private var hasExistingPIN: Bool {
        device.adminPINHash != nil && device.adminPINSalt != nil
    }

    private var canCommit: Bool {
        guard !realPatients.isEmpty, !selectedPatientID.isEmpty else { return false }
        // PIN only needs to be valid+matching when we're actually setting
        // one. With an existing PIN the .pin step is skipped entirely.
        if !hasExistingPIN {
            guard PINAuth.isValidPINShape(pinInput), pinInput == pinConfirm else {
                return false
            }
        }
        if keyChoice == .replace {
            return !newAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgress
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                content
                Divider()
                stepNav
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Switch to Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                keyChoice = availableChoices.first ?? .clear
                if selectedPatientID.isEmpty {
                    if let activeReal = realPatients.first(where: { $0.isActive }) {
                        selectedPatientID = activeReal.id
                    } else if let first = realPatients.first {
                        selectedPatientID = first.id
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Step machinery

    private var stepProgress: some View {
        // Collapse the 3-step bar to a 2-step bar when the .pin step is
        // going to be skipped (existing PIN preserved).
        let total: Double = hasExistingPIN
            ? Double(Step.allCases.count - 2)
            : Double(Step.allCases.count - 1)
        let value: Double = {
            if hasExistingPIN && step == .apiKey { return 1 }
            return Double(step.rawValue)
        }()
        return ProgressView(value: value, total: max(total, 1))
            .progressViewStyle(.linear)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .patient: patientPage
        case .pin:     pinPage
        case .apiKey:  apiKeyPage
        }
    }

    private var stepNav: some View {
        HStack {
            if step != .patient {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step == .apiKey {
                Button("Switch", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            } else {
                Button("Continue") { goNext() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
        }
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        // Skip the PIN setup step when the device already has one — we'd
        // just be making the user re-enter a PIN we're going to keep.
        if next == .pin && hasExistingPIN {
            step = .apiKey
        } else {
            step = next
        }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        if prev == .pin && hasExistingPIN {
            // Step skipped on the way forward; skip it on the way back too.
            step = .patient
            return
        }
        step = prev
        if step == .pin {
            // Returning to the PIN page should let the user re-do entry
            // rather than dropping them in a partial confirm state.
            pinConfirm = ""
            pinStage = .enter
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .patient:
            return !realPatients.isEmpty
                && !selectedPatientID.isEmpty
                && !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
        case .pin:
            return PINAuth.isValidPINShape(pinInput) && pinInput == pinConfirm
        case .apiKey:
            return true
        }
    }

    // MARK: - Per-step pages

    @ViewBuilder
    private var patientPage: some View {
        Form {
            Section {
                if realPatients.isEmpty {
                    Label {
                        Text("No patient profiles yet. Open the Profiles tab and add one before switching modes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Picker("Patient", selection: $selectedPatientID) {
                        ForEach(realPatients) { p in
                            Text("\(p.displayName) · age \(p.age)").tag(p.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } header: {
                Text("Whose Device Is This?")
            } footer: {
                Text("Pick the child this device will belong to. Their profile drives the voice and AI prompts after the switch.")
            }

            Section {
                TextField("Patient's \(UIDevice.current.model)", text: $deviceName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Device Name")
            } footer: {
                Text("Shown when AirDropping scenes from this device.")
            }
        }
    }

    @ViewBuilder
    private var pinPage: some View {
        VStack(spacing: 16) {
            Text("Admin PIN")
                .font(.headline)
            Text(pinStage == .enter
                 ? "Enter a 4–6 digit PIN. Used to unlock Admin when Face ID isn't available."
                 : "Enter the same PIN again to confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if pinStage == .enter {
                NumericKeypad(pin: $pinInput, maxLength: 6) {
                    if PINAuth.isValidPINShape(pinInput) {
                        pinStage = .confirm
                    }
                }
                Button("Next") { pinStage = .confirm }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!PINAuth.isValidPINShape(pinInput))
            } else {
                NumericKeypad(pin: $pinConfirm,
                              maxLength: pinInput.count)
                if !pinConfirm.isEmpty && !pinInput.hasPrefix(pinConfirm) {
                    Text("Doesn't match — try again")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Restart PIN") {
                    pinInput = ""
                    pinConfirm = ""
                    pinStage = .enter
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var apiKeyPage: some View {
        Form {
            Section {
                Picker("API Key", selection: $keyChoice) {
                    ForEach(availableChoices) { c in
                        Text(keyChoiceLabel(c)).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if keyChoice == .replace {
                    SecureField("sk-…", text: $newAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text(keyFooter)
            }
        }
    }

    private var keyFooter: String {
        switch keyChoice {
        case .keep:
            return "The patient (or their family) will use the API key already on this device. Token usage bills to whoever owns that key."
        case .clear:
            return "Generation falls back to Mock. The patient can add a key later from Admin → Sentence Provider."
        case .replace:
            return "Stored in this device's Keychain. Never synced via iCloud."
        }
    }

    private func commit() {
        // PIN — only set a new one if the .pin step actually ran. When the
        // device already had a PIN we preserved it and skipped that step,
        // so the existing hash/salt stay in place.
        if !hasExistingPIN {
            let salt = PINAuth.newSalt()
            guard let hash = PINAuth.hash(pin: pinInput, salt: salt) else { return }
            device.adminPINSalt = salt
            device.adminPINHash = hash
        }

        // Device name (preserve existing if user cleared it)
        let trimmedName = deviceName.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            device.displayName = trimmedName
        }

        // Role + Face ID
        device.role = .patient
        device.requireFaceIDForAdmin = true
        device.modifiedAt = .now

        // Activate the selected real patient and deactivate everyone else
        // (including Sandbox). Without this, the engine would keep talking
        // through whichever profile was active before the switch.
        let all = (try? modelContext.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for p in all {
            if p.id == selectedPatientID {
                if !p.isActive { p.isActive = true }
                p.modifiedAt = now
            } else if p.isActive {
                p.isActive = false
                p.modifiedAt = now
            }
        }
        try? modelContext.save()
        profileResolver.refresh()

        // API key
        switch keyChoice {
        case .keep:
            break
        case .clear:
            OpenAIKeyVault.clearKey()
        case .replace:
            OpenAIKeyVault.setKey(newAPIKey)
        }

        onConfirm()
    }
}

// MARK: - Caregiver transition sheet

/// Presented when an Admin user flips the device role from Patient back to
/// Caregiver. Confirms current-PIN to prove they're the responsible adult
/// (not the child who knows the PIN), then activates the Sandbox profile.
/// "Keep admin protected" defaults ON — the therapist retains the PIN gate
/// even after handing the device back to caregiver mode unless they
/// explicitly turn it off. The PIN stays around so flipping back to Patient
/// later doesn't require re-setup.
private struct CaregiverTransitionSheet: View {
    let device: DeviceProfile
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var pinInput = ""
    @State private var pinError: String?
    @State private var keepGate = true
    @State private var keyChoice: KeyChoice = .keep
    @State private var newAPIKey: String = ""
    @State private var step: Step = .pin

    /// Two pages — PIN unlock (with keypad room) followed by gate +
    /// API key options. Matches the PatientTransitionSheet pattern so the
    /// keypad never has to share a single Form with other controls on
    /// iPad mini.
    private enum Step: Int, CaseIterable {
        case pin
        case options
    }

    enum KeyChoice: String, CaseIterable, Identifiable {
        case keep, clear, replace
        var id: String { rawValue }
    }

    private var hasExistingKey: Bool {
        OpenAIKeyVault.currentKey() != nil
    }

    private var availableChoices: [KeyChoice] {
        hasExistingKey ? [.keep, .clear, .replace] : [.clear, .replace]
    }

    private func keyChoiceLabel(_ c: KeyChoice) -> String {
        switch c {
        case .keep:    return "Keep the API key already on this device"
        case .clear:   return "Clear the API key (use Mock responses)"
        case .replace: return "Replace with a different key"
        }
    }

    private var canCommit: Bool {
        guard let salt = device.adminPINSalt,
              let hash = device.adminPINHash else {
            // No PIN was ever set — patient mode somehow without gate.
            // Allow commit and just clear any residual state.
            return true
        }
        guard PINAuth.isValidPINShape(pinInput) else { return false }
        return PINAuth.verify(pin: pinInput, hash: hash, salt: salt)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if device.adminPINHash != nil {
                    stepProgress
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }
                content
                Divider()
                stepNav
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Switch to Caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                keyChoice = availableChoices.first ?? .clear
                // Skip PIN page when there's no PIN to verify.
                if device.adminPINHash == nil { step = .options }
            }
        }
        .interactiveDismissDisabled()
    }

    private var stepProgress: some View {
        ProgressView(value: Double(step.rawValue),
                     total: Double(Step.allCases.count - 1))
            .progressViewStyle(.linear)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pin:     pinPage
        case .options: optionsPage
        }
    }

    private var stepNav: some View {
        HStack {
            if step != .pin && device.adminPINHash != nil {
                Button("Back") { step = .pin }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step == .options {
                Button("Switch", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            } else {
                Button("Continue") {
                    if canAdvanceFromPIN { step = .options }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvanceFromPIN)
            }
        }
    }

    private var canAdvanceFromPIN: Bool {
        guard let salt = device.adminPINSalt,
              let hash = device.adminPINHash else { return true }
        return PINAuth.isValidPINShape(pinInput)
            && PINAuth.verify(pin: pinInput, hash: hash, salt: salt)
    }

    @ViewBuilder
    private var pinPage: some View {
        VStack(spacing: 16) {
            Text("Confirm Current PIN")
                .font(.headline)
            Text("Re-entering the PIN prevents anyone with grid access — including the child — from quietly returning the device to caregiver mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            NumericKeypad(pin: $pinInput, maxLength: 6,
                          dotStyle: .typedOnly)
            if let pinError {
                Text(pinError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var optionsPage: some View {
        Form {
            Section {
                Text("This swaps the active patient profile for the Sandbox profile and removes the patient handoff. Nothing is deleted — you can return to Patient mode anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Return to Caregiver Mode")
            }

            Section {
                Toggle("Keep admin protected", isOn: $keepGate)
            } header: {
                Text("Admin Gate")
            } footer: {
                Text(keepGate
                     ? "Face ID + PIN gate stays on. Recommended — your tuning work stays private even while the patient isn't using the device."
                     : "Gate removed. Anyone can open Admin without authentication. The PIN is cleared.")
            }

            Section {
                Picker("API Key", selection: $keyChoice) {
                    ForEach(availableChoices) { c in
                        Text(keyChoiceLabel(c)).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if keyChoice == .replace {
                    SecureField("sk-…", text: $newAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("OpenAI API Key")
            }
        }
    }

    private func commit() {
        // Re-verify before any mutation. canCommit already guards but be
        // explicit so a malformed state never silently switches roles.
        if let salt = device.adminPINSalt,
           let hash = device.adminPINHash,
           !PINAuth.verify(pin: pinInput, hash: hash, salt: salt) {
            pinError = "Incorrect PIN."
            pinInput = ""
            return
        }

        // Activate Sandbox; deactivate any real active profile.
        let all = (try? modelContext.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for p in all {
            if p.isSystem {
                if !p.isActive { p.isActive = true; p.modifiedAt = now }
            } else if p.isActive {
                p.isActive = false
                p.modifiedAt = now
            }
        }

        // Device flip.
        device.role = .caregiver
        if !keepGate {
            device.requireFaceIDForAdmin = false
            device.adminPINHash = nil
            device.adminPINSalt = nil
        }
        device.modifiedAt = now

        // API key.
        switch keyChoice {
        case .keep:    break
        case .clear:   OpenAIKeyVault.clearKey()
        case .replace: OpenAIKeyVault.setKey(newAPIKey)
        }

        try? modelContext.save()
        onConfirm()
    }
}
