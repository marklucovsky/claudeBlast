// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct PageEditorView: View {
    @Bindable var page: PageModel
    let scene: BlasterScene
    var autoOpenPickerWithKeys: Set<String> = []
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var isPickingTiles = false
    @State private var showArrangeGrid = false
    @State private var editingTile: PageTileModel? = nil
    @State private var pickerInitialKeys: Set<String> = []

    var body: some View {
        Group {
            if page.orderedTiles.isEmpty {
                ContentUnavailableView {
                    Label("No Tiles", systemImage: "square.grid.2x2")
                } description: {
                    Text("Tap + to add tiles to this page.")
                } actions: {
                    Button("Add Tiles") { isPickingTiles = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(page.orderedTiles) { pageTile in
                        tileRow(pageTile)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode?.wrappedValue != .active else { return }
                                editingTile = pageTile
                            }
                    }
                    .onDelete(perform: deleteTiles)
                    .onMove(perform: moveTiles)
                }
            }
        }
        .navigationTitle(page.displayName)
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
                .disabled(page.orderedTiles.count < 2)

                Button { isPickingTiles = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPickingTiles, onDismiss: { pickerInitialKeys = [] }) {
            TilePickerView(page: page, initialSelectedKeys: pickerInitialKeys)
        }
        .task {
            guard !autoOpenPickerWithKeys.isEmpty else { return }
            pickerInitialKeys = autoOpenPickerWithKeys
            isPickingTiles = true
        }
        .sheet(item: $editingTile) { tile in
            TilePropertiesSheet(pageTile: tile, scene: scene)
        }
        .sheet(isPresented: $showArrangeGrid) {
            GridArrangeView(page: page)
        }
    }

    @ViewBuilder
    private func tileRow(_ pageTile: PageTileModel) -> some View {
        HStack(spacing: 12) {
            Group {
                if UIImage(named: pageTile.tile.bundleImage) != nil {
                    Image(pageTile.tile.bundleImage)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .background(wordClassColor(pageTile.tile.wordClass).opacity(0.12))
                } else {
                    Text(String(pageTile.tile.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(wordClassColor(pageTile.tile.wordClass))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(pageTile.tile.displayName)
                HStack(spacing: 8) {
                    if pageTile.isAudible {
                        Label("Audible", systemImage: "speaker.wave.2")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if !pageTile.link.isEmpty {
                        Label(pageTile.link, systemImage: "arrow.right.circle")
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
        let ordered = page.orderedTiles
        for index in offsets.sorted().reversed() {
            let pt = ordered[index]
            page.removeTile(pt)
            modelContext.delete(pt)
        }
    }

    private func moveTiles(from source: IndexSet, to destination: Int) {
        page.tileOrder.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Tile Properties Sheet

struct TilePropertiesSheet: View {
    @Bindable var pageTile: PageTileModel
    let scene: BlasterScene
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if UIImage(named: pageTile.tile.bundleImage) != nil {
                                Image(pageTile.tile.bundleImage)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(4)
                                    .background(wordClassColor(pageTile.tile.wordClass).opacity(0.12))
                            } else {
                                Text(String(pageTile.tile.displayName.prefix(1)).uppercased())
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(wordClassColor(pageTile.tile.wordClass))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pageTile.tile.displayName)
                                .font(.headline)
                            Text(pageTile.tile.wordClass)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Behavior") {
                    Toggle("Add to sentence tray", isOn: $pageTile.isAudible)
                }

                Section("Navigation") {
                    Picker("Link to Page", selection: $pageTile.link) {
                        Text("None").tag("")
                        ForEach(scene.pages, id: \.displayName) { page in
                            Text(page.displayName).tag(page.displayName)
                        }
                    }
                    if !pageTile.link.isEmpty {
                        Text("Tapping this tile navigates to \"\(pageTile.link)\".")
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
