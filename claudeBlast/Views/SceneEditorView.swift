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
    @AppStorage("openai_api_key") private var storedAPIKey: String = ""
    private var resolvedAPIKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? storedAPIKey
    }

    @State private var isAddingPage = false
    /// Identifier of a freshly-created page to navigate into. Stored as the
    /// page key string now that pages are inline structs rather than
    /// SwiftData entities.
    @State private var navigateToNewPageKey: String? = nil
    @State private var pickerKeysForNewPage: Set<String> = []
    @State private var sceneToExport: BlasterSceneFile?

    var body: some View {
        List {
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
                    exportScene()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sceneToExport) { file in
            ActivityView(items: [file.temporaryFileURL()])
        }
        .sheet(isPresented: $isAddingPage) {
            PageGeneratorSheet(scene: scene, allTiles: allTiles, apiKey: resolvedAPIKey) { pageKey, preSelectedKeys in
                pickerKeysForNewPage = preSelectedKeys
                navigateToNewPageKey = pageKey
            }
        }
        .navigationDestination(item: $navigateToNewPageKey) { pageKey in
            PageEditorView(scene: scene, pageKey: pageKey, autoOpenPickerWithKeys: pickerKeysForNewPage)
        }
    }

    private func exportScene() {
        let defaultKeys = Set(allTiles.filter { imageResolver.hasImage(for: $0.bundleImage) }.map(\.key))
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
        for index in offsets.sorted().reversed() {
            pages.remove(at: index)
        }
        scene.pages = pages
        if !scene.pages.contains(where: { $0.key == scene.homePageKey }) {
            scene.homePageKey = scene.pages.first?.key ?? ""
        }
        try? modelContext.save()
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

    var body: some View {
        NavigationStack {
            if let preview {
                PagePreviewView(
                    preview: preview,
                    pageName: pageName,
                    allTiles: allTiles,
                    onAccept: { buildAndAccept(preview, editMode: false) },
                    onEdit:   { buildAndAccept(preview, editMode: true) },
                    onRetry:  { self.preview = nil; runGeneration() },
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

                if let error = generationError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if apiKey.isEmpty {
                    Section {
                        Text("Add an OpenAI API key in Admin to enable AI generation.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
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
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pageGoal.trimmingCharacters(in: .whitespaces).isEmpty
                          || pageName.trimmingCharacters(in: .whitespaces).isEmpty
                          || apiKey.isEmpty
                          || isGenerating)

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
        Task {
            do {
                let result = try await service.generate(pageGoal: goal, pageName: name, allTiles: tiles)
                await MainActor.run { preview = result }
            } catch {
                await MainActor.run { generationError = error.localizedDescription }
            }
            await MainActor.run { isGenerating = false }
        }
    }

    private func buildAndAccept(_ result: GeneratedPageResult, editMode: Bool) {
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        let tileLookup = Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })

        if editMode {
            // Edit path: create empty page, pass pre-selected keys to caller.
            createEmptyPage(preSelectedKeys: result.primaryTileKeys)
        } else {
            // Accept path: append the AI-generated page (and any sub-pages)
            // to the scene's inline pages array.
            var pages = scene.pages
            let primaryTiles: [TileEntry] = result.primaryPage.tiles.compactMap { gen in
                guard tileLookup[gen.key] != nil else { return nil }
                return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
            }
            pages.append(PageSpec(key: key, tiles: primaryTiles))
            for genSub in result.subPages {
                let subTiles: [TileEntry] = genSub.tiles.compactMap { gen in
                    guard tileLookup[gen.key] != nil else { return nil }
                    return TileEntry(key: gen.key, link: gen.link, isAudible: gen.isAudible)
                }
                pages.append(PageSpec(key: genSub.key, tiles: subTiles))
            }
            scene.pages = pages
            if scene.homePageKey.isEmpty { scene.homePageKey = key }
            onCreate(key, [])
        }
        dismiss()
    }

    private func createEmptyPage(preSelectedKeys: Set<String>) {
        let key = normalizedPageKey(pageName)
        guard !key.isEmpty else { return }
        var pages = scene.pages
        pages.append(PageSpec(key: key, tiles: []))
        scene.pages = pages
        if scene.homePageKey.isEmpty { scene.homePageKey = key }
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
                            GeneratedTileCell(tile: tile, link: genTile.link)
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
                Button("Edit") { onEdit() }
                    .buttonStyle(.bordered)
                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// Lightweight tile cell for AI preview grids (no SwiftData dependency).
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
