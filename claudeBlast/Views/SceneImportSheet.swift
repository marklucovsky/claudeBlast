// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneImportSheet.swift
//  claudeBlast
//
//  Presented when opening a .blasterscene file from outside the app.
//

import SwiftUI
import SwiftData

struct SceneImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var preview: ExportableScene?
    @State private var error: String?
    @State private var importResult: SceneImporter.ImportResult?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView(
                        "Import Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let preview {
                    importPreview(preview)
                } else {
                    ProgressView("Loading scene...")
                }
            }
            .navigationTitle("Import Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .task { loadPreview() }
    }

    @ViewBuilder
    private func importPreview(_ scene: ExportableScene) -> some View {
        VStack(spacing: 16) {
            List {
                Section {
                    LabeledContent("Name", value: scene.name)
                    if !scene.description.isEmpty {
                        LabeledContent("Description", value: scene.description)
                    }
                    LabeledContent("Pages", value: "\(scene.pages.count)")
                    let tileCount = scene.pages.reduce(0) { $0 + $1.tiles.count }
                    LabeledContent("Tiles", value: "\(tileCount)")
                    if let newTiles = scene.tiles, !newTiles.isEmpty {
                        LabeledContent("New vocabulary", value: "\(newTiles.count) tile(s)")
                    }
                }

                Section("Pages") {
                    ForEach(scene.pages, id: \.key) { page in
                        HStack {
                            Text(page.key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.body)
                            Spacer()
                            Text("\(page.tiles.count) tiles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if page.key == scene.homePageKey {
                                Image(systemName: "house.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            if let result = importResult {
                importResultBanner(result)
            }

            Button {
                performImport()
            } label: {
                Label("Import Scene", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(importResult != nil)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func importResultBanner(_ result: SceneImporter.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Imported successfully", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
            if result.newTileCount > 0 {
                Text("\(result.newTileCount) new tile(s) added to vocabulary")
                    .font(.caption)
            }
            if !result.skippedKeys.isEmpty {
                Text("\(result.skippedKeys.count) tile(s) not found: \(result.skippedKeys.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Done") { onDismiss() }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.green.opacity(0.1)))
        .padding(.horizontal)
    }

    private func loadPreview() {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            preview = try SceneImporter.preview(data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performImport() {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            importResult = try SceneImporter.importJSON(data, context: modelContext,
                                                         sourceURL: url.scheme == "https" ? url.absoluteString : "")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
