// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct PageEditorView: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    var autoOpenPickerWithKeys: Set<String> = []
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var isPickingTiles = false
    @State private var showArrangeGrid = false
    @State private var editingTileKey: String? = nil
    @State private var pickerInitialKeys: Set<String> = []

    private var tileLookup: [String: TileModel] {
        Dictionary(uniqueKeysWithValues: allTiles.map { ($0.key, $0) })
    }

    private var pageIndex: Int? {
        scene.pages.firstIndex { $0.key == pageKey }
    }

    private var page: PageSpec? {
        scene.pages.first { $0.key == pageKey }
    }

    var body: some View {
        Group {
            if let page, page.tiles.isEmpty {
                ContentUnavailableView {
                    Label("No Tiles", systemImage: "square.grid.2x2")
                } description: {
                    Text("Tap + to add tiles to this page.")
                } actions: {
                    Button("Add Tiles") { isPickingTiles = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if let page {
                List {
                    ForEach(page.tiles, id: \.key) { entry in
                        tileRow(entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode?.wrappedValue != .active else { return }
                                editingTileKey = entry.key
                            }
                    }
                    .onDelete(perform: deleteTiles)
                    .onMove(perform: moveTiles)
                }
            } else {
                ContentUnavailableView("Page not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(pageKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showArrangeGrid = true
                } label: {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .disabled((page?.tiles.count ?? 0) < 2)

                Button { isPickingTiles = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPickingTiles, onDismiss: { pickerInitialKeys = [] }) {
            TilePickerView(scene: scene, pageKey: pageKey, initialSelectedKeys: pickerInitialKeys)
        }
        .task {
            guard !autoOpenPickerWithKeys.isEmpty else { return }
            pickerInitialKeys = autoOpenPickerWithKeys
            isPickingTiles = true
        }
        .sheet(item: $editingTileKey) { key in
            TilePropertiesSheet(scene: scene, pageKey: pageKey, tileKey: key)
        }
        .sheet(isPresented: $showArrangeGrid) {
            GridArrangeView(scene: scene, pageKey: pageKey)
        }
    }

    @ViewBuilder
    private func tileRow(_ entry: TileEntry) -> some View {
        HStack(spacing: 12) {
            let tile = tileLookup[entry.key]
            TileImageView(key: tile?.bundleImage ?? entry.key,
                          wordClass: tile?.wordClass ?? "")
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(tile?.displayName ?? entry.key)
                HStack(spacing: 8) {
                    if entry.isAudible {
                        Label("Audible", systemImage: "speaker.wave.2")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if !entry.link.isEmpty {
                        Label(entry.link, systemImage: "arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()
            if editMode?.wrappedValue != .active {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func deleteTiles(at offsets: IndexSet) {
        guard let pageIdx = pageIndex else { return }
        var pages = scene.pages
        for index in offsets.sorted().reversed() {
            pages[pageIdx].tiles.remove(at: index)
        }
        scene.pages = pages
        try? modelContext.save()
    }

    private func moveTiles(from source: IndexSet, to destination: Int) {
        guard let pageIdx = pageIndex else { return }
        var pages = scene.pages
        pages[pageIdx].tiles.move(fromOffsets: source, toOffset: destination)
        scene.pages = pages
        try? modelContext.save()
    }
}

// Allow .sheet(item:) on String state.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Tile Properties Sheet

struct TilePropertiesSheet: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    let tileKey: String
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Environment(\.dismiss) private var dismiss

    private var tile: TileModel? {
        allTiles.first { $0.key == tileKey }
    }

    private var entry: TileEntry? {
        scene.pages.first { $0.key == pageKey }?.tiles.first { $0.key == tileKey }
    }

    private var entryBinding: (link: Binding<String>, audible: Binding<Bool>) {
        let link = Binding<String>(
            get: { entry?.link ?? "" },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                pages[p].tiles[t].link = newValue
                scene.pages = pages
            }
        )
        let audible = Binding<Bool>(
            get: { entry?.isAudible ?? true },
            set: { newValue in
                var pages = scene.pages
                guard let p = pages.firstIndex(where: { $0.key == pageKey }),
                      let t = pages[p].tiles.firstIndex(where: { $0.key == tileKey }) else { return }
                pages[p].tiles[t].isAudible = newValue
                scene.pages = pages
            }
        )
        return (link, audible)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        TileImageView(key: tile?.bundleImage ?? tileKey,
                                      wordClass: tile?.wordClass ?? "")
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile?.displayName ?? tileKey)
                                .font(.headline)
                            Text(tile?.wordClass ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Behavior") {
                    Toggle("Add to sentence tray", isOn: entryBinding.audible)
                }

                Section("Navigation") {
                    Picker("Link to Page", selection: entryBinding.link) {
                        Text("None").tag("")
                        ForEach(scene.pages, id: \.key) { page in
                            Text(page.key).tag(page.key)
                        }
                    }
                    let currentLink = entry?.link ?? ""
                    if !currentLink.isEmpty {
                        Text("Tapping this tile navigates to \"\(currentLink)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tile Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
