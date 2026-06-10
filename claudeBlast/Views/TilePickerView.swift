// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePickerView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TilePickerView: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    var initialSelectedKeys: Set<String> = []
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @State private var selectedKeys: Set<String> = []
    @State private var searchText = ""
    @State private var selectedWordClass = "all"
    @State private var suggestionGoal = ""
    @State private var isSuggesting = false
    @State private var suggestionError: String? = nil
    @State private var showAddWord = false
    @Environment(\.isSearching) private var isSearching

    private var apiKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    private var existingKeys: Set<String> {
        Set(scene.pages.first { $0.key == pageKey }?.tiles.map(\.key) ?? [])
    }

    private var wordClasses: [String] {
        ["all"] + Set(allTiles.map(\.wordClass)).sorted()
    }

    private var filteredTiles: [TileModel] {
        allTiles.filter { tile in
            !existingKeys.contains(tile.key)
            && (selectedWordClass == "all" || tile.wordClass == selectedWordClass)
            && (searchText.isEmpty
                || tile.displayName.localizedCaseInsensitiveContains(searchText)
                || tile.key.localizedCaseInsensitiveContains(searchText))
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96))]

    var body: some View {
        NavigationStack {
            ScrollView {
                suggestionBar
                    .padding(.horizontal)
                    .padding(.top, 12)

                wordClassFilter
                    .padding(.vertical, 8)

                if filteredTiles.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredTiles) { tile in
                            pickerCell(tile)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .searchable(text: $searchText, prompt: "Search tiles")
            .sheet(isPresented: $showAddWord) {
                AddWordSheet(
                    initialWord: searchText,
                    existingTiles: allTiles,
                    defaultWordClass: addWordDefaultClass
                ) { tile in
                    placeTileOnPage(tile.key)
                    searchText = ""
                }
            }
            .onAppear {
                if !initialSelectedKeys.isEmpty {
                    selectedKeys = initialSelectedKeys.subtracting(existingKeys)
                }
            }
            .navigationTitle("Add Tiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // While search is active, hide these — the searchable's own Cancel
                // exits search mode cleanly. Showing two "cancel"-style buttons
                // at once creates confusion about which discards selections.
                if !isSearching {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(selectedKeys.isEmpty ? "Dismiss" : "Discard") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selectedKeys.count)") {
                            addSelectedTiles()
                            dismiss()
                        }
                        .disabled(selectedKeys.isEmpty)
                    }
                }
            }
        }
    }

    /// Word class to pre-select when adding a new word: the active filter if one
    /// is chosen, otherwise the first real class.
    private var addWordDefaultClass: String {
        if selectedWordClass != "all" { return selectedWordClass }
        return wordClasses.first { $0 != "all" } ?? "describe"
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            ContentUnavailableView("No tiles found", systemImage: "magnifyingglass")
        } else {
            // The grid hides tiles already on the page / filtered by class, so an
            // empty grid doesn't mean the word is new. Check the whole vocabulary
            // for an exact match and surface it rather than claiming it's new.
            let normalized = TileModel.normalizeKey(trimmed)
            let matches = allTiles.filter {
                $0.key == normalized || $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if matches.isEmpty {
                ContentUnavailableView {
                    Label("No match for “\(trimmed)”", systemImage: "magnifyingglass")
                } description: {
                    Text("Add it as a new word in your vocabulary.")
                } actions: {
                    Button {
                        showAddWord = true
                    } label: {
                        Label("Add “\(trimmed)” as a new word", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                existingWordView(trimmed, matches)
            }
        }
    }

    /// The searched word already exists. Show which classes it exists as (and
    /// whether already on this page), let the user add an off-page one directly,
    /// and offer to create a different-type homograph.
    @ViewBuilder
    private func existingWordView(_ trimmed: String, _ matches: [TileModel]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("“\(trimmed)” is already in your vocabulary")
                .font(.headline)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(matches) { tile in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(TileColorResolver.color(for: tile.wordClass))
                            .frame(width: 10, height: 10)
                        Text(tile.wordClass)
                        Spacer()
                        if existingKeys.contains(tile.key) {
                            Text("On this page")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Add to page") {
                                placeTileOnPage(tile.key)
                                searchText = ""
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal)

            Button {
                showAddWord = true
            } label: {
                Label("Add “\(trimmed)” as a different type", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: 440)
    }

    private func placeTileOnPage(_ key: String) {
        var pages = scene.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        guard !pages[idx].tiles.contains(where: { $0.key == key }) else { return }
        pages[idx].tiles.append(TileEntry(key: key, link: "", isAudible: true))
        scene.pages = pages
        try? modelContext.save()
    }

    private var wordClassFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wordClasses, id: \.self) { wc in
                    Button {
                        selectedWordClass = wc
                    } label: {
                        Text(wc == "all" ? "All" : wc)
                            .font(.caption)
                            .fontWeight(selectedWordClass == wc ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedWordClass == wc
                                          ? Color.accentColor
                                          : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedWordClass == wc ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func pickerCell(_ tile: TileModel) -> some View {
        let isSelected = selectedKeys.contains(tile.key)
        Button {
            if isSelected { selectedKeys.remove(tile.key) }
            else { selectedKeys.insert(tile.key) }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(tile.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private var suggestionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Suggest tiles for… (e.g. emotions for a 6-year-old)", text: $suggestionGoal)
                    .font(.subheadline)
                    .submitLabel(.go)
                    .onSubmit { suggestTiles() }
                    .disabled(isSuggesting)

                if isSuggesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Go") { suggestTiles() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(suggestionGoal.trimmingCharacters(in: .whitespaces).isEmpty
                                  || apiKey.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))

            if let error = suggestionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if apiKey.isEmpty {
                Text("Add an OpenAI API key in Admin to enable AI suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func suggestTiles() {
        let goal = suggestionGoal.trimmingCharacters(in: .whitespaces)
        guard !goal.isEmpty, !apiKey.isEmpty else { return }
        isSuggesting = true
        suggestionError = nil
        let service = TileSuggestionService(apiKey: apiKey)
        let tiles = allTiles  // capture before async hop
        Task {
            do {
                let keys = try await service.suggest(goal: goal, allTiles: tiles)
                selectedKeys = selectedKeys.union(keys.subtracting(existingKeys))
                // Clear the word class filter so suggested tiles are all visible
                selectedWordClass = "all"
            } catch {
                suggestionError = error.localizedDescription
            }
            isSuggesting = false
        }
    }

    private func addSelectedTiles() {
        var seenKeys = Set<String>()
        let keysToAdd = allTiles.compactMap { tile -> String? in
            guard selectedKeys.contains(tile.key),
                  !existingKeys.contains(tile.key),
                  seenKeys.insert(tile.key).inserted else { return nil }
            return tile.key
        }
        guard !keysToAdd.isEmpty else { return }
        var pages = scene.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        for key in keysToAdd {
            pages[idx].tiles.append(TileEntry(key: key, link: "", isAudible: true))
        }
        scene.pages = pages
        try? modelContext.save()
    }
}
