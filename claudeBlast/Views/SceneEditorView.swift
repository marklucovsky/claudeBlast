// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UIKit

struct SceneEditorView: View {
    @Bindable var scene: BlasterScene
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(TileImageResolver.self) private var imageResolver
    @Environment(SceneArtCoordinator.self) private var sceneArtCoordinator
    @Environment(\.scenePhase) private var scenePhase

    /// Per-scene art controller from the app-level coordinator, so a background
    /// run survives this editor being dismissed and re-entered.
    private var artController: SceneImageBatchController {
        sceneArtCoordinator.controller(for: scene.id)
    }
    private var resolvedAPIKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    @State private var isAddingPage = false
    @State private var isRefining = false
    @State private var isGeneratingArt = false
    @State private var showPreview = false
    @State private var showKeySheet = false
    @State private var pageToLink: PageLinkTarget? = nil

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    /// Caregiver words this scene introduced that still have no art.
    private var tilesNeedingArt: [TileModel] {
        SceneImageBatch.tilesNeedingArt(in: scene, tileLookup: tileLookup)
    }
    /// Identifier of a freshly-created page to navigate into. Stored as the
    /// page key string now that pages are inline structs rather than
    /// SwiftData entities.
    @State private var navigateToNewPageKey: String? = nil
    @State private var pickerKeysForNewPage: Set<String> = []
    @State private var sceneToExport: BlasterSceneFile?

    var body: some View {
        List {
            if !scene.creationSummary.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.tint)
                        Text(scene.creationSummary).font(.subheadline)
                        Spacer()
                        Button { scene.creationSummary = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if artController.isActive {
                Section {
                    Button {
                        isGeneratingArt = true
                    } label: {
                        HStack(spacing: 10) {
                            if artController.phase == .paused {
                                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                            } else {
                                ProgressView()
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artController.phase == .paused ? "Art paused" : "Creating new-word art…")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(artController.completed) of \(artController.total) done · tap to manage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("In progress")
                } footer: {
                    Text(artController.phase == .paused
                         ? "Paused. Tap to resume, continue in the background, or cancel."
                         : "Running in the background. Tap to view progress, pause, or cancel.")
                }
            } else if !tilesNeedingArt.isEmpty {
                if resolvedAPIKey.isEmpty {
                    Section {
                        Button {
                            showKeySheet = true
                        } label: {
                            Label("Add an AI Key to generate artwork for new words",
                                  systemImage: "key.fill")
                        }
                    } footer: {
                        Text("\(tilesNeedingArt.count) new word\(tilesNeedingArt.count == 1 ? "" : "s") still need a picture. Add your key to generate them with AI.")
                    }
                } else {
                    Section {
                        Button {
                            artController.start(tiles: tilesNeedingArt, apiKey: resolvedAPIKey,
                                                context: modelContext, resolver: imageResolver)
                            isGeneratingArt = true
                        } label: {
                            Label("Generate art for \(tilesNeedingArt.count) new word\(tilesNeedingArt.count == 1 ? "" : "s")",
                                  systemImage: "sparkles")
                        }
                    } footer: {
                        Text("These words were added by AI and don't have pictures yet.")
                    }
                }
            }

            Section("Scene Info") {
                LabeledContent("Name") {
                    TextField("Scene name", text: $scene.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Description") {
                    TextField("Optional description", text: $scene.descriptionText)
                        .multilineTextAlignment(.trailing)
                }
                if !scene.pages.isEmpty {
                    Picker("Home Page", selection: $scene.homePageKey) {
                        ForEach(scene.pages, id: \.key) { page in
                            Text(page.key).tag(page.key)
                        }
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { scene.isFocused }, set: { setProfile(focused: $0) })) {
                    Text("Focused board")
                }
                .disabled(scene.isDefault)
            } header: {
                Text("Board")
            } footer: {
                Text("Focused trims the board for 1:1 sessions: the topical tiles plus a short needs strip (hungry/thirsty, help, feelings) and the body & health page. Off uses the full familiar board (people, food, drinks, body & health).")
            }

            Section("Pages (\(scene.pages.count))") {
                ForEach(scene.pages, id: \.key) { page in
                    NavigationLink(destination: PageEditorView(scene: scene, pageKey: page.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(page.key)
                                    .font(.headline)
                                if scene.homePageKey == page.key {
                                    Text("HOME")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.blue.opacity(0.15)))
                                        .foregroundStyle(.blue)
                                }
                            }
                            Text("\(page.tiles.count) tile\(page.tiles.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete(perform: deletePages)

                Button {
                    isAddingPage = true
                } label: {
                    Label("Add Page", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(scene.name.isEmpty ? "New Scene" : scene.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPreview = true
                } label: {
                    Image(systemName: "eye")
                }
                .accessibilityLabel("Preview scene")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isRefining = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Refine with AI")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportScene()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
        }
        .fullScreenCover(isPresented: $showPreview) {
            ScenePreviewBoardView(scene: scene, allTiles: allTiles)
        }
        .sheet(isPresented: $showKeySheet) {
            APIKeyEntrySheet()
        }
        .sheet(isPresented: $isRefining) {
            SceneRefinementSheet(scene: scene, allTiles: allTiles, apiKey: resolvedAPIKey)
        }
        .sheet(isPresented: $isGeneratingArt) {
            SceneImageBatchSheet(controller: artController)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: artController.appBecameActive()
            case .background: artController.appMovedToBackground()
            default: break
            }
        }
        .onChange(of: isGeneratingArt) { _, shown in
            // Clear a finished run once its summary is dismissed so the banner
            // returns to its idle state.
            if !shown, artController.phase == .finished { artController.reset() }
        }
        .sheet(isPresented: $isAddingPage) {
            PageGeneratorSheet(scene: scene, allTiles: allTiles, apiKey: resolvedAPIKey) { pageKey, preSelectedKeys in
                if !preSelectedKeys.isEmpty {
                    // Edit path: dive into the new page with the picker pre-loaded.
                    pickerKeysForNewPage = preSelectedKeys
                    navigateToNewPageKey = pageKey
                } else if scene.pages.contains(where: { $0.key != pageKey }) {
                    // Finalized page with somewhere to link → offer the link step,
                    // then return to the scene editor (page is in the Pages list).
                    pageToLink = PageLinkTarget(pageKey: pageKey)
                }
                // else: finalized page, nothing to link → stay in the scene editor.
            }
        }
        .navigationDestination(item: $navigateToNewPageKey) { pageKey in
            PageEditorView(scene: scene, pageKey: pageKey, autoOpenPickerWithKeys: pickerKeysForNewPage)
        }
        .sheet(item: $pageToLink) { target in
            PageLinkPlacementSheet(scene: scene, target: target, allTiles: allTiles)
        }
    }

    private func exportScene() {
        // Bundled (system) keys aren't packaged; caregiver words are. Provenance-
        // based so it's independent of the active image set.
        let defaultKeys = Set(allTiles.filter(\.isSystem).map(\.key))
        let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
        guard let data = try? SceneExporter.exportJSON(scene,
                                                       defaultTileKeys: defaultKeys,
                                                       tileLookup: tileLookup) else { return }
        sceneToExport = BlasterSceneFile(
            data: data,
            filename: scene.name.sanitizedFilename + "." + BlasterSceneFormat.fileExtension
        )
    }

    private func deletePages(at offsets: IndexSet) {
        var pages = scene.pages
        let deletedKeys = Set(offsets.map { pages[$0].key })
        for index in offsets.sorted().reversed() {
            pages.remove(at: index)
        }
        // Clean up links to the deleted page(s) so nothing opens an empty page:
        // silent nav tiles (incl. the page_link tile) are removed; audible tiles
        // that also linked there keep the word but drop the dead link.
        if !deletedKeys.isEmpty {
            for i in pages.indices {
                pages[i].tiles = pages[i].tiles.compactMap { entry in
                    guard deletedKeys.contains(entry.link) else { return entry }
                    return entry.isAudible
                        ? TileEntry(key: entry.key, link: "", isAudible: true)
                        : nil
                }
            }
        }
        scene.pages = pages
        if !scene.pages.contains(where: { $0.key == scene.homePageKey }) {
            scene.homePageKey = scene.pages.first?.key ?? ""
        }
        // Drop the now-orphaned page_link tiles for the deleted pages from vocab.
        for key in deletedKeys {
            let linkKey = PageLink.key(forPage: key)
            if let tile = allTiles.first(where: { $0.key == linkKey }) {
                modelContext.delete(tile)
            }
        }
        try? modelContext.save()
    }

    /// Re-scaffold the scene at the chosen board profile. Pure local transform:
    /// the topical layer is preserved and the core board is rebuilt full or lean.
    private func setProfile(focused: Bool) {
        let lookup = tileLookup
        let topical = SceneNavigation.topicalKeys(of: scene).map { key -> GeneratedTile in
            let tile = lookup[key]
            let isCaregiverWord = (tile?.isSystem == false)
            return GeneratedTile(key: key, isAudible: true, link: "",
                                 displayName: tile?.value,
                                 wordClass: isCaregiverWord ? tile?.wordClass : nil)
        }
        let base = GeneratedScene(
            name: scene.name,
            description: scene.descriptionText,
            homePageKey: scene.homePageKey,
            pages: [GeneratedPage(key: scene.homePageKey, tiles: topical)]
        )
        let scaffolded = SceneNavigation.scaffold(base, allTiles: allTiles,
                                                  validKeys: Set(allTiles.map(\.key)),
                                                  profile: focused ? .focused : .full)
        do {
            try SceneBuilder.update(scene, from: scaffolded, tileLookup: lookup, context: modelContext)
            scene.isFocused = focused
            try? modelContext.save()
        } catch {
            // Leave the scene unchanged on failure.
        }
    }
}

// MARK: - Page Generator Sheet

private struct PageGeneratorSheet: View {
    let scene: BlasterScene
    let allTiles: [TileModel]
    let apiKey: String
    /// Callback: (newly created page key, pre-selected keys for Edit path —
    /// empty for Accept path).
    let onCreate: (String, Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var pageName = ""
    @State private var pageGoal = ""
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var preview: GeneratedPageResult? = nil
    /// Set while previewing an unedited cached page sample; drives the cached
    /// accept (import) path and shows bundled art. Cleared on Retry (→ live AI).
    @State private var cachedPageSample: PageSample? = nil
    @State private var cachedPageImages: [String: Data] = [:]

    var body: some View {
        NavigationStack {
            if let preview {
                PagePreviewView(
                    preview: preview,
                    pageName: pageName,
                    allTiles: allTiles,
                    previewImages: cachedPageImages,
                    allowEdit: cachedPageSample == nil,
                    onAccept: { buildAndAccept(preview, editMode: false) },
                    onEdit:   { buildAndAccept(preview, editMode: true) },
                    onRetry:  { cachedPageSample = nil; self.preview = nil; runGeneration() },
                    onCancel: { dismiss() }
                )
                .navigationTitle("Page Preview")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                generatorForm
            }
        }
    }

    private var generatorForm: some View {
        VStack(spacing: 0) {
            Form {
                Section("Page Name") {
                    TextField("e.g. emotions", text: $pageName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(isGenerating)
                }

                Section {
                    TextField("e.g. feelings and emotions for a 6-year-old", text: $pageGoal)
                        .disabled(isGenerating)
                } header: {
                    Label("AI Goal", systemImage: "sparkles")
                } footer: {
                    Text("Describe what this page should help communicate.")
                }

                if !PageSampleCatalog.all.isEmpty {
                    Section {
                        ForEach(PageSampleCatalog.all) { sample in
                            Button {
                                pageName = sample.title
                                pageGoal = sample.goal
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.grid.2x2.fill")
                                            .font(.caption).foregroundStyle(.tint)
                                        Text(sample.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("Ready-made")
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                            .foregroundStyle(.tint)
                                    }
                                    Text(sample.blurb)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .disabled(isGenerating)
                        }
                    } header: {
                        Text("Start from an example")
                    } footer: {
                        Text("Loads a ready-made page instantly. Edit the goal to generate a fresh one with AI.")
                            .font(.caption)
                    }
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
                        Text("Add an OpenAI API key in Admin to generate a custom page. The ready-made examples above work without a key.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    if let sample = PageSampleCatalog.matching(pageGoal) {
                        loadCachedPage(sample)
                    } else {
                        runGeneration()
                    }
                } label: {
                    Group {
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Generating…")
                            }
                        } else {
                            let isCached = PageSampleCatalog.matching(pageGoal) != nil
                            Label(isCached ? "Load Example Page" : "Generate",
                                  systemImage: isCached ? "square.grid.2x2.fill" : "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pageGoal.trimmingCharacters(in: .whitespaces).isEmpty
                          || pageName.trimmingCharacters(in: .whitespaces).isEmpty
                          || isGenerating
                          || (apiKey.isEmpty && PageSampleCatalog.matching(pageGoal) == nil))

                Button("Skip AI — Create Empty Page") {
                    createEmptyPage(preSelectedKeys: [])
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(pageName.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
            }
            .padding()
        }
        .navigationTitle("New Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func runGeneration() {
        let goal = pageGoal.trimmingCharacters(in: .whitespaces)
        let name = normalizedPageKey(pageName)
        guard !goal.isEmpty, !name.isEmpty, !apiKey.isEmpty else { return }
        isGenerating = true
        generationError = nil
        let service = PageGeneratorService(apiKey: apiKey)
        let tiles = allTiles
        let pages = scene.pages
        let homeKey = scene.homePageKey
        Task {
            do {
                let result = try await service.generate(pageGoal: goal, pageName: name, allTiles: tiles,
                                                        scenePages: pages, homePageKey: homeKey)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { generationError = error.localizedDescription }
            }
            await MainActor.run { isGenerating = false }
        }
    }

    private func buildAndAccept(_ result: GeneratedPageResult, editMode: Bool) {
        // Cached sample accepted as-is → import the bundle (preserves bundled art).
        if let sample = cachedPageSample, !editMode {
            if let key = sample.importPage(into: scene, context: modelContext, allTiles: allTiles) {
                try? modelContext.save()
                onCreate(key, [])
            }
            dismiss()
            return
        }
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        var lookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

        // Materialize proposed-new words (both paths) so they're real tiles —
        // wired onto the page (accept) or pre-selectable in the picker (edit).
        for genPage in [result.primaryPage] + result.subPages {
            for gen in genPage.tiles where gen.isProposedNew {
                guard lookup[gen.key] == nil,
                      let displayName = gen.displayName,
                      let wordClass = gen.wordClass else { continue }
                let tile = TileModel(key: gen.key, value: displayName, wordClass: wordClass)
                tile.isSystem = false
                modelContext.insert(tile)
                lookup[gen.key] = tile
            }
        }

        if editMode {
            // Edit path: create empty page, pass pre-selected keys to caller.
            createEmptyPage(preSelectedKeys: result.primaryTileKeys)
        } else {
            // Accept path: append the AI-generated page (and any sub-pages)
            // to the scene's inline pages array.
            var pages = scene.pages
            let primaryTiles: [TileEntry] = result.primaryPage.tiles.compactMap { gen in
                guard lookup[gen.key] != nil else { return nil }
                return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
            }
            pages.append(PageSpec(key: key, tiles: primaryTiles))
            for genSub in result.subPages {
                let subTiles: [TileEntry] = genSub.tiles.compactMap { gen in
                    guard lookup[gen.key] != nil else { return nil }
                    return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
                }
                pages.append(PageSpec(key: genSub.key, tiles: subTiles))
            }
            scene.pages = pages
            if scene.homePageKey.isEmpty { scene.homePageKey = key }
            PageLink.mint(pageKey: key,
                          displayName: pageName.trimmingCharacters(in: .whitespacesAndNewlines),
                          context: modelContext, existing: lookup)
            onCreate(key, [])
        }
        try? modelContext.save()
        dismiss()
    }

    private func loadCachedPage(_ sample: PageSample) {
        guard let loaded = sample.loadPreview() else {
            generationError = "Couldn't load the example."
            return
        }
        cachedPageSample = sample
        cachedPageImages = loaded.images
        if pageName.trimmingCharacters(in: .whitespaces).isEmpty { pageName = sample.title }
        preview = loaded.result
    }

    private func createEmptyPage(preSelectedKeys: Set<String>) {
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        var pages = scene.pages
        pages.append(PageSpec(key: key, tiles: []))
        scene.pages = pages
        if scene.homePageKey.isEmpty { scene.homePageKey = key }
        PageLink.mint(pageKey: key,
                      displayName: pageName.trimmingCharacters(in: .whitespacesAndNewlines),
                      context: modelContext,
                      existing: Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) }))
        onCreate(key, preSelectedKeys)
        dismiss()
    }

    private func normalizedPageKey(_ name: String) -> String {
        name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Page Preview View

private struct PagePreviewView: View {
    let preview: GeneratedPageResult
    let pageName: String
    let allTiles: [TileModel]
    var previewImages: [String: Data] = [:]
    var allowEdit: Bool = true
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var selectedSection = 0  // 0 = primary, 1+ = sub-pages

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 76))]

    private var allSections: [GeneratedPage] {
        [preview.primaryPage] + preview.subPages
    }

    private var currentTiles: [GeneratedTile] {
        allSections[min(selectedSection, allSections.count - 1)].tiles
    }

    var body: some View {
        VStack(spacing: 0) {
            if allSections.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allSections.indices, id: \.self) { i in
                            Button { selectedSection = i } label: {
                                Text(i == 0 ? pageName : allSections[i].key)
                                    .font(.caption)
                                    .fontWeight(selectedSection == i ? .semibold : .regular)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(selectedSection == i
                                                       ? Color.accentColor
                                                       : Color.secondary.opacity(0.15))
                                    )
                                    .foregroundStyle(selectedSection == i ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            } else {
                Text(pageName)
                    .font(.headline)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }

            Text("\(currentTiles.count) tile\(currentTiles.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(currentTiles, id: \.key) { genTile in
                        if let tile = tileLookup[genTile.key] {
                            GeneratedTileCell(key: tile.bundleImage, displayName: tile.displayName,
                                              wordClass: tile.wordClass, link: genTile.link,
                                              imageData: previewImages[genTile.key])
                        } else if let name = genTile.displayName, let wc = genTile.wordClass {
                            GeneratedTileCell(key: genTile.key, displayName: name,
                                              wordClass: wc, link: genTile.link, isNew: true,
                                              imageData: previewImages[genTile.key])
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("Retry") { onRetry() }
                    .buttonStyle(.bordered)
                Spacer()
                if allowEdit {
                    Button("Edit") { onEdit() }
                        .buttonStyle(.bordered)
                }
                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// Lightweight tile cell for AI preview grids (no SwiftData dependency).
private struct GeneratedTileCell: View {
    let key: String
    let displayName: String
    let wordClass: String
    let link: String
    var isNew: Bool = false
    var imageData: Data? = nil

    private var isNav: Bool { !link.isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageData, let ui = UIImage(data: imageData) {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        TileImageView(key: key, wordClass: wordClass)
                    }
                }
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

// MARK: - Scene Refinement Sheet

/// Iteratively refine the active scene with a natural-language instruction
/// ("add a fish pond and a creek"). Refinement rewrites the scene's topical
/// layer and re-scaffolds the familiar core board around it (see
/// SceneRefinerService / SceneNavigation). The change is previewed before it is
/// applied in place.
private struct SceneRefinementSheet: View {
    let scene: BlasterScene
    let allTiles: [TileModel]
    let apiKey: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var instruction = ""
    @State private var isRefining = false
    @State private var errorMessage: String? = nil
    @State private var preview: GeneratedScene? = nil

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private var profile: SceneNavigation.Profile { scene.isFocused ? .focused : .full }

    var body: some View {
        NavigationStack {
            if let preview {
                ScenePreviewView(
                    preview: preview,
                    allTiles: allTiles,
                    apiKey: apiKey,
                    profile: profile,
                    onAccept: { scene in apply(scene) },
                    onCancel: { dismiss() }
                )
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Describe the change…", text: $instruction, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Refine \(scene.name.isEmpty ? "Scene" : scene.name)")
            } footer: {
                Text("e.g. \u{201C}add a fish pond and a creek\u{201D} — the activity tiles update; the familiar core board stays the same.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    runRefine()
                } label: {
                    HStack {
                        if isRefining { ProgressView().padding(.trailing, 4) }
                        Text(isRefining ? "Refining\u{2026}" : "Refine")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty || apiKey.isEmpty || isRefining)
            }
        }
        .navigationTitle("Refine Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func runRefine() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !apiKey.isEmpty else { return }
        isRefining = true
        errorMessage = nil
        let service = SceneRefinerService(apiKey: apiKey)
        let lookup = tileLookup
        let topical = SceneNavigation.topicalKeys(of: scene).map { key -> GeneratedTile in
            let tile = lookup[key]
            let isCaregiverWord = (tile?.isSystem == false)
            return GeneratedTile(key: key, isAudible: true, link: "",
                                 displayName: tile?.value,
                                 wordClass: isCaregiverWord ? tile?.wordClass : nil)
        }
        let tiles = allTiles
        Task {
            do {
                let result = try await service.refine(instruction: text, currentTopical: topical, allTiles: tiles, profile: profile)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isRefining = false }
        }
    }

    private func apply(_ generated: GeneratedScene) {
        do {
            try SceneBuilder.update(scene, from: generated, tileLookup: tileLookup, context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            preview = nil
        }
    }
}
