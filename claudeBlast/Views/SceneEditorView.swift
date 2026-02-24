//
//  SceneEditorView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct SceneEditorView: View {
    @Bindable var scene: BlasterScene
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingPage = false
    @State private var newPageName = ""

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
        .alert("New Page", isPresented: $isAddingPage) {
            TextField("Page name", text: $newPageName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Create") { addPage() }
            Button("Cancel", role: .cancel) { newPageName = "" }
        } message: {
            Text("Enter a name for the new page (e.g. \"my_words\").")
        }
    }

    private func addPage() {
        let key = newPageName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else { newPageName = ""; return }
        let page = PageModel(displayName: key)
        modelContext.insert(page)
        scene.pages.append(page)
        if scene.homePageKey.isEmpty {
            scene.homePageKey = key
        }
        newPageName = ""
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
