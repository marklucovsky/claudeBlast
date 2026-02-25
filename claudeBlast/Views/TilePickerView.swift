//
//  TilePickerView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TilePickerView: View {
    let page: PageModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @State private var selectedKeys: Set<String> = []
    @State private var searchText = ""
    @State private var selectedWordClass = "all"
    @State private var suggestionGoal = ""
    @State private var isSuggesting = false
    @State private var suggestionError: String? = nil

    @AppStorage("openai_api_key") private var storedAPIKey: String = ""
    private var apiKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? storedAPIKey
    }

    private var existingKeys: Set<String> {
        Set(page.tiles.map { $0.tile.key })
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
                    ContentUnavailableView("No tiles found", systemImage: "magnifyingglass")
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
            .navigationTitle("Add Tiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                    Group {
                        if UIImage(named: tile.bundleImage) != nil {
                            Image(tile.bundleImage)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                                .background(wordClassColor(tile.wordClass).opacity(0.12))
                        } else {
                            Text(String(tile.displayName.prefix(1)).uppercased())
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(wordClassColor(tile.wordClass))
                        }
                    }
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
                selectedKeys = selectedKeys.union(keys)
                // Clear the word class filter so suggested tiles are all visible
                selectedWordClass = "all"
            } catch {
                suggestionError = error.localizedDescription
            }
            isSuggesting = false
        }
    }

    private func addSelectedTiles() {
        let tilesToAdd = allTiles.filter { selectedKeys.contains($0.key) }
        for tile in tilesToAdd {
            let pt = PageTileModel(tile: tile, link: "", isAudible: true)
            modelContext.insert(pt)
            page.tiles.append(pt)
            page.tileOrder.append(pt.id)
        }
    }
}
