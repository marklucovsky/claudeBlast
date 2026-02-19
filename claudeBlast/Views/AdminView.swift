//
//  AdminView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section("Scenes") {
                    ForEach(scenes) { scene in
                        SceneRow(scene: scene) {
                            activateScene(scene)
                        }
                    }
                    .onDelete(perform: deleteScenes)
                }

                Section {
                    Button {
                        createSampleScene()
                    } label: {
                        Label("Create Sample Scene", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Admin")
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

    private func createSampleScene() {
        let tiles = [
            TileModel(key: "happy", wordClass: "describe"),
            TileModel(key: "sad", wordClass: "describe"),
            TileModel(key: "angry", wordClass: "describe"),
            TileModel(key: "afraid", wordClass: "describe"),
            TileModel(key: "tired", wordClass: "describe"),
            TileModel(key: "hungry", wordClass: "describe"),
            TileModel(key: "yes", wordClass: "social"),
            TileModel(key: "no", wordClass: "social"),
            TileModel(key: "help", wordClass: "actions"),
            TileModel(key: "stop", wordClass: "actions"),
            TileModel(key: "more", wordClass: "actions"),
            TileModel(key: "please", wordClass: "social"),
        ]

        for tile in tiles {
            modelContext.insert(tile)
        }

        let pageTiles = tiles.map { PageTileModel(tile: $0) }
        let tileOrder = pageTiles.map(\.id)
        let page = PageModel.make(
            displayName: "feelings_session",
            tiles: pageTiles,
            tileOrder: tileOrder
        )
        modelContext.insert(page)

        let scene = BlasterScene(
            name: "Feelings Session",
            descriptionText: "Focused emotions vocabulary for therapy",
            homePageKey: "feelings_session"
        )
        scene.pages = [page]
        modelContext.insert(scene)
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
