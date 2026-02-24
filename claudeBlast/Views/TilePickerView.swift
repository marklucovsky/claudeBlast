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
