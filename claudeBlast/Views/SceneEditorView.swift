//
//  SceneEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct SceneEditorView: View {
    @Bindable var scene: BlasterScene
    var initialPageGoal: String = ""
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingPage = false
    @State private var navigateToNewPage: PageModel? = nil
    @State private var navigateToNewPageGoal: String = ""

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
                        ForEach(scene.pages, id: \.displayName) { page in
                            Text(page.displayName).tag(page.displayName)
                        }
                    }
                }
            }

            Section("Pages (\(scene.pages.count))") {
                ForEach(scene.pages) { page in
                    NavigationLink(destination: PageEditorView(page: page, scene: scene)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(page.displayName)
                                    .font(.headline)
                                if scene.homePageKey == page.displayName {
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
        .sheet(isPresented: $isAddingPage) {
            AddPageSheet(scene: scene) { page, goal in
                navigateToNewPageGoal = goal
                navigateToNewPage = page
            }
        }
        .navigationDestination(item: $navigateToNewPage) { page in
            PageEditorView(page: page, scene: scene, autoSuggestGoal: navigateToNewPageGoal)
        }
        .task {
            guard !initialPageGoal.isEmpty,
                  let home = scene.pages.first(where: { $0.displayName == scene.homePageKey }),
                  navigateToNewPage == nil
            else { return }
            navigateToNewPageGoal = initialPageGoal
            navigateToNewPage = home
        }
    }

    private func deletePages(at offsets: IndexSet) {
        for index in offsets.sorted().reversed() {
            let page = scene.pages[index]
            modelContext.delete(page)
            scene.pages.remove(at: index)
        }
        if !scene.pages.contains(where: { $0.displayName == scene.homePageKey }) {
            scene.homePageKey = scene.pages.first?.displayName ?? ""
        }
    }
}

// MARK: - Add Page Sheet

private struct AddPageSheet: View {
    let scene: BlasterScene
    let onCreate: (PageModel, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var pageName = ""
    @State private var goal = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Page Name") {
                    TextField("e.g. emotions", text: $pageName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        TextField("Suggest tiles for… (optional)", text: $goal)
                    }
                } header: {
                    Text("AI Tile Suggestion")
                } footer: {
                    Text("AI will pre-select tiles when the tile picker opens.")
                }
            }
            .navigationTitle("New Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createAndClose() }
                        .disabled(pageName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createAndClose() {
        let key = pageName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else { return }
        let page = PageModel(displayName: key)
        modelContext.insert(page)
        scene.pages.append(page)
        if scene.homePageKey.isEmpty { scene.homePageKey = key }
        onCreate(page, goal)
        dismiss()
    }
}
